//
//  DinoAgentRuntime.swift
//  dino
//
//  Created for Dino Browser.
//  In-app autonomous ReAct agent runtime.
//  Orchestrates Goal -> Perception -> LLM -> Safety Gate -> Action -> Settle -> Verify.
//  Zero external dependencies.
//

import Foundation
import SwiftUI
import AppKit
import Combine
import WebKit

enum AgentRuntimeStatus: Equatable {
    case idle
    case running(goal: String, step: Int)
    case paused(reason: String)
    case waitingHITL(reason: String, question: String?)
    case completed(summary: String)
    case failed(error: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

struct AgentStepLog: Identifiable, Hashable {
    let id = UUID()
    let timestamp = Date()
    let stepNumber: Int
    let thought: String
    let actionDescription: String
    let isSuccess: Bool
}

@MainActor
final class DinoAgentRuntime: ObservableObject {
    static let shared = DinoAgentRuntime()

    @Published var status: AgentRuntimeStatus = .idle
    @Published var currentThought: String = ""
    @Published var stepLogs: [AgentStepLog] = []
    @Published var activeGoal: String = ""
    @Published var stepCount: Int = 0

    private var activeTask: Task<Void, Never>? = nil
    private var history: [[String: Any]] = []
    private weak var currentTab: Tab? = nil
    private let maxSteps = 25

    private init() {}

    // MARK: - Mission Lifecycle

    func startTask(goal: String, tab: Tab) {
        guard !status.isRunning else { return }
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanGoal.isEmpty else { return }

        self.activeGoal = cleanGoal
        self.currentTab = tab
        self.stepCount = 0
        self.stepLogs = []
        self.history = []
        self.currentThought = "Analyzing page context and user goal..."
        self.status = .running(goal: cleanGoal, step: 0)

        tab.isAgentDriving = true

        activeTask = Task { [weak self] in
            await self?.runReActLoop(goal: cleanGoal, tab: tab)
        }
    }

    func pause() {
        guard case .running = status else { return }
        status = .paused(reason: "Paused by user")
        currentThought = "Execution paused."
        currentTab?.isAgentDriving = false
    }

    func resume() {
        guard let tab = currentTab, !activeGoal.isEmpty else { return }
        status = .running(goal: activeGoal, step: stepCount)
        tab.isAgentDriving = true
        activeTask = Task { [weak self] in
            await self?.runReActLoop(goal: self?.activeGoal ?? "", tab: tab)
        }
    }

    func abort() {
        activeTask?.cancel()
        activeTask = nil
        currentTab?.isAgentDriving = false
        if let tab = currentTab {
            Task {
                _ = try? await tab.webView.evaluateJavaScript("if (window.__dino && window.__dino.hideVirtualCursor) window.__dino.hideVirtualCursor();")
            }
        }
        status = .idle
        currentThought = ""
    }

    func resolveHITL(with response: String? = nil) {
        guard case .waitingHITL = status, let tab = currentTab else { return }
        if let response = response, !response.isEmpty {
            history.append(["role": "user", "text": "Human Response: \(response)"])
        }
        status = .running(goal: activeGoal, step: stepCount)
        tab.isAgentDriving = true
        activeTask = Task { [weak self] in
            await self?.runReActLoop(goal: self?.activeGoal ?? "", tab: tab)
        }
    }

    // MARK: - Cognitive ReAct Loop

    private func runReActLoop(goal: String, tab: Tab) async {
        while stepCount < maxSteps {
            if Task.isCancelled {
                tab.isAgentDriving = false
                return
            }

            stepCount += 1
            status = .running(goal: goal, step: stepCount)

            // 1. Check for Anti-Bot challenge (Turnstile, reCAPTCHA, 2FA)
            let botStatus = await tab.checkHitlStatus()
            if botStatus.detected && !botStatus.resolved {
                status = .waitingHITL(reason: "Security challenge detected (\(botStatus.type ?? "Verification")). Please clear it in the page.", question: nil)
                currentThought = "Waiting for human to complete security check..."
                tab.isAgentDriving = false
                return
            }

            // 2. Settle page
            _ = try? await tab.waitForStability(quietMs: 150, timeoutMs: 3000)

            // 3. Capture interactive DOM snapshot
            let domSnapshot: String
            do {
                let treeResult = try await tab.getSemanticTree(viewportOnly: true)
                if let s = treeResult.summary, !s.isEmpty {
                    domSnapshot = s
                } else if !treeResult.elements.isEmpty {
                    domSnapshot = treeResult.elements.map { "[\($0.id)] <\($0.tag) role=\"\($0.role ?? "")\"> \($0.text)" }.joined(separator: "\n")
                } else {
                    domSnapshot = "Empty Page"
                }
            } catch {
                appendLog(step: stepCount, thought: "Failed to read DOM", action: "Error reading page", isSuccess: false)
                status = .failed(error: "Could not inspect page: \(error.localizedDescription)")
                tab.isAgentDriving = false
                return
            }

            let activeURL = tab.url
            let pageTitle = tab.title

            // 4. Request reasoning & next tool call from LLM Client
            currentThought = "Evaluating actions for step \(stepCount)..."
            let stepResponse: AgentStepResponse
            do {
                stepResponse = try await DinoLLMClient.shared.nextStep(
                    goal: goal,
                    history: history,
                    currentDOM: domSnapshot,
                    activeURL: activeURL,
                    pageTitle: pageTitle
                )
            } catch {
                let errText = error.localizedDescription
                appendLog(step: stepCount, thought: "LLM Error", action: errText, isSuccess: false)
                status = .failed(error: errText)
                tab.isAgentDriving = false
                return
            }

            self.currentThought = stepResponse.thought
            if !stepResponse.thought.isEmpty {
                history.append(["role": "assistant", "text": stepResponse.thought])
            }

            // 5. Execute Tool Call
            guard let toolCall = stepResponse.toolCall else {
                // If model responded with text and no tool call, check if task is complete
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Refining plan...", isSuccess: true)
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            let toolName = toolCall.name
            let args = toolCall.arguments

            switch toolName {
            case "complete":
                let summary = (args["summary"] as? String) ?? stepResponse.thought
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Completed: \(summary)", isSuccess: true)
                _ = try? await tab.webView.evaluateJavaScript("if (window.__dino && window.__dino.hideVirtualCursor) window.__dino.hideVirtualCursor();")
                status = .completed(summary: summary)
                tab.isAgentDriving = false
                return

            case "ask_user":
                let question = (args["question"] as? String) ?? "Please provide input."
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Asked user: \(question)", isSuccess: true)
                status = .waitingHITL(reason: "Input needed", question: question)
                tab.isAgentDriving = false
                return

            case "click":
                guard let ref = args["ref"] as? String else { continue }

                // Security Gate: Check for high-stakes action
                if DinoDOMSanitizer.isHighStakesAction(elementText: ref) {
                    status = .waitingHITL(reason: "High-stakes action detected: clicking '\(ref)'. Confirm to proceed.", question: nil)
                    tab.isAgentDriving = false
                    return
                }

                appendLog(step: stepCount, thought: stepResponse.thought, action: "Clicking [\(ref)]", isSuccess: true)
                let action = DinoAction(action: "click", target: ref)
                _ = try? await tab.performAction(action)
                history.append(["role": "user", "text": "Clicked element [\(ref)]."])

            case "type":
                guard let ref = args["ref"] as? String, let text = args["text"] as? String else { continue }
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Typing \"\(text.prefix(20))\" into [\(ref)]", isSuccess: true)
                let pressEnter = (args["pressEnter"] as? Bool) ?? false
                let action = DinoAction(action: "fill", target: ref, text: text, submit: pressEnter)
                _ = try? await tab.performAction(action)
                history.append(["role": "user", "text": "Typed into [\(ref)]."])

            case "scroll":
                let direction = (args["direction"] as? String) ?? "down"
                let amount = (args["amount"] as? Int) ?? 400
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Scrolling \(direction) \(amount)px", isSuccess: true)
                let action = DinoAction(action: "scroll", direction: direction, amount: CGFloat(amount))
                _ = try? await tab.performAction(action)
                history.append(["role": "user", "text": "Scrolled \(direction)."])

            case "navigate":
                guard let urlStr = args["url"] as? String, let targetURL = URL(string: urlStr) else { continue }
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Navigating to \(targetURL.host ?? urlStr)", isSuccess: true)
                tab.load(url: targetURL)
                history.append(["role": "user", "text": "Navigated to \(urlStr)."])

            default:
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Unknown tool: \(toolName)", isSuccess: false)
            }

            // Brief pause between steps for rendering & visual tracking
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        if stepCount >= maxSteps {
            status = .failed(error: "Maximum step limit reached (\(maxSteps) steps).")
            tab.isAgentDriving = false
        }
    }

    private func appendLog(step: Int, thought: String, action: String, isSuccess: Bool) {
        let entry = AgentStepLog(stepNumber: step, thought: thought, actionDescription: action, isSuccess: isSuccess)
        stepLogs.append(entry)
    }
}

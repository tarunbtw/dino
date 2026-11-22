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

struct AgentChatMessage: Identifiable, Hashable {
    enum Sender {
        case user
        case agent
        case action
        case error
    }

    let id = UUID()
    let timestamp = Date()
    let sender: Sender
    let text: String
    var details: String? = nil
}

struct AgentChatSession: Identifiable, Hashable {
    let id: UUID
    var title: String
    let createdAt: Date
    var messages: [AgentChatMessage]
    var stepLogs: [AgentStepLog]
}

@MainActor
final class DinoAgentRuntime: ObservableObject {
    static let shared = DinoAgentRuntime()

    @Published var status: AgentRuntimeStatus = .idle
    @Published var currentThought: String = ""
    @Published var stepLogs: [AgentStepLog] = []
    @Published var messages: [AgentChatMessage] = []
    @Published var sessions: [AgentChatSession] = []
    @Published var activeSessionId: UUID? = nil
    @Published var activeGoal: String = ""
    @Published var stepCount: Int = 0

    private var activeTask: Task<Void, Never>? = nil
    private var history: [[String: Any]] = []
    private weak var currentTab: Tab? = nil
    private weak var browserStore: BrowserStore? = nil
    private let maxSteps = 25
    private var lastActionSignature: String = ""
    private var repeatActionCount: Int = 0
    private var consecutiveScrollCount: Int = 0

    private init() {}

    // MARK: - Mission Lifecycle

    func startTask(goal: String, tab: Tab, store: BrowserStore? = nil) {
        guard !status.isRunning else { return }
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanGoal.isEmpty else { return }

        self.browserStore = store

        if let id = activeSessionId, let idx = sessions.firstIndex(where: { $0.id == id }) {
            if sessions[idx].messages.isEmpty {
                sessions[idx].title = String(cleanGoal.prefix(28))
            }
        } else {
            let initialTitle = String(cleanGoal.prefix(28))
            let session = AgentChatSession(id: UUID(), title: initialTitle, createdAt: Date(), messages: [], stepLogs: [])
            sessions.insert(session, at: 0)
            activeSessionId = session.id
        }

        self.activeGoal = cleanGoal
        self.currentTab = tab
        self.stepCount = 0
        self.stepLogs = []
        self.history = []
        self.lastActionSignature = ""
        self.repeatActionCount = 0
        self.consecutiveScrollCount = 0
        let userMsg = AgentChatMessage(sender: .user, text: cleanGoal)
        self.messages.append(userMsg)
        self.syncCurrentSession()

        self.currentThought = "Analyzing page context and user goal..."
        self.status = .running(goal: cleanGoal, step: 0)

        tab.isAgentDriving = true

        activeTask = Task { [weak self] in
            await self?.runReActLoop(goal: cleanGoal, tab: tab)
        }
    }

    func newSession() {
        syncCurrentSession()
        abort()
        messages.removeAll()
        stepLogs.removeAll()
        history.removeAll()
        activeGoal = ""
        activeSessionId = nil
    }

    func clearSession() {
        newSession()
    }

    func selectSession(_ session: AgentChatSession) {
        guard session.id != activeSessionId else { return }
        syncCurrentSession()
        abort()
        activeSessionId = session.id
        messages = session.messages
        stepLogs = session.stepLogs
        activeGoal = session.messages.first(where: { $0.sender == .user })?.text ?? ""
        history.removeAll()
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            newSession()
        }
    }

    func clearAllSessions() {
        abort()
        sessions.removeAll()
        messages.removeAll()
        stepLogs.removeAll()
        history.removeAll()
        activeGoal = ""
        activeSessionId = nil
    }

    func syncCurrentSession() {
        guard let id = activeSessionId, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages = messages
        sessions[idx].stepLogs = stepLogs
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
            let drivingTab = self.currentTab ?? tab
            if Task.isCancelled {
                drivingTab.isAgentDriving = false
                self.currentTab?.isAgentDriving = false
                return
            }

            stepCount += 1
            status = .running(goal: goal, step: stepCount)

            // 1. Check for Anti-Bot challenge (Turnstile, reCAPTCHA, 2FA)
            let botStatus = await drivingTab.checkHitlStatus()
            if botStatus.detected && !botStatus.resolved {
                status = .waitingHITL(reason: "Security challenge detected (\(botStatus.type ?? "Verification")). Please clear it in the page.", question: nil)
                currentThought = "Waiting for human to complete security check..."
                drivingTab.isAgentDriving = false
                self.currentTab?.isAgentDriving = false
                return
            }

            // 2. Settle page & capture DOM
            let domSnapshot: String
            if drivingTab.isBlank || drivingTab.url == nil || drivingTab.url?.absoluteString == "about:blank" {
                domSnapshot = "<page url=\"about:blank\">Empty page. No interactive elements present. To fulfill the user's request, call navigate(url: \"https://...\") to open the target website.</page>"
            } else {
                _ = try? await drivingTab.waitForStability(quietMs: 150, timeoutMs: 2500)
                do {
                    let treeResult = try await drivingTab.getSemanticTree(viewportOnly: true)
                    if let s = treeResult.summary, !s.isEmpty {
                        domSnapshot = s
                    } else if !treeResult.elements.isEmpty {
                        domSnapshot = treeResult.elements.map { "[\($0.id)] <\($0.tag) role=\"\($0.role ?? "")\"> \($0.text)" }.joined(separator: "\n")
                    } else {
                        domSnapshot = "Page loaded with no interactable elements."
                    }
                } catch {
                    appendLog(step: stepCount, thought: "Failed to read DOM", action: "Error reading page", isSuccess: false)
                    status = .failed(error: "Could not inspect page: \(error.localizedDescription)")
                    drivingTab.isAgentDriving = false
                    self.currentTab?.isAgentDriving = false
                    return
                }
            }

            let activeURL = drivingTab.url
            let pageTitle = drivingTab.title

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
                drivingTab.isAgentDriving = false
                self.currentTab?.isAgentDriving = false
                return
            }

            self.currentThought = stepResponse.thought
            if !stepResponse.thought.isEmpty {
                history.append(["role": "assistant", "text": stepResponse.thought])
            }

            // 5. Execute Tool Call
            guard let toolCall = stepResponse.toolCall else {
                let directResponse = stepResponse.thought.trimmingCharacters(in: .whitespacesAndNewlines)
                if !directResponse.isEmpty {
                    // Conversational response without tool execution (e.g. greeting or direct answer)
                    messages.append(AgentChatMessage(sender: .agent, text: directResponse))
                    syncCurrentSession()
                    status = .completed(summary: directResponse)
                    drivingTab.isAgentDriving = false
                    self.currentTab?.isAgentDriving = false
                    return
                }
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Refining plan...", isSuccess: true)
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            let toolName = toolCall.name
            let args = toolCall.arguments

            // Stagnation / Loop Guard: Detect identical repeated actions
            let currentSignature = "\(toolName):\(args)"
            if currentSignature == lastActionSignature {
                repeatActionCount += 1
            } else {
                repeatActionCount = 1
                lastActionSignature = currentSignature
            }

            // Consecutive Scroll Guard: Prevent pointless vertical feed scrolling on web portals
            if toolName == "scroll" {
                consecutiveScrollCount += 1
                if consecutiveScrollCount >= 3 {
                    let failMsg = "Action 'scroll' executed 3 times without finding target section. Halting to prevent token loop. In web portals and dashboards, sections like attendance or profile are in the navigation menu (☰) or sidebar."
                    appendLog(step: stepCount, thought: stepResponse.thought, action: failMsg, isSuccess: false)
                    status = .failed(error: failMsg)
                    drivingTab.isAgentDriving = false
                    self.currentTab?.isAgentDriving = false
                    return
                }
            } else {
                consecutiveScrollCount = 0
            }

            if repeatActionCount >= 3 {
                let failMsg = "Action '\(toolName)' repeated 3 times without effect. Halting mission to prevent token loop."
                appendLog(step: stepCount, thought: stepResponse.thought, action: failMsg, isSuccess: false)
                status = .failed(error: failMsg)
                drivingTab.isAgentDriving = false
                self.currentTab?.isAgentDriving = false
                return
            }

            switch toolName {
            case "complete":
                let summary = (args["summary"] as? String) ?? stepResponse.thought
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Completed: \(summary)", isSuccess: true)
                messages.append(AgentChatMessage(sender: .agent, text: summary))
                syncCurrentSession()
                _ = try? await drivingTab.webView.evaluateJavaScript("if (window.__dino && window.__dino.hideVirtualCursor) window.__dino.hideVirtualCursor();")
                status = .completed(summary: summary)
                drivingTab.isAgentDriving = false
                self.currentTab?.isAgentDriving = false
                return

            case "ask_user":
                let question = (args["question"] as? String) ?? "Please provide input."
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Asked user: \(question)", isSuccess: true)
                status = .waitingHITL(reason: "Input needed", question: question)
                drivingTab.isAgentDriving = false
                self.currentTab?.isAgentDriving = false
                return

            case "new_tab":
                guard let urlStr = args["url"] as? String else { continue }
                let clean = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = (clean.hasPrefix("http://") || clean.hasPrefix("https://")) ? clean : "https://\(clean)"
                guard let targetURL = URL(string: normalized) else { continue }
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Opening new tab: \(targetURL.host ?? normalized)", isSuccess: true)

                let nextTab: Tab
                if let store = self.browserStore {
                    let freshTab = store.newTab(url: targetURL, select: true)
                    self.currentTab = freshTab
                    freshTab.isAgentDriving = true
                    nextTab = freshTab
                } else {
                    drivingTab.load(url: targetURL)
                    nextTab = drivingTab
                }
                history.append(["role": "user", "text": "Opened new tab at \(normalized) and switched focus to it."])
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await nextTab.waitForNavigationSettled(timeout: 2.5)

            case "click":
                guard let rawRef = args["ref"] as? String else { continue }
                let ref = rawRef.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t\r\n"))
                let actionContext = (args["reason"] as? String) ?? stepResponse.thought

                // Security Gate: Check for high-stakes action
                if DinoDOMSanitizer.isHighStakesAction(elementText: actionContext) {
                    status = .waitingHITL(reason: "High-stakes action detected: '\(actionContext)'. Confirm to proceed.", question: nil)
                    drivingTab.isAgentDriving = false
                    self.currentTab?.isAgentDriving = false
                    return
                }

                appendLog(step: stepCount, thought: stepResponse.thought, action: "Clicking [\(ref)]", isSuccess: true)
                let action = DinoAction(action: "click", target: ref)
                let result = (try? await drivingTab.performAction(action)) ?? DinoActionResult(success: false, message: "Execution error")
                if result.success {
                    history.append(["role": "user", "text": "Clicked element [\(ref)]."])
                } else {
                    let errMsg = result.message.isEmpty ? "Could not click element." : result.message
                    appendLog(step: stepCount, thought: stepResponse.thought, action: "Click failed: \(errMsg)", isSuccess: false)
                    history.append(["role": "user", "text": "Click failed on [\(ref)]: \(errMsg). Try another element or action."])
                }
                try? await Task.sleep(nanoseconds: 700_000_000)

            case "type":
                guard let rawRef = args["ref"] as? String, let text = args["text"] as? String else { continue }
                let ref = rawRef.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t\r\n"))
                let pressEnter = (args["pressEnter"] as? Bool)
                    ?? (args["press_enter"] as? Bool)
                    ?? (args["submit"] as? Bool)
                    ?? (args["enter"] as? Bool)
                    ?? (stepResponse.thought.localizedCaseInsensitiveContains("enter") || stepResponse.thought.localizedCaseInsensitiveContains("search"))

                appendLog(step: stepCount, thought: stepResponse.thought, action: "Typed \"\(text.prefix(30))\" into [\(ref)]\(pressEnter ? " and pressed Enter" : "")", isSuccess: true)
                let action = DinoAction(action: "type", target: ref, text: text, submit: pressEnter)
                let result = (try? await drivingTab.performAction(action)) ?? DinoActionResult(success: false, message: "Execution error")
                if result.success {
                    history.append(["role": "user", "text": "Typed into [\(ref)]\(pressEnter ? " and submitted" : "")."])
                } else {
                    let errMsg = result.message.isEmpty ? "Could not type into element." : result.message
                    appendLog(step: stepCount, thought: stepResponse.thought, action: "Type failed: \(errMsg)", isSuccess: false)
                    history.append(["role": "user", "text": "Typing failed on [\(ref)]: \(errMsg). Try clicking the search button or navigating directly to the URL."])
                }
                try? await Task.sleep(nanoseconds: 800_000_000)

            case "scroll":
                let direction = (args["direction"] as? String) ?? "down"
                let amount = (args["amount"] as? Int) ?? 400
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Scrolling \(direction) \(amount)px", isSuccess: true)
                let action = DinoAction(action: "scroll", direction: direction, amount: CGFloat(amount))
                _ = try? await drivingTab.performAction(action)
                let scrollFeedback = consecutiveScrollCount >= 2
                    ? "Scrolled \(direction) \(amount)px. NOTE: You have scrolled multiple times. If you are searching for a specific portal feature or sub-page (e.g. Attendance, Profile, Grades, Settings), it is in the navigation menu (☰) or sidebar drawer. Look for a menu or navigation button instead of continuing to scroll."
                    : "Scrolled \(direction)."
                history.append(["role": "user", "text": scrollFeedback])

            case "navigate":
                guard let urlStr = args["url"] as? String else { continue }
                let clean = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = (clean.hasPrefix("http://") || clean.hasPrefix("https://")) ? clean : "https://\(clean)"
                guard let targetURL = URL(string: normalized) else { continue }
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Navigating to \(targetURL.host ?? normalized)", isSuccess: true)
                drivingTab.load(url: targetURL)
                history.append(["role": "user", "text": "Navigated to \(normalized)."])
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await drivingTab.waitForNavigationSettled(timeout: 2.5)

            default:
                appendLog(step: stepCount, thought: stepResponse.thought, action: "Unknown tool: \(toolName)", isSuccess: false)
            }

            // Brief pause between steps for rendering & visual tracking
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        if stepCount >= maxSteps {
            status = .failed(error: "Maximum step limit reached (\(maxSteps) steps).")
            let drivingTab = self.currentTab ?? tab
            drivingTab.isAgentDriving = false
            self.currentTab?.isAgentDriving = false
        }
    }

    private func appendLog(step: Int, thought: String, action: String, isSuccess: Bool) {
        let entry = AgentStepLog(stepNumber: step, thought: thought, actionDescription: action, isSuccess: isSuccess)
        stepLogs.append(entry)
        if !action.isEmpty && !action.hasPrefix("Refining") {
            messages.append(AgentChatMessage(sender: isSuccess ? .action : .error, text: action, details: thought.isEmpty ? nil : thought))
        }
        syncCurrentSession()
    }
}

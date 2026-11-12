//
//  AutopilotRailView.swift
//  dino
//
//  Created by tarun on 15/10/26.
//

import SwiftUI
import AppKit
import Foundation

struct AutopilotLogEntry: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let text: String
    let isSuccess: Bool

    init(text: String, isSuccess: Bool) {
        self.id = UUID()
        self.timestamp = Date()
        self.text = text
        self.isSuccess = isSuccess
    }
}

/// Slide-over assistant drawer (⌘⇧A) providing live natural language page instructions,
/// deterministic zero-token macro playbook recording/replaying, and HITL security guardrails.
struct AutopilotRailView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject private var playbookManager = AgentPlaybookManager.shared
    @ObservedObject private var settings = SettingsStore.shared

    @State private var newPlaybookName: String = ""
    @State private var instructionInput: String = ""
    @State private var isExecuting: Bool = false
    @State private var isReplayingPlaybook: String? = nil
    @State private var statusLogs: [AutopilotLogEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Security & HITL Status Banner
                    hitlSection

                    // Active Tab Context Card
                    tabContextCard

                    // Macro Playbooks Section
                    playbooksSection

                    // Intent Action Section
                    intentSection

                    // Live Log Feed
                    logFeedSection
                }
                .padding(14)
            }
        }
        .frame(width: 320)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.97)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color.primary.opacity(0.08)),
            alignment: .leading
        )
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(settings.accentColor)

            Text("Autopilot")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    store.isAutopilotRailVisible = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close Autopilot Rail (⌘⇧A)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - HITL Security Status

    @ViewBuilder
    private var hitlSection: some View {
        if let tab = store.activeTab {
            if tab.isHitlActive {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("Security Challenge Active")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                    }

                    if let type = tab.hitlChallengeType {
                        Text("Type: \(type)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Button("Check & Resume") {
                        Task {
                            let status = await tab.checkHitlStatus()
                            if status.resolved {
                                withAnimation {
                                    tab.isHitlActive = false
                                    tab.hitlChallengeType = nil
                                }
                                addLog("Challenge resolved. Automation resumed.", isSuccess: true)
                            } else {
                                addLog("Challenge still pending verification.", isSuccess: false)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("HITL Guard Active (Auto-Detecting)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Active Tab Context Card

    private var tabContextCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACTIVE TARGET")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            let title = store.activeTab?.title.isEmpty == false ? store.activeTab!.title : "Untitled"
            let urlString = store.activeTab?.url?.absoluteString ?? "about:blank"

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Text(urlString)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Macro Playbooks Section

    private var playbooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MACRO PLAYBOOKS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("0 Tokens")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(settings.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(settings.accentColor.opacity(0.12), in: Capsule())
            }

            if playbookManager.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Text("Recording '\(playbookManager.activeRecordingName)' (\(playbookManager.recordedActions.count))")
                        .font(.system(size: 11, weight: .medium))

                    Spacer()

                    Button("Save") {
                        let actions = playbookManager.stopRecording()
                        addLog("Saved '\(playbookManager.activeRecordingName)' (\(actions.count) actions)", isSuccess: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                HStack(spacing: 6) {
                    TextField("Playbook name", text: $newPlaybookName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    Button("Record") {
                        let name = newPlaybookName.trimmingCharacters(in: .whitespacesAndNewlines)
                        playbookManager.startRecording(name: name.isEmpty ? "playbook" : name)
                        addLog("Started recording playbook '\(playbookManager.activeRecordingName)'", isSuccess: true)
                        newPlaybookName = ""
                    }
                    .controlSize(.small)
                }
            }

            // Saved playbooks list
            if !playbookManager.savedPlaybookNames.isEmpty {
                VStack(spacing: 4) {
                    ForEach(playbookManager.savedPlaybookNames, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(settings.accentColor)

                            Text(name)
                                .font(.system(size: 11))
                                .lineLimit(1)

                            Spacer()

                            if isReplayingPlaybook == name {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button(action: {
                                    guard let tab = store.activeTab,
                                          let actions = playbookManager.load(name: name) else { return }
                                    Task {
                                        isReplayingPlaybook = name
                                        addLog("Replaying '\(name)' (\(actions.count) steps)...", isSuccess: true)
                                        let res = try? await playbookManager.replay(actions: actions, on: tab)
                                        isReplayingPlaybook = nil
                                        if res?.success == true {
                                            addLog("Playbook '\(name)' completed successfully (\(res?.executed ?? 0) steps, 0 tokens)", isSuccess: true)
                                        } else {
                                            addLog("Playbook '\(name)' failed at step \(res?.executed ?? 0): \(res?.error ?? "Unknown error")", isSuccess: false)
                                        }
                                    }
                                }) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .help("Run Playbook")

                                Button(action: {
                                    playbookManager.delete(name: name)
                                    addLog("Deleted playbook '\(name)'", isSuccess: true)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Delete Playbook")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Natural Language Intent Section

    private var intentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAGE INSTRUCTION")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("e.g. Click checkout button", text: $instructionInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit {
                        executeInstruction()
                    }

                Button(action: executeInstruction) {
                    if isExecuting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(settings.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isExecuting || instructionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 6) {
                Button("Inspect Marks") {
                    guard let tab = store.activeTab else { return }
                    Task {
                        _ = try? await tab.captureScreenshot(labeled: true)
                        addLog("Labeled marks generated for page", isSuccess: true)
                    }
                }
                .controlSize(.small)

                Button("Page Diff") {
                    guard let tab = store.activeTab else { return }
                    Task {
                        if let diff = try? await tab.getDiff(viewportOnly: true),
                           let summary = diff["summary"] as? String {
                            addLog("DOM Diff: \(summary.prefix(80))...", isSuccess: true)
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func executeInstruction() {
        let text = instructionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let tab = store.activeTab else { return }
        isExecuting = true
        addLog("Resolving intent: \"\(text)\"...", isSuccess: true)

        Task {
            do {
                let match = try await tab.findSemantic(query: text, role: nil, viewportOnly: true)
                guard let ref = match["ref"] as? String else {
                    addLog("No element matched intent: \"\(text)\"", isSuccess: false)
                    isExecuting = false
                    return
                }

                let action = DinoAction(action: "click", target: ref)
                let result = try await tab.performAction(action)
                if result.success {
                    addLog("Successfully clicked [\(ref)] for intent \"\(text)\"", isSuccess: true)
                    instructionInput = ""
                } else {
                    addLog("Action failed on [\(ref)]: \(result.message)", isSuccess: false)
                }
            } catch {
                addLog("Execution error: \(error.localizedDescription)", isSuccess: false)
            }
            isExecuting = false
        }
    }

    // MARK: - Live Log Feed

    private var logFeedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ACTIVITY LOG")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !statusLogs.isEmpty {
                    Button("Clear") {
                        statusLogs.removeAll()
                    }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if statusLogs.isEmpty {
                Text("No recent activity")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(statusLogs) { entry in
                        HStack(alignment: .top, spacing: 4) {
                            Circle()
                                .fill(entry.isSuccess ? Color.green : Color.red)
                                .frame(width: 5, height: 5)
                                .padding(.top, 3)

                            Text(entry.text)
                                .font(.system(size: 10))
                                .foregroundStyle(entry.isSuccess ? Color.primary : Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private func addLog(_ message: String, isSuccess: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            statusLogs.insert(AutopilotLogEntry(text: message, isSuccess: isSuccess), at: 0)
            if statusLogs.count > 25 {
                statusLogs.removeLast()
            }
        }
    }
}

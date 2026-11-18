//
//  AutopilotRailView.swift
//  dino
//
//  Created for Dino Browser.
//  In-app Autonomous Copilot & Assistant Drawer (⌘⇧A).
//  Supports dual-mode autonomous actions, live ReAct thought streaming,
//  non-stealing virtual mouse tracking, zero-token playbooks, and HITL safety gates.
//

import SwiftUI
import AppKit

struct AutopilotRailView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject private var runtime = DinoAgentRuntime.shared
    @ObservedObject private var playbookManager = AgentPlaybookManager.shared
    @ObservedObject private var settings = SettingsStore.shared
    private let vault = DinoModelVault.shared

    @State private var instructionInput: String = ""
    @State private var hitlInput: String = ""
    @State private var isShowingKeyModal: Bool = false
    @State private var tempAPIKey: String = ""
    @State private var newPlaybookName: String = ""
    @State private var isReplayingPlaybook: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    modelSelectorCard
                    activeTabContextCard

                    if case .waitingHITL(let reason, let question) = runtime.status {
                        hitlInterventionCard(reason: reason, question: question)
                    }

                    autonomousExecutionCard

                    macroPlaybooksSection
                    stepHistorySection
                }
                .padding(14)
            }
        }
        .frame(width: 330)
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
        .sheet(isPresented: $isShowingKeyModal) {
            apiKeyModalView
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(settings.accentColor)

            Text("Dino Copilot")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if runtime.status.isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Step \(runtime.stepCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12), in: Capsule())
            }

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
            .help("Close Copilot Drawer (⌘⇧A)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Model Selector Card

    private var modelSelectorCard: some View {
        HStack {
            Menu {
                ForEach(DinoModelProvider.allCases) { provider in
                    Button(action: {
                        vault.activeProvider = provider
                    }) {
                        HStack {
                            Text(provider.displayName)
                            if vault.activeProvider == provider {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                    Text(vault.activeProvider.displayName)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)

            Spacer()

            if vault.activeProvider.requiresAPIKey {
                let hasKey = vault.key(for: vault.activeProvider) != nil
                Button(action: {
                    tempAPIKey = vault.key(for: vault.activeProvider) ?? ""
                    isShowingKeyModal = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: hasKey ? "key.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(hasKey ? Color.green : Color.orange)
                        Text(hasKey ? "Key Set" : "Add Key")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(hasKey ? Color.secondary : Color.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(hasKey ? Color.primary.opacity(0.04) : Color.orange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Active Tab Context

    private var activeTabContextCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TARGET PAGE")
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
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - HITL Intervention Card

    private func hitlInterventionCard(reason: String, question: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Text("Human Confirmation Needed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Text(question ?? reason)
                .font(.system(size: 11))
                .foregroundStyle(.primary)

            if question != nil {
                HStack(spacing: 6) {
                    TextField("Your answer...", text: $hitlInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    Button("Submit") {
                        let text = hitlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        hitlInput = ""
                        runtime.resolveHITL(with: text)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Approve Action") {
                        runtime.resolveHITL()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)

                    Button("Abort") {
                        runtime.abort()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Autonomous Execution Card

    private var autonomousExecutionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUTONOMOUS ACTION")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("e.g. Fill this form with my resume details", text: $instructionInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(runtime.status.isRunning)
                    .onSubmit {
                        submitInstruction()
                    }

                if runtime.status.isRunning {
                    Button(action: { runtime.abort() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop execution")
                } else {
                    Button(action: submitInstruction) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(settings.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(instructionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            // Quick suggestion chips
            if !runtime.status.isRunning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        suggestionChip("Fill form")
                        suggestionChip("Summarize page")
                        suggestionChip("Find checkout button")
                        suggestionChip("Extract table")
                    }
                }
            }

            // Live Thought Stream Bubble
            if !runtime.currentThought.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if runtime.status.isRunning {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 9))
                                .foregroundStyle(settings.accentColor)
                        }
                        Text(runtime.status.isRunning ? "Dino is thinking..." : "Reasoning")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(runtime.currentThought)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func suggestionChip(_ label: String) -> some View {
        Button(action: {
            instructionInput = label
            submitInstruction()
        }) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func submitInstruction() {
        let text = instructionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let tab = store.activeTab else { return }

        if vault.activeProvider.requiresAPIKey && vault.key(for: vault.activeProvider) == nil {
            tempAPIKey = ""
            isShowingKeyModal = true
            return
        }

        instructionInput = ""
        runtime.startTask(goal: text, tab: tab)
    }

    // MARK: - Macro Playbooks Section

    private var macroPlaybooksSection: some View {
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
                        _ = playbookManager.stopRecording()
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
                        newPlaybookName = ""
                    }
                    .controlSize(.small)
                }
            }

            // Saved playbooks list
            let names = playbookManager.savedPlaybookNames
            if !names.isEmpty {
                VStack(spacing: 4) {
                    ForEach(names, id: \.self) { name in
                        HStack {
                            Text(name)
                                .font(.system(size: 11))
                                .lineLimit(1)

                            Spacer()

                            Button(action: {
                                guard let tab = store.activeTab,
                                      let actions = playbookManager.load(name: name) else { return }
                                Task {
                                    isReplayingPlaybook = name
                                    _ = try? await playbookManager.replay(actions: actions, on: tab)
                                    isReplayingPlaybook = nil
                                }
                            }) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                playbookManager.delete(name: name)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Step History Section

    private var stepHistorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STEP HISTORY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !runtime.stepLogs.isEmpty {
                    Text("\(runtime.stepLogs.count) steps")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            if runtime.stepLogs.isEmpty {
                Text("No actions taken yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(runtime.stepLogs) { log in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(log.stepNumber).")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .leading)

                            Circle()
                                .fill(log.isSuccess ? Color.green : Color.red)
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.actionDescription)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(log.isSuccess ? Color.primary : Color.red)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    // MARK: - API Key Configuration Modal

    private var apiKeyModalView: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "key.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(settings.accentColor)

                Text("Configure \(vault.activeProvider.displayName)")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button("Done") {
                    isShowingKeyModal = false
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key (Stored in macOS Keychain)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                SecureField("Enter API Key...", text: $tempAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                Text("Your key is stored hardware-encrypted in your Mac's Keychain and never leaves your computer.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                if vault.key(for: vault.activeProvider) != nil {
                    Button("Remove Key", role: .destructive) {
                        vault.deleteKey(for: vault.activeProvider)
                        tempAPIKey = ""
                        isShowingKeyModal = false
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button("Save Key") {
                    vault.saveKey(tempAPIKey, for: vault.activeProvider)
                    isShowingKeyModal = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

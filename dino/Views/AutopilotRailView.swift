//
//  AutopilotRailView.swift
//  dino
//
//  Created for Dino Browser.
//  In-app Autonomous Copilot & Assistant Docked Card.
//  Terax-inspired floating UI: sleek model picker, 3 suggestion cards,
//  clean chat stream, and unified composer with Keychain-backed model keys.
//

import SwiftUI
import AppKit

struct AutopilotRailView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject private var runtime = DinoAgentRuntime.shared
    @ObservedObject private var settings = SettingsStore.shared
    private let vault = DinoModelVault.shared

    @State private var instructionInput: String = ""
    @State private var hitlInput: String = ""
    @State private var isShowingKeyModal: Bool = false
    @State private var tempAPIKey: String = ""
    @State private var hoveredCardIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            topHeaderBar

            Divider()
                .background(Color.white.opacity(0.08))

            if runtime.messages.isEmpty {
                welcomeEmptyState
            } else {
                conversationFeedView
            }

            Divider()
                .background(Color.white.opacity(0.08))

            bottomComposerBar
        }
        .frame(width: 390, height: 510)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0x18181B, opacity: 0.94))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.42), radius: 24, x: 0, y: 12)
        .sheet(isPresented: $isShowingKeyModal) {
            apiKeyModalView
        }
    }

    // MARK: - Top Header Bar (Terax Style: Model Pill, Key Badge, New Chat, Close)

    private var topHeaderBar: some View {
        HStack(spacing: 8) {
            // Model Selector Dropdown Pill
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
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(vault.activeProvider.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)

            // Keychain Key Status Badge
            if vault.activeProvider.requiresAPIKey {
                let hasKey = vault.key(for: vault.activeProvider) != nil
                Button(action: {
                    tempAPIKey = vault.key(for: vault.activeProvider) ?? ""
                    isShowingKeyModal = true
                }) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(hasKey ? Color.green : Color.orange)
                            .frame(width: 5, height: 5)

                        Text(hasKey ? "Key Set" : "Add Key")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(hasKey ? Color.secondary : Color.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(hasKey ? "API Key is set in Keychain. Click to change." : "Click to enter your API key")
            }

            Spacer()

            // Status Indicator (Running / Idle)
            if runtime.status.isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Step \(runtime.stepCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12), in: Capsule())
            }

            // New Chat Button
            Button(action: {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    runtime.clearSession()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("New chat")
                        .font(.system(size: 11, weight: .regular))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Start new chat session")

            // Close Button
            Button(action: {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    store.isAutopilotRailVisible = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close (⌘⇧A)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Welcome Empty State (Exact Match to Terax Visual Layout)

    private var welcomeEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            // Dino Squircle Mark & Title Header
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 3)

                    if let mark = NSImage(named: "DinoMark") {
                        Image(nsImage: mark)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(hex: 0x82A8BE, opacity: 1.0))
                    }
                }

                Text("Ask Dino anything")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Dino sees the active tab — web content,\nforms, and interactive controls.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // 3 Clean Suggestion Cards (Terax-style)
            VStack(spacing: 8) {
                suggestionCard(
                    index: 0,
                    icon: "magnifyingglass",
                    title: "Navigate & search",
                    subtitle: "Open YouTube and search barse nair",
                    prompt: "Open YouTube and search barse nair"
                )

                suggestionCard(
                    index: 1,
                    icon: "pencil.and.list.clipboard",
                    title: "Fill form",
                    subtitle: "Auto-detect and fill inputs on this page",
                    prompt: "Inspect this page and help me fill out the form fields"
                )

                suggestionCard(
                    index: 2,
                    icon: "sparkles",
                    title: "Summarize page",
                    subtitle: "Extract key takeaways and insights",
                    prompt: "Summarize this page into key takeaways and action items"
                )
            }
            .padding(.horizontal, 14)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func suggestionCard(index: Int, icon: String, title: String, subtitle: String, prompt: String) -> some View {
        Button(action: {
            submitInstruction(prompt)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 30, height: 30)

                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hoveredCardIndex == index ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredCardIndex = isHovered ? index : nil
        }
    }

    // MARK: - Conversation Feed View (Active Chat State)

    private var conversationFeedView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(runtime.messages) { message in
                        chatBubble(for: message)
                            .id(message.id)
                    }

                    // Live Thinking Stream Bubble
                    if runtime.status.isRunning {
                        HStack(alignment: .top, spacing: 8) {
                            ProgressView()
                                .controlSize(.mini)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dino is thinking...")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                if !runtime.currentThought.isEmpty {
                                    Text(runtime.currentThought)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .id("thinking_indicator")
                    }

                    // HITL Human Intervention Gate
                    if case .waitingHITL(let reason, let question) = runtime.status {
                        hitlInterventionCard(reason: reason, question: question)
                            .id("hitl_card")
                    }
                }
                .padding(12)
            }
            .onChange(of: runtime.messages.count) { _, _ in
                if let last = runtime.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: runtime.currentThought) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("thinking_indicator", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func chatBubble(for message: AgentChatMessage) -> some View {
        switch message.sender {
        case .user:
            HStack {
                Spacer()
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(settings.accentColor)
                    )
            }

        case .action:
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.green)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)

                    if let details = message.details, !details.isEmpty {
                        Text(details)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .agent:
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 22, height: 22)

                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(settings.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .error:
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.top, 2)

                Text(message.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)

                Spacer()
            }
            .padding(8)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - HITL Human-In-The-Loop Card

    private func hitlInterventionCard(reason: String, question: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("Confirmation Needed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Text(question ?? reason)
                .font(.system(size: 11))
                .foregroundStyle(.primary)

            if question != nil {
                HStack(spacing: 6) {
                    TextField("Type your response...", text: $hitlInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .onSubmit {
                            submitHITL()
                        }

                    Button("Submit") {
                        submitHITL()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Approve") {
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
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func submitHITL() {
        let text = hitlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        hitlInput = ""
        runtime.resolveHITL(with: text.isEmpty ? nil : text)
    }

    // MARK: - Bottom Composer Bar (Terax Clean Input Box)

    private var bottomComposerBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Dino anything...", text: $instructionInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .disabled(runtime.status.isRunning)
                .onSubmit {
                    submitInstruction()
                }

            if runtime.status.isRunning {
                Button(action: {
                    runtime.abort()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 22, height: 22)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop execution")
            } else {
                let canSend = !instructionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button(action: {
                    submitInstruction()
                }) {
                    ZStack {
                        Circle()
                            .fill(canSend ? settings.accentColor : Color.white.opacity(0.10))
                            .frame(width: 22, height: 22)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(canSend ? Color.white : Color.white.opacity(0.35))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send instruction")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Mission Dispatch

    private func submitInstruction(_ customText: String? = nil) {
        let text = (customText ?? instructionInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Guarantee an active tab exists (prevent silent Enter failure on blank window)
        let tab: Tab
        if let active = store.activeTab {
            tab = active
        } else {
            tab = store.newTab(url: nil, select: true)
        }

        // Check if API key is required and missing
        if vault.activeProvider.requiresAPIKey && vault.key(for: vault.activeProvider) == nil {
            tempAPIKey = ""
            isShowingKeyModal = true
            return
        }

        instructionInput = ""
        runtime.startTask(goal: text, tab: tab)
    }

    // MARK: - API Key Configuration Modal (Hardware Keychain Backed)

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
                    .foregroundStyle(.secondary)
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
                    let trimmed = tempAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        vault.saveKey(trimmed, for: vault.activeProvider)
                    }
                    isShowingKeyModal = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(tempAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

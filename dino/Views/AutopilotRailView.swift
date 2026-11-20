//
//  AutopilotRailView.swift
//  dino
//
//  Created for Dino Browser.
//  In-app Autonomous Copilot & Assistant Docked Card.
//  Firn design tokens: mathematical paired-grey palette, editorial typography,
//  zero AI slop, native tab context awareness, and private local model key vault.
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
    @State private var hoveredActionIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            topHeaderBar

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            if runtime.messages.isEmpty {
                restingCanvasState
            } else {
                conversationFeedView
            }

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            bottomComposerBar
        }
        .frame(width: 380, height: 480)
        .background {
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .fill(Theme.page.opacity(0.96))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 24, y: 8)
        .shadow(color: Color.black.opacity(0.20), radius: 3, y: 1)
    }

    // MARK: - Top Header Bar (Firn Paired-Grey Style)

    private var topHeaderBar: some View {
        HStack(spacing: 8) {
            // Chats Menu (New chat ⌵ / Chat History & Ops)
            Menu {
                Button(action: {
                    withAnimation(Theme.glide) {
                        runtime.newSession()
                    }
                }) {
                    Label("New Chat", systemImage: "plus")
                }

                if !runtime.sessions.isEmpty {
                    Divider()
                    ForEach(runtime.sessions) { session in
                        Button(action: {
                            withAnimation(Theme.glide) {
                                runtime.selectSession(session)
                            }
                        }) {
                            HStack {
                                Text(session.title)
                                if runtime.activeSessionId == session.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()
                    Button(role: .destructive, action: {
                        withAnimation(Theme.glide) {
                            if let activeId = runtime.activeSessionId {
                                runtime.deleteSession(id: activeId)
                            } else {
                                runtime.clearSession()
                            }
                        }
                    }) {
                        Label("Delete Current Chat", systemImage: "trash")
                    }

                    Button(role: .destructive, action: {
                        withAnimation(Theme.glide) {
                            runtime.clearAllSessions()
                        }
                    }) {
                        Label("Clear All Chats", systemImage: "trash.fill")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)

                    Text(currentSessionLabel)
                        .font(Theme.font(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
                )
            }
            .menuStyle(.borderlessButton)
            .help("Chat sessions & operations")

            // Status Indicator (Step count when running)
            if runtime.status.isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: 0x8FAE8B))
                        .frame(width: 5, height: 5)
                    Text("Step \(runtime.stepCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(hex: 0x8FAE8B).opacity(0.12), in: Capsule())
            }

            Spacer()

            // Quick New Chat Button
            Button(action: {
                withAnimation(Theme.glide) {
                    runtime.newSession()
                }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 20, height: 20)
                    .background(Theme.hover, in: Circle())
            }
            .buttonStyle(.plain)
            .help("New chat")

            // Minimize Button
            Button(action: {
                withAnimation(Theme.glide) {
                    store.isAutopilotMinimized = true
                }
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 20, height: 20)
                    .background(Theme.hover, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Minimize (Click outside also minimizes)")

            // Close Button
            Button(action: {
                withAnimation(Theme.glide) {
                    store.isAutopilotRailVisible = false
                    store.isAutopilotMinimized = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 20, height: 20)
                    .background(Theme.hover, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close Agent (⌘⇧A)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var currentSessionLabel: String {
        if let id = runtime.activeSessionId,
           let session = runtime.sessions.first(where: { $0.id == id }) {
            return session.title.isEmpty ? "Chat" : String(session.title.prefix(16))
        }
        return "New chat"
    }

    // MARK: - Resting Canvas State (Editorial, Clean, Firn-Native)

    private var restingCanvasState: some View {
        VStack(spacing: 16) {
            Spacer()

            // Header: Dino Mark & Typography
            VStack(spacing: 8) {
                if let mark = NSImage(named: "DinoMark") {
                    Image(nsImage: mark)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .shadow(color: Color(hex: 0x023121, opacity: 0.25), radius: 6, y: 2)
                }

                Text("Agent")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)

                // Missing API key prompt if not configured
                if vault.activeProvider.requiresAPIKey && !vault.hasKey(for: vault.activeProvider) {
                    Button(action: {
                        store.openSettings(section: "Agent")
                    }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: 0xD69268))
                                .frame(width: 5, height: 5)
                            Text("Configure \(vault.activeProvider.displayName) key in Settings")
                                .font(Theme.font(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: 0xD69268))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0xD69268).opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Active Site Context Line
                let activeSite = store.activeTab?.url.flatMap { WebAddress.site(of: $0) }
                if let site = activeSite, !site.isEmpty && site != "about:blank" {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 9))
                        Text(site)
                            .font(Theme.font(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.hover, in: Capsule())
                } else {
                    Text("Automate, inspect, or summarize web pages.")
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.faint)
                }
            }

            // Clean Minimal Action Rows (Matching Dino Command Palette)
            VStack(spacing: 3) {
                let isBlank = store.activeTab?.isBlank ?? true
                if isBlank {
                    actionRow(
                        index: 0,
                        icon: "magnifyingglass",
                        title: "Search the web",
                        hint: "Google / DuckDuckGo",
                        prompt: "Open DuckDuckGo and search for "
                    )
                    actionRow(
                        index: 1,
                        icon: "arrow.up.right",
                        title: "Navigate to site",
                        hint: "Enter any URL",
                        prompt: "Navigate to "
                    )
                } else {
                    actionRow(
                        index: 0,
                        icon: "doc.text.magnifyingglass",
                        title: "Summarize this page",
                        hint: "Key points & takeaways",
                        prompt: "Summarize the key information and takeaways on this page"
                    )
                    actionRow(
                        index: 1,
                        icon: "square.and.pencil",
                        title: "Fill form fields",
                        hint: "Auto-detect inputs",
                        prompt: "Inspect the form fields on this page and help me fill them"
                    )
                    actionRow(
                        index: 2,
                        icon: "tablecells",
                        title: "Extract structured data",
                        hint: "Tables & lists",
                        prompt: "Extract the primary data or tables from this page into structured text"
                    )
                }
            }
            .padding(.horizontal, 14)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionRow(index: Int, icon: String, title: String, hint: String, prompt: String) -> some View {
        Button(action: {
            submitInstruction(prompt)
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 16)

                Text(title)
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.ink)

                Spacer()

                Text(hint)
                    .font(Theme.font(size: 10.5))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(hoveredActionIndex == index ? Theme.press : Theme.hover.opacity(0.4))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredActionIndex = isHovered ? index : nil
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

                    // Live Thinking Stream
                    if runtime.status.isRunning {
                        HStack(alignment: .top, spacing: 8) {
                            ProgressView()
                                .controlSize(.mini)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Thinking...")
                                    .font(Theme.font(size: 10.5, weight: .medium))
                                    .foregroundStyle(Theme.muted)

                                if !runtime.currentThought.isEmpty {
                                    Text(runtime.currentThought)
                                        .font(Theme.font(size: 11))
                                        .foregroundStyle(Theme.faint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.hover, in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
                        .id("thinking_indicator")
                    }

                    // HITL Human-In-The-Loop Safety Gate
                    if case .waitingHITL(let reason, let question) = runtime.status {
                        hitlInterventionCard(reason: reason, question: question)
                            .id("hitl_card")
                    }
                }
                .padding(12)
            }
            .onChange(of: runtime.messages.count) { _, _ in
                if let last = runtime.messages.last {
                    withAnimation(Theme.glide) {
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
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Theme.frame)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
                    )
            }

        case .action:
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.text)
                        .font(Theme.font(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)

                    if let details = message.details, !details.isEmpty {
                        Text(details)
                            .font(Theme.font(size: 10))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

        case .agent:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                    Text("Copilot")
                        .font(Theme.font(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }

                Text(message.text)
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.frame.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))

        case .error:
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0xD69268))
                    .padding(.top, 2)

                Text(message.text)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Color(hex: 0xD69268))

                Spacer()
            }
            .padding(8)
            .background(Color(hex: 0xD69268).opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: - HITL Human-In-The-Loop Card

    private func hitlInterventionCard(reason: String, question: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0xD69268))
                Text("Confirmation Required")
                    .font(Theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xD69268))
            }

            Text(question ?? reason)
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.ink)

            if question != nil {
                HStack(spacing: 6) {
                    TextField("Type your response...", text: $hitlInput)
                        .textFieldStyle(.plain)
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.ink)
                        .padding(6)
                        .background(Theme.frame, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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

                    Button("Abort") {
                        runtime.abort()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color(hex: 0xD69268).opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .strokeBorder(Color(hex: 0xD69268).opacity(0.35), lineWidth: 0.5)
        )
    }

    private func submitHITL() {
        let text = hitlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        hitlInput = ""
        runtime.resolveHITL(with: text.isEmpty ? nil : text)
    }

    // MARK: - Bottom Composer Bar (Matching Dino Address Bar / Find Bar)

    private var bottomComposerBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Agent to do something on this page...", text: $instructionInput)
                .textFieldStyle(.plain)
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.ink)
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
                            .fill(Color(hex: 0xD69268))
                            .frame(width: 22, height: 22)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.ink)
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
                            .fill(canSend ? Theme.ink : Theme.hover)
                            .frame(width: 22, height: 22)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(canSend ? Theme.page : Theme.faint)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send instruction")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .fill(Theme.frame)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Mission Dispatch

    private func submitInstruction(_ customText: String? = nil) {
        let text = (customText ?? instructionInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Guarantee active tab exists
        let tab: Tab
        if let active = store.activeTab {
            tab = active
        } else {
            tab = store.newTab(url: nil, select: true)
        }

        // Check API key requirement
        if vault.activeProvider.requiresAPIKey && !vault.hasKey(for: vault.activeProvider) {
            store.openSettings(section: "Agent")
            return
        }

        instructionInput = ""
        runtime.startTask(goal: text, tab: tab)
    }
}

// MARK: - Minimized Floating Corner Button

struct AutopilotMinimizedButton: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject private var runtime = DinoAgentRuntime.shared
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            withAnimation(Theme.glide) {
                store.isAutopilotMinimized = false
            }
        }) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Theme.page.opacity(0.96))
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(isHovered ? Theme.accent.opacity(0.6) : Theme.activeTabHairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.24), radius: 10, y: 4)
                    .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)

                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(runtime.status.isRunning ? Theme.accent : Theme.ink)
                    .frame(width: 44, height: 44)

                if runtime.status.isRunning {
                    Circle()
                        .fill(Color(hex: 0x8FAE8B))
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle()
                                .stroke(Theme.page, lineWidth: 1.5)
                        )
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(runtime.status.isRunning ? "Dino Agent is driving (Step \(runtime.stepCount)) — Click to expand" : "Dino Agent (⌘⇧A) — Click to expand")
    }
}

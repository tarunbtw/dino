//
//  AutopilotRailView.swift
//  dino
//
//  Floating Agent chat rail styled in Chromium Dark Mode + HeroUI tokens.
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

    private static let alertCoral = Color(hex: 0xF28B82)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        VStack(spacing: 0) {
            topHeaderBar

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            if runtime.messages.isEmpty {
                restingCanvasState
            } else {
                conversationFeedView
            }

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            bottomComposerBar
        }
        .frame(width: 372, height: 468)
        .background(shape.fill(Theme.surface))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.borderHover, lineWidth: 1))
        .shadow(color: Theme.shadowPeek, radius: 24, y: 10)
        .shadow(color: Theme.shadowSoft, radius: 4, y: 2)
    }

    // MARK: - Top Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 8) {
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
                        Label("Delete Chat", systemImage: "trash")
                    }

                    Button(role: .destructive, action: {
                        withAnimation(Theme.glide) {
                            runtime.clearAllSessions()
                        }
                    }) {
                        Label("Clear All", systemImage: "trash.fill")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)

                    Text(currentSessionLabel)
                        .font(Theme.font(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.surfaceHover, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .help("Chat history")

            if runtime.status.isRunning {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                    Text("Step \(runtime.stepCount)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.accentFaint, in: Capsule())
            }

            Spacer()

            headerIconButton(icon: "plus", help: "New chat") {
                withAnimation(Theme.glide) {
                    runtime.newSession()
                }
            }

            headerIconButton(icon: "minus", help: "Minimize") {
                withAnimation(Theme.glide) {
                    store.isAutopilotMinimized = true
                }
            }

            headerIconButton(icon: "xmark", help: "Close (⌘⇧A)") {
                withAnimation(Theme.glide) {
                    store.isAutopilotRailVisible = false
                    store.isAutopilotMinimized = false
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func headerIconButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 24, height: 24)
                .background(Theme.hover, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var currentSessionLabel: String {
        if let id = runtime.activeSessionId,
           let session = runtime.sessions.first(where: { $0.id == id }) {
            return session.title.isEmpty ? "Chat" : String(session.title.prefix(18))
        }
        return "New chat"
    }

    // MARK: - Resting State

    private var restingCanvasState: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 8) {
                Text("Agent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Text("\(vault.activeProvider.displayName) · \(vault.selectedModel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)

                if vault.activeProvider.requiresAPIKey && !vault.hasKey(for: vault.activeProvider) {
                    Button(action: {
                        store.openSettings(section: "Agent")
                    }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Self.alertCoral)
                                .frame(width: 5, height: 5)
                            Text("Set \(vault.activeProvider.displayName) key")
                                .font(Theme.font(size: 11, weight: .medium))
                                .foregroundStyle(Self.alertCoral)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Self.alertCoral.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if let site = store.activeTab?.url.map({ WebAddress.site(of: $0) }),
                          !site.isEmpty && site != "about:blank" {
                    Text(site)
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Theme.page, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                }
            }

            VStack(spacing: 4) {
                let isBlank = store.activeTab?.isBlank ?? true
                if isBlank {
                    actionRow(
                        index: 0,
                        icon: "magnifyingglass",
                        title: "Search the web",
                        prompt: "Open DuckDuckGo and search for "
                    )
                    actionRow(
                        index: 1,
                        icon: "arrow.up.right",
                        title: "Navigate to site",
                        prompt: "Navigate to "
                    )
                } else {
                    actionRow(
                        index: 0,
                        icon: "doc.plaintext",
                        title: "Summarize page",
                        prompt: "Summarize the key information and takeaways on this page"
                    )
                    actionRow(
                        index: 1,
                        icon: "square.and.pencil",
                        title: "Fill form fields",
                        prompt: "Inspect the form fields on this page and help me fill them"
                    )
                    actionRow(
                        index: 2,
                        icon: "tablecells",
                        title: "Extract data",
                        prompt: "Extract the primary data or tables from this page into structured text"
                    )
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionRow(index: Int, icon: String, title: String, prompt: String) -> some View {
        Button(action: {
            submitInstruction(prompt)
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(hoveredActionIndex == index ? Theme.accent : Theme.muted)
                    .frame(width: 16)

                Text(title)
                    .font(Theme.font(size: 12.5))
                    .foregroundStyle(Theme.ink)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hoveredActionIndex == index ? Theme.muted : Theme.faint)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(hoveredActionIndex == index ? Theme.surfaceHover : Theme.page)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredActionIndex = isHovered ? index : nil
        }
    }

    // MARK: - Conversation Feed

    private enum FeedItem: Identifiable {
        case user(AgentChatMessage)
        case actionGroup(id: UUID, actions: [AgentChatMessage])
        case agent(AgentChatMessage)
        case error(AgentChatMessage)

        var id: UUID {
            switch self {
            case .user(let m): return m.id
            case .actionGroup(let id, _): return id
            case .agent(let m): return m.id
            case .error(let m): return m.id
            }
        }
    }

    private var groupedFeedItems: [FeedItem] {
        var items: [FeedItem] = []
        var pendingActions: [AgentChatMessage] = []
        var groupID: UUID? = nil

        for message in runtime.messages {
            if message.sender == .action {
                if pendingActions.isEmpty {
                    groupID = message.id
                }
                pendingActions.append(message)
            } else {
                if !pendingActions.isEmpty, let gid = groupID {
                    items.append(.actionGroup(id: gid, actions: pendingActions))
                    pendingActions.removeAll()
                    groupID = nil
                }
                switch message.sender {
                case .user: items.append(.user(message))
                case .agent: items.append(.agent(message))
                case .error: items.append(.error(message))
                case .action: break
                }
            }
        }

        if !pendingActions.isEmpty, let gid = groupID {
            items.append(.actionGroup(id: gid, actions: pendingActions))
        }

        return items
    }

    private var conversationFeedView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groupedFeedItems) { item in
                        switch item {
                        case .user(let message):
                            userChatBubble(message: message)
                                .id(message.id)
                        case .actionGroup(let id, let actions):
                            CollapsibleStepGroupView(
                                actions: actions,
                                isRunning: runtime.status.isRunning && runtime.messages.last?.sender == .action
                            )
                            .id(id)
                        case .agent(let message):
                            agentChatBubble(message: message)
                                .id(message.id)
                        case .error(let message):
                            errorChatBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if runtime.status.isRunning && (runtime.messages.last?.sender != .action) {
                        HStack(alignment: .top, spacing: 8) {
                            ProgressView()
                                .controlSize(.mini)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Thinking…")
                                    .font(Theme.font(size: 11, weight: .medium))
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
                        .background(Theme.page, in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                        .id("thinking_indicator")
                    }

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

    private func userChatBubble(message: AgentChatMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Spacer(minLength: 28)

            CopyButton(text: message.text)
                .padding(.top, 4)

            Text(message.text)
                .font(Theme.font(size: 12.5))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surfaceHover)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .textSelection(.enabled)
        }
    }

    private func agentChatBubble(message: AgentChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message.text)
                .font(Theme.font(size: 12.5))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            CopyButton(text: message.text)
        }
        .padding(10)
        .background(Theme.page, in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func errorChatBubble(message: AgentChatMessage) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Self.alertCoral)
                .padding(.top, 2)

            Text(message.text)
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Self.alertCoral)

            Spacer()
        }
        .padding(9)
        .background(Self.alertCoral.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Self.alertCoral.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - HITL Card

    private func hitlInterventionCard(reason: String, question: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Self.alertCoral)
                Text("Confirmation Required")
                    .font(Theme.font(size: 11.5, weight: .semibold))
                    .foregroundStyle(Self.alertCoral)
            }

            Text(question ?? reason)
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.ink)

            if question != nil {
                HStack(spacing: 6) {
                    TextField("Response…", text: $hitlInput)
                        .textFieldStyle(.plain)
                        .font(Theme.font(size: 11.5))
                        .foregroundStyle(Theme.ink)
                        .padding(6)
                        .background(Theme.page, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                        .onSubmit {
                            submitHITL()
                        }

                    Button("Submit") {
                        submitHITL()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Approve") {
                        runtime.resolveHITL()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
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
        .background(Self.alertCoral.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .strokeBorder(Self.alertCoral.opacity(0.35), lineWidth: 1)
        )
    }

    private func submitHITL() {
        let text = hitlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        hitlInput = ""
        runtime.resolveHITL(with: text.isEmpty ? nil : text)
    }

    // MARK: - Bottom Composer Bar

    private var bottomComposerBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Agent…", text: $instructionInput)
                .textFieldStyle(.plain)
                .font(Theme.font(size: 12.5))
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
                            .fill(Self.alertCoral)
                            .frame(width: 22, height: 22)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.frame)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                let canSend = !instructionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button(action: {
                    submitInstruction()
                }) {
                    ZStack {
                        Circle()
                            .fill(canSend ? Theme.accent : Theme.surfaceActive)
                            .frame(width: 22, height: 22)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(canSend ? Theme.frame : Theme.muted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .fill(Theme.page)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    // MARK: - Mission Dispatch

    private func submitInstruction(_ customText: String? = nil) {
        let text = (customText ?? instructionInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let tab: Tab
        if let active = store.activeTab {
            tab = active
        } else {
            tab = store.newTab(url: nil, select: true)
        }

        if vault.activeProvider.requiresAPIKey && !vault.hasKey(for: vault.activeProvider) {
            store.openSettings(section: "Agent")
            return
        }

        instructionInput = ""
        runtime.startTask(goal: text, tab: tab, store: store)
    }
}

// MARK: - Collapsible Step Group

struct CollapsibleStepGroupView: View {
    let actions: [AgentChatMessage]
    let isRunning: Bool
    @State private var isExpanded: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.accent)
                    }

                    let stepLabel = actions.count == 1 ? "1 step" : "\(actions.count) steps"
                    Text(isRunning ? "Step \(actions.count)…" : stepLabel)
                        .font(Theme.font(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.muted)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(index + 1).")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                                .frame(width: 14, alignment: .trailing)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.text)
                                    .font(Theme.font(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let details = action.details, !details.isEmpty {
                                    Text(details)
                                        .font(Theme.font(size: 10))
                                        .foregroundStyle(Theme.faint)
                                        .lineSpacing(2)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .fill(isHovered ? Theme.surfaceHover : Theme.page)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Copy Button

struct CopyButton: View {
    let text: String
    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation {
                    isCopied = false
                }
            }
        }) {
            HStack(spacing: 3) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isCopied ? Theme.accent : (isHovered ? Theme.ink : Theme.faint))

                if isCopied {
                    Text("Copied")
                        .font(Theme.font(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, isCopied ? 5 : 3)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovered ? Theme.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isCopied ? "Copied" : "Copy")
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
                    .fill(isHovered ? Theme.surfaceHover : Theme.surface)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(isHovered ? Theme.borderHover : Theme.border, lineWidth: 1)
                    )
                    .shadow(color: Theme.shadowPeek, radius: 10, y: 4)
                    .shadow(color: Theme.shadowSoft, radius: 2, y: 1)

                Image(systemName: "cpu")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(runtime.status.isRunning ? Theme.accent : Theme.ink)
                    .frame(width: 40, height: 40)

                if runtime.status.isRunning {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Theme.surface, lineWidth: 1.5)
                        )
                        .offset(x: -1, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .help(runtime.status.isRunning ? "Agent running (Step \(runtime.stepCount))" : "Agent (⌘⇧A)")
    }
}

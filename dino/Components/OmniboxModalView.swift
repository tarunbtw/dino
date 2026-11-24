//
//  OmniboxModalView.swift
//  dino
//
//  Firn-style Command Bar (⌘T, clicking + New tab, or clicking address bar).
//  Floats cleanly in the center of the window over a dimmed page with zero layout shift.
//

import SwiftUI
import AppKit

struct OmniboxModalView: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool
    var isEmbeddedStage: Bool = false
    @State private var text: String = ""
    @State private var selectedIndex: Int = 0
    @State private var liveSuggestions: [SearchSuggestion] = []
    @State private var suggestionTask: Task<Void, Never>? = nil
    @FocusState private var isFieldFocused: Bool
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var history = HistoryStore.shared

    struct CommandItem: Identifiable, Equatable {
        let id: String
        enum Kind { case search, action, url, tab, history }
        let kind: Kind
        let icon: String
        let title: String
        let hint: String
        let action: () -> Void

        static func == (lhs: CommandItem, rhs: CommandItem) -> Bool { lhs.id == rhs.id }
    }

    private var items: [CommandItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if store.isPickingSplit {
                var list: [CommandItem] = []
                for tab in store.openTabs where tab.id != store.splitPickAnchor?.id && !tab.isBlank {
                    list.append(CommandItem(
                        id: "tab:\(tab.id)",
                        kind: .tab,
                        icon: "arrow.right.circle",
                        title: tab.title.isEmpty ? (tab.url?.host ?? "Tab") : tab.title,
                        hint: "Open in Split",
                        action: {
                            if let anchor = store.splitPickAnchor {
                                store.openSplit(tab, beside: anchor, on: store.splitPickSide.other)
                            }
                        }
                    ))
                }
                return list
            }
            return []
        }
        let lower = trimmed.lowercased()
        var list: [CommandItem] = []
        var addedIDs: Set<String> = []

        func addUnique(_ item: CommandItem) {
            if addedIDs.insert(item.id).inserted {
                list.append(item)
            }
        }

        let isDirectAddress = URLParser.isAddress(trimmed)
        let searchURL = URL(string: "\(settings.searchEngineBaseURL)\(URLParser.encodeQueryComponent(trimmed))")

        if isDirectAddress {
            // 1. Direct URL Navigation takes priority for addresses like "google.com", "apple.com", "youtube.com"
            let candidate = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("dino://")) ? trimmed : "https://\(trimmed)"
            if let url = URL(string: candidate) {
                addUnique(CommandItem(
                    id: "url:\(candidate)",
                    kind: .url,
                    icon: "globe",
                    title: trimmed,
                    hint: store.isPickingSplit ? "Open in Split" : "Open Address",
                    action: { openURL(url) }
                ))
            }

            // 2. Fallback Search query
            addUnique(CommandItem(
                id: "search:\(trimmed)",
                kind: .search,
                icon: "magnifyingglass",
                title: trimmed,
                hint: store.isPickingSplit ? "Search in Split" : "Search \(settings.searchEngineName)",
                action: { if let u = searchURL { openURL(u) } }
            ))
        } else {
            // Check for Top Hit: navigation match from live suggestions or local history
            if !store.isPickingSplit, let navSuggestion = liveSuggestions.first(where: { $0.isNavigation && $0.url != nil }) {
                if let url = navSuggestion.url {
                    let displayTitle = navSuggestion.title ?? navSuggestion.text
                    let hostHint = url.host ?? ""
                    addUnique(CommandItem(
                        id: "tophit:\(url.absoluteString)",
                        kind: .url,
                        icon: "globe",
                        title: displayTitle,
                        hint: hostHint.isEmpty ? "Top Hit" : "Top Hit — \(hostHint)",
                        action: { openURL(url) }
                    ))
                }
            } else if !store.isPickingSplit {
                let historyMatches = history.suggestions(for: trimmed, limit: 1)
                if let firstHist = historyMatches.first, let url = URL(string: firstHist.url) {
                    let displayTitle = firstHist.title.isEmpty ? firstHist.host : firstHist.title
                    addUnique(CommandItem(
                        id: "tophit:\(firstHist.url)",
                        kind: .url,
                        icon: "globe",
                        title: displayTitle,
                        hint: "Top Hit — \(firstHist.host)",
                        action: { openURL(url) }
                    ))
                }
            }

            // Normal keywords like "google", "apple", "news" take user to search query
            addUnique(CommandItem(
                id: "search:\(trimmed)",
                kind: .search,
                icon: "magnifyingglass",
                title: trimmed,
                hint: store.isPickingSplit ? "Search in Split" : "Search \(settings.searchEngineName)",
                action: { if let u = searchURL { openURL(u) } }
            ))
        }

        // Live Search Engine & Navigation Suggestions
        if !store.isPickingSplit {
            for suggestion in liveSuggestions where suggestion.text.lowercased() != lower {
                if suggestion.isNavigation, let targetURL = suggestion.url {
                    let displayTitle = suggestion.title ?? suggestion.text
                    addUnique(CommandItem(
                        id: "nav:\(targetURL.absoluteString)",
                        kind: .url,
                        icon: "globe",
                        title: displayTitle,
                        hint: store.isPickingSplit ? "Open in Split" : "Open Address",
                        action: { openURL(targetURL) }
                    ))
                } else {
                    let sURL = URL(string: "\(settings.searchEngineBaseURL)\(URLParser.encodeQueryComponent(suggestion.text))")
                    addUnique(CommandItem(
                        id: "sugg:\(suggestion.text)",
                        kind: .search,
                        icon: "magnifyingglass",
                        title: suggestion.text,
                        hint: "",
                        action: { if let u = sURL { openURL(u) } }
                    ))
                }
            }
        }

        // Matching History items
        if !store.isPickingSplit {
            let histItems = history.suggestions(for: trimmed, limit: 4)
            for item in histItems {
                if let url = URL(string: item.url) {
                    addUnique(CommandItem(
                        id: "hist:\(item.url)",
                        kind: .history,
                        icon: "clock.arrow.circlepath",
                        title: item.title.isEmpty ? item.host : item.title,
                        hint: item.host,
                        action: { openURL(url) }
                    ))
                }
            }
        }

        // Settings Action Row
        if "settings".contains(lower) || "preferences".contains(lower) || lower.contains("setting") {
            addUnique(CommandItem(
                id: "action:settings",
                kind: .action,
                icon: "command",
                title: "Settings",
                hint: "⌘,",
                action: {
                    store.openSettings()
                }
            ))
        }

        // Bar Actions (New Space, etc.)
        if "new space".contains(lower) {
            addUnique(CommandItem(
                id: "action:new-space",
                kind: .action,
                icon: "command",
                title: "New Space…",
                hint: "",
                action: {
                    store.createSpace(name: "New Space")
                }
            ))
        }

        // Matching open tabs
        for tab in store.tabs where !tab.isBlank && !tab.isGhost {
            if let anchor = store.splitPickAnchor, tab.id == anchor.id { continue }
            if tab.title.localizedCaseInsensitiveContains(lower) || (tab.url?.absoluteString.localizedCaseInsensitiveContains(lower) ?? false) {
                addUnique(CommandItem(
                    id: "tab:\(tab.id)",
                    kind: .tab,
                    icon: "arrow.right.circle",
                    title: tab.title.isEmpty ? (tab.url?.host ?? "Tab") : tab.title,
                    hint: store.isPickingSplit ? "Open in Split" : "Switch to Tab",
                    action: {
                        if let anchor = store.splitPickAnchor {
                            store.openSplit(tab, beside: anchor, on: store.splitPickSide.other)
                        } else {
                            store.selectTab(id: tab.id)
                        }
                    }
                ))
                if list.count >= 8 { break }
            }
        }

        return Array(list.prefix(8))
    }

    var body: some View {
        let rows = items
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if isEmbeddedStage {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isFieldFocused = false }
                } else {
                    // Dimming backdrop clipped strictly to concentric page geometry
                    let pageShape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
                    if !store.isPickingSplit {
                        pageShape
                            .fill(Theme.commandDim)
                            .contentShape(pageShape)
                            .onTapGesture { dismiss() }
                    } else {
                        // In split pick mode, clicking outside the omnibox commits the split with a new blank tab
                        pageShape
                            .fill(Color.clear)
                            .contentShape(pageShape)
                            .onTapGesture {
                                dismiss(cancelledByEscape: false)
                            }
                    }
                }

                // Centered modal card
                VStack(spacing: 0) {
                    // Search Field
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)

                        TextField("Search or enter address", text: $text)
                            .textFieldStyle(.plain)
                            .font(Theme.font(size: 16))
                            .foregroundStyle(Theme.ink)
                            .focused($isFieldFocused)
                            .onSubmit { submit(rows: rows) }
                            .onExitCommand { dismiss(cancelledByEscape: true) }
                            .onChange(of: text) { _, newText in
                                selectedIndex = 0
                                suggestionTask?.cancel()
                                guard SearchSuggestions.mayAsk(about: newText), !store.isPickingSplit else {
                                    liveSuggestions = []
                                    return
                                }
                                suggestionTask = Task {
                                    try? await Task.sleep(nanoseconds: 100_000_000)
                                    guard !Task.isCancelled else { return }
                                    let results = await SearchSuggestions.fetch(newText, engine: settings.searchEngine)
                                    guard !Task.isCancelled else { return }
                                    await MainActor.run {
                                        self.liveSuggestions = results
                                    }
                                }
                            }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)

                    if !rows.isEmpty {
                        Rectangle()
                            .fill(Theme.activeTabHairline)
                            .frame(height: 0.5)
                            .padding(.horizontal, 12)

                        VStack(spacing: 2) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                let isSelected = index == selectedIndex
                                Button(action: {
                                    item.action()
                                    dismiss()
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 14))
                                            .frame(width: 16, height: 16)
                                            .foregroundStyle(Theme.muted)

                                        Text(item.title)
                                            .font(Theme.font(size: 13))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)

                                        Spacer(minLength: 12)

                                        if !item.hint.isEmpty {
                                            Text(item.hint)
                                                .font(Theme.font(size: 11))
                                                .foregroundStyle(Theme.faint)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? Theme.surfaceHover : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { isHover in
                                    if isHover { selectedIndex = index }
                                }
                            }
                        }
                        .padding(6)
                    }
                }
                .frame(width: store.isPickingSplit ? min(420, max(240, (proxy.size.width / 2) - 32)) : min(560, max(240, proxy.size.width - 64)))
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surface.opacity(isEmbeddedStage ? 0.90 : 1.0))
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.borderHover, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 24, y: 8)
                .shadow(color: Color.black.opacity(0.20), radius: 3, y: 1)
                .frame(maxWidth: .infinity)
                .padding(.leading, store.isPickingSplit ? (store.splitPickSide == .left ? (proxy.size.width / 2) : 0) : 0)
                .padding(.trailing, store.isPickingSplit ? (store.splitPickSide == .right ? (proxy.size.width / 2) : 0) : 0)
                .padding(.top, isEmbeddedStage ? max(48, (proxy.size.height - 48) * 0.42) : max(48, proxy.size.height * 0.22))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background {
            ArrowCatcher(
                onArrow: { offset in
                    let count = rows.count
                    guard count > 0 else { return }
                    selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
                },
                requireFieldEditorFocus: isEmbeddedStage
            )
        }
        .onAppear {
            selectedIndex = 0
            if !isEmbeddedStage && store.isEditingCurrentURL, let active = store.peekTab ?? store.activeTab, let url = active.url, !active.isBlank {
                text = url.absoluteString
            } else {
                text = ""
            }
            let canAutoFocus = !isEmbeddedStage || (
                settings.hasCompletedOnboarding &&
                settings.hasSeenQuickShortcutsCard &&
                !store.isShowingNewSpaceSheet &&
                !store.isShowingArcImportModal &&
                !store.isShowingExtensionsModal
            )
            if canAutoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFieldFocused = true
                    if !isEmbeddedStage && store.isEditingCurrentURL {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    }
                }
            }
        }
        .onChange(of: settings.hasSeenQuickShortcutsCard) { _, seen in
            if isEmbeddedStage && seen && settings.hasCompletedOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    isFieldFocused = true
                }
            }
        }
        .onMoveCommand { direction in
            let count = items.count
            guard count > 0 else { return }
            switch direction {
            case .up:
                selectedIndex = max(0, selectedIndex - 1)
            case .down:
                selectedIndex = min(count - 1, selectedIndex + 1)
            default:
                break
            }
        }
    }

    private func submit(rows: [CommandItem]) {
        if rows.indices.contains(selectedIndex) {
            rows[selectedIndex].action()
        } else if let first = rows.first {
            first.action()
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let target = URLParser.parse(trimmed)
                openURL(target)
            }
        }
        dismiss()
    }

    private func openURL(_ url: URL) {
        if let anchor = store.splitPickAnchor {
            let newT = store.newTab(url: url, select: false)
            store.openSplit(newT, beside: anchor, on: store.splitPickSide.other)
            return
        }
        if store.isEditingCurrentURL, let target = store.peekTab ?? store.activeTab {
            target.load(url: url)
        } else if let active = store.activeTab, active.isBlank {
            active.load(url: url)
        } else {
            store.newTab(url: url, select: true)
        }
    }

    private func dismiss(cancelledByEscape: Bool = false) {
        if isEmbeddedStage {
            text = ""
            liveSuggestions = []
            isFieldFocused = false
            return
        }
        store.isEditingCurrentURL = false
        if store.isPickingSplit {
            if cancelledByEscape {
                store.cancelSplitPick()
            } else {
                store.commitSplitPickWithNewTab(selectAnchor: false)
            }
        } else {
            isPresented = false
            store.isAddressBarFocused = false
        }
    }
}

/// Intercepts ↑, ↓, Tab, Shift+Tab, and optional Return while typing or navigating modals.
struct ArrowCatcher: NSViewRepresentable {
    let onArrow: (Int) -> Void
    var onReturn: (() -> Void)? = nil
    var requireFieldEditorFocus: Bool = false

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onArrow = onArrow
        view.onReturn = onReturn
        view.requireFieldEditorFocus = requireFieldEditorFocus
    }

    final class CatcherView: NSView {
        var onArrow: ((Int) -> Void)?
        var onReturn: (() -> Void)?
        var requireFieldEditorFocus: Bool = false
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let caught = MainActor.assumeIsolated { self?.catches(event) ?? false }
                return caught ? nil : event
            }
        }

        private func catches(_ event: NSEvent) -> Bool {
            guard let window, event.window === window,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return false
            }

            if requireFieldEditorFocus && (window.firstResponder as? NSTextView)?.isFieldEditor != true {
                return false
            }

            if (event.keyCode == 36 || event.keyCode == 76), let onReturn {
                onReturn()
                return true
            }

            let offset: Int
            if event.keyCode == 125 || event.keyCode == 48 { // Down arrow or Tab
                offset = (event.modifierFlags.contains(.shift) && event.keyCode == 48) ? -1 : 1
            } else if event.keyCode == 126 { // Up arrow
                offset = -1
            } else {
                offset = 0
            }
            guard offset != 0, let onArrow else { return false }
            onArrow(offset)
            return true
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

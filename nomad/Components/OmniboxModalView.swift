//
//  OmniboxModalView.swift
//  nomad
//
//  Firn-style Command Bar (⌘T, clicking + New tab, or clicking address bar).
//  Floats cleanly in the center of the window over a dimmed page with zero layout shift.
//

import SwiftUI
import AppKit

struct OmniboxModalView: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool
    @State private var text: String = ""
    @State private var selectedIndex: Int = 0
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
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var list: [CommandItem] = []

        // 1. Search Query Row (Row 1, matching Firn Image 2)
        let searchURL = URL(string: "\(settings.searchEngineBaseURL)\(URLParser.encodeQueryComponent(trimmed))")
        list.append(CommandItem(
            id: "search:\(trimmed)",
            kind: .search,
            icon: "magnifyingglass",
            title: trimmed,
            hint: "Search \(settings.searchEngineName)",
            action: {
                if let u = searchURL {
                    openURL(u)
                }
            }
        ))

        // 2. Settings Action Row (Row 2, matching Firn Image 2)
        if "settings".contains(lower) || "preferences".contains(lower) || lower.contains("setting") {
            list.append(CommandItem(
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

        // 3. Direct URL navigation if query looks like a host/URL
        if trimmed.contains(".") && !trimmed.contains(" ") {
            let candidate = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
            if let url = URL(string: candidate) {
                list.append(CommandItem(
                    id: "url:\(candidate)",
                    kind: .url,
                    icon: "globe",
                    title: trimmed,
                    hint: "Open Address",
                    action: {
                        openURL(url)
                    }
                ))
            }
        }

        // 4. Bar Actions (New Space, Reload, etc.)
        if "new space".contains(lower) {
            list.append(CommandItem(
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

        // 5. Matching open tabs
        for tab in store.tabs where !tab.isBlank && !tab.isGhost {
            if tab.title.localizedCaseInsensitiveContains(lower) || (tab.url?.absoluteString.localizedCaseInsensitiveContains(lower) ?? false) {
                list.append(CommandItem(
                    id: "tab:\(tab.id)",
                    kind: .tab,
                    icon: "globe",
                    title: tab.title.isEmpty ? (tab.url?.host ?? "Tab") : tab.title,
                    hint: "Switch to Tab",
                    action: {
                        store.selectTab(id: tab.id)
                    }
                ))
                if list.count >= 6 { break }
            }
        }

        return list
    }

    var body: some View {
        let rows = items
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Dimming backdrop
                Theme.commandDim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }

                // Centered modal card
                VStack(spacing: 0) {
                    // Search Field
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)

                        TextField("Search or enter address", text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.ink)
                            .focused($isFieldFocused)
                            .onSubmit { submit(rows: rows) }
                            .onExitCommand { dismiss() }
                            .onChange(of: text) {
                                selectedIndex = 0
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
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)

                                        Spacer(minLength: 12)

                                        if !item.hint.isEmpty {
                                            Text(item.hint)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Theme.faint)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? Theme.press : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                }
                .frame(width: min(560, max(0, proxy.size.width - 64)))
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.page)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 24, y: 8)
                .shadow(color: Color.black.opacity(0.20), radius: 3, y: 1)
                .padding(.top, max(48, proxy.size.height * 0.22))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            selectedIndex = 0
            text = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
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
                let parsed = URLParser.parse(trimmed)
                openURL(parsed)
            }
        }
        dismiss()
    }

    private func openURL(_ url: URL) {
        if let active = store.activeTab, active.isBlank {
            active.load(url: url)
        } else {
            store.newTab(url: url, select: true)
        }
    }

    private func dismiss() {
        isPresented = false
        store.isAddressBarFocused = false
    }
}

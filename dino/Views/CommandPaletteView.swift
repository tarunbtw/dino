//
//  CommandPaletteView.swift
//  dino
//
//  Floating Command Palette (⌘K) styled in Chromium Dark Mode + HeroUI tokens.
//

import SwiftUI
import AppKit

/// Item in the Command Palette (⌘K)
struct CommandItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let shortcut: String?
    let category: Category
    let action: @MainActor () -> Void

    enum Category: String, CaseIterable {
        case tabs = "Tabs"
        case actions = "Actions"
        case history = "Bookmarks"
    }

    static func == (lhs: CommandItem, rhs: CommandItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Floating Command Palette for Dino (⌘K).
struct CommandPaletteView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var ignoreHoverUntilPointerMoves: Bool = false
    @State private var lastPointerLocation: CGPoint? = nil
    @FocusState private var isFieldFocused: Bool

    private var allItems: [CommandItem] {
        var items: [CommandItem] = []

        // 1. Open Tabs
        for tab in store.tabs {
            let title = tab.title.isEmpty ? (tab.url?.host ?? "New Tab") : tab.title
            let subtitle = tab.url.map { WebAddress.site(of: $0) }
            items.append(CommandItem(
                id: "tab-\(tab.id.uuidString)",
                title: title,
                subtitle: (subtitle?.isEmpty ?? true) ? nil : subtitle,
                icon: tab.isIncognito ? "eye.slash" : "macwindow",
                shortcut: nil,
                category: .tabs,
                action: {
                    store.selectTab(id: tab.id)
                    onDismiss()
                }
            ))
        }

        // 2. Built-in Actions
        items.append(CommandItem(
            id: "act-devdrawer",
            title: "Developer Tools",
            subtitle: nil,
            icon: "curlybraces",
            shortcut: "⌘⌥I",
            category: .actions,
            action: {
                store.activeTab?.isDevDrawerVisible.toggle()
                onDismiss()
            }
        ))

        items.append(CommandItem(
            id: "act-zapper",
            title: "Element Zapper",
            subtitle: nil,
            icon: "wand.and.rays",
            shortcut: "⇧⌘H",
            category: .actions,
            action: {
                store.activeTab?.toggleElementZapper()
                onDismiss()
            }
        ))

        if let tab = store.activeTab, let host = tab.url?.host, ZapperStore.shared.count(for: host) > 0 {
            items.append(CommandItem(
                id: "act-unhide",
                title: "Unhide Elements on \(host)",
                subtitle: "\(ZapperStore.shared.count(for: host)) hidden",
                icon: "arrow.counterclockwise",
                shortcut: nil,
                category: .actions,
                action: {
                    tab.unhideAllZappedElements()
                    onDismiss()
                }
            ))
        }

        items.append(CommandItem(
            id: "act-reader",
            title: "Reading Mode",
            subtitle: nil,
            icon: "doc.plaintext",
            shortcut: "⇧⌘R",
            category: .actions,
            action: {
                store.activeTab?.toggleReaderMode()
                onDismiss()
            }
        ))

        items.append(CommandItem(
            id: "act-pip",
            title: "Picture-in-Picture",
            subtitle: nil,
            icon: "pip.enter",
            shortcut: "⇧⌘P",
            category: .actions,
            action: {
                store.activeTab?.togglePictureInPicture()
                onDismiss()
            }
        ))

        items.append(CommandItem(
            id: "act-newtab",
            title: "New Tab",
            subtitle: nil,
            icon: "plus",
            shortcut: "⌘T",
            category: .actions,
            action: {
                store.isAddressBarFocused = true
                onDismiss()
            }
        ))

        items.append(CommandItem(
            id: "act-newprivate",
            title: "New Private Tab",
            subtitle: nil,
            icon: "eye.slash",
            shortcut: "⇧⌘N",
            category: .actions,
            action: {
                store.newIncognitoTab()
                onDismiss()
            }
        ))

        items.append(CommandItem(
            id: "act-settings",
            title: "Settings",
            subtitle: nil,
            icon: "gearshape",
            shortcut: "⌘,",
            category: .actions,
            action: {
                store.openSettings()
                onDismiss()
            }
        ))

        // 3. Bookmarks
        for bm in settings.bookmarks {
            items.append(CommandItem(
                id: "bm-\(bm.id.uuidString)",
                title: bm.title,
                subtitle: bm.url,
                icon: "bookmark.fill",
                shortcut: nil,
                category: .history,
                action: {
                    if let url = URL(string: bm.url) {
                        store.activeTab?.load(url: url)
                    }
                    onDismiss()
                }
            ))
        }

        return items
    }

    private var filteredItems: [CommandItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return allItems
        }
        return allItems.filter {
            $0.title.lowercased().contains(q) ||
            ($0.subtitle?.lowercased().contains(q) ?? false) ||
            $0.category.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        let items = filteredItems
        let cardShape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)

        ZStack {
            Theme.commandDim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                // Search Header
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)

                    TextField("Search commands, tabs, or bookmarks…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Theme.ink)
                        .focused($isFieldFocused)

                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("⌘K")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceHover, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 14)
                .frame(height: 46)

                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)

                // Results List
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            if items.isEmpty {
                                Text("No matching commands")
                                    .font(Theme.font(size: 12.5))
                                    .foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    let isSelected = index == selectedIndex
                                    Button(action: { item.action() }) {
                                        HStack(spacing: 10) {
                                            Image(systemName: item.icon)
                                                .font(.system(size: 12.5, weight: .medium))
                                                .foregroundStyle(isSelected ? Theme.accent : Theme.muted)
                                                .frame(width: 20)

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(item.title)
                                                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                                                    .foregroundStyle(Theme.ink)
                                                    .lineLimit(1)

                                                if let sub = item.subtitle {
                                                    Text(sub)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(Theme.muted)
                                                        .lineLimit(1)
                                                }
                                            }

                                            Spacer(minLength: 12)

                                            if let sc = item.shortcut {
                                                Text(sc)
                                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                                    .foregroundStyle(Theme.muted)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Theme.surfaceActive, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                            } else {
                                                Text(item.category.rawValue)
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(Theme.faint)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .frame(height: item.subtitle == nil ? 34 : 42)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(isSelected ? Theme.surfaceHover : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .id(item.id)
                                    .onHover { hovering in
                                        if hovering && !ignoreHoverUntilPointerMoves {
                                            selectedIndex = index
                                        }
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onContinuousHover { phase in
                        if case .active(let loc) = phase {
                            if let prev = lastPointerLocation {
                                let moved = abs(loc.x - prev.x) > 1.5 || abs(loc.y - prev.y) > 1.5
                                if moved {
                                    ignoreHoverUntilPointerMoves = false
                                    lastPointerLocation = loc
                                }
                            } else {
                                lastPointerLocation = loc
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, idx in
                        if items.indices.contains(idx) {
                            proxy.scrollTo(items[idx].id)
                        }
                    }
                }
            }
            .frame(width: 520)
            .background(cardShape.fill(Theme.surface))
            .overlay(cardShape.strokeBorder(Theme.borderHover, lineWidth: 1))
            .clipShape(cardShape)
            .shadow(color: Theme.shadowPeek, radius: 24, y: 10)
            .shadow(color: Theme.shadowSoft, radius: 4, y: 2)
        }
        .background {
            ArrowCatcher(
                onArrow: { offset in
                    let count = items.count
                    guard count > 0 else { return }
                    ignoreHoverUntilPointerMoves = true
                    selectedIndex = (selectedIndex + offset + count) % count
                },
                onReturn: {
                    submitCurrentSelection()
                }
            )
        }
        .onAppear {
            selectedIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                isFieldFocused = true
            }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onExitCommand(perform: onDismiss)
    }

    private func submitCurrentSelection() {
        let items = filteredItems
        guard !items.isEmpty, items.indices.contains(selectedIndex) else { return }
        items[selectedIndex].action()
    }
}

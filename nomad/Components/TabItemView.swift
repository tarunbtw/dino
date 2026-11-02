//
//  TabItemView.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI
import AppKit
import WebKit

/// An individual tab pill in the tab bar.
/// Double-clicking expands the tab pill into an inline URL/search field.
/// Immediate sliding tab drag on any tab (active or inactive) without moving the window.
struct TabItemView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: Tab
    let isActive: Bool
    let isDragging: Bool
    let tabWidth: CGFloat
    let index: Int
    let count: Int
    let step: CGFloat
    let offsetX: CGFloat
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    @State private var isHovered: Bool = false
    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @State private var lastClickTime: TimeInterval = 0
    @FocusState private var isFieldFocused: Bool

    var body: some View {

        HStack(spacing: 0) {
            if isEditing {
                // Expanded URL Editing Mode
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)

                    TextField("Enter a web address", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .regular))
                        .focused($isFieldFocused)
                        .onSubmit {
                            submitEdit()
                        }
                        .onExitCommand {
                            cancelEdit()
                        }

                    Button(action: { cancelEdit() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            } else {
                // Standard Tab Pill Content
                HStack(spacing: 0) {
                    if tabWidth < 50 {
                        // Compact favicon-only mode (Close button when hovered)
                        ZStack {
                            if isHovered {
                                Button(action: { store.closeTab(id: tab.id) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18, height: 18)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Close Tab (⌘W)")
                            } else {
                                tabIconView
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Standard & Medium width mode
                        HStack(spacing: 6) {
                            tabIconView
                            tabTitleView
                        }
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tabWidth < 70 ? .center : .leading)

                        // Trailing controls (Ungroup button when split + Close button)
                        if isHovered || isActive {
                            HStack(spacing: 2) {
                                if isTabSplit {
                                    Button(action: {
                                        store.closeSplit(for: tab.id)
                                    }) {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 14, height: 16)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Separate Tabs (Ungroup)")
                                }

                                Button(action: {
                                    store.closeTab(id: tab.id)
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16, height: 16)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Close Tab (⌘W)")
                            }
                            .padding(.trailing, 6)
                        } else if tabWidth >= 70 {
                            Spacer().frame(width: 14)
                        }
                    }
                }
            }
        }
        .frame(height: 30)
        .frame(width: isEditing ? max(tabWidth, 280) : tabWidth)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isEditing ? Color.primary.opacity(0.4) : (isActive ? Color.primary.opacity(0.06) : Color.clear), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { isHovered = $0 }
        .offset(x: offsetX, y: 0)
        .zIndex(isDragging ? 100 : (isActive ? 1 : 0))
        .shadow(color: .black.opacity(isDragging ? 0.16 : 0), radius: 8, y: 2)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .gesture(
            isEditing ? nil :
            DragGesture(minimumDistance: 3, coordinateSpace: .named("TabStripSpace"))
                .onChanged { value in
                    onDragChanged(value.translation.width)
                }
                .onEnded { value in
                    onDragEnded(value.translation.width)
                }
        )
        .onTapGesture {
            guard !isEditing else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastClickTime < 0.35 {
                startEditing()
            } else {
                store.selectTab(id: tab.id)
            }
            lastClickTime = now
        }
        .contextMenu {
            if let split = store.splitPairs.first(where: { $0.contains(tab.id) }) {
                Button("Swap Split Panes") {
                    store.swapSplit(splitPairId: split.id)
                }
                Button("Separate Tabs (Ungroup)") {
                    store.closeSplit(for: tab.id)
                }
            } else {
                Button("Split with New Tab") {
                    store.splitCurrentTab()
                }

                let candidateTabs = store.tabs.filter { $0.id != tab.id && !$0.isPinned }
                if !candidateTabs.isEmpty {
                    Menu("Split with Tab") {
                        ForEach(candidateTabs) { other in
                            Button(other.title.isEmpty ? "Blank Tab" : other.title) {
                                store.splitTab(primaryId: tab.id, secondaryId: other.id)
                            }
                        }
                    }
                }
            }
            Divider()
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                store.togglePin(tabId: tab.id)
            }
            Button("Reload") {
                tab.reload()
            }
            Button("Duplicate Tab") {
                store.newTab(url: tab.url, isIncognito: tab.isIncognito, select: true)
            }
            Button("Close Other Tabs") {
                let others = store.tabs.filter { $0.id != tab.id }
                for other in others {
                    store.closeTab(id: other.id)
                }
            }
            Divider()
            Button("Close Tab") {
                store.closeTab(id: tab.id)
            }
        }

        .overlay(alignment: .topLeading) {
            if isEditing && !editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OmniboxSuggestionsView(query: editText, width: min(max(tabWidth, 280), 380)) { selectedURL in
                    tab.load(url: selectedURL)
                    cancelEdit()
                }
                .offset(y: 36)
                .zIndex(300)
            }
        }
        .onChange(of: isActive) { _, active in
            if !active && isEditing {
                cancelEdit()
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && isEditing {
                cancelEdit()
            }
        }
        .onChange(of: store.isAddressBarFocused) { _, focused in
            if focused && isActive && !tab.isBlank {
                startEditing()
                store.isAddressBarFocused = false
            }
        }
    }

    private var isTabSplit: Bool {
        store.splitPairs.contains { $0.contains(tab.id) }
    }

    @ViewBuilder
    private var tabTitleView: some View {
        if tabWidth >= 70 {
            Text(displayTitle)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isTabSplit {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 8.5))
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
        }
    }

    @ViewBuilder
    private var tabIconView: some View {
        if tab.isLoading {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.65)
                .frame(width: 14, height: 14)
        } else if tab.isIncognito && (tab.favicon == nil || tab.isBlank) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.purple.opacity(0.85))
                .frame(width: 14, height: 14)
        } else if let scheme = tab.url?.scheme, (scheme == ExtensionManager.scheme || scheme == "webkit-extension"),
                  let host = tab.url?.host,
                  let context = ExtensionManager.shared.contexts[host],
                  let icon = context.action(for: nil)?.icon(for: CGSize(width: 16, height: 16)) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else if let favicon = tab.favicon {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 14, height: 14)
        }
    }

    private var iconName: String {
        if tab.isInternalPage {
            return "gearshape.fill"
        }
        if tab.isIncognito {
            return "eye.slash.fill"
        }
        if let scheme = tab.url?.scheme, (scheme == ExtensionManager.scheme || scheme == "webkit-extension") {
            return "puzzlepiece.extension"
        }
        return tab.isBlank ? "sparkles" : "globe"
    }

    private var displayTitle: String {
        if tab.isInternalPage {
            return tab.title
        }
        if tab.isIncognito && (tab.url == nil || tab.isBlank) {
            return "Private Tab"
        }
        if let scheme = tab.url?.scheme, (scheme == ExtensionManager.scheme || scheme == "webkit-extension") {
            if let host = tab.url?.host, let ext = ExtensionManager.shared.installed.first(where: { $0.id == host }) {
                return ext.name
            }
            return tab.title
        }
        let trimmedTitle = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty && trimmedTitle != "New Tab" {
            return trimmedTitle
        }
        if let host = tab.url?.host, !host.isEmpty, !tab.isBlank {
            return host
        }
        return tab.isBlank ? "New Tab" : (trimmedTitle.isEmpty ? "New Tab" : trimmedTitle)
    }

    private func startEditing() {
        editText = tab.url?.absoluteString ?? (tab.title == "New Tab" ? "" : tab.title)
        isEditing = true
        DispatchQueue.main.async {
            isFieldFocused = true
        }
    }

    private func submitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let parsed = URLParser.parse(trimmed)
            if parsed.scheme == "nomad" && parsed.host == "settings" {
                store.openSettings()
            } else {
                tab.load(text: trimmed)
            }
        }
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }
}

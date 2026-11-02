//
//  VerticalSidebarView.swift
//  nomad
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit

/// Arc/Search-style vertical collapsible sidebar housing spaces, pinned tabs, and vertical tab rows.
struct VerticalSidebarView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore

    @State private var isHoveringNewSpace: Bool = false
    @State private var isShowingNewSpaceSheet: Bool = false
    @State private var newSpaceName: String = ""
    @State private var isDraggingSidebarWidth: Bool = false

    private var isCollapsed: Bool { settings.isSidebarCollapsed }
    private var sidebarWidth: CGFloat { isCollapsed ? 54 : CGFloat(settings.sidebarWidth) }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Traffic lights safe area + collapse toggle
            headerSection
                .frame(height: 48)

            // Spaces Switcher Bar
            spacesBarSection
                .padding(.horizontal, isCollapsed ? 6 : 10)
                .padding(.bottom, 6)

            // Pinned Tabs Shelf
            if !store.pinnedTabs.isEmpty {
                pinnedTabsSection
                    .padding(.horizontal, isCollapsed ? 6 : 10)
                    .padding(.bottom, 6)

                Divider()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }

            // Tabs List for Active Space
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(store.unpinnedTabsForActiveSpace) { tab in
                        VerticalTabRowView(
                            store: store,
                            tab: tab,
                            isActive: tab.id == store.activeTabId,
                            isCollapsed: isCollapsed
                        )
                    }
                }
                .padding(.horizontal, isCollapsed ? 6 : 8)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .padding(.horizontal, 10)

            // Footer Section (+ New Tab, Toggle Layout)
            footerSection
                .frame(height: 40)
                .padding(.horizontal, isCollapsed ? 6 : 10)
        }
        .frame(width: sidebarWidth)
        .background {
            if settings.isVibrant {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .trailing) {
            if !isCollapsed {
                sidebarResizeHandle
            }
        }
        .sheet(isPresented: $isShowingNewSpaceSheet) {
            newSpaceSheetView
        }
    }

    // MARK: - Header Section
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 6) {
            if !isCollapsed {
                // Window Drag Area for traffic lights
                WindowDragArea()
                    .frame(width: 72, height: 48)

                Spacer()
            }

            // Toggle Sidebar Collapse Button
            Button(action: {
                settings.toggleSidebarCollapsed()
            }) {
                Image(systemName: isCollapsed ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand Sidebar (⇧⌘S)" : "Collapse Sidebar (⇧⌘S)")

            if isCollapsed {
                // In collapsed mode, place Layout switch icon below
            } else {
                // Switch back to Horizontal Top Tabs
                Button(action: {
                    settings.toggleTabLayout()
                }) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Switch to Top Tab Strip (⌥⌘T)")
            }
        }
        .padding(.horizontal, isCollapsed ? 8 : 10)
    }

    // MARK: - Spaces Bar Section
    @ViewBuilder
    private var spacesBarSection: some View {
        if isCollapsed {
            // Collapsed: Small vertical dots/icons
            VStack(spacing: 4) {
                ForEach(store.spaces) { space in
                    let isCurrent = space.id == store.activeSpaceId
                    Button(action: { store.switchSpace(id: space.id) }) {
                        Circle()
                            .fill(Color(hex: space.colorHex) ?? settings.accentColor)
                            .frame(width: isCurrent ? 10 : 6, height: isCurrent ? 10 : 6)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Space: \(space.name)")
                }
            }
        } else {
            // Expanded: Horizontal scroll of space pills + add button
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.spaces) { space in
                        let isCurrent = space.id == store.activeSpaceId
                        let spaceColor = Color(hex: space.colorHex) ?? settings.accentColor

                        Button(action: { store.switchSpace(id: space.id) }) {
                            HStack(spacing: 4) {
                                Image(systemName: space.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(isCurrent ? spaceColor : Color.secondary)

                                Text(space.name)
                                    .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                isCurrent ? spaceColor.opacity(0.12) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isCurrent ? spaceColor.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if store.spaces.count > 1 {
                                Button("Delete Space", role: .destructive) {
                                    store.deleteSpace(id: space.id)
                                }
                            }
                        }
                    }

                    // Create Space Button (+)
                    Button(action: {
                        newSpaceName = ""
                        isShowingNewSpaceSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.04), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("New Space")
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Pinned Tabs Section
    @ViewBuilder
    private var pinnedTabsSection: some View {
        let pinned = store.pinnedTabs
        if isCollapsed {
            VStack(spacing: 4) {
                ForEach(pinned) { tab in
                    pinnedSquare(tab: tab, size: 28)
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32, maximum: 40), spacing: 6)], spacing: 6) {
                ForEach(pinned) { tab in
                    pinnedSquare(tab: tab, size: 34)
                }
            }
        }
    }

    @ViewBuilder
    private func pinnedSquare(tab: Tab, size: CGFloat) -> some View {
        let isFocused = tab.id == store.activeTabId
        Button(action: { store.selectTab(id: tab.id) }) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isFocused ? Color.primary.opacity(0.10) : Color.primary.opacity(0.04))

                if isFocused {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(settings.accentColor.opacity(0.5), lineWidth: 1)
                }

                if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: tab.isBlank ? "sparkles" : "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(isFocused ? Color.primary : Color.secondary)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .help(tab.title.isEmpty ? (tab.url?.host ?? "Pinned Tab") : tab.title)
        .contextMenu {
            Button("Unpin Tab") {
                store.togglePin(tabId: tab.id)
            }
            Button("Close Tab") {
                store.closeTab(id: tab.id)
            }
        }
    }

    // MARK: - Footer Section
    @ViewBuilder
    private var footerSection: some View {
        HStack(spacing: 6) {
            Button(action: {
                store.newTab(url: nil, select: true)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    if !isCollapsed {
                        Text("New Tab")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("⌘T")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, isCollapsed ? 4 : 8)
                .frame(height: 28)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Button(action: { store.openSettings() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
            }
        }
    }

    // MARK: - Trailing Resize Handle
    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.5))
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newW = min(340, max(160, settings.sidebarWidth + Double(value.translation.width)))
                        settings.sidebarWidth = newW
                    }
            )
    }

    // MARK: - New Space Creation Sheet
    private var newSpaceSheetView: some View {
        VStack(spacing: 16) {
            Text("Create New Space")
                .font(.headline)

            TextField("Space Name (e.g. Research, Personal)", text: $newSpaceName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isShowingNewSpaceSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    store.createSpace(name: newSpaceName)
                    isShowingNewSpaceSheet = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}

/// An individual tab row inside the vertical sidebar.
private struct VerticalTabRowView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: Tab
    let isActive: Bool
    let isCollapsed: Bool

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            store.selectTab(id: tab.id)
        }) {
            HStack(spacing: 8) {
                // Tab Favicon / Indicator
                tabIconView
                    .frame(width: 16, height: 16)

                if !isCollapsed {
                    expandedContent
                }
            }
            .padding(.horizontal, isCollapsed ? 6 : 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive ? Color.primary.opacity(0.06) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isCollapsed ? displayTitle : "")
        .contextMenu {
            if let split = store.splitPairs.first(where: { $0.contains(tab.id) }) {
                Button("Swap Split Panes") {
                    store.swapSplit(splitPairId: split.id)
                }
                Button("Close Split View") {
                    store.closeSplit(for: tab.id)
                }
            } else {
                Button("Split with New Tab") {
                    store.splitCurrentTab()
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
    }

    @ViewBuilder
    private var expandedContent: some View {
        // Tab Title
        Text(displayTitle)
            .font(.system(size: 11, weight: isActive ? .medium : .regular))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

        // Split View Indicator
        if store.splitPairs.contains(where: { $0.contains(tab.id) }) {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 8.5))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }

        // Close Button (visible on hover or when active)
        if isHovered || isActive {
            Button(action: {
                store.closeTab(id: tab.id)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Tab (⌘W)")
        }
    }

    @ViewBuilder
    private var tabIconView: some View {
        if tab.isLoading {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.65)
        } else if tab.isIncognito && (tab.favicon == nil || tab.isBlank) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.purple.opacity(0.85))
        } else if let favicon = tab.favicon {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: tab.isBlank ? "sparkles" : "globe")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
    }

    private var displayTitle: String {
        if tab.isInternalPage {
            return tab.title
        }
        if tab.isIncognito && (tab.url == nil || tab.isBlank) {
            return "Private Tab"
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
}

// Color helper for Hex strings
private extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}


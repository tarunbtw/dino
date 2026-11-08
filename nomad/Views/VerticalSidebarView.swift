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

    @State private var draggingTabId: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var isSettling: Bool = false
    @State private var isHoveringNewTab: Bool = false
    @State private var isHoveringSettings: Bool = false
    @State private var isShowingExtensionsMenu: Bool = false
    @State private var isShowingDownloadsMenu: Bool = false
    @ObservedObject private var downloadManager = DownloadManager.shared
    private let tabRowHeight: CGFloat = 28
    private let tabRowSpacing: CGFloat = 2
    private var tabStep: CGFloat { isCollapsed ? (34 + tabRowSpacing) : (tabRowHeight + tabRowSpacing) }

    private var isCollapsed: Bool { settings.isSidebarCollapsed }
    private var sidebarWidth: CGFloat { isCollapsed ? 80 : CGFloat(settings.sidebarWidth) }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Traffic lights & Back/Forward/Reload / Collapse/Expand
            headerSection

            // Spaces Switcher Bar
            spacesBarSection
                .padding(.horizontal, isCollapsed ? 6 : 10)
                .padding(.bottom, 6)

            // Pinned Tabs Shelf
            if !store.pinnedTabs.isEmpty {
                pinnedTabsSection
                    .padding(.horizontal, isCollapsed ? 6 : 10)
                    .padding(.bottom, 6)

                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }

            // Tabs List for Active Space
            ScrollView(.vertical, showsIndicators: false) {
                let currentTabs = store.unpinnedTabsForActiveSpace
                VStack(spacing: tabRowSpacing) {
                    ForEach(Array(currentTabs.enumerated()), id: \.element.id) { index, tab in
                        let isDragging = draggingTabId == tab.id
                        let offset = tabOffsetY(for: tab, index: index, tabs: currentTabs)

                        VerticalTabRowView(
                            store: store,
                            tab: tab,
                            isActive: tab.id == store.activeTabId,
                            isDragging: isDragging,
                            isCollapsed: isCollapsed,
                            offsetY: offset,
                            onDragChanged: { translation in
                                handleDragChanged(tabId: tab.id, translation: translation)
                            },
                            onDragEnded: { translation in
                                handleDragEnded(tabId: tab.id, translation: translation, tabs: currentTabs)
                            }
                        )
                        .animation(draggingTabId == nil ? nil : (isDragging && !isSettling ? nil : .spring(response: 0.18, dampingFraction: 0.95)), value: offset)
                    }

                    // New Tab Button directly below open tabs
                    Button(action: {
                        store.newTab(url: nil, select: true)
                    }) {
                        if isCollapsed {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 34, height: 34)
                                .background(isHoveringNewTab ? Color.primary.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("New Tab")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("⌘T")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(isHoveringNewTab ? Color.primary.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringNewTab = $0 }
                    .help("New Tab (⌘T)")
                }
                .padding(.horizontal, isCollapsed ? 6 : 8)
                .padding(.top, 2)
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "VerticalSidebarSpace")
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Search-style SideFoot Section
            footerSection
                .padding(.horizontal, isCollapsed ? 6 : 10)
        }
        .frame(width: sidebarWidth)
        .simultaneousGesture(
            TapGesture().onEnded {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        )
        .background(Palette.frame.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)
        }
        .overlay(alignment: .trailing) {
            sidebarResizeHandle
        }
        .sheet(isPresented: $isShowingNewSpaceSheet) {
            newSpaceSheetView
        }
    }

    // MARK: - Header Section
    @ViewBuilder
    private var headerSection: some View {
        if isCollapsed {
            VStack(spacing: 2) {
                // Window drag area for traffic lights (80pt width, 44pt height)
                WindowDragArea()
                    .frame(width: 80, height: 44)

                // Expand Sidebar Door right at top below traffic lights
                Door(icon: "sidebar.right", help: "Expand Sidebar (⌘S)") {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        settings.toggleSidebarCollapsed()
                    }
                }
            }
            .frame(width: 80)
            .padding(.bottom, 4)
        } else {
            HStack(spacing: 4) {
                // Traffic lights safe drag area (80pt clearance)
                WindowDragArea()
                    .frame(width: Metrics.sideLights, height: 44)

                if let activeTab = store.activeTab {
                    Door(icon: "chevron.left", help: "Back (⌘[)") { activeTab.goBack() }
                        .disabled(!activeTab.canGoBack)
                        .opacity(activeTab.canGoBack ? 1.0 : 0.35)

                    Door(icon: "chevron.right", help: "Forward (⌘])") { activeTab.goForward() }
                        .disabled(!activeTab.canGoForward)
                        .opacity(activeTab.canGoForward ? 1.0 : 0.35)

                    Door(icon: activeTab.isLoading ? "xmark" : "arrow.clockwise", help: activeTab.isLoading ? "Stop Loading" : "Reload (⌘R)") {
                        if activeTab.isLoading { activeTab.stopLoading() } else { activeTab.reload() }
                    }
                }

                Spacer()

                // Collapse Sidebar Door
                Door(icon: "sidebar.left", help: "Collapse Sidebar (⌘S)") {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        settings.toggleSidebarCollapsed()
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
        }
    }

    // MARK: - Spaces Bar Section
    @ViewBuilder
    private var spacesBarSection: some View {
        if isCollapsed {
            // Collapsed: Clickable space color dots with comfortable hit areas
            VStack(spacing: 4) {
                ForEach(store.spaces) { space in
                    let isCurrent = space.id == store.activeSpaceId
                    let dotColor = Color(hex: space.colorHex) ?? settings.accentColor
                    Button(action: {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                            store.switchSpace(id: space.id)
                        }
                    }) {
                        ZStack {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(dotColor.opacity(0.16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(dotColor.opacity(0.45), lineWidth: 1)
                                    )
                            }
                            Circle()
                                .fill(dotColor)
                                .frame(width: isCurrent ? 8 : 7, height: isCurrent ? 8 : 7)
                        }
                        .frame(width: 38, height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Space: \(space.name)")
                }
            }
            .frame(maxWidth: .infinity)
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
                    pinnedSquare(tab: tab, size: 34)
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 44), spacing: 4)], spacing: 4) {
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
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isFocused ? Palette.wash : Color.primary.opacity(0.04))

                if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    let letter = tab.title.isEmpty ? (tab.url?.host?.prefix(1).uppercased() ?? "T") : String(tab.title.prefix(1)).uppercased()
                    Text(letter)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isFocused ? Palette.ink : Palette.muted)
                }
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

    // MARK: - Search-style SideFoot Section
    @ViewBuilder
    private var footerSection: some View {
        if isCollapsed {
            VStack(spacing: 6) {
                // Extensions
                Door(icon: "puzzlepiece.extension", on: isShowingExtensionsMenu, help: "Extensions") {
                    isShowingExtensionsMenu.toggle()
                }
                .background(ExtensionAnchor(id: "extensions_menu_anchor_sidebar_collapsed"))
                .popover(isPresented: $isShowingExtensionsMenu, arrowEdge: .trailing) {
                    if let activeTab = store.activeTab {
                        ExtensionsMenuPopover(tab: activeTab, store: store, isPresented: $isShowingExtensionsMenu)
                    }
                }

                // Downloads (if any)
                if !downloadManager.downloads.isEmpty {
                    Door(icon: "arrow.down.circle", on: isShowingDownloadsMenu, help: "Downloads") {
                        isShowingDownloadsMenu.toggle()
                    }
                    .popover(isPresented: $isShowingDownloadsMenu, arrowEdge: .trailing) {
                        DownloadsMenuPopover(store: store, isPresented: $isShowingDownloadsMenu)
                    }
                }

                // Bookmarks
                if let activeTab = store.activeTab {
                    let urlString = activeTab.url?.absoluteString ?? ""
                    let canBookmark = !activeTab.isBlank && !activeTab.isInternalPage && !urlString.isEmpty && urlString != "about:blank"
                    let isBookmarked = canBookmark && settings.isBookmarked(urlString)

                    Door(icon: isBookmarked ? "bookmark.fill" : "bookmark", on: isBookmarked, help: isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark Tab (⌘D)") {
                        store.toggleBookmark(for: activeTab)
                    }
                    .disabled(!canBookmark)
                    .opacity(canBookmark ? 1.0 : 0.35)
                }

                // Settings
                Door(icon: "gearshape", help: "Settings (nomad://settings, ⌘,)") {
                    store.openSettings()
                }

                // Tabs on Top
                Door(icon: "rectangle.topthird.inset.filled", help: "Tabs Across Top (⇧⌘S)") {
                    settings.toggleTabLayout()
                }

                // Expand Sidebar
                Door(icon: "sidebar.right", help: "Expand Sidebar (⌘S)") {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        settings.toggleSidebarCollapsed()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        } else {
            // Expanded: Clean single row (Search-style SideFoot)
            HStack(spacing: 2) {
                // Pinned extensions & Extensions puzzle door
                ExtensionActionBar(store: store)

                Door(icon: "puzzlepiece.extension", on: isShowingExtensionsMenu, help: "Extensions") {
                    isShowingExtensionsMenu.toggle()
                }
                .background(ExtensionAnchor(id: "extensions_menu_anchor_sidebar"))
                .popover(isPresented: $isShowingExtensionsMenu, arrowEdge: .trailing) {
                    if let activeTab = store.activeTab {
                        ExtensionsMenuPopover(tab: activeTab, store: store, isPresented: $isShowingExtensionsMenu)
                    }
                }

                // Bookmarks
                if let activeTab = store.activeTab {
                    let urlString = activeTab.url?.absoluteString ?? ""
                    let canBookmark = !activeTab.isBlank && !activeTab.isInternalPage && !urlString.isEmpty && urlString != "about:blank"
                    let isBookmarked = canBookmark && settings.isBookmarked(urlString)

                    Door(icon: isBookmarked ? "bookmark.fill" : "bookmark", on: isBookmarked, help: isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark Tab (⌘D)") {
                        store.toggleBookmark(for: activeTab)
                    }
                    .disabled(!canBookmark)
                    .opacity(canBookmark ? 1.0 : 0.35)
                }

                // Downloads (ONLY if active or completed!)
                if !downloadManager.downloads.isEmpty {
                    Door(icon: "arrow.down.circle", on: isShowingDownloadsMenu, help: "Downloads") {
                        isShowingDownloadsMenu.toggle()
                    }
                    .popover(isPresented: $isShowingDownloadsMenu, arrowEdge: .trailing) {
                        DownloadsMenuPopover(store: store, isPresented: $isShowingDownloadsMenu)
                    }
                }

                // Ghost tabs indicator (if active)
                if !store.ghostTabs.isEmpty {
                    AgentGhostTabsPill(store: store)
                }

                Spacer(minLength: 0)

                // Layout Switcher: Tabs on Top (⇧⌘S)
                Door(icon: "rectangle.topthird.inset.filled", help: "Tabs Across Top (⇧⌘S)") {
                    settings.toggleTabLayout()
                }

                // Settings (⌘,)
                Door(icon: "gearshape", help: "Settings (nomad://settings, ⌘,)") {
                    store.openSettings()
                }

                // Collapse Sidebar (⌘S)
                Door(icon: "sidebar.left", help: "Collapse Sidebar (⌘S)") {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        settings.toggleSidebarCollapsed()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Trailing Resize Handle
    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
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
                        if isCollapsed {
                            if value.translation.width > 12 {
                                settings.isSidebarCollapsed = false
                                settings.sidebarWidth = max(180, 80 + Double(value.translation.width))
                            }
                        } else {
                            let newW = min(340, max(160, settings.sidebarWidth + Double(value.translation.width)))
                            settings.sidebarWidth = newW
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    if isCollapsed {
                        settings.isSidebarCollapsed = false
                        settings.sidebarWidth = 220
                    } else {
                        settings.sidebarWidth = 220
                    }
                }
            }
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

    // MARK: - Vertical Tab Drag Reordering
    private func tabOffsetY(for tab: Tab, index: Int, tabs: [Tab]) -> CGFloat {
        guard let draggingId = draggingTabId,
              let draggingIndex = tabs.firstIndex(where: { $0.id == draggingId }) else {
            return 0
        }

        if tab.id == draggingId {
            return dragOffset
        }

        let rawShift = Int((dragOffset / tabStep).rounded())
        let targetIndex = min(max(0, draggingIndex + rawShift), tabs.count - 1)

        if draggingIndex < targetIndex {
            // Dragging down: tabs between (draggingIndex + 1) and targetIndex shift up
            if index > draggingIndex && index <= targetIndex {
                return -tabStep
            }
        } else if draggingIndex > targetIndex {
            // Dragging up: tabs between targetIndex and (draggingIndex - 1) shift down
            if index >= targetIndex && index < draggingIndex {
                return tabStep
            }
        }

        return 0
    }

    private func handleDragChanged(tabId: UUID, translation: CGFloat) {
        guard !isSettling else { return }
        if draggingTabId == nil {
            draggingTabId = tabId
            if store.activeTabId != tabId {
                store.selectTab(id: tabId)
            }
        }
        dragOffset = translation
    }

    private func handleDragEnded(tabId: UUID, translation: CGFloat, tabs: [Tab]) {
        guard !isSettling,
              let draggingLocalIndex = tabs.firstIndex(where: { $0.id == tabId }),
              let draggingGlobalIndex = store.tabs.firstIndex(where: { $0.id == tabId }) else {
            draggingTabId = nil
            dragOffset = 0
            isSettling = false
            return
        }

        let rawShift = Int((translation / tabStep).rounded())
        let targetLocalIndex = min(max(0, draggingLocalIndex + rawShift), tabs.count - 1)

        isSettling = true

        if targetLocalIndex != draggingLocalIndex {
            let targetTab = tabs[targetLocalIndex]
            if let targetGlobalIndex = store.tabs.firstIndex(where: { $0.id == targetTab.id }) {
                let targetOffset = CGFloat(targetLocalIndex - draggingLocalIndex) * tabStep
                withAnimation(.spring(response: 0.18, dampingFraction: 0.95)) {
                    dragOffset = targetOffset
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        store.moveTab(from: draggingGlobalIndex, to: targetGlobalIndex)
                        draggingTabId = nil
                        dragOffset = 0
                        isSettling = false
                    }
                }
                return
            }
        }

        withAnimation(.spring(response: 0.18, dampingFraction: 0.95)) {
            dragOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                draggingTabId = nil
                isSettling = false
            }
        }
    }
}

/// An individual tab row inside the vertical sidebar.
private struct VerticalTabRowView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: Tab
    let isActive: Bool
    let isDragging: Bool
    let isCollapsed: Bool
    let offsetY: CGFloat
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    @ObservedObject private var settings = SettingsStore.shared
    @State private var isHovered: Bool = false
    @State private var lastClickTime: TimeInterval = 0

    var body: some View {
        Group {
            if isCollapsed {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? Color.primary.opacity(0.16) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))

                    if isActive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(settings.accentColor, lineWidth: 1.5)
                    }

                    tabIconView
                        .frame(width: 16, height: 16)
                }
                .frame(width: 34, height: 34)
                .overlay(alignment: .leading) {
                    if isActive {
                        Capsule()
                            .fill(settings.accentColor)
                            .frame(width: 3, height: 16)
                            .offset(x: -8)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                HStack(spacing: 0) {
                    if isActive {
                        Capsule()
                            .fill(settings.accentColor)
                            .frame(width: 3, height: 14)
                            .padding(.trailing, 6)
                    } else {
                        Color.clear
                            .frame(width: 3, height: 14)
                            .padding(.trailing, 6)
                    }

                    tabIconView
                        .frame(width: 16, height: 16)
                        .padding(.trailing, 8)

                    expandedContent
                }
                .padding(.horizontal, 6)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Palette.sideWash : (isHovered ? Palette.sideHover : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .onTapGesture {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastClickTime < 0.35 {
                store.selectTab(id: tab.id)
                store.isAddressBarFocused = true
            } else {
                store.selectTab(id: tab.id)
            }
            lastClickTime = now
        }
        .offset(y: offsetY)
        .zIndex(isDragging ? 100 : (isActive ? 1 : 0))
        .shadow(color: .black.opacity(isDragging ? 0.16 : 0), radius: 8, y: 2)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("VerticalSidebarSpace"))
                .onChanged { value in
                    onDragChanged(value.translation.height)
                }
                .onEnded { value in
                    onDragEnded(value.translation.height)
                }
        )
        .onHover { isHovered = $0 }
        .help(isCollapsed ? displayTitle : "")
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
    }

    @ViewBuilder
    private var expandedContent: some View {
        // Tab Title
        Text(displayTitle)
            .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isActive ? Palette.ink : Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)

        // Split View Indicator
        if store.splitPairs.contains(where: { $0.contains(tab.id) }) {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 8.5))
                .foregroundStyle(isActive ? Palette.ink : Palette.muted)
        }

        // Close / Ungroup Buttons (visible on hover or when active)
        if isHovered || isActive {
            HStack(spacing: 2) {
                if store.splitPairs.contains(where: { $0.contains(tab.id) }) {
                    Button(action: {
                        store.closeSplit(for: tab.id)
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(Color.secondary)
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
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Tab (⌘W)")
            }
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


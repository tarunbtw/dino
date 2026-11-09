//
//  VerticalSidebarView.swift
//  nomad
//
//  Firn-style vertical sidebar: traffic lights, sidebar toggle, navigation chevrons,
//  address bar with resting domain, space tabs list with + New tab, and centered space profile switcher.
//

import SwiftUI
import AppKit

struct VerticalSidebarView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore

    @State private var draggingTabId: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var isSettling: Bool = false
    @State private var isHoveringNewTab: Bool = false
    @State private var isHoveringAddress: Bool = false

    private let tabRowHeight: CGFloat = Theme.rowHeight
    private let tabRowSpacing: CGFloat = Theme.rowSpacing
    private var tabStep: CGFloat { tabRowHeight + tabRowSpacing }

    private var sidebarWidth: CGFloat { CGFloat(settings.sidebarWidth) }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Traffic lights, Sidebar door, Back/Forward
            headerSection

            // Address bar with domain & reload
            addressBarSection

            // Pinned Tabs Shelf (if any)
            if !store.pinnedTabs.isEmpty {
                pinnedTabsSection
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)

                Rectangle()
                    .fill(Theme.activeTabHairline)
                    .frame(height: 0.5)
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

                    // + New tab button
                    newTabRow
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "VerticalSidebarSpace")
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Centered Space Profile Row
            footerSection
                .padding(.horizontal, 10)
        }
        .frame(width: sidebarWidth)
        .simultaneousGesture(
            TapGesture().onEnded {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        )
        .background(Theme.frame.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(width: 0.5)
        }
        .overlay(alignment: .trailing) {
            sidebarResizeHandle
        }
    }

    // MARK: - Header Section
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 2) {
            WindowLights()
                .frame(width: Theme.trafficLightsWidth, height: Theme.rowHeight)

            Door(icon: "sidebar.left", help: "Hide sidebar (⌘S)") {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    settings.toggleSidebarCollapsed()
                }
            }

            Spacer(minLength: 0)

            if let activeTab = store.activeTab {
                Door(icon: "chevron.left", help: "Back (⌘[)") { activeTab.goBack() }
                    .disabled(!activeTab.canGoBack)
                    .opacity(activeTab.canGoBack ? 1.0 : 0.35)

                Door(icon: "chevron.right", help: "Forward (⌘])") { activeTab.goForward() }
                    .disabled(!activeTab.canGoForward)
                    .opacity(activeTab.canGoForward ? 1.0 : 0.35)
            }
        }
        .frame(height: Theme.rowHeight)
        .padding(.top, Theme.pageInset)
        .padding(.horizontal, 8)
    }

    // MARK: - Address Bar Section
    @ViewBuilder
    private var addressBarSection: some View {
        let activeTab = store.activeTab
        let displaySite = WebAddress.site(of: activeTab?.url)

        Button(action: {
            store.isAddressBarFocused = true
        }) {
            HStack(spacing: 8) {
                Text(displaySite.isEmpty ? "Search or enter address" : displaySite)
                    .font(.system(size: 13))
                    .foregroundStyle(displaySite.isEmpty ? Theme.muted : Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if let tab = activeTab {
                    Button(action: {
                        if tab.isLoading { tab.stopLoading() } else { tab.reload() }
                    }) {
                        Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(tab.isLoading ? "Stop loading" : "Reload this page (⌘R)")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(isHoveringAddress ? Theme.press : Theme.hover)
                    .overlay {
                        if let tab = activeTab, tab.isLoading {
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                                    .fill(Theme.frost)
                                    .frame(width: geo.size.width * CGFloat(max(0.05, tab.estimatedProgress)))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                        }
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringAddress = $0 }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - New Tab Row
    @ViewBuilder
    private var newTabRow: some View {
        Button(action: {
            store.isAddressBarFocused = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                Text("New tab")
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .frame(height: Theme.rowHeight)
            .background(isHoveringNewTab ? Theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringNewTab = $0 }
        .help("New tab (⌘T)")
    }

    // MARK: - Pinned Tabs Section
    @ViewBuilder
    private var pinnedTabsSection: some View {
        let pinned = store.pinnedTabs
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 44), spacing: 4)], spacing: 4) {
            ForEach(pinned) { tab in
                pinnedSquare(tab: tab, size: 34)
            }
        }
    }

    @ViewBuilder
    private func pinnedSquare(tab: Tab, size: CGFloat) -> some View {
        let isFocused = tab.id == store.activeTabId
        Button(action: { store.selectTab(id: tab.id) }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocused ? Theme.activeTab : Theme.hover)

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
                        .foregroundStyle(isFocused ? Theme.ink : Theme.muted)
                }
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    // MARK: - Centered Space Row
    @ViewBuilder
    private var footerSection: some View {
        SpaceRow(store: store)
            .padding(.bottom, Theme.pageInset)
    }

    // MARK: - Sidebar Resize Handle
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
                        let newW = min(360, max(180, settings.sidebarWidth + Double(value.translation.width)))
                        settings.sidebarWidth = newW
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    settings.sidebarWidth = 240
                }
            }
    }

    // MARK: - Drag Reordering
    private func tabOffsetY(for tab: Tab, index: Int, tabs: [Tab]) -> CGFloat {
        guard let draggingId = draggingTabId, draggingId != tab.id,
              let fromIdx = tabs.firstIndex(where: { $0.id == draggingId }) else {
            return tab.id == draggingTabId ? dragOffset : 0
        }
        let currentIndex = index
        let projectedIndex = targetIndex(fromIndex: fromIdx, count: tabs.count)

        if fromIdx < projectedIndex {
            if currentIndex > fromIdx && currentIndex <= projectedIndex {
                return -tabStep
            }
        } else if fromIdx > projectedIndex {
            if currentIndex >= projectedIndex && currentIndex < fromIdx {
                return tabStep
            }
        }
        return 0
    }

    private func targetIndex(fromIndex: Int, count: Int) -> Int {
        let movedSlots = Int(round(dragOffset / tabStep))
        return min(max(fromIndex + movedSlots, 0), count - 1)
    }

    private func handleDragChanged(tabId: UUID, translation: CGFloat) {
        if draggingTabId == nil {
            draggingTabId = tabId
            isSettling = false
        }
        dragOffset = translation
    }

    private func handleDragEnded(tabId: UUID, translation: CGFloat, tabs: [Tab]) {
        guard let fromIdx = tabs.firstIndex(where: { $0.id == tabId }) else {
            draggingTabId = nil
            dragOffset = 0
            return
        }
        let toIdx = targetIndex(fromIndex: fromIdx, count: tabs.count)
        isSettling = true
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            dragOffset = CGFloat(toIdx - fromIdx) * tabStep
        }
        if toIdx != fromIdx {
            store.moveTab(from: fromIdx, to: toIdx)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                draggingTabId = nil
                dragOffset = 0
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
    let offsetY: CGFloat
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            tabIconView
                .frame(width: 16, height: 16)

            Text(displayTitle)
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? Theme.ink : Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button(action: {
                    store.closeTab(id: tab.id)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close tab (⌘W)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                .fill(isActive ? Theme.activeTab : (isHovered ? Theme.hover : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
        .onTapGesture {
            store.selectTab(id: tab.id)
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
        .help(displayTitle)
        .contextMenu {
            Button("Reload") {
                tab.reload()
            }
            Button("Duplicate Tab") {
                store.newTab(url: tab.url, isIncognito: tab.isIncognito, select: true)
            }
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                store.togglePin(tabId: tab.id)
            }
            Divider()
            Button("Close Tab") {
                store.closeTab(id: tab.id)
            }
        }
    }

    @ViewBuilder
    private var tabIconView: some View {
        if tab.isInternalPage {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        } else if let favicon = tab.favicon {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: tab.isBlank ? "sparkles" : "globe")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Theme.ink : Theme.muted)
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

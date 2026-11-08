//
//  TabStripView.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI
import AppKit

/// Horizontal tab strip housing all open tabs and the new tab button.
/// Features a single matched-geometry sliding pill that glides between tabs.
struct TabStripView: View {
    @ObservedObject var store: BrowserStore

    private let minTabWidth: CGFloat = Metrics.tabMinWidth
    private let maxTabWidth: CGFloat = Metrics.tabWidth
    private let plusButtonWidth: CGFloat = Metrics.plusWidth
    private let tabSpacing: CGFloat = Metrics.tabGap

    @Namespace private var slidingPill
    @State private var draggingTabId: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var isSettling: Bool = false

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let visible = store.visibleTabs
            let pinnedCount = visible.filter { $0.isPinned }.count
            let unpinnedCount = max(1, visible.count - pinnedCount)
            let pinnedWidth = CGFloat(pinnedCount) * (Metrics.pinWidth + tabSpacing)
            let totalSpacing = CGFloat(visible.count) * tabSpacing
            let availableForTabs = max(minTabWidth, availableWidth - plusButtonWidth - pinnedWidth - totalSpacing - 8)
            let naturalWidth = availableForTabs / CGFloat(unpinnedCount)
            let computedTabWidth = max(minTabWidth, min(maxTabWidth, naturalWidth))
            let needsScroll = naturalWidth < minTabWidth

            if needsScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    tabsHStack(computedTabWidth: computedTabWidth)
                }
                .scrollIndicators(.hidden)
                .frame(height: geo.size.height, alignment: .center)
            } else {
                HStack(spacing: tabSpacing) {
                    tabsHStack(computedTabWidth: computedTabWidth)

                    // Trailing empty space allows native window dragging
                    WindowDragArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: geo.size.height, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func tabsHStack(computedTabWidth: CGFloat) -> some View {
        let visibleTabs: [Tab] = store.visibleTabs
        let count = visibleTabs.count
        let step = computedTabWidth + tabSpacing

        HStack(spacing: tabSpacing) {
            ForEach(Array(visibleTabs.enumerated()), id: \.element.id) { index, tab in
                let isDragging = draggingTabId == tab.id
                let tabW: CGFloat = tab.isPinned ? Metrics.pinWidth : computedTabWidth
                let offset = tabOffset(for: tab, index: index, step: step)

                TabItemView(
                    store: store,
                    tab: tab,
                    isActive: tab.id == store.activeTabId,
                    isDragging: isDragging,
                    tabWidth: tabW,
                    index: index,
                    count: count,
                    step: step,
                    offsetX: offset,
                    pillNamespace: slidingPill,
                    onDragChanged: { translation in
                        handleDragChanged(tabId: tab.id, translation: translation)
                    },
                    onDragEnded: { translation in
                        handleDragEnded(tabId: tab.id, translation: translation, step: step)
                    }
                )
                .animation(draggingTabId == nil ? nil : (isDragging && !isSettling ? nil : .spring(response: 0.18, dampingFraction: 0.95)), value: offset)
            }

            // New Tab Button (+)
            Button(action: {
                store.newTab(url: nil, select: true)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")
        }
        .frame(height: 30)
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .coordinateSpace(name: "TabStripSpace")
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: store.activeTabId)
        .animation(.spring(response: 0.25, dampingFraction: 0.90), value: computedTabWidth)
    }

    private func tabOffset(for tab: Tab, index: Int, step: CGFloat) -> CGFloat {
        guard let draggingId = draggingTabId,
              let draggingIndex = store.tabs.firstIndex(where: { $0.id == draggingId }) else {
            return 0
        }

        if tab.id == draggingId {
            return dragOffset
        }

        let count = store.tabs.count
        let rawShift = Int((dragOffset / step).rounded())
        let maxAllowedLeft = -draggingIndex
        let maxAllowedRight = (count - 1) - draggingIndex
        let targetIndexOffset = max(maxAllowedLeft, min(maxAllowedRight, rawShift))

        if targetIndexOffset > 0 {
            if index > draggingIndex && index <= draggingIndex + targetIndexOffset {
                return -step
            }
        } else if targetIndexOffset < 0 {
            if index < draggingIndex && index >= draggingIndex + targetIndexOffset {
                return step
            }
        }

        return 0
    }

    private func handleDragChanged(tabId: UUID, translation: CGFloat) {
        if draggingTabId == nil {
            draggingTabId = tabId
            isSettling = false
        }
        dragOffset = translation
    }

    private func handleDragEnded(tabId: UUID, translation: CGFloat, step: CGFloat) {
        guard let fromIndex = store.tabs.firstIndex(where: { $0.id == tabId }) else {
            draggingTabId = nil
            dragOffset = 0
            return
        }

        let count = store.tabs.count
        let rawShift = Int((translation / step).rounded())
        let maxAllowedLeft = -fromIndex
        let maxAllowedRight = (count - 1) - fromIndex
        let shift = max(maxAllowedLeft, min(maxAllowedRight, rawShift))

        let toIndex = fromIndex + shift
        if shift != 0 && toIndex >= 0 && toIndex < count {
            isSettling = true
            withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                store.moveTab(from: fromIndex, to: toIndex)
                dragOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                self.draggingTabId = nil
                self.isSettling = false
            }
        } else {
            isSettling = true
            withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                dragOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                self.draggingTabId = nil
                self.isSettling = false
            }
        }
    }
}

//
//  SplitRowView.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//

import SwiftUI
import AppKit

/// Unified sidebar row representing a Split View pair (docs/split-row-design.html).
/// Renders two halves side by side within a single 36pt row.
struct SplitRowView: View {
    @ObservedObject var store: BrowserStore
    let split: SplitPair
    @ObservedObject var leftTab: Tab
    @ObservedObject var rightTab: Tab

    @State private var isHoveringRow = false
    @State private var hoveredTabId: UUID? = nil

    private var isOnScreen: Bool {
        store.activeTabId == leftTab.id || store.activeTabId == rightTab.id
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)

        GeometryReader { geo in
            let w = geo.size.width
            let leftShare = CGFloat(split.ratio)
            let leftWidth = max(40, w * leftShare)
            let rightWidth = max(40, w - leftWidth)

            HStack(spacing: 0) {
                halfPane(tab: leftTab, width: leftWidth)

                // Divider line between the two halves
                Rectangle()
                    .fill(Theme.activeTabHairline)
                    .frame(width: 0.5)

                halfPane(tab: rightTab, width: rightWidth)
            }
        }
        .frame(height: Theme.rowHeight)
        .background {
            if isOnScreen {
                shape.fill(Theme.activeTab)
                    .overlay {
                        shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
                    }
            } else if isHoveringRow {
                shape.fill(Theme.hover)
            }
        }
        .contentShape(shape)
        .onHover { isHoveringRow = $0 }
    }

    @ViewBuilder
    private func halfPane(tab: Tab, width: CGFloat) -> some View {
        let isTabActive = store.activeTabId == tab.id
        let isTabHovered = hoveredTabId == tab.id

        Button {
            store.selectTab(id: tab.id)
        } label: {
            HStack(spacing: 6) {
                // Favicon
                if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 2.5))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 14, height: 14)
                }

                // Title
                Text(tab.title.isEmpty ? (tab.url?.host ?? "Tab") : tab.title)
                    .font(Theme.tabFont)
                    .foregroundStyle(isTabActive ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                // Close button on hover
                if isTabHovered || (isHoveringRow && isTabActive) {
                    Button(action: {
                        store.closeTab(id: tab.id)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close tab")
                }
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: Theme.rowHeight, alignment: .leading)
            .background(isTabActive && !isOnScreen ? Theme.press : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHover in
            if isHover {
                hoveredTabId = tab.id
            } else if hoveredTabId == tab.id {
                hoveredTabId = nil
            }
        }
        .contextMenu {
            Button("Separate Tabs", systemImage: "rectangle.split.2x1.slash") {
                store.closeSplit(for: tab.id)
            }
            Button("Swap Sides", systemImage: "arrow.left.arrow.right") {
                store.swapSplit(splitPairId: split.id)
            }
            Divider()
            Button("Add to Basecamp", systemImage: "pin") {
                store.addToBasecamp(tab: tab)
            }
            Button("Close Tab", systemImage: "xmark") {
                store.closeTab(id: tab.id)
            }
        }
    }
}


//
//  BasecampGrid.swift
//  nomad
//
//  Ported from Firn's Basecamp: everyday pinned sites as square tiles
//  at the top of the sidebar. Responsive balanced flow layout.
//

import SwiftUI
import AppKit

struct BasecampGrid: View {
    @ObservedObject var store: BrowserStore
    let sidebarWidth: CGFloat

    var body: some View {
        let tiles = store.basecampTabs
        if !tiles.isEmpty {
            let layout = BasecampLayout.make(count: tiles.count, width: Double(sidebarWidth - 16))
            VStack(spacing: CGFloat(BasecampLayout.gap)) {
                var index = 0
                ForEach(0..<layout.rows.count, id: \.self) { rowIndex in
                    let rowCount = layout.rows[rowIndex]
                    HStack(spacing: CGFloat(BasecampLayout.gap)) {
                        ForEach(0..<rowCount, id: \.self) { _ in
                            if index < tiles.count {
                                let tab = tiles[index]
                                BasecampTileView(store: store, tab: tab, width: CGFloat(layout.tileWidth))
                            }
                            let _ = { index += 1 }()
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }
}

private struct BasecampTileView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: Tab
    let width: CGFloat
    @State private var isHovering = false

    var body: some View {
        let isFocused = tab.id == store.activeTabId
        let siteColors = tab.siteColors

        Button(action: {
            store.selectTab(id: tab.id)
        }) {
            ZStack {
                // Background fill
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocused ? Theme.activeTab : (isHovering ? Theme.hover : Theme.frameWash))

                // Favicon or initial
                if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    let letter = tab.title.isEmpty ? (tab.url?.host?.prefix(1).uppercased() ?? "T") : String(tab.title.prefix(1)).uppercased()
                    Text(letter)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isFocused ? Theme.ink : Theme.muted)
                }
            }
            .frame(width: width, height: CGFloat(BasecampLayout.tileHeight))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? (siteColors?.main.color.opacity(0.8) ?? Theme.frost)
                            : (isHovering ? Theme.activeTabHairline : Color.clear),
                        lineWidth: isFocused ? 1.5 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tab.title.isEmpty ? (tab.url?.host ?? "Pinned Tile") : tab.title)
        .contextMenu {
            if tab.isAwayFromHome {
                Button("Go Back to Home", systemImage: "house") {
                    tab.goHome()
                }
            }
            Button("Open as Split", systemImage: "rectangle.split.2x1") {
                store.pickSplit(beside: tab)
            }
            Button("Remove from Basecamp", systemImage: "pin.slash") {
                store.removeFromBasecamp(tab: tab)
            }
            Divider()
            Button("Close Tab", systemImage: "xmark") {
                store.closeTab(id: tab.id)
            }
        }
    }
}


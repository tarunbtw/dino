//
//  QuickSwitcherPanel.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//

import SwiftUI
import AppKit

/// Visual ⌃Tab Quick Switcher HUD showing recent tabs as cards with page snapshots.
struct QuickSwitcherPanel: View {
    @ObservedObject var store: BrowserStore

    private let cardWidth: CGFloat = 160
    private let cardHeight: CGFloat = 100

    var body: some View {
        let tabs = store.recentTabsForActiveSpace
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let spaceColor = Theme.spaceColor(store.activeSpace.colorHex)

        ZStack {
            // Subtle backdrop
            Theme.commandDim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    store.cancelTabSwitch()
                }

            // Cards Panel
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    let isPicked = tab.id == store.quickSwitcherPickedId
                    cardView(for: tab, isPicked: isPicked, spaceColor: spaceColor)
                }
            }
            .padding(12)
            .background {
                shape.fill(Theme.page)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 28, y: 10)
            .shadow(color: Color.black.opacity(0.20), radius: 4, y: 1)
        }
    }

    @ViewBuilder
    private func cardView(for tab: Tab, isPicked: Bool, spaceColor: Color) -> some View {
        let pictureShape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        Button {
            store.pickTabSwitch(id: tab.id)
            store.finishTabSwitch()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Page Snapshot or Favicon
                ZStack {
                    if let snapshot = store.tabSnapshots[tab.id] {
                        Image(nsImage: snapshot)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                    } else {
                        Theme.hover
                            .overlay {
                                if let favicon = tab.favicon {
                                    Image(nsImage: favicon)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                } else {
                                    Image(systemName: "globe")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Theme.faint)
                                }
                            }
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(pictureShape)
                .overlay {
                    pictureShape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
                }
                .overlay {
                    // Pick ring in space accent color
                    if isPicked {
                        pictureShape.inset(by: -2.5)
                            .strokeBorder(spaceColor, lineWidth: 2.5)
                            .shadow(color: spaceColor.opacity(0.55), radius: 6)
                    }
                }

                // Favicon & Title
                HStack(spacing: 6) {
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

                    Text(tab.title.isEmpty ? (tab.url?.host ?? "Tab") : tab.title)
                        .font(Theme.font(size: 12))
                        .foregroundStyle(isPicked ? Theme.ink : Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: cardWidth, alignment: .leading)
            }
            .padding(6)
            .background(isPicked ? Theme.press : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHover in
            if isHover {
                store.pickTabSwitch(id: tab.id)
            }
        }
    }
}

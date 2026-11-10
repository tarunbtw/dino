//
//  MiniPlayer.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//

import SwiftUI
import AppKit

/// Frosted Mini Player capsule appearing above the spaces row when a background tab is playing media.
struct MiniPlayer: View {
    @ObservedObject var store: BrowserStore

    var body: some View {
        if let tab = store.miniPlayerTab {
            MiniPlayerCard(tab: tab) {
                store.selectTab(id: tab.id)
            }
            .id(tab.id)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
}

private struct MiniPlayerCard: View {
    @ObservedObject var tab: Tab
    let onSelect: () -> Void

    @State private var isHovering = false

    private var site: String {
        let host = tab.url?.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 100, style: .continuous)
        let isPaused = tab.isAudioPausedByPlayer

        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Site Icon
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

                // Title and Site
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title.isEmpty ? site : tab.title)
                        .font(Theme.font(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(site.isEmpty ? "Media" : site)
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Play / Pause Button
                Button {
                    tab.toggleMediaPlayback()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 22, height: 22)
                        .background(Theme.press, in: Circle())
                }
                .buttonStyle(.plain)
                .help(isPaused ? "Play" : "Pause")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background {
                shape.fill(Theme.page)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Show playing tab")
    }
}


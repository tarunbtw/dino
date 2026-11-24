//
//  MiniPlayer.swift
//  dino
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

    private var displayTitle: String {
        let raw = tab.title.isEmpty ? site : tab.title
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("▶") {
            cleaned = cleaned.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.isEmpty ? (site.isEmpty ? "Media" : site) : cleaned
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 100, style: .continuous)
        let isPaused = tab.isAudioPausedByPlayer || !tab.isPlayingAudio

        HStack(spacing: 8) {
            // Main clickable body to select and jump to the playing tab
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    // Site / Media Icon
                    if let favicon = tab.favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 2.5))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 14, height: 14)
                    }

                    // Title and Site
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayTitle)
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Play / Pause Button (toggles media without switching tabs)
            Button {
                tab.toggleMediaPlayback()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 9.5, weight: .semibold))
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
            shape.fill(Theme.surface)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .help("Jump to playing tab")
    }
}

//
//  SpaceRow.swift
//  dino
//
//  Modern HeroUI-inspired Space / Profile switcher capsule with gradient avatar orb.
//

import SwiftUI
import AppKit

/// Smooth organic gradient avatar orb for a Space / Profile.
struct SpaceAvatarOrb: View {
    let colorHex: String
    let name: String
    var size: CGFloat = 18

    var body: some View {
        let baseColor = Theme.spaceColor(colorHex)
        let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: baseColor.opacity(0.95), location: 0.0),
                            .init(color: baseColor.opacity(0.65), location: 0.65),
                            .init(color: Theme.frame.opacity(0.9), location: 1.0)
                        ],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: size * 0.85
                    )
                )

            // Crisp translucent inner specular sheen
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )

            if !initial.isEmpty {
                Text(initial)
                    .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: baseColor.opacity(0.25), radius: 3, y: 1)
    }
}

struct SpaceRow: View {
    @ObservedObject var store: BrowserStore
    @State private var isHovering = false

    var body: some View {
        let space = store.activeSpace

        HStack(spacing: 4) {
            Menu {
                ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, s in
                    if index < 9 {
                        Button(action: {
                            store.switchSpace(id: s.id)
                        }) {
                            if s.id == store.activeSpaceId {
                                Label(s.name, systemImage: "checkmark")
                            } else {
                                Text(s.name)
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
                    } else {
                        Button(action: {
                            store.switchSpace(id: s.id)
                        }) {
                            if s.id == store.activeSpaceId {
                                Label(s.name, systemImage: "checkmark")
                            } else {
                                Text(s.name)
                            }
                        }
                    }
                }

                Divider()

                Button("New Space…") {
                    store.isShowingNewSpaceSheet = true
                }

                Button("Space Settings…") {
                    store.openSettings(section: "Spaces")
                }
            } label: {
                HStack(spacing: 7) {
                    SpaceAvatarOrb(colorHex: space.colorHex, name: space.name, size: 18)

                    Text(space.name)
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.leading, 6)
                .padding(.trailing, 10)
                .frame(height: 30)
                .background(isHovering ? Theme.surfaceHover : Theme.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(isHovering ? Theme.borderHover : Theme.border, lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .help("Switch Space")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

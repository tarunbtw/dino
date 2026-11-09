//
//  SpaceRow.swift
//  nomad
//
//  The row at the bottom of the sidebar: the active space's name, centered,
//  with a native pop-up menu for switching or configuring spaces.
//

import SwiftUI
import AppKit

struct SpaceRow: View {
    @ObservedObject var store: BrowserStore
    @State private var isHovering = false

    var body: some View {
        let space = store.activeSpace
        VStack(spacing: 3) {
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
                Text(space.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.spaceInk(space.colorHex))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        isHovering ? Theme.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { isHovering = $0 }
            .help("Spaces")

            if store.spaces.count > 1 {
                HStack(spacing: 4) {
                    ForEach(store.spaces) { s in
                        Circle()
                            .fill(s.id == store.activeSpaceId ? Theme.ink : Theme.faint)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

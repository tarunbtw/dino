//
//  SettingsView+Spaces.swift
//  dino
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit

extension SettingsView {
    var spacesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "Spaces", subtitle: "Manage your contextual workspaces, custom colors, and tabs.")

            // Spaces List & Selection
            card(title: "Your Spaces") {
                VStack(spacing: 6) {
                    ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, s in
                        let isSelected = s.id == store.activeSpaceId
                        let spaceColor = Color(hex: s.colorHex)

                        HStack(spacing: 12) {
                            Circle()
                                .fill(spaceColor)
                                .frame(width: 10, height: 10)

                            Text(s.name)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(Theme.ink)

                            Spacer()

                            if index < 9 {
                                Text("⌃\(index + 1)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.faint)
                            }

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Theme.press : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.switchSpace(id: s.id)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Button(action: {
                        store.isShowingNewSpaceSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("New Space…")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.press, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Edit Active Space
            let activeSpace = store.activeSpace
            card(title: "Space Details: \(activeSpace.name)") {
                VStack(alignment: .leading, spacing: 14) {
                    // Space Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)

                        TextField("Space Name", text: Binding(
                            get: { activeSpace.name },
                            set: { newName in
                                if let idx = store.spaces.firstIndex(where: { $0.id == activeSpace.id }) {
                                    store.spaces[idx].name = newName
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    }

                    // Space Color Palette
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)

                        HStack(spacing: 8) {
                            ForEach(Theme.spaceColors, id: \.name) { item in
                                let isPicked = activeSpace.colorHex.lowercased() == item.hex.lowercased()
                                Button(action: {
                                    if let idx = store.spaces.firstIndex(where: { $0.id == activeSpace.id }) {
                                        store.spaces[idx].colorHex = item.hex
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: item.hex))
                                            .frame(width: 22, height: 22)

                                        if isPicked {
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: 2)
                                                .frame(width: 22, height: 22)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(item.name.capitalized)
                            }
                        }
                    }
                }
            }

            // Delete Space
            if store.spaces.count > 1 {
                card(title: "Delete Space") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete “\(activeSpace.name)”")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Its tabs will be merged into the primary space.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("Delete Space", role: .destructive) {
                            store.deleteSpace(id: activeSpace.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
        }
    }
}

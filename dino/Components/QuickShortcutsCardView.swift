//
//  QuickShortcutsCardView.swift
//  dino
//
//  One-time centered card showing core keybinds right after onboarding completes.
//

import SwiftUI

struct QuickShortcutsCardView: View {
    let onDismiss: () -> Void

    @State private var isHoveringDone = false

    private let shortcuts: [(label: String, keys: String)] = [
        ("New tab", "⌘T"),
        ("Address bar", "⌘L"),
        ("Command palette", "⌘K"),
        ("Toggle sidebar", "⌘S"),
        ("Split view", "⌥⌘S")
    ]

    var body: some View {
        ZStack {
            Theme.commandDim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
            VStack(alignment: .leading, spacing: 18) {
                Text("Keybinds")
                    .font(Theme.panelTitleFont)
                    .foregroundStyle(Theme.ink)

                VStack(spacing: 10) {
                    ForEach(shortcuts, id: \.label) { item in
                        HStack {
                            Text(item.label)
                                .font(Theme.tabFont)
                                .foregroundStyle(Theme.ink)

                            Spacer()

                            Text(item.keys)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Theme.surfaceHover)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Theme.border, lineWidth: 1)
                                )
                        }
                    }
                }

                HStack {
                    Spacer()

                    Button("Got it", action: onDismiss)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.frame)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                                .fill(isHoveringDone ? Theme.accent.opacity(0.9) : Theme.accent)
                        )
                        .buttonStyle(.plain)
                        .onHover { isHoveringDone = $0 }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 2)
            }
            .padding(24)
            .frame(width: 360)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.borderHover, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
            .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onDismiss)
    }
}

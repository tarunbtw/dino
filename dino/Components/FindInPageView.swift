//
//  FindInPageView.swift
//  dino
//
//  Created by tarun on 10/12/26.
//

import SwiftUI
import AppKit

/// Sleek floating Find in Page search bar (⌘F) positioned in the top-right corner of the web canvas.
/// Follows Firn's frosted glass styling, match occurrence counting, and smooth navigation.
struct FindInPageView: View {
    @ObservedObject var tab: Tab
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)

            TextField("Find on page", text: Binding(
                get: { tab.findQuery },
                set: { tab.findInPage($0, forward: true) }
            ))
            .textFieldStyle(.plain)
            .font(Theme.tabFont)
            .foregroundStyle(Theme.ink)
            .focused($isFieldFocused)
            .onSubmit {
                let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                tab.findInPage(tab.findQuery, forward: !backwards)
                isFieldFocused = true
            }
            .onExitCommand {
                tab.closeFind()
            }

            if !tab.findQuery.isEmpty {
                let count = tab.findCount ?? (tab.findHasMatches ? 1 : 0)
                Text(FindOnPage.label(count: count))
                    .font(Theme.font(size: 11))
                    .foregroundStyle(tab.findHasMatches ? Theme.muted : Theme.faint)
                    .monospacedDigit()
                    .fixedSize()
            }

            HStack(spacing: 2) {
                FindIconButton(systemImage: "chevron.up", help: "Previous match (⇧Return)") {
                    tab.findInPage(tab.findQuery, forward: false)
                }
                .disabled(tab.findQuery.isEmpty || !tab.findHasMatches)

                FindIconButton(systemImage: "chevron.down", help: "Next match (Return)") {
                    tab.findInPage(tab.findQuery, forward: true)
                }
                .disabled(tab.findQuery.isEmpty || !tab.findHasMatches)

                FindIconButton(systemImage: "xmark", help: "Close (Esc)") {
                    tab.closeFind()
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: 320, height: Theme.rowHeight)
        .background {
            shape.fill(Theme.page)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 6)
        .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
        .onAppear {
            isFieldFocused = true
        }
    }
}

/// Frosted icon button for Find in Page controls.
private struct FindIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isEnabled ? (isHovered ? Theme.ink : Theme.muted) : Theme.faint.opacity(0.4))
                .frame(width: 22, height: 22)
                .background(isHovered && isEnabled ? Theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

//
//  Door.swift
//  dino
//
//  HeroUI-aligned compact icon button (28x28) for sidebar controls.
//

import SwiftUI

struct Door: View {
    let icon: String
    var on: Bool = false
    var help: String = ""
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(on ? Theme.ink : (isHovering ? Theme.ink : Theme.muted))
                .frame(width: 26, height: 26)
                .background(
                    shape.fill(on ? Theme.surfaceHover : (isHovering ? Theme.hover : Color.clear))
                )
                .overlay {
                    if on || isHovering {
                        shape.strokeBorder(Theme.border, lineWidth: 1)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .help(help)
    }
}

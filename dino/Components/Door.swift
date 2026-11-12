//
//  Door.swift
//  dino
//
//  Created by tarun on 11/10/26.
//

import SwiftUI

/// Minimal 26x26 door icon button matching Search (Side.swift).
struct Door: View {
    let icon: String
    var on: Bool = false
    var help: String = ""
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? Theme.ink : (isHovering ? Theme.ink : Theme.muted))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? Theme.press : (isHovering ? Theme.hover : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}


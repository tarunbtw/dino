//
//  DinoStageScene.swift
//  dino
//
//  Clean atmospheric landscape stage for empty tabs and browser backdrop.
//

import SwiftUI
import AppKit

struct DinoStageScene: View {
    let spaceColor: String

    init(spaceColor: String = "blue") {
        self.spaceColor = spaceColor
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.page

                Image("DinoBackdrop")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                // Subtle atmospheric darkening veil for crisp Chromium Dark Mode legibility
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.18), location: 0.0),
                        .init(color: Color.black.opacity(0.28), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.page)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

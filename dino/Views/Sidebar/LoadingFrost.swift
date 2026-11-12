//
//  LoadingFrost.swift
//  dino
//
//  Created by tarun on 10/11/26.
//

import SwiftUI
import AppKit

/// Address bar loading progress frost matching Firn's linear gradient shimmer.
struct LoadingFrost: View {
    let isLoading: Bool
    let progress: Double
    let spaceColorHex: String

    @State private var formed: Double = 0.0
    @State private var isShown: Bool = false

    var body: some View {
        GeometryReader { geo in
            let tintColor = Theme.spaceColor(spaceColorHex)
            let width = geo.size.width * CGFloat(formed * 1.2)

            ZStack(alignment: .leading) {
                // Main Gradient Bar
                LinearGradient(
                    stops: [
                        .init(color: tintColor.opacity(0.35), location: 0),
                        .init(color: tintColor.opacity(0.35), location: 0.8),
                        .init(color: tintColor.opacity(0.0), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)

                // Front Edge Glow
                let glowColor = tintColor.opacity(0.6)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [glowColor, glowColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 18
                        )
                    )
                    .frame(width: 36, height: geo.size.height * 1.5)
                    .position(x: max(18, width * 0.85), y: geo.size.height / 2)
            }
        }
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(false)
        .onChange(of: isLoading, initial: true) { _, loading in
            if loading {
                start()
            } else if isShown {
                thaw()
            }
        }
        .onChange(of: progress) { _, val in
            guard isLoading, val > formed else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                formed = val
            }
        }
    }

    private func start() {
        formed = 0.08
        isShown = true
        withAnimation(.easeOut(duration: 0.3)) {
            formed = max(0.12, progress)
        }
    }

    private func thaw() {
        withAnimation(.easeOut(duration: 0.2)) {
            formed = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.25)) {
                isShown = false
            }
            formed = 0.0
        }
    }
}


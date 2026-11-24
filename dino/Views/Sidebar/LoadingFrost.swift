//
//  LoadingFrost.swift
//  dino
//
//  Reactive address bar loading progress shimmer synced directly to Tab KVO updates.
//

import SwiftUI
import AppKit

/// Address bar loading progress shimmer.
struct LoadingFrost: View {
    let isLoading: Bool
    let progress: Double
    let spaceColorHex: String

    @State private var formed: Double = 0.0
    @State private var isShown: Bool = false
    @State private var thawTask: Task<Void, Never>? = nil

    var body: some View {
        GeometryReader { geo in
            let tintColor = Theme.accent
            let width = geo.size.width * CGFloat(formed * 1.15)

            ZStack(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: tintColor.opacity(0.22), location: 0.0),
                        .init(color: tintColor.opacity(0.26), location: 0.78),
                        .init(color: tintColor.opacity(0.0), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)

                let glowColor = tintColor.opacity(0.45)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [glowColor, glowColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 16
                        )
                    )
                    .frame(width: 32, height: geo.size.height * 1.4)
                    .position(x: max(16, width * 0.85), y: geo.size.height / 2)
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
            guard isLoading else { return }
            if !isShown {
                isShown = true
            }
            if val > formed {
                withAnimation(.easeOut(duration: 0.22)) {
                    formed = val
                }
            }
        }
    }

    private func start() {
        thawTask?.cancel()
        thawTask = nil
        formed = max(0.08, progress)
        isShown = true
        withAnimation(.easeOut(duration: 0.25)) {
            formed = max(0.14, progress)
        }
    }

    private func thaw() {
        thawTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            formed = 1.0
        }
        thawTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    isShown = false
                }
                formed = 0.0
            }
        }
    }
}

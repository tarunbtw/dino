//
//  Palette.swift
//  nomad
//
//  Mathematical paired-grey color system, metrics, and card modifiers
//  inspired by officecommun.com/search.
//

import SwiftUI
import AppKit

/// Paired light/dark greys where the page is the ground and UI chrome recedes.
enum Palette {
    static let ground = Color(nsColor: NS.ground)
    static let ink = Color(nsColor: NS.ink)
    static let muted = Color(nsColor: NS.muted)
    static let faint = Color(nsColor: NS.faint)
    static let hairline = Color(nsColor: NS.hairline)
    static let wash = Color(nsColor: NS.wash)
    static let pinLive = Color(nsColor: NS.pinLive)
    static let hover = Color(nsColor: NS.hover)
    static let frame = Color(nsColor: NS.frame)
    static let sideWash = Color(nsColor: NS.sideWash)
    static let sideHover = Color(nsColor: NS.sideHover)
    static let sideTile = Color(nsColor: NS.sideTile)
    static let sidePinLive = Color(nsColor: NS.sidePinLive)

    enum NS {
        static let ground = pair(1.0, 0.11)
        static let ink = pair(0.09, 0.93)
        static let muted = pair(0.55, 0.58)
        static let faint = pair(0.83, 0.32)
        static let hairline = pair(0.91, 0.20)
        static let wash = pair(0.937, 0.175)
        static let pinLive = pair(0.90, 0.21)
        static let hover = pair(0.965, 0.15)
        static let frame = pair(0.955, 0.075)
        static let sideWash = pair(0.895, 0.155)
        static let sideHover = pair(0.915, 0.13)
        static let sideTile = pair(0.925, 0.115)
        static let sidePinLive = pair(0.86, 0.19)

        private static func pair(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
            NSColor(name: nil) { appearance in
                let dim = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(white: dim ? dark : light, alpha: 1)
            }
        }
    }
}

/// Precise layout metrics for Search-grade minimalism.
enum Metrics {
    static let strip: CGFloat = 52
    static let cardGap: CGFloat = 8
    static let cardRadius: CGFloat = 10
    static let lights: CGFloat = 100
    static let sideLights: CGFloat = 80
    static let tabWidth: CGFloat = 186
    static let tabTitled: CGFloat = 80
    static let tabMinWidth: CGFloat = 36
    static let tabGap: CGFloat = 3
    static let pinWidth: CGFloat = 32
    static let plusWidth: CGFloat = 28
    static let fieldWidth: CGFloat = 560
    static let sideWidth: CGFloat = 220
}

/// Renders the web page as an inset, rounded card with a hairline edge and soft drop shadow.
struct CardEdge: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(Palette.ground)
                        .shadow(color: Color.black.opacity(0.07), radius: 6, x: 0, y: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}


//
//  Palette.swift
//  nomad
//
//  Mathematical paired-grey color system, Firn design tokens, and metrics.
//

import SwiftUI
import AppKit

/// Firn design tokens and metrics.
enum Theme {
    static let frame = Color(hex: 0x3A3734)
    static let frameWash = Color(hex: 0x3A3734, opacity: 0.55)
    static let page = Color(hex: 0x2B2826)
    static let ink = Color(hex: 0xF5F1EC)
    static let muted = Color(hex: 0xD4CDC5)
    static let faint = Color(hex: 0x958D85)
    static let frost = Color(hex: 0xA0C4D6, opacity: 0.45)
    static let accent = Color(hex: 0x82A8BE)
    static let hover = Color(hex: 0xF5F1EC, opacity: 0.07)
    static let press = Color(hex: 0xF5F1EC, opacity: 0.13)
    static let activeTab = Color(hex: 0xF5F1EC, opacity: 0.17)
    static let activeTabHairline = Color(hex: 0x000000, opacity: 0.25)
    static let commandDim = Color(hex: 0x000000, opacity: 0.45)
    static let commandVeil = Color(hex: 0x2B2826, opacity: 0.62)
    static let shadowPeek = Color(hex: 0x000000, opacity: 0.45)

    static let pageInset: CGFloat = 8
    static let pageCornerRadius: CGFloat = 10
    static let rowHeight: CGFloat = 36
    static let tabRadius: CGFloat = 8
    static let fieldRadius: CGFloat = 8
    static let panelRadius: CGFloat = 14
    static let trafficLightsWidth: CGFloat = 85
    static let rowSpacing: CGFloat = 4
    static let rowPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 16

    static let tabFont = Font.system(size: 13)
    static let labelFont = Font.system(size: 12)
    static let groupHeaderFont = Font.system(size: 13, weight: .semibold)
    static let hintFont = Font.system(size: 11)
    static let panelTitleFont = Font.system(size: 22, weight: .regular, design: .serif)

    static let spaceColors: [(name: String, hex: String)] = [
        ("glacier", "#7F9CB0"),
        ("sand", "#C9A27E"),
        ("sage", "#8FAE8B"),
        ("heather", "#B88A9E"),
        ("ochre", "#C4A95B"),
        ("dusk", "#8E8FB8"),
        ("clay", "#B07F6A"),
        ("lagoon", "#6FA3A0")
    ]

    static func spaceColor(_ hex: String) -> Color {
        Color(hex: hex)
    }

    static func spaceInk(_ hex: String) -> Color {
        spaceColor(hex)
    }
}

/// Address utilities for clean domain display.
enum WebAddress {
    static func site(of url: URL?) -> String {
        guard let url else { return "" }
        if url.isFileURL { return url.lastPathComponent }
        if url.scheme == "nomad" { return url.host ?? url.absoluteString }
        guard let host = url.host(percentEncoded: false) else { return url.absoluteString }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let port = url.port { return "\(site):\(port)" }
        return site
    }
}

extension Color {
    init(hex: UInt32, opacity: CGFloat = 1) {
        self.init(nsColor: NSColor(hex: hex, opacity: opacity))
    }

    init(light: UInt32, dark: UInt32, opacity: CGFloat = 1) {
        self.init(hex: dark, opacity: opacity)
    }

    init(light: UInt32, lightOpacity: CGFloat, dark: UInt32, darkOpacity: CGFloat) {
        self.init(hex: dark, opacity: darkOpacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32, opacity: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}

/// Paired light/dark greys where the page is the ground and UI chrome recedes.
enum Palette {
    static let ground = Theme.page
    static let ink = Theme.ink
    static let muted = Theme.muted
    static let faint = Theme.faint
    static let hairline = Color(hex: 0x000000, opacity: 0.25)
    static let wash = Theme.hover
    static let pinLive = Theme.activeTab
    static let hover = Theme.hover
    static let frame = Theme.frame
    static let sideWash = Theme.activeTab
    static let sideHover = Theme.hover
    static let sideTile = Theme.hover
    static let sidePinLive = Theme.activeTab

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


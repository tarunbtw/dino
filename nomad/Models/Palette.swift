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
    @MainActor static var pageCornerRadius: CGFloat {
        guard let window = WindowCorners.shared.radius else { return 10 }
        return min(max(window - pageInset, 6), 24)
    }
    static let rowHeight: CGFloat = 36
    static let tabRadius: CGFloat = 8
    static let fieldRadius: CGFloat = 8
    static let panelRadius: CGFloat = 14
    static let trafficLightsWidth: CGFloat = 85
    static let rowSpacing: CGFloat = 4
    static let rowPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 16

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }

    static let tabFont = Font.system(size: 13)
    static let labelFont = Font.system(size: 12)
    static let groupHeaderFont = Font.system(size: 13, weight: .semibold)
    static let hintFont = Font.system(size: 11)
    static let panelTitleFont = Font.system(size: 22, weight: .regular, design: .serif)

    static let tileRimTop = Color(hex: 0xFFFFFF, opacity: 0.16)
    static let tileRimBottom = Color(hex: 0xFFFFFF, opacity: 0.03)
    static let shadowSoft = Color(hex: 0x000000, opacity: 0.15)
    static let shadowLift = Color(hex: 0x000000, opacity: 0.20)

    static let glide = Animation.spring(response: 0.24, dampingFraction: 0.88)

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

    // MARK: - First Light
    enum FirstLight {
        static let skyTop = Color(hex: 0x2E2F31)
        static let cool = Color(hex: 0x6E98B2, opacity: 0.24)
        static let warm = Color(hex: 0xD69268, opacity: 0.16)
        static let warm2 = Color(hex: 0xA0786E, opacity: 0.10)
        static let sun = Color(hex: 0xD68C60, opacity: 0.32)
        static let sunMid = Color(hex: 0xD68C60, opacity: 0.10)
        static let flake = NSColor(hex: 0x7F9CB0, opacity: 1)
        static let flakeOpacity: Float = 0.22
        static let grainOpacity: Double = 0.50

        static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
            func channel(_ shift: UInt32) -> UInt32 {
                let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
                return UInt32((x + (y - x) * amount).rounded()) << shift
            }
            return channel(16) | channel(8) | channel(0)
        }

        static func spaceHex(_ nameOrHex: String) -> UInt32 {
            switch nameOrHex.lowercased() {
            case "sand": return 0xC9A27E
            case "sage": return 0x8FAE8B
            case "heather": return 0xB88A9E
            case "ochre": return 0xC4A95B
            case "dusk": return 0x8E8FB8
            case "clay": return 0xB07F6A
            case "lagoon": return 0x6FA3A0
            case "glacier": return 0x7F9CB0
            default:
                let clean = nameOrHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if let val = UInt32(clean, radix: 16) { return val }
                return 0x7F9CB0
            }
        }

        static func snow(_ space: String) -> [Color] {
            let tint = spaceHex(space)
            if tint == 0x7F9CB0 {
                return [0x34353A, 0x3A3F46, 0x414B55, 0x495865, 0x536777].map { Color(hex: $0) }
            }
            return [0.12, 0.20, 0.29, 0.38, 0.48].map {
                Color(hex: mix(0x2B2826, tint, $0))
            }
        }
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

/// Frosted backdrop with space tint and dual hairline rim for modal sheets.
struct CommandBarGlass: View {
    let shape: RoundedRectangle
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            shape.fill(Theme.page)
                .overlay { shape.fill(color.opacity(0.18)) }
                .overlay { shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5) }
        } else {
            shape.fill(.regularMaterial)
                .overlay { shape.fill(Theme.commandVeil) }
                .overlay { shape.fill(color.opacity(0.18)) }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .overlay { shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5) }
        }
    }
}


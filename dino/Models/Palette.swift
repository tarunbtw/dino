//
//  Palette.swift
//  dino
//
//  Mathematical paired-grey color system, Firn design tokens, and metrics.
//

import SwiftUI
import AppKit

/// Chromium Dark Mode & HeroUI design tokens and metrics.
enum Theme {
    // MARK: - Chromium Dark Mode Surfaces
    static let frame = Color(hex: 0x1F1F1F)
    static let frameWash = Color(hex: 0x1F1F1F, opacity: 0.65)
    static let page = Color(hex: 0x28292A)
    static let surface = Color(hex: 0x2D2E31)
    static let surfaceHover = Color(hex: 0x35363A)
    static let surfaceActive = Color(hex: 0x3C4043)

    // MARK: - HeroUI Hairline Borders
    static let border = Color(hex: 0xFFFFFF, opacity: 0.08)
    static let borderHover = Color(hex: 0xFFFFFF, opacity: 0.16)

    // MARK: - Typography & Accents
    static let ink = Color(hex: 0xE8EAED)
    static let muted = Color(hex: 0x9AA0A6)
    static let faint = Color(hex: 0x5F6368)
    static let frost = Color(hex: 0x8AB4F8, opacity: 0.45)
    static let accent = Color(hex: 0x8AB4F8)
    static let accentFaint = Color(hex: 0x8AB4F8, opacity: 0.16)

    // MARK: - Interactive States
    static let hover = Color(hex: 0xFFFFFF, opacity: 0.06)
    static let press = Color(hex: 0xFFFFFF, opacity: 0.11)
    static let activeTab = Color(hex: 0x35363A)
    static let activeTabHairline = Color(hex: 0xFFFFFF, opacity: 0.08)
    static let commandDim = Color(hex: 0x000000, opacity: 0.52)
    static let commandVeil = Color(hex: 0x202124, opacity: 0.78)
    static let shadowPeek = Color(hex: 0x000000, opacity: 0.48)

    static let pageInset: CGFloat = 8
    @MainActor static var pageCornerRadius: CGFloat {
        guard let window = WindowCorners.shared.radius else { return 10 }
        return min(max(window - pageInset, 6), 24)
    }
    static let rowHeight: CGFloat = 34
    static let tabRadius: CGFloat = 8
    static let fieldRadius: CGFloat = 10
    static let panelRadius: CGFloat = 14
    static let trafficLightsWidth: CGFloat = 85
    static let rowSpacing: CGFloat = 3
    static let rowPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 16

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }

    static let tabFont = Font.system(size: 13)
    static let labelFont = Font.system(size: 12)
    static let groupHeaderFont = Font.system(size: 12.5, weight: .semibold)
    static let hintFont = Font.system(size: 11)
    static let panelTitleFont = Font.system(size: 22, weight: .medium)

    static let tileRimTop = Color(hex: 0xFFFFFF, opacity: 0.12)
    static let tileRimBottom = Color(hex: 0xFFFFFF, opacity: 0.03)
    static let shadowSoft = Color(hex: 0x000000, opacity: 0.18)
    static let shadowLift = Color(hex: 0x000000, opacity: 0.24)

    static let glide = Animation.spring(response: 0.24, dampingFraction: 0.88)

    static let spaceColors: [(name: String, hex: String)] = [
        ("blue", "#8AB4F8"),
        ("mint", "#81C995"),
        ("lavender", "#C58AF9"),
        ("coral", "#F28B82"),
        ("amber", "#FDD663"),
        ("cyan", "#78D9EC"),
        ("rose", "#FF8BCB"),
        ("slate", "#9AA0A6")
    ]

    static func spaceColor(_ hex: String) -> Color {
        Color(hex: hex)
    }

    // MARK: - Ambient Tint Helper
    enum FirstLight {
        static func spaceHex(_ nameOrHex: String) -> UInt32 {
            switch nameOrHex.lowercased() {
            case "blue": return 0x8AB4F8
            case "mint": return 0x81C995
            case "lavender": return 0xC58AF9
            case "coral": return 0xF28B82
            case "amber": return 0xFDD663
            case "cyan": return 0x78D9EC
            case "rose": return 0xFF8BCB
            case "slate": return 0x9AA0A6
            default:
                let clean = nameOrHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if let val = UInt32(clean, radix: 16) { return val }
                return 0x8AB4F8
            }
        }
    }
}

/// Address utilities for clean domain display.
enum WebAddress {
    static func site(of url: URL?) -> String {
        guard let url else { return "" }
        if url.isFileURL { return url.lastPathComponent }
        if url.scheme == "dino" { return url.host ?? url.absoluteString }
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


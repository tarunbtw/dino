//
//  DinoAvatar.swift
//  dino
//
//  Executive-grade Spaces emblem engine.
//  Replaces cartoon character doodles with sleek Apple-grade continuous squircle badges.
//

import SwiftUI
import AppKit

/// Deterministic, executive-grade Space emblem tinted by space accent colors.
public struct DinoAvatar: View {
    public let seed: String
    public let colorHex: String
    public var size: CGFloat = 20
    public var animated: Bool = false

    public init(seed: String, colorHex: String, size: CGFloat = 20, animated: Bool = false) {
        self.seed = seed
        self.colorHex = colorHex
        self.size = size
        self.animated = animated
    }

    private var colors: (base: Color, light: Color, deep: Color) {
        let cleanHex = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let hexVal = UInt32(cleanHex, radix: 16) ?? 0x8AB4F8
        let r = Double((hexVal >> 16) & 0xFF) / 255.0
        let g = Double((hexVal >> 8) & 0xFF) / 255.0
        let b = Double(hexVal & 0xFF) / 255.0

        let base = Color(red: r, green: g, blue: b)
        let light = Color(red: min(1.0, r * 1.25 + 0.10), green: min(1.0, g * 1.25 + 0.10), blue: min(1.0, b * 1.25 + 0.10))
        let deep = Color(red: max(0.0, r * 0.70), green: max(0.0, g * 0.70), blue: max(0.0, b * 0.70))
        return (base, light, deep)
    }

    private var symbol: String {
        let symbols = [
            "person.fill",
            "briefcase.fill",
            "terminal.fill",
            "sparkles",
            "cube.fill",
            "globe",
            "square.stack.3d.up.fill",
            "atom"
        ]
        var hash: UInt64 = 14695981039346656037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return symbols[Int(hash % UInt64(symbols.count))]
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        let c = colors

        ZStack {
            // Sleek Apple squircle with space gradient
            shape
                .fill(
                    LinearGradient(
                        colors: [c.light, c.base, c.deep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Inner glass rim highlight
            shape
                .strokeBorder(Color.white.opacity(0.32), lineWidth: max(0.75, size * 0.04))

            // Subtle interior icon
            Image(systemName: symbol)
                .font(.system(size: size * 0.50, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .shadow(color: Color.black.opacity(0.25), radius: 1, y: 0.5)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
    }
}

/// Backward compatibility alias so existing views don't need changes.
public typealias BlobatarAvatar = DinoAvatar

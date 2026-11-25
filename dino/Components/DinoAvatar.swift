//
//  DinoAvatar.swift
//  dino
//
//  Authentic, lightweight Blobatar avatar engine.
//  Generates organic fluid blob characters with expressive eyes and smile.
//

import SwiftUI
import AppKit

/// Organic closed cubic-spline blob geometry.
public struct BlobShape: Shape {
    public let radii: [CGFloat]

    public init(radii: [CGFloat]) {
        self.radii = radii
    }

    public func path(in rect: CGRect) -> Path {
        let count = radii.count
        guard count >= 3 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) * 0.44
        var points: [CGPoint] = []
        for i in 0..<count {
            let angle = CGFloat(i) * 2 * .pi / CGFloat(count) - .pi / 2
            let r = baseRadius * radii[i]
            points.append(CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle)))
        }
        var path = Path()
        let pt: (Int) -> CGPoint = { idx in points[((idx % count) + count) % count] }
        path.move(to: pt(0))
        for i in 0..<count {
            let p0 = pt(i - 1)
            let p1 = pt(i)
            let p2 = pt(i + 1)
            let p3 = pt(i + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}

/// Deterministic, expressive Blobatar tinted by space accent colors.
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

    private var hash: UInt64 {
        var h: UInt64 = 14695981039346656037
        for byte in seed.utf8 {
            h ^= UInt64(byte)
            h &*= 1099511628211
        }
        return h
    }

    private var colors: (base: Color, light: Color, deep: Color) {
        let cleanHex = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let hexVal = UInt32(cleanHex, radix: 16) ?? 0x8AB4F8
        let r = Double((hexVal >> 16) & 0xFF) / 255.0
        let g = Double((hexVal >> 8) & 0xFF) / 255.0
        let b = Double(hexVal & 0xFF) / 255.0

        let base = Color(red: r, green: g, blue: b)
        let light = Color(red: min(1.0, r * 1.25 + 0.12), green: min(1.0, g * 1.25 + 0.12), blue: min(1.0, b * 1.25 + 0.12))
        let deep = Color(red: max(0.0, r * 0.72), green: max(0.0, g * 0.72), blue: max(0.0, b * 0.72))
        return (base, light, deep)
    }

    private var radii: [CGFloat] {
        let count = 6
        var list: [CGFloat] = []
        for i in 0..<count {
            let val = Double((hash >> (i * 5)) & 0x1F) / 31.0
            list.append(CGFloat(0.86 + val * 0.28))
        }
        return list
    }

    public var body: some View {
        let c = colors
        let shape = BlobShape(radii: radii)
        let eyeWidth = max(2.5, size * 0.13)
        let eyeHeight = max(4.0, size * 0.26)
        let eyeSpacing = max(3.5, size * 0.16)
        let ink = Color(red: 0.10, green: 0.11, blue: 0.13)
        let hasSmile = (hash % 2 == 0)
        let isWinking = (!hasSmile && (hash % 5 == 0))
        let eyeTilt = Double((hash >> 30) & 0x7) - 3.5

        ZStack {
            // Fluid organic body
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
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.40), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.75, size * 0.04)
                )

            // Face features
            VStack(spacing: max(1.0, size * 0.04)) {
                // Eyes row
                HStack(spacing: eyeSpacing) {
                    // Left Eye
                    Capsule()
                        .fill(ink)
                        .frame(width: eyeWidth, height: eyeHeight)
                        .overlay(alignment: .topLeading) {
                            Circle()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: max(1.2, eyeWidth * 0.42), height: max(1.2, eyeWidth * 0.42))
                                .offset(x: max(0.5, eyeWidth * 0.15), y: max(0.5, eyeHeight * 0.15))
                        }
                        .rotationEffect(.degrees(-eyeTilt))

                    // Right Eye
                    if isWinking {
                        // Playful wink arc
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: eyeHeight * 0.65))
                            p.addQuadCurve(
                                to: CGPoint(x: eyeWidth * 1.25, y: eyeHeight * 0.65),
                                control: CGPoint(x: eyeWidth * 0.625, y: eyeHeight * 0.15)
                            )
                        }
                        .stroke(ink, style: StrokeStyle(lineWidth: max(1.2, size * 0.055), lineCap: .round))
                        .frame(width: eyeWidth * 1.25, height: eyeHeight)
                    } else {
                        Capsule()
                            .fill(ink)
                            .frame(width: eyeWidth, height: eyeHeight)
                            .overlay(alignment: .topLeading) {
                                Circle()
                                    .fill(Color.white.opacity(0.92))
                                    .frame(width: max(1.2, eyeWidth * 0.42), height: max(1.2, eyeWidth * 0.42))
                                    .offset(x: max(0.5, eyeWidth * 0.15), y: max(0.5, eyeHeight * 0.15))
                            }
                            .rotationEffect(.degrees(eyeTilt))
                    }
                }
                .offset(y: hasSmile ? -size * 0.02 : 0)

                // Friendly little smile
                if hasSmile {
                    Path { p in
                        let w = max(4.0, size * 0.20)
                        let h = max(1.5, size * 0.08)
                        p.move(to: CGPoint(x: 0, y: 0))
                        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w / 2, y: h))
                    }
                    .stroke(ink, style: StrokeStyle(lineWidth: max(1.0, size * 0.05), lineCap: .round))
                    .frame(width: max(4.0, size * 0.20), height: max(1.5, size * 0.08))
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.18), radius: max(1.5, size * 0.06), y: 1)
    }
}

/// Backward compatibility alias so existing views don't need changes.
public typealias BlobatarAvatar = DinoAvatar

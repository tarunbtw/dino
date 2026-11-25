//
//  DinoAvatar.swift
//  dino
//
//  Ultra-lightweight, deterministic character avatar engine.
//  Replaces legacy BlobatarKit (3,386 lines) with a pure, zero-overhead SwiftUI vector avatar.
//

import SwiftUI
import AppKit

/// Deterministic character avatar generated from a seed and tinted by a Space color.
public struct DinoAvatar: View {
    public let seed: String
    public let colorHex: String
    public var size: CGFloat = 20
    public var animated: Bool = false

    @State private var isBlinking = false

    public init(seed: String, colorHex: String, size: CGFloat = 20, animated: Bool = false) {
        self.seed = seed
        self.colorHex = colorHex
        self.size = size
        self.animated = animated
    }

    // Deterministic random numbers from seed
    private var dna: AvatarDNA {
        AvatarDNA(seed: seed, colorHex: colorHex)
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let s = min(w, h)
            let center = CGPoint(x: w / 2, y: h / 2)

            // 1. Draw Body
            drawBody(in: &context, size: s, center: center, dna: dna)

            // 2. Draw Ears / Topper
            drawTopper(in: &context, size: s, center: center, dna: dna)

            // 3. Draw Blush Cheeks
            drawCheeks(in: &context, size: s, center: center, dna: dna)

            // 4. Draw Face (Eyes & Mouth)
            drawFace(in: &context, size: s, center: center, dna: dna, blinking: isBlinking)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true).delay(3.5)) {
                isBlinking = true
            }
        }
    }

    // MARK: - Canvas Rendering

    private func drawBody(in context: inout GraphicsContext, size: CGFloat, center: CGPoint, dna: AvatarDNA) {
        let bodyRect = CGRect(x: center.x - size * 0.44, y: center.y - size * 0.42, width: size * 0.88, height: size * 0.84)
        let path: Path

        switch dna.shape {
        case .squircle:
            path = Path(roundedRect: bodyRect, cornerRadius: size * 0.28, style: .continuous)
        case .capsule:
            path = Path(roundedRect: bodyRect, cornerRadius: size * 0.42, style: .continuous)
        case .pebble:
            path = Path(ellipseIn: bodyRect)
        case .blob:
            var p = Path()
            let r = bodyRect
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addCurve(to: CGPoint(x: r.maxX, y: r.midY), control1: CGPoint(x: r.maxX * 0.95, y: r.minY), control2: CGPoint(x: r.maxX, y: r.midY * 0.9))
            p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY * 0.95), control2: CGPoint(x: r.maxX * 0.9, y: r.maxY))
            p.addCurve(to: CGPoint(x: r.minX, y: r.midY), control1: CGPoint(x: r.minX * 1.1, y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY * 0.95))
            p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX, y: r.midY * 0.9), control2: CGPoint(x: r.minX * 1.1, y: r.minY))
            path = p
        }

        // Body Gradient
        let gradient = Gradient(colors: [dna.colorLight, dna.colorBase, dna.colorDeep])
        context.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: center.x, y: bodyRect.minY), endPoint: CGPoint(x: center.x, y: bodyRect.maxY)))

        // Inner rim lighting
        let strokeColor = Color.white.opacity(0.22)
        context.stroke(path, with: .color(strokeColor), lineWidth: max(0.75, size * 0.04))
    }

    private func drawTopper(in context: inout GraphicsContext, size: CGFloat, center: CGPoint, dna: AvatarDNA) {
        switch dna.topper {
        case .none:
            break
        case .sprout:
            // Cute tiny sprout leaf on head
            let leafX = center.x
            let leafY = center.y - size * 0.42
            var leaf = Path()
            leaf.move(to: CGPoint(x: leafX, y: leafY))
            leaf.addQuadCurve(to: CGPoint(x: leafX + size * 0.14, y: leafY - size * 0.12), control: CGPoint(x: leafX + size * 0.12, y: leafY - size * 0.02))
            leaf.addQuadCurve(to: CGPoint(x: leafX, y: leafY), control: CGPoint(x: leafX + size * 0.02, y: leafY - size * 0.14))
            context.fill(leaf, with: .color(Color.green.opacity(0.85)))
        case .ears:
            // Cute little rounded bear/cat ears
            let earRadius = size * 0.11
            let leftEar = CGRect(x: center.x - size * 0.36, y: center.y - size * 0.46, width: earRadius * 2, height: earRadius * 2)
            let rightEar = CGRect(x: center.x + size * 0.36 - earRadius * 2, y: center.y - size * 0.46, width: earRadius * 2, height: earRadius * 2)
            context.fill(Path(ellipseIn: leftEar), with: .color(dna.colorDeep))
            context.fill(Path(ellipseIn: rightEar), with: .color(dna.colorDeep))
        case .antenna:
            // Little tech antenna with orb
            let stem = Path { p in
                p.move(to: CGPoint(x: center.x, y: center.y - size * 0.4))
                p.addLine(to: CGPoint(x: center.x, y: center.y - size * 0.5))
            }
            context.stroke(stem, with: .color(dna.colorDeep), lineWidth: max(1.0, size * 0.05))
            let orb = CGRect(x: center.x - size * 0.06, y: center.y - size * 0.56, width: size * 0.12, height: size * 0.12)
            context.fill(Path(ellipseIn: orb), with: .color(dna.colorLight))
        }
    }

    private func drawCheeks(in context: inout GraphicsContext, size: CGFloat, center: CGPoint, dna: AvatarDNA) {
        let cheekRadius = size * 0.075
        let cheekY = center.y + size * 0.08
        let leftCheek = CGRect(x: center.x - size * 0.28, y: cheekY, width: cheekRadius * 2, height: cheekRadius * 1.5)
        let rightCheek = CGRect(x: center.x + size * 0.28 - cheekRadius * 2, y: cheekY, width: cheekRadius * 2, height: cheekRadius * 1.5)

        let blushColor = Color.pink.opacity(0.28)
        context.fill(Path(ellipseIn: leftCheek), with: .color(blushColor))
        context.fill(Path(ellipseIn: rightCheek), with: .color(blushColor))
    }

    private func drawFace(in context: inout GraphicsContext, size: CGFloat, center: CGPoint, dna: AvatarDNA, blinking: Bool) {
        let eyeY = center.y - size * 0.02
        let eyeSpacing = size * 0.17
        let eyeColor = dna.isLightBackground ? Color(white: 0.12) : Color.white.opacity(0.92)

        if blinking {
            // Closed blinking eyes (flat line)
            let leftLine = Path { p in
                p.move(to: CGPoint(x: center.x - eyeSpacing - size * 0.05, y: eyeY))
                p.addLine(to: CGPoint(x: center.x - eyeSpacing + size * 0.05, y: eyeY))
            }
            let rightLine = Path { p in
                p.move(to: CGPoint(x: center.x + eyeSpacing - size * 0.05, y: eyeY))
                p.addLine(to: CGPoint(x: center.x + eyeSpacing + size * 0.05, y: eyeY))
            }
            context.stroke(leftLine, with: .color(eyeColor), lineWidth: max(1.2, size * 0.06))
            context.stroke(rightLine, with: .color(eyeColor), lineWidth: max(1.2, size * 0.06))
            return
        }

        switch dna.expression {
        case .dotWithShine:
            let eyeRadius = size * 0.065
            let leftRect = CGRect(x: center.x - eyeSpacing - eyeRadius, y: eyeY - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2)
            let rightRect = CGRect(x: center.x + eyeSpacing - eyeRadius, y: eyeY - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2)
            context.fill(Path(ellipseIn: leftRect), with: .color(eyeColor))
            context.fill(Path(ellipseIn: rightRect), with: .color(eyeColor))

            // Catchlight sparkle
            let shineRadius = eyeRadius * 0.38
            let leftShine = CGRect(x: leftRect.midX - shineRadius * 0.5, y: leftRect.minY + shineRadius * 0.4, width: shineRadius, height: shineRadius)
            let rightShine = CGRect(x: rightRect.midX - shineRadius * 0.5, y: rightRect.minY + shineRadius * 0.4, width: shineRadius, height: shineRadius)
            context.fill(Path(ellipseIn: leftShine), with: .color(Color.white.opacity(0.9)))
            context.fill(Path(ellipseIn: rightShine), with: .color(Color.white.opacity(0.9)))

        case .happyArch:
            let archW = size * 0.1
            let leftArch = Path { p in
                p.move(to: CGPoint(x: center.x - eyeSpacing - archW / 2, y: eyeY + size * 0.02))
                p.addQuadCurve(to: CGPoint(x: center.x - eyeSpacing + archW / 2, y: eyeY + size * 0.02), control: CGPoint(x: center.x - eyeSpacing, y: eyeY - size * 0.06))
            }
            let rightArch = Path { p in
                p.move(to: CGPoint(x: center.x + eyeSpacing - archW / 2, y: eyeY + size * 0.02))
                p.addQuadCurve(to: CGPoint(x: center.x + eyeSpacing + archW / 2, y: eyeY + size * 0.02), control: CGPoint(x: center.x + eyeSpacing, y: eyeY - size * 0.06))
            }
            context.stroke(leftArch, with: .color(eyeColor), lineWidth: max(1.2, size * 0.06))
            context.stroke(rightArch, with: .color(eyeColor), lineWidth: max(1.2, size * 0.06))

        case .wink:
            // Left eye normal dot, right eye wink arch
            let eyeRadius = size * 0.065
            let leftRect = CGRect(x: center.x - eyeSpacing - eyeRadius, y: eyeY - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2)
            context.fill(Path(ellipseIn: leftRect), with: .color(eyeColor))

            let archW = size * 0.1
            let rightArch = Path { p in
                p.move(to: CGPoint(x: center.x + eyeSpacing - archW / 2, y: eyeY + size * 0.02))
                p.addQuadCurve(to: CGPoint(x: center.x + eyeSpacing + archW / 2, y: eyeY + size * 0.02), control: CGPoint(x: center.x + eyeSpacing, y: eyeY - size * 0.06))
            }
            context.stroke(rightArch, with: .color(eyeColor), lineWidth: max(1.2, size * 0.06))

        case .sleepy:
            let lineW = size * 0.09
            let leftLine = Path { p in
                p.move(to: CGPoint(x: center.x - eyeSpacing - lineW / 2, y: eyeY))
                p.addLine(to: CGPoint(x: center.x - eyeSpacing + lineW / 2, y: eyeY))
            }
            let rightLine = Path { p in
                p.move(to: CGPoint(x: center.x + eyeSpacing - lineW / 2, y: eyeY))
                p.addLine(to: CGPoint(x: center.x + eyeSpacing + lineW / 2, y: eyeY))
            }
            context.stroke(leftLine, with: .color(eyeColor), lineWidth: max(1.2, size * 0.06))
            context.stroke(rightLine, with: .color(eyeColor), lineWidth: max(1.2, size * 0.06))
        }

        // Mouth
        let mouthY = center.y + size * 0.12
        let mouthW = size * 0.12
        let mouthPath = Path { p in
            p.move(to: CGPoint(x: center.x - mouthW / 2, y: mouthY))
            p.addQuadCurve(to: CGPoint(x: center.x + mouthW / 2, y: mouthY), control: CGPoint(x: center.x, y: mouthY + size * 0.06))
        }
        context.stroke(mouthPath, with: .color(eyeColor), lineWidth: max(1.0, size * 0.05))
    }
}

/// Backward compatibility alias so existing views don't need changes.
public typealias BlobatarAvatar = DinoAvatar

// MARK: - Avatar DNA Generator

private struct AvatarDNA {
    enum BodyShape: CaseIterable {
        case squircle, capsule, pebble, blob
    }

    enum FaceExpression: CaseIterable {
        case dotWithShine, happyArch, wink, sleepy
    }

    enum Topper: CaseIterable {
        case none, sprout, ears, antenna
    }

    let shape: BodyShape
    let expression: FaceExpression
    let topper: Topper
    let colorBase: Color
    let colorLight: Color
    let colorDeep: Color
    let isLightBackground: Bool

    init(seed: String, colorHex: String) {
        // Deterministic hash from seed string
        var hash: UInt64 = 14695981039346656037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }

        let shapes = BodyShape.allCases
        self.shape = shapes[Int(hash % UInt64(shapes.count))]

        let expressions = FaceExpression.allCases
        self.expression = expressions[Int((hash >> 8) % UInt64(expressions.count))]

        let toppers = Topper.allCases
        self.topper = toppers[Int((hash >> 16) % UInt64(toppers.count))]

        // Color computation
        let cleanHex = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let hexVal = UInt32(cleanHex, radix: 16) ?? 0x3B82F6
        let r = Double((hexVal >> 16) & 0xFF) / 255.0
        let g = Double((hexVal >> 8) & 0xFF) / 255.0
        let b = Double(hexVal & 0xFF) / 255.0

        let base = Color(red: r, green: g, blue: b)
        let light = Color(red: min(1.0, r * 1.25 + 0.1), green: min(1.0, g * 1.25 + 0.1), blue: min(1.0, b * 1.25 + 0.1))
        let deep = Color(red: max(0.0, r * 0.75), green: max(0.0, g * 0.75), blue: max(0.0, b * 0.75))

        self.colorBase = base
        self.colorLight = light
        self.colorDeep = deep

        // Luminance check
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        self.isLightBackground = lum > 0.55
    }
}

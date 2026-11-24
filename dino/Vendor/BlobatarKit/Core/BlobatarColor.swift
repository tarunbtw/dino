import Foundation

/// A color in the OKLCh color space used by Blobatar's authored palette.
public struct BlobatarOKLCH: Sendable, Hashable, Codable {
    public var l: Double
    public var c: Double
    public var h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }
}

/// The three serialized color slots used by a rendered blobatar.
public struct BlobatarPalette: Sendable, Hashable, Codable {
    public var background: String
    public var head: String
    public var eye: String

    public init(background: String, head: String, eye: String) {
        self.background = background
        self.head = head
        self.eye = eye
    }
}

/// The authored palette before conversion to sRGB hex strings.
public struct BlobatarColorRamp: Sendable, Hashable, Codable {
    public var background: BlobatarOKLCH
    public var head: BlobatarOKLCH
    public var eye: BlobatarOKLCH

    public init(background: BlobatarOKLCH, head: BlobatarOKLCH, eye: BlobatarOKLCH) {
        self.background = background
        self.head = head
        self.eye = eye
    }
}

/// A seed-relative tint endpoint.
public struct BlobatarTint: Sendable, Hashable, Codable {
    public var h: Double
    public var l: Double
    public var pull: Double
    public var c: Double

    public init(h: Double, l: Double, pull: Double, c: Double) {
        self.h = h
        self.l = l
        self.pull = pull
        self.c = c
    }
}

/// Exact Swift port of Blobatar 2.4.0's authored OKLCh palette pipeline.
public enum BlobatarColor {
    public static let hot = BlobatarTint(h: 27, l: 0.58, pull: 0.6, c: 0.18)
    public static let rose = BlobatarTint(h: 358, l: 0.72, pull: 0.55, c: 0.16)
    public static let blush = BlobatarTint(h: 12, l: 0.84, pull: 0.4, c: 0.1)
    public static let bile = BlobatarTint(h: 142, l: 0.66, pull: 0.6, c: 0.13)

    public static let HOT = hot
    public static let ROSE = rose
    public static let BLUSH = blush
    public static let BILE = bile

    public static let tints: [(name: String, tint: BlobatarTint)] = [
        ("hot", hot),
        ("rose", rose),
        ("blush", blush),
        ("bile", bile),
    ]

    public static let TINTS = tints

    public static let darkSurface = BlobatarOKLCH(l: 0.145, c: 0, h: 0)
    public static let surfaceFloor = 1.5
    public static let tintFloor = 4.55

    private struct Tone: Sendable {
        let edge: Double
        let l: Double
        let c: Double
    }

    private static let tones = [
        Tone(edge: 0.2, l: 0.86, c: 0.085),
        Tone(edge: 0.36, l: 0.9, c: 0.028),
        Tone(edge: 0.62, l: 0.73, c: 0.135),
        Tone(edge: 0.8, l: 0.62, c: 0.165),
        Tone(edge: 0.93, l: 0.87, c: 0.16),
        Tone(edge: 1.0, l: 0.34, c: 0.035),
    ]

    /// Minimum contrast ratios, in their application order.
    public static let floors: [(foreground: String, background: String, ratio: Double)] = [
        ("head", "bg", 1.25),
        ("eye", "head", 4.5),
    ]

    public static let FLOORS = floors

    /// OKLCh to linear-light sRGB. Components can be outside `0...1`.
    private static func toLinear(_ color: BlobatarOKLCH) -> (Double, Double, Double) {
        let radians = color.h * .pi / 180
        let a = color.c * cos(radians)
        let b = color.c * sin(radians)

        let lPrime = color.l + 0.3963377774 * a + 0.2158037573 * b
        let mPrime = color.l - 0.1055613458 * a - 0.0638541728 * b
        let sPrime = color.l - 0.0894841775 * a - 1.291485548 * b

        let l = lPrime * lPrime * lPrime
        let m = mPrime * mPrime * mPrime
        let s = sPrime * sPrime * sPrime

        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
        )
    }

    private static func isInGamut(_ rgb: (Double, Double, Double)) -> Bool {
        rgb.0 >= -1e-4 && rgb.0 <= 1 + 1e-4
            && rgb.1 >= -1e-4 && rgb.1 <= 1 + 1e-4
            && rgb.2 >= -1e-4 && rgb.2 <= 1 + 1e-4
    }

    /// Resolves to in-gamut linear sRGB by reducing chroma rather than clipping hue.
    private static func resolve(_ color: BlobatarOKLCH) -> (Double, Double, Double) {
        var rgb = toLinear(color)
        if !isInGamut(rgb) {
            var low = 0.0
            var high = color.c
            for _ in 0..<12 {
                let middle = (low + high) / 2
                var probe = color
                probe.c = middle
                if isInGamut(toLinear(probe)) {
                    low = middle
                } else {
                    high = middle
                }
            }
            var resolved = color
            resolved.c = low
            rgb = toLinear(resolved)
        }
        return (clamp(rgb.0), clamp(rgb.1), clamp(rgb.2))
    }

    private static func luminance(_ color: BlobatarOKLCH) -> Double {
        let rgb = resolve(color)
        return 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2
    }

    public static func contrast(_ a: BlobatarOKLCH, _ b: BlobatarOKLCH) -> Double {
        let x = luminance(a)
        let y = luminance(b)
        return (Swift.max(x, y) + 0.05) / (Swift.min(x, y) + 0.05)
    }

    public static func ensureContrast(
        _ foreground: BlobatarOKLCH,
        _ background: BlobatarOKLCH,
        minimum: Double
    ) -> BlobatarOKLCH {
        if contrast(foreground, background) >= minimum {
            return foreground
        }

        let lean = foreground.l >= background.l ? 1.0 : -1.0
        for direction in [lean, -lean] {
            var probe = foreground
            for _ in 0..<60 {
                probe.l = clamp(probe.l + direction * 0.02)
                if contrast(probe, background) >= minimum {
                    return probe
                }
                if probe.l == 0 || probe.l == 1 {
                    break
                }
            }
        }

        var black = foreground
        black.l = 0
        black.c = 0
        var white = foreground
        white.l = 1
        white.c = 0
        return contrast(black, background) >= contrast(white, background) ? black : white
    }

    public static func ensureContrast(
        _ foreground: BlobatarOKLCH,
        _ background: BlobatarOKLCH,
        min minimum: Double
    ) -> BlobatarOKLCH {
        ensureContrast(foreground, background, minimum: minimum)
    }

    public static func toHex(_ color: BlobatarOKLCH) -> String {
        let rgb = resolve(color)
        let channels = [rgb.0, rgb.1, rgb.2].map { value -> Int in
            let encoded = value <= 0.0031308
                ? 12.92 * value
                : 1.055 * pow(value, 1 / 2.4) - 0.055
            return Int((encoded * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", channels[0], channels[1], channels[2])
    }

    public static func fromHex(_ hex: String) -> BlobatarOKLCH {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0
        let bytes = [
            Double((value >> 16) & 255),
            Double((value >> 8) & 255),
            Double(value & 255),
        ]
        let rgb = bytes.map { byte -> Double in
            let encoded = byte / 255
            return encoded <= 0.04045
                ? encoded / 12.92
                : pow((encoded + 0.055) / 1.055, 2.4)
        }

        let l = cbrt(0.4122214708 * rgb[0] + 0.5363325363 * rgb[1] + 0.0514459929 * rgb[2])
        let m = cbrt(0.2119034982 * rgb[0] + 0.6806995451 * rgb[1] + 0.1073969566 * rgb[2])
        let s = cbrt(0.0883024619 * rgb[0] + 0.2817188376 * rgb[1] + 0.6299787005 * rgb[2])

        let a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s

        return BlobatarOKLCH(
            l: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            c: hypot(a, b),
            h: atan2(b, a) * 180 / .pi
        )
    }

    /// Blends in cartesian OKLab, matching `color-mix(in oklab, ...)`.
    public static func mix(_ a: BlobatarOKLCH, _ b: BlobatarOKLCH, t: Double) -> BlobatarOKLCH {
        let ax = a.c * cos(a.h * .pi / 180)
        let ay = a.c * sin(a.h * .pi / 180)
        let bx = b.c * cos(b.h * .pi / 180)
        let by = b.c * sin(b.h * .pi / 180)
        let x = ax + (bx - ax) * t
        let y = ay + (by - ay) * t
        return BlobatarOKLCH(
            l: a.l + (b.l - a.l) * t,
            c: hypot(x, y),
            h: atan2(y, x) * 180 / .pi
        )
    }

    public static func mixHex(_ a: String, _ b: String, t: Double) -> String {
        toHex(mix(fromHex(a), fromHex(b), t: t))
    }

    public static func tinted(
        head: String,
        eye: String,
        tint: BlobatarTint
    ) -> (head: String, eye: String) {
        let base = fromHex(head)
        let baseEye = fromHex(eye)

        var tintedHead = BlobatarOKLCH(
            l: base.l + (tint.l - base.l) * tint.pull,
            c: Swift.max(base.c, tint.c),
            h: tint.h
        )
        tintedHead = ensureContrast(tintedHead, darkSurface, minimum: surfaceFloor)

        var tintedEye = ensureContrast(baseEye, tintedHead, minimum: tintFloor)
        let direction = tintedEye.l >= tintedHead.l ? 1.0 : -1.0
        let headHex = toHex(tintedHead)

        for _ in 0..<40 {
            let eyeHex = toHex(tintedEye)
            var worst = Double.infinity
            for index in 0...10 {
                let amount = Double(index) / 10
                worst = Swift.min(
                    worst,
                    contrast(
                        fromHex(mixHex(eye, eyeHex, t: amount)),
                        fromHex(mixHex(head, headHex, t: amount))
                    )
                )
            }
            if worst >= tintFloor {
                return (headHex, eyeHex)
            }
            let lightness = clamp(tintedEye.l + direction * 0.02)
            if lightness == tintedEye.l {
                return (headHex, eyeHex)
            }
            tintedEye.l = lightness
        }

        return (headHex, toHex(tintedEye))
    }

    public static func tinted(
        _ head: String,
        _ eye: String,
        _ tint: BlobatarTint
    ) -> (head: String, eye: String) {
        tinted(head: head, eye: eye, tint: tint)
    }

    public static func ramp(
        hue: Double,
        enforce: Bool = true,
        tone: Double = 0
    ) -> BlobatarColorRamp {
        let authoredTone = toneAt(tone)
        var head = BlobatarOKLCH(l: authoredTone.l, c: authoredTone.c, h: hue)
        head = ensureContrast(head, darkSurface, minimum: surfaceFloor)
        let background = BlobatarOKLCH(l: 0.965, c: 0.01, h: hue)
        var eye = head.l >= 0.5
            ? BlobatarOKLCH(l: 0.17, c: 0.02, h: hue)
            : BlobatarOKLCH(l: 0.97, c: 0.012, h: hue)

        if enforce {
            head = ensureContrast(head, background, minimum: 1.25)
            eye = ensureContrast(eye, head, minimum: 4.5)
        }

        return BlobatarColorRamp(background: background, head: head, eye: eye)
    }

    public static func palette(
        hue: Double,
        enforce: Bool = true,
        tone: Double = 0
    ) -> BlobatarPalette {
        let authored = ramp(hue: hue, enforce: enforce, tone: tone)
        return BlobatarPalette(
            background: toHex(authored.background),
            head: toHex(authored.head),
            eye: toHex(authored.eye)
        )
    }

    private static func toneAt(_ value: Double) -> Tone {
        for tone in tones where value < tone.edge {
            return tone
        }
        return tones[0]
    }

    private static func clamp(_ value: Double) -> Double {
        Swift.min(1, Swift.max(0, value))
    }
}

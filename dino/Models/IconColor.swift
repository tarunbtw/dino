//
//  IconColor.swift
//  dino
//
//  Extracts and calms a site icon's signature colors into the range
//  of the browser's space palette.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

public nonisolated enum IconColor {
    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public var color: Color {
            Color(red: red, green: green, blue: blue)
        }
    }

    public struct Colors: Equatable, Sendable {
        public let main: RGB
        public let ring: [RGB]
    }

    nonisolated static let side = 32
    nonisolated static let slices = 8

    public nonisolated static func from(png data: Data) -> Colors? {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, noCache),
              let image = CGImageSourceCreateImageAtIndex(source, 0, noCache),
              image.width <= 256, image.height <= 256,
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? colors(rgba: pixels) : nil
    }

    nonisolated static func colors(rgba: [UInt8]) -> Colors? {
        guard let main = pick(rgba: rgba) else { return nil }
        let center = Double(side) / 2
        var found = (0..<slices).map { slice -> HSB? in
            vote(rgba: rgba) { x, y in
                var angle = atan2(Double(y) + 0.5 - center, Double(x) + 0.5 - center)
                if angle < 0 { angle += 2 * .pi }
                return Int((angle / (2 * .pi / Double(slices))).rounded()) % slices == slice
            }.flatMap { $0.colorful >= 2 ? $0.color : nil }
        }
        let known = found
        for slice in 0..<slices where known[slice] == nil {
            for step in 1...slices / 2 {
                if let near = known[(slice + slices - step) % slices] ?? known[(slice + step) % slices] {
                    found[slice] = near
                    break
                }
            }
        }
        return Colors(main: main, ring: found.map { $0.map(calmed) ?? main })
    }

    nonisolated static func pick(rgba: [UInt8]) -> RGB? {
        guard let result = vote(rgba: rgba, include: { _, _ in true }),
              Double(result.colorful) / Double(result.visible) >= 0.05,
              let color = result.color else { return nil }
        return calmed(color)
    }

    private nonisolated static func vote(
        rgba: [UInt8], include: (_ x: Int, _ y: Int) -> Bool
    ) -> (color: HSB?, visible: Int, colorful: Int)? {
        let bins = 24
        var weights = [Double](repeating: 0, count: bins)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: bins)
        var visible = 0
        var colorful = 0
        var index = 0
        while index + 3 < rgba.count {
            defer { index += 4 }
            let pixel = index / 4
            guard include(pixel % side, pixel / side) else { continue }
            let alpha = Double(rgba[index + 3]) / 255
            guard alpha >= 0.5 else { continue }
            visible += 1
            let red = min(Double(rgba[index]) / 255 / alpha, 1)
            let green = min(Double(rgba[index + 1]) / 255 / alpha, 1)
            let blue = min(Double(rgba[index + 2]) / 255 / alpha, 1)
            let hsb = HSB(red: red, green: green, blue: blue)
            guard hsb.saturation >= 0.25, hsb.brightness >= 0.2 else { continue }
            colorful += 1
            let bin = min(Int(hsb.hue * Double(bins)), bins - 1)
            let weight = hsb.saturation
            weights[bin] += weight
            sums[bin].0 += red * weight
            sums[bin].1 += green * weight
            sums[bin].2 += blue * weight
        }
        guard visible > 0 else { return nil }

        func around(_ bin: Int) -> [Int] { [(bin + bins - 1) % bins, bin, (bin + 1) % bins] }
        let best = (0..<bins).max { a, b in
            around(a).reduce(0) { $0 + weights[$1] } < around(b).reduce(0) { $0 + weights[$1] }
        } ?? 0
        let near = around(best)
        let total = near.reduce(0) { $0 + weights[$1] }
        guard total > 0 else { return (nil, visible, colorful) }
        let average = HSB(
            red: near.reduce(0) { $0 + sums[$1].0 } / total,
            green: near.reduce(0) { $0 + sums[$1].1 } / total,
            blue: near.reduce(0) { $0 + sums[$1].2 } / total)
        return (average, visible, colorful)
    }

    nonisolated static func calmed(_ color: HSB) -> RGB {
        HSB(hue: color.hue,
            saturation: min(max(color.saturation, 0.28), 0.5),
            brightness: min(max(color.brightness, 0.6), 0.8)).rgb
    }

    struct HSB {
        let hue: Double
        let saturation: Double
        let brightness: Double

        init(hue: Double, saturation: Double, brightness: Double) {
            self.hue = hue
            self.saturation = saturation
            self.brightness = brightness
        }

        init(red: Double, green: Double, blue: Double) {
            let high = max(red, green, blue)
            let low = min(red, green, blue)
            let spread = high - low
            brightness = high
            saturation = high > 0 ? spread / high : 0
            guard spread > 0 else { hue = 0; return }
            var h: Double
            if high == red { h = (green - blue) / spread }
            else if high == green { h = (blue - red) / spread + 2 }
            else { h = (red - green) / spread + 4 }
            h /= 6
            hue = h < 0 ? h + 1 : h
        }

        var rgb: RGB {
            let h = hue * 6
            let sector = Int(h) % 6
            let f = h - Double(Int(h))
            let p = brightness * (1 - saturation)
            let q = brightness * (1 - saturation * f)
            let t = brightness * (1 - saturation * (1 - f))
            let v = brightness
            switch sector {
            case 0: return RGB(red: v, green: t, blue: p)
            case 1: return RGB(red: q, green: v, blue: p)
            case 2: return RGB(red: p, green: v, blue: t)
            case 3: return RGB(red: p, green: v, blue: t)
            case 4: return RGB(red: t, green: p, blue: v)
            default: return RGB(red: v, green: p, blue: q)
            }
        }
    }
}


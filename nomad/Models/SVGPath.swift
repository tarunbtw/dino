//
//  SVGPath.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//

import CoreGraphics
import Foundation

/// Reads the path data of an SVG `<path d="…">` into a CGPath.
/// Supports M, L, H, V, C, S, Q, A, and Z in absolute and relative forms.
public enum SVGPath {
    public static func cgPath(_ data: String) -> CGPath {
        let path = CGMutablePath()
        var scanner = Scanner(data)
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = "M"

        while scanner.skipSeparators(), !scanner.isAtEnd {
            if let letter = scanner.letter() { command = letter }
            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var control: CGPoint?

            switch command.uppercased() {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                command = relative ? "l" : "L"
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                control = c2
                current = p
            case "S":
                guard let c2 = point(), let p = point() else { return path }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                control = c2
                current = p
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let p = point()
                else { return path }
                addArc(to: path, from: current, to: p, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = p
            case "Z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
            lastControl = control
        }
        return path
    }

    private static func addArc(
        to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint,
        rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool
    ) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = sqrt(max(numerator / denominator, 0))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let center = CGPoint(
            x: cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2,
            y: sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        )
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(Int((abs(delta) / (.pi / 2)).rounded(.up)), 1)
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        func onEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                y: center.y + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi
            )
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(
                x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi
            )
        }
        var t = theta
        for index in 0..<segments {
            let next = t + step
            let a = onEllipse(t), b = index == segments - 1 ? p1 : onEllipse(next)
            let da = derivative(t), db = derivative(next)
            path.addCurve(
                to: b,
                control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y)
            )
            t = next
        }
    }

    private struct Scanner {
        private let chars: [Character]
        private var index = 0

        init(_ text: String) { chars = Array(text) }

        var isAtEnd: Bool { index >= chars.count }

        mutating func skipSeparators() -> Bool {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index].isNewline || chars[index] == "\t" {
                index += 1
            }
            return true
        }

        mutating func letter() -> Character? {
            _ = skipSeparators()
            guard index < chars.count, chars[index].isLetter, chars[index] != "e", chars[index] != "E" else { return nil }
            defer { index += 1 }
            return chars[index]
        }

        mutating func flag() -> Bool? {
            _ = skipSeparators()
            guard index < chars.count, chars[index] == "0" || chars[index] == "1" else { return nil }
            defer { index += 1 }
            return chars[index] == "1"
        }

        mutating func number() -> CGFloat? {
            _ = skipSeparators()
            var text = ""
            var sawDot = false, sawDigit = false
            if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                text.append(chars[index]); index += 1
            }
            while index < chars.count {
                let c = chars[index]
                if c.isASCII, c.isNumber { sawDigit = true }
                else if c == ".", !sawDot { sawDot = true }
                else { break }
                text.append(c); index += 1
            }
            guard sawDigit, let value = Double(text) else { return nil }
            return CGFloat(value)
        }
    }
}


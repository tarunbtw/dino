import SwiftUI

extension Path {
    init(blobatar source: BlobatarPath) {
        var path = Path()
        var current = CGPoint.zero

        for command in source.commands {
            switch command {
            case let .move(point):
                current = CGPoint(x: point.x, y: point.y)
                path.move(to: current)
            case let .line(point):
                current = CGPoint(x: point.x, y: point.y)
                path.addLine(to: current)
            case let .horizontal(x):
                current.x = x
                path.addLine(to: current)
            case let .vertical(y):
                current.y = y
                path.addLine(to: current)
            case let .cubic(control1, control2, end):
                current = CGPoint(x: end.x, y: end.y)
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: control1.x, y: control1.y),
                    control2: CGPoint(x: control2.x, y: control2.y)
                )
            case let .quadratic(control, end):
                current = CGPoint(x: end.x, y: end.y)
                path.addQuadCurve(
                    to: current,
                    control: CGPoint(x: control.x, y: control.y)
                )
            case .close:
                path.closeSubpath()
            }
        }

        self = path
    }
}

extension Color {
    init(blobatarHex hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(digits, radix: 16) ?? 0
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

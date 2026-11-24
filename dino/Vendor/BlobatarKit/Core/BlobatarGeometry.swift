import Foundation

/// Exact command-level ports of Blobatar 2.4.0's vector primitives.
public enum BlobatarGeometry {
    public static func superellipse(_ shape: BlobatarSuperellipse) -> BlobatarPath {
        let k = min(1, (8 * pow(2, -1 / shape.exponent) - 4) / 3)
        let a = shape.rx
        let b = shape.ry
        let ak = a * k
        let bk = b * k
        let points = [
            BlobatarPoint(x: a, y: 0),
            BlobatarPoint(x: a, y: bk), BlobatarPoint(x: ak, y: b), BlobatarPoint(x: 0, y: b),
            BlobatarPoint(x: -ak, y: b), BlobatarPoint(x: -a, y: bk), BlobatarPoint(x: -a, y: 0),
            BlobatarPoint(x: -a, y: -bk), BlobatarPoint(x: -ak, y: -b), BlobatarPoint(x: 0, y: -b),
            BlobatarPoint(x: ak, y: -b), BlobatarPoint(x: a, y: -bk), BlobatarPoint(x: a, y: 0),
        ]

        let angle = shape.rotation * .pi / 180
        let cosine = cos(angle)
        let sine = sin(angle)
        let transform: (BlobatarPoint) -> BlobatarPoint = { point in
            .init(
                x: shape.cx + point.x * cosine - point.y * sine,
                y: shape.cy + point.x * sine + point.y * cosine
            )
        }

        var commands: [BlobatarPathCommand] = [.move(to: transform(points[0]))]
        for index in stride(from: 1, to: 13, by: 3) {
            commands.append(.cubic(
                control1: transform(points[index]),
                control2: transform(points[index + 1]),
                end: transform(points[index + 2])
            ))
        }
        commands.append(.close)
        return BlobatarPath(commands: commands)
    }

    public static func arc(
        cx: Double,
        cy: Double,
        width: Double,
        depth: Double
    ) -> BlobatarPath {
        BlobatarPath(commands: [
            .move(to: .init(x: cx - width, y: cy)),
            .quadratic(control: .init(x: cx, y: cy + depth), end: .init(x: cx + width, y: cy)),
        ])
    }

    public static func arc(
        _ cx: Double,
        _ cy: Double,
        _ width: Double,
        _ depth: Double
    ) -> BlobatarPath {
        arc(cx: cx, cy: cy, width: width, depth: depth)
    }

    public static func blobPath(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double,
        radii: [Double],
        rotation: Double = 0
    ) -> BlobatarPath {
        precondition(!radii.isEmpty, "An organic path requires at least one radius")
        let count = radii.count
        let start = rotation * .pi / 180
        let points = radii.enumerated().map { index, multiplier in
            let angle = start + 2 * .pi * Double(index) / Double(count)
            return BlobatarPoint(
                x: cx + rx * multiplier * cos(angle),
                y: cy + ry * multiplier * sin(angle)
            )
        }
        let point: (Int) -> BlobatarPoint = { index in
            points[((index % count) + count) % count]
        }

        var commands: [BlobatarPathCommand] = [.move(to: point(0))]
        for index in 0..<count {
            let p0 = point(index - 1)
            let p1 = point(index)
            let p2 = point(index + 1)
            let p3 = point(index + 2)
            commands.append(.cubic(
                control1: .init(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                ),
                control2: .init(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                ),
                end: p2
            ))
        }
        commands.append(.close)
        return BlobatarPath(commands: commands)
    }

    public static func blobPath(
        _ cx: Double,
        _ cy: Double,
        _ rx: Double,
        _ ry: Double,
        _ radii: [Double],
        _ rotation: Double = 0
    ) -> BlobatarPath {
        blobPath(cx: cx, cy: cy, rx: rx, ry: ry, radii: radii, rotation: rotation)
    }

    public static func polygon(_ polygon: BlobatarPolygon) -> BlobatarPath {
        let k = polygon.rounding > 0 ? (polygon.rounding < 1 ? polygon.rounding / 2 : 0.5) : 0
        let start = polygon.rotation * .pi / 180 - .pi / 2
        let vertices = (0..<polygon.sides).map { index in
            let angle = start + 2 * .pi * Double(index) / Double(polygon.sides)
            return BlobatarPoint(
                x: polygon.cx + polygon.rx * cos(angle),
                y: polygon.cy + polygon.ry * sin(angle)
            )
        }
        let vertex: (Int) -> BlobatarPoint = { index in
            vertices[((index % polygon.sides) + polygon.sides) % polygon.sides]
        }
        let cut: (Int, Int) -> BlobatarPoint = { from, to in
            let p0 = vertex(from)
            let p1 = vertex(to)
            return .init(x: p0.x + (p1.x - p0.x) * k, y: p0.y + (p1.y - p0.y) * k)
        }

        var commands: [BlobatarPathCommand] = [.move(to: cut(0, -1))]
        for index in 0..<polygon.sides {
            commands.append(.quadratic(control: vertex(index), end: cut(index, index + 1)))
            if k < 0.5 {
                commands.append(.line(to: cut(index + 1, index)))
            }
        }
        commands.append(.close)
        return BlobatarPath(commands: commands)
    }

    public static func box(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double
    ) -> BlobatarPath {
        BlobatarPath(commands: [
            .move(to: .init(x: cx - rx, y: cy - ry)),
            .horizontal(to: cx + rx),
            .vertical(to: cy + ry),
            .horizontal(to: cx - rx),
            .close,
        ])
    }

    public static func box(
        _ cx: Double,
        _ cy: Double,
        _ rx: Double,
        _ ry: Double
    ) -> BlobatarPath {
        box(cx: cx, cy: cy, rx: rx, ry: ry)
    }

    public static func taper(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double,
        tip: Double
    ) -> BlobatarPath {
        let t = max(1.05, tip)
        let tx = rx * sqrt(1 - 1 / (t * t))
        let tangentY = cy - ry / t
        let apex = cy - t * ry
        let px = tx * 0.14
        let easedY = tangentY + 0.86 * (apex - tangentY)
        return BlobatarPath(commands: [
            .move(to: .init(x: cx - tx, y: tangentY)),
            .line(to: .init(x: cx - px, y: easedY)),
            .quadratic(
                control: .init(x: cx, y: apex),
                end: .init(x: cx + px, y: easedY)
            ),
            .line(to: .init(x: cx + tx, y: tangentY)),
            .close,
        ])
    }

    public static func taper(
        _ cx: Double,
        _ cy: Double,
        _ rx: Double,
        _ ry: Double,
        _ tip: Double
    ) -> BlobatarPath {
        taper(cx: cx, cy: cy, rx: rx, ry: ry, tip: tip)
    }
}

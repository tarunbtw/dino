import Foundation

struct BlobatarPaletteTransition: Hashable {
    var from: BlobatarPalette
    var to: BlobatarPalette
    var startedAt: TimeInterval
    var duration: TimeInterval

    func sampled(at time: TimeInterval) -> BlobatarPalette {
        let linear = min(max((time - startedAt) / duration, 0), 1)
        let eased = duration > 0.3
            ? BlobatarTransitionResolver.cubicBezier(
                linear, x1: 0.42, y1: 0, x2: 0.58, y2: 1
            )
            : BlobatarTransitionResolver.cubicBezier(
                linear, x1: 0.45, y1: 0.05, x2: 0.5, y2: 1
            )
        return BlobatarCanvasPalette.interpolated(from: from, to: to, progress: eased)
    }
}

enum BlobatarTransitionResolver {
    static func renderedPose(
        at time: TimeInterval,
        transition: BlobatarPoseTransition?,
        fallback: BlobatarExpression,
        parameters: BlobatarMotionParameters,
        eyeLeans: [Double]
    ) -> BlobatarPose {
        guard let transition else { return fallback.pose }
        return BlobatarMotion.sample(
            at: time,
            parameters: parameters,
            input: .init(
                animation: .none,
                expression: fallback,
                poseTransition: transition,
                eyeLeans: eyeLeans
            )
        ).pose
    }

    static func poseTransition(
        at time: TimeInterval,
        existing: BlobatarPoseTransition?,
        current: BlobatarExpression,
        target: BlobatarExpression,
        parameters: BlobatarMotionParameters,
        eyeLeans: [Double]
    ) -> BlobatarPoseTransition {
        BlobatarPoseTransition(
            from: renderedPose(
                at: time,
                transition: existing,
                fallback: current,
                parameters: parameters,
                eyeLeans: eyeLeans
            ),
            to: target.pose,
            startedAt: time
        )
    }

    static func paletteTransition(
        at time: TimeInterval,
        existing: BlobatarPaletteTransition?,
        fallback: BlobatarPalette,
        target: BlobatarPalette,
        returningToIdle: Bool
    ) -> BlobatarPaletteTransition {
        BlobatarPaletteTransition(
            from: existing?.sampled(at: time) ?? fallback,
            to: target,
            startedAt: time,
            duration: returningToIdle ? 0.4 : 0.3
        )
    }

    static func cubicBezier(
        _ progress: Double,
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double
    ) -> Double {
        let x = min(max(progress, 0), 1)
        if x == 0 || x == 1 { return x }
        var low = 0.0
        var high = 1.0
        var parameter = x
        for _ in 0..<16 {
            let sampled = bezierComponent(parameter, x1, x2)
            if abs(sampled - x) < 1e-12 { break }
            if sampled < x { low = parameter } else { high = parameter }
            parameter = (low + high) / 2
        }
        return bezierComponent(parameter, y1, y2)
    }

    private static func bezierComponent(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * p1
            + 3 * inverse * t * t * p2
            + t * t * t
    }
}

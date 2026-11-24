import Foundation

/// Every expression channel in Blobatar 2.4.0.
///
/// Scales are factors, rotations are degrees, offsets are view-box units, and
/// `heat`, `shake`, `rock`, and `lock` are unit amplitudes. The `*2` values are
/// right-eye differentials, not absolute right-eye values.
public struct BlobatarPose: Sendable, Hashable, Codable {
    public var esx: Double
    public var esy: Double
    public var tilt: Double
    public var edy: Double
    public var edx: Double
    public var esx2: Double
    public var esy2: Double
    public var tilt2: Double
    public var edy2: Double
    public var lock: Double
    public var heat: Double
    public var shake: Double
    public var rock: Double
    public var bdy: Double

    public init(
        esx: Double = 1,
        esy: Double = 1,
        tilt: Double = 0,
        edy: Double = 0,
        edx: Double = 0,
        esx2: Double = 0,
        esy2: Double = 0,
        tilt2: Double = 0,
        edy2: Double = 0,
        lock: Double = 0,
        heat: Double = 0,
        shake: Double = 0,
        rock: Double = 0,
        bdy: Double = 0
    ) {
        self.esx = esx
        self.esy = esy
        self.tilt = tilt
        self.edy = edy
        self.edx = edx
        self.esx2 = esx2
        self.esy2 = esy2
        self.tilt2 = tilt2
        self.edy2 = edy2
        self.lock = lock
        self.heat = heat
        self.shake = shake
        self.rock = rock
        self.bdy = bdy
    }

    public static let identity = BlobatarPose()

    /// Component-wise interpolation used by the native expression morph.
    public func interpolated(to other: BlobatarPose, progress: Double) -> BlobatarPose {
        let t = min(max(progress, 0), 1)
        let mix: (Double, Double) -> Double = { $0 + ($1 - $0) * t }
        return BlobatarPose(
            esx: mix(esx, other.esx),
            esy: mix(esy, other.esy),
            tilt: mix(tilt, other.tilt),
            edy: mix(edy, other.edy),
            edx: mix(edx, other.edx),
            esx2: mix(esx2, other.esx2),
            esy2: mix(esy2, other.esy2),
            tilt2: mix(tilt2, other.tilt2),
            edy2: mix(edy2, other.edy2),
            lock: mix(lock, other.lock),
            heat: mix(heat, other.heat),
            shake: mix(shake, other.shake),
            rock: mix(rock, other.rock),
            bdy: mix(bdy, other.bdy)
        )
    }
}

/// The frozen Blobatar 2.4.0 expression roster: idle plus thirteen named poses.
public enum BlobatarExpression: String, CaseIterable, Sendable, Hashable, Codable {
    case idle
    case happy
    case sad
    case mad
    case surprised
    case wink
    case sleepy
    case smug
    case unsure
    case scared
    case love
    case shy
    case sick
    case thinking

    public var pose: BlobatarPose {
        switch self {
        case .idle:
            return .identity
        case .happy:
            return BlobatarPose(
                esx: 1.72, esy: 0.3, tilt: 8, edy: -1.5, edx: 1.5,
                esx2: 0.08, esy2: 0.05, tilt2: -16, lock: 1, bdy: -2.2
            )
        case .sad:
            return BlobatarPose(
                esx: 0.6, esy: 0.56, tilt: 26, edy: 3.6, edx: 1.9,
                esx2: -0.05, esy2: -0.07, tilt2: -7, lock: 1, bdy: 2.6
            )
        case .mad:
            return BlobatarPose(
                esx: 1.85, esy: 0.26, tilt: -33, edy: 0.4, edx: 0.6,
                esy2: -0.03, tilt2: 5, lock: 1, heat: 0.62,
                shake: 0.55, bdy: 0.8
            )
        case .surprised:
            return BlobatarPose(
                esx: 1.34, esy: 1.2, tilt: -6, edy: -1.05, edx: 0.5,
                esx2: 0.05, esy2: 0.07, tilt2: 3, lock: 1, bdy: -1.4
            )
        case .wink:
            return BlobatarPose(
                esx: 1.32, esy: 0.76, tilt: 5, edy: -0.6, edx: 0.8,
                esx2: 0.26, esy2: -0.56, tilt2: -11, lock: 1, bdy: -1.1
            )
        case .sleepy:
            return BlobatarPose(
                esx: 1.14, esy: 0.22, tilt: 0, edy: 2.4, edx: 0.3,
                esx2: -0.04, esy2: 0.03, tilt2: 4, lock: 1, bdy: 1.2
            )
        case .smug:
            return BlobatarPose(
                esx: 1.3, esy: 0.42, tilt: 18, edy: -0.5, edx: 0.5,
                esx2: 0.06, esy2: -0.06, tilt2: -36, lock: 1, bdy: -1
            )
        case .unsure:
            return BlobatarPose(
                esx: 0.95, esy: 1.02, tilt: 4, edy: -0.2, edx: 0.3,
                esx2: 0.24, esy2: -0.44, tilt2: -18, lock: 1
            )
        case .scared:
            return BlobatarPose(
                esx: 0.78, esy: 0.96, tilt: -12, edy: -1.5, edx: -0.8,
                esx2: -0.04, esy2: 0.05, tilt2: 4, lock: 1,
                shake: 0.35, bdy: -0.6
            )
        case .love:
            return BlobatarPose(
                esx: 0.86, esy: 1.28, tilt: -14, edy: -0.5, edx: -0.35,
                esx2: 0.05, esy2: 0.06, tilt2: 6, lock: 1,
                heat: 0.6, bdy: -1.6
            )
        case .shy:
            return BlobatarPose(
                esx: 0.62, esy: 0.5, tilt: 10, edy: 1.4, edx: -0.2,
                esx2: -0.05, esy2: -0.04, tilt2: -8, lock: 1,
                heat: 0.55, bdy: 0.9
            )
        case .sick:
            return BlobatarPose(
                esx: 1.25, esy: 0.34, tilt: 20, edy: 1.8, edx: 0.8,
                esx2: 0.05, esy2: -0.05, tilt2: -6, lock: 1,
                heat: 0.6, shake: 0.18, bdy: 1.4
            )
        case .thinking:
            return BlobatarPose(
                esx: 1.15, esy: 0.62, tilt: 0, edy: 4.2, edx: 0.4,
                esx2: 0.02, esy2: 0.06, edy2: -8.4, lock: 1,
                rock: 0.8, bdy: -0.4
            )
        }
    }

    /// The seed-relative color endpoint used by the four tinting expressions.
    public var tint: BlobatarTint? {
        switch self {
        case .mad: return BlobatarColor.hot
        case .love: return BlobatarColor.rose
        case .shy: return BlobatarColor.blush
        case .sick: return BlobatarColor.bile
        default: return nil
        }
    }

    /// Resolves the expression's finished palette exactly as `tintWith` does in
    /// Blobatar 2.4.0. Non-tinting expressions return the original palette.
    public func applyingTint(to palette: BlobatarPalette) -> BlobatarPalette {
        guard let tint else { return palette }
        let endpoint = BlobatarColor.tinted(head: palette.head, eye: palette.eye, tint: tint)
        return BlobatarPalette(
            background: palette.background,
            head: BlobatarColor.mixHex(palette.head, endpoint.head, t: pose.heat),
            eye: BlobatarColor.mixHex(palette.eye, endpoint.eye, t: pose.heat)
        )
    }
}

public extension BlobatarLayout {
    /// Exact static `bakePose` semantics. Eye geometry is scaled in each eye's
    /// own frame, then the resulting capsule rotation is resolved; the body
    /// offset remains a wrapper translation so silhouette coordinates stay pure.
    func applying(_ pose: BlobatarPose) -> BlobatarLayout {
        var result = self
        result.eyes = eyes.enumerated().map { index, eye in
            let right = index == 0 ? 0.0 : 1.0
            let side = index == 0 ? -1.0 : 1.0
            var posed = eye
            posed.cx += pose.edx * side
            posed.cy += pose.edy + pose.edy2 * right
            posed.rx *= pose.esx + pose.esx2 * right
            posed.ry *= pose.esy + pose.esy2 * right
            posed.rotation = eye.rotation * (1 - pose.lock)
                + (pose.tilt + pose.tilt2 * right) * side
            return posed
        }
        result.expressionBodyOffsetY = pose.bdy
        return result
    }

    func applying(_ expression: BlobatarExpression) -> BlobatarLayout {
        applying(expression.pose)
    }
}

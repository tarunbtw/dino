import Foundation

/// Seed-derived values emitted by Blobatar 2.4.0's `motionVars`.
public struct BlobatarMotionParameters: Sendable, Hashable, Codable {
    public var breathingPhaseMilliseconds: Int
    public var bobPhaseMilliseconds: Int
    public var blinkDurationMilliseconds: Int
    public var blinkPhaseMilliseconds: Int
    public var lookX: Double
    public var lookXMagnitude: Double
    public var lookY: Double
    public var lookYMagnitude: Double
    public var saccadeDurationMilliseconds: Int
    public var saccadePhaseMilliseconds: Int

    public init(
        breathingPhaseMilliseconds: Int,
        bobPhaseMilliseconds: Int,
        blinkDurationMilliseconds: Int,
        blinkPhaseMilliseconds: Int,
        lookX: Double,
        lookXMagnitude: Double,
        lookY: Double,
        lookYMagnitude: Double,
        saccadeDurationMilliseconds: Int,
        saccadePhaseMilliseconds: Int
    ) {
        self.breathingPhaseMilliseconds = breathingPhaseMilliseconds
        self.bobPhaseMilliseconds = bobPhaseMilliseconds
        self.blinkDurationMilliseconds = blinkDurationMilliseconds
        self.blinkPhaseMilliseconds = blinkPhaseMilliseconds
        self.lookX = lookX
        self.lookXMagnitude = lookXMagnitude
        self.lookY = lookY
        self.lookYMagnitude = lookYMagnitude
        self.saccadeDurationMilliseconds = saccadeDurationMilliseconds
        self.saccadePhaseMilliseconds = saccadePhaseMilliseconds
    }

    /// Exact `animate.ts` derivation, including JavaScript rounding and negative delays.
    public init(traits: BlobatarTraits) {
        let blink = Self.jsRound(traits.number("motion.blink", in: 3_500..<6_500))
        let saccade = Self.jsRound(traits.number("motion.saccade", in: 4_200..<7_600))
        let xMagnitude = traits.number("motion.lookX", in: 1..<2.2)
        let yMagnitude = traits.number("motion.lookY", in: 0.8..<1.7)

        breathingPhaseMilliseconds = -Self.jsRound(traits.number("motion.phase", in: 0..<2_800))
        bobPhaseMilliseconds = -Self.jsRound(traits.number("motion.bob", in: 0..<3_400))
        blinkDurationMilliseconds = blink
        blinkPhaseMilliseconds = -Self.jsRound(
            traits.number("motion.blinkPhase", in: 0..<Double(blink))
        )
        lookXMagnitude = Self.roundToHundredth(xMagnitude)
        lookX = Self.roundToHundredth(
            xMagnitude * (traits.boolean("motion.lookXFlip") ? -1 : 1)
        )
        lookYMagnitude = Self.roundToHundredth(yMagnitude)
        lookY = Self.roundToHundredth(
            yMagnitude * (traits.boolean("motion.lookYFlip") ? -1 : 1)
        )
        saccadeDurationMilliseconds = saccade
        saccadePhaseMilliseconds = -Self.jsRound(
            traits.number("motion.saccadePhase", in: 0..<Double(saccade))
        )
    }

    public static func resolve(_ traits: BlobatarTraits) -> BlobatarMotionParameters {
        BlobatarMotionParameters(traits: traits)
    }

    public var phaseMilliseconds: Int {
        get { breathingPhaseMilliseconds }
        set { breathingPhaseMilliseconds = newValue }
    }

    public var bobPhase: Int {
        get { bobPhaseMilliseconds }
        set { bobPhaseMilliseconds = newValue }
    }

    private static func jsRound(_ value: Double) -> Int {
        Int(floor(value + 0.5))
    }

    private static func roundToHundredth(_ value: Double) -> Double {
        let rounded = floor(value * 100 + 0.5) / 100
        return rounded == 0 ? 0 : rounded
    }
}

/// A deterministic expression morph. `startedAt` uses the same clock passed to
/// `BlobatarMotion.sample`.
public struct BlobatarPoseTransition: Sendable, Hashable, Codable {
    public var from: BlobatarPose
    public var to: BlobatarPose
    public var startedAt: TimeInterval

    public init(from: BlobatarPose, to: BlobatarPose, startedAt: TimeInterval) {
        self.from = from
        self.to = to
        self.startedAt = startedAt
    }

    public init(
        from: BlobatarExpression,
        to: BlobatarExpression,
        startedAt: TimeInterval
    ) {
        self.init(from: from.pose, to: to.pose, startedAt: startedAt)
    }
}

/// State required to reproduce CSS hover interpolation without hidden timers.
public struct BlobatarHoverTransition: Sendable, Hashable, Codable {
    public var startedAt: TimeInterval
    public var amplitudeAtStart: Double
    public var reactionAtStart: Double

    public init(
        startedAt: TimeInterval,
        amplitudeAtStart: Double,
        reactionAtStart: Double
    ) {
        self.startedAt = startedAt
        self.amplitudeAtStart = amplitudeAtStart
        self.reactionAtStart = reactionAtStart
    }
}

/// An analytically sampled pointer-gaze spring. Positions and velocities are in
/// 100×100 view-box units, so sampling is deterministic and frame-rate independent.
public struct BlobatarGaze: Sendable, Hashable, Codable {
    public var target: BlobatarPoint
    public var initial: BlobatarPoint
    public var initialVelocity: BlobatarPoint
    public var startedAt: TimeInterval
    public var maximumOffset: Double
    public var stiffness: Double
    public var damping: Double

    public init(
        target: BlobatarPoint,
        initial: BlobatarPoint = .init(x: 0, y: 0),
        initialVelocity: BlobatarPoint = .init(x: 0, y: 0),
        startedAt: TimeInterval = 0,
        maximumOffset: Double = 1.2,
        stiffness: Double = 120,
        damping: Double = 14
    ) {
        self.target = target
        self.initial = initial
        self.initialVelocity = initialVelocity
        self.startedAt = startedAt
        self.maximumOffset = maximumOffset
        self.stiffness = stiffness
        self.damping = damping
    }
}

/// All external state that can affect a timeline sample.
public struct BlobatarMotionInput: Sendable, Hashable, Codable {
    public var animation: BlobatarAnimation
    public var isHovered: Bool
    public var supportsHover: Bool
    public var reduceMotion: Bool
    public var expression: BlobatarExpression
    public var poseTransition: BlobatarPoseTransition?
    public var hoverTransition: BlobatarHoverTransition?
    public var amplitudeOverride: Double?
    public var gaze: BlobatarGaze?
    public var eyeLeans: [Double]
    public var poseIsBaked: Bool
    /// CSS `--mo-rate`: values above one slow the complete timeline.
    public var playbackRate: Double

    public init(
        animation: BlobatarAnimation = .none,
        isHovered: Bool = false,
        supportsHover: Bool = true,
        reduceMotion: Bool = false,
        expression: BlobatarExpression = .idle,
        poseTransition: BlobatarPoseTransition? = nil,
        hoverTransition: BlobatarHoverTransition? = nil,
        amplitudeOverride: Double? = nil,
        gaze: BlobatarGaze? = nil,
        eyeLeans: [Double] = [],
        poseIsBaked: Bool = false,
        playbackRate: Double = 1
    ) {
        self.animation = animation
        self.isHovered = isHovered
        self.supportsHover = supportsHover
        self.reduceMotion = reduceMotion
        self.expression = expression
        self.poseTransition = poseTransition
        self.hoverTransition = hoverTransition
        self.amplitudeOverride = amplitudeOverride
        self.gaze = gaze
        self.eyeLeans = eyeLeans
        self.poseIsBaked = poseIsBaked
        self.playbackRate = playbackRate
    }
}

public struct BlobatarBodyMotionState: Sendable, Hashable, Codable {
    public var hoverScale: Double
    public var hoverOffsetY: Double
    public var breatheScaleX: Double
    public var breatheScaleY: Double
    public var bobOffsetY: Double
    public var expressionOffsetY: Double
    public var shakeOffset: BlobatarPoint

    public init(
        hoverScale: Double = 1,
        hoverOffsetY: Double = 0,
        breatheScaleX: Double = 1,
        breatheScaleY: Double = 1,
        bobOffsetY: Double = 0,
        expressionOffsetY: Double = 0,
        shakeOffset: BlobatarPoint = .init(x: 0, y: 0)
    ) {
        self.hoverScale = hoverScale
        self.hoverOffsetY = hoverOffsetY
        self.breatheScaleX = breatheScaleX
        self.breatheScaleY = breatheScaleY
        self.bobOffsetY = bobOffsetY
        self.expressionOffsetY = expressionOffsetY
        self.shakeOffset = shakeOffset
    }
}

public struct BlobatarEyeMotionState: Sendable, Hashable, Codable {
    public var poseOffset: BlobatarPoint
    public var poseScaleX: Double
    public var poseScaleY: Double
    public var poseRotationDegrees: Double
    public var blinkScaleY: Double
    public var wrapScaleX: Double
    public var wrapScaleY: Double
    public var wrapRotationDegrees: Double

    public init(
        poseOffset: BlobatarPoint = .init(x: 0, y: 0),
        poseScaleX: Double = 1,
        poseScaleY: Double = 1,
        poseRotationDegrees: Double = 0,
        blinkScaleY: Double = 1,
        wrapScaleX: Double = 1,
        wrapScaleY: Double = 1,
        wrapRotationDegrees: Double = 0
    ) {
        self.poseOffset = poseOffset
        self.poseScaleX = poseScaleX
        self.poseScaleY = poseScaleY
        self.poseRotationDegrees = poseRotationDegrees
        self.blinkScaleY = blinkScaleY
        self.wrapScaleX = wrapScaleX
        self.wrapScaleY = wrapScaleY
        self.wrapRotationDegrees = wrapRotationDegrees
    }
}

/// One frame of render-neutral motion. Translations use view-box units, scales
/// are factors, and rotations use degrees.
public struct BlobatarMotionState: Sendable, Hashable, Codable {
    public var amplitude: Double
    public var pose: BlobatarPose
    public var body: BlobatarBodyMotionState
    public var eyes: [BlobatarEyeMotionState]
    public var saccadeOffset: BlobatarPoint
    public var gazeOffset: BlobatarPoint
    public var rockPhase: Double

    public init(
        amplitude: Double,
        pose: BlobatarPose,
        body: BlobatarBodyMotionState,
        eyes: [BlobatarEyeMotionState],
        saccadeOffset: BlobatarPoint,
        gazeOffset: BlobatarPoint,
        rockPhase: Double
    ) {
        self.amplitude = amplitude
        self.pose = pose
        self.body = body
        self.eyes = eyes
        self.saccadeOffset = saccadeOffset
        self.gazeOffset = gazeOffset
        self.rockPhase = rockPhase
    }

    public var combinedEyeGroupOffset: BlobatarPoint {
        .init(x: saccadeOffset.x + gazeOffset.x, y: saccadeOffset.y + gazeOffset.y)
    }
}

/// A single-clock, deterministic port of `motion.css` and `animate.ts`.
public enum BlobatarMotion {
    public static func sample(
        at time: TimeInterval,
        parameters: BlobatarMotionParameters,
        input: BlobatarMotionInput = .init()
    ) -> BlobatarMotionState {
        let rate = max(input.playbackRate, 0.000_001)
        let clock = time / rate
        let amplitude = resolvedAmplitude(at: time, rate: rate, input: input)
        let reaction = resolvedHoverReaction(at: time, rate: rate, input: input)
        let pose = resolvedPose(at: time, rate: rate, input: input)
        let ambientLoopsRun = !input.reduceMotion && (
            input.animation == .always
                || (input.animation == .hover && input.supportsHover)
        )
        // motion.css pauses touch-hover ambient effects, then re-enables the
        // expression-specific thinking seesaw. `.always` remains fully live.
        let expressionRockRuns = !input.reduceMotion
            && input.animation != .none
            && pose.rock != 0

        let breathing = ambientLoopsRun
            ? alternateProgress(
                milliseconds: clock * 1_000,
                delay: parameters.breathingPhaseMilliseconds,
                duration: 2_800
            )
            : 0
        let bob = ambientLoopsRun
            ? alternateProgress(
                milliseconds: clock * 1_000,
                delay: parameters.bobPhaseMilliseconds,
                duration: 3_400
            )
            : 0
        let shake = ambientLoopsRun && pose.shake != 0
            ? shakeOffset(at: clock, amplitude: pose.shake)
            : .zero
        let saccadeFrame = ambientLoopsRun
            ? saccade(at: clock, parameters: parameters, amplitude: amplitude)
            : .identity
        let blink = ambientLoopsRun
            ? blinkScale(at: clock, parameters: parameters, amplitude: amplitude)
            : 1
        let rockPhase = expressionRockRuns ? rockPhase(at: clock) : 1
        let gaze = ambientLoopsRun && input.gaze != nil
            ? gazeOffset(at: time, gaze: input.gaze)
            : .zero

        let body = BlobatarBodyMotionState(
            hoverScale: 1 + 0.04 * reaction,
            hoverOffsetY: -1.5 * reaction,
            breatheScaleX: 1 + 0.022 * amplitude * breathing,
            breatheScaleY: 1 - 0.018 * amplitude * breathing,
            bobOffsetY: -1.1 * amplitude * bob,
            expressionOffsetY: input.poseIsBaked ? 0 : pose.bdy,
            shakeOffset: shake
        )

        let eyes = (0..<2).map { index -> BlobatarEyeMotionState in
            let selector = index == 0 ? 0.0 : 1.0
            let side = index == 0 ? -1.0 : 1.0
            let lean = input.eyeLeans.indices.contains(index) ? input.eyeLeans[index] : 0
            let phaseShare = selector * (1 - pose.rock)
                + pose.rock * ((1 + side * rockPhase) / 2)
            let bakedShare = selector
            let currentY = pose.edy + pose.edy2 * phaseShare
            let bakedY = pose.edy + pose.edy2 * bakedShare

            return BlobatarEyeMotionState(
                poseOffset: input.poseIsBaked
                    ? .init(x: 0, y: currentY - bakedY)
                    : .init(x: pose.edx * side, y: currentY),
                poseScaleX: input.poseIsBaked ? 1 : pose.esx + pose.esx2 * selector,
                poseScaleY: input.poseIsBaked ? 1 : pose.esy + pose.esy2 * selector,
                poseRotationDegrees: input.poseIsBaked
                    ? 0
                    : (pose.tilt + pose.tilt2 * selector) * side - lean * pose.lock,
                blinkScaleY: blink,
                wrapScaleX: saccadeFrame.wrap[index].x,
                wrapScaleY: saccadeFrame.wrap[index].y,
                wrapRotationDegrees: saccadeFrame.rotation[index]
            )
        }

        return BlobatarMotionState(
            amplitude: amplitude,
            pose: pose,
            body: body,
            eyes: eyes,
            saccadeOffset: saccadeFrame.offset,
            gazeOffset: gaze,
            rockPhase: rockPhase
        )
    }

    /// Convenience that samples a generated model from its unbaked identity layout.
    public static func sample(
        at time: TimeInterval,
        model: borrowing BlobatarModel,
        isHovered: Bool = false,
        supportsHover: Bool = true,
        reduceMotion: Bool = false,
        gaze: BlobatarGaze? = nil,
        playbackRate: Double = 1
    ) -> BlobatarMotionState {
        let input = BlobatarMotionInput(
            animation: model.configuration.animation,
            isHovered: isHovered,
            supportsHover: supportsHover,
            reduceMotion: reduceMotion,
            expression: model.configuration.expression ?? .idle,
            gaze: gaze,
            eyeLeans: model.layout.eyes.map(\.rotation),
            poseIsBaked: false,
            playbackRate: playbackRate
        )
        return sample(at: time, parameters: model.motion, input: input)
    }

    /// Semantic static pose used by non-animated and Reduce Motion renderers.
    public static func staticState(
        expression: BlobatarExpression = .idle,
        eyeLeans: [Double] = []
    ) -> BlobatarMotionState {
        let parameters = BlobatarMotionParameters(
            breathingPhaseMilliseconds: 0,
            bobPhaseMilliseconds: 0,
            blinkDurationMilliseconds: 4_800,
            blinkPhaseMilliseconds: 0,
            lookX: 1.4,
            lookXMagnitude: 1.4,
            lookY: 1.1,
            lookYMagnitude: 1.1,
            saccadeDurationMilliseconds: 5_600,
            saccadePhaseMilliseconds: 0
        )
        return sample(
            at: 0,
            parameters: parameters,
            input: .init(
                animation: .none,
                reduceMotion: true,
                expression: expression,
                eyeLeans: eyeLeans
            )
        )
    }
}

private extension BlobatarMotion {
    struct SaccadeFrame {
        var offset: BlobatarPoint
        var wrap: [BlobatarPoint]
        var rotation: [Double]

        static let identity = SaccadeFrame(
            offset: .zero,
            wrap: [.unit, .unit],
            rotation: [0, 0]
        )
    }

    static func resolvedAmplitude(
        at time: TimeInterval,
        rate: Double,
        input: BlobatarMotionInput
    ) -> Double {
        guard !input.reduceMotion else { return 0 }
        switch input.animation {
        case .none:
            return 0
        case .always:
            return 1
        case .hover:
            guard input.supportsHover else { return 0 }
            if let override = input.amplitudeOverride {
                return clamp(override)
            }
            let target = input.isHovered ? 1.0 : 0.0
            guard let transition = input.hoverTransition else { return target }
            let progress = clamp((time - transition.startedAt) / (0.4 * rate))
            return mix(transition.amplitudeAtStart, target, cssEaseOut(progress))
        }
    }

    static func resolvedHoverReaction(
        at time: TimeInterval,
        rate: Double,
        input: BlobatarMotionInput
    ) -> Double {
        guard !input.reduceMotion, input.animation != .none, input.supportsHover else { return 0 }
        let target = input.isHovered ? 1.0 : 0.0
        guard let transition = input.hoverTransition else { return target }
        let duration = (input.isHovered ? 0.22 : 0.16) * rate
        let progress = clamp((time - transition.startedAt) / duration)
        return mix(
            transition.reactionAtStart,
            target,
            cubicBezier(progress, x1: 0.23, y1: 1, x2: 0.32, y2: 1)
        )
    }

    static func resolvedPose(
        at time: TimeInterval,
        rate: Double,
        input: BlobatarMotionInput
    ) -> BlobatarPose {
        guard !input.reduceMotion, let transition = input.poseTransition else {
            return input.expression.pose
        }
        let returningToIdle = transition.to == .identity
        let duration = (returningToIdle ? 0.4 : 0.3) * rate
        let linear = clamp((time - transition.startedAt) / duration)
        let eased = returningToIdle
            ? cssEaseInOut(linear)
            : cubicBezier(linear, x1: 0.45, y1: 0.05, x2: 0.5, y2: 1)
        return transition.from.interpolated(to: transition.to, progress: eased)
    }

    static func alternateProgress(milliseconds: Double, delay: Int, duration: Double) -> Double {
        let position = (milliseconds - Double(delay)) / duration
        let iteration = floor(position)
        let fraction = position - iteration
        let directed = Int(iteration).isMultiple(of: 2) ? fraction : 1 - fraction
        return cssEaseInOut(directed)
    }

    static func blinkScale(
        at time: TimeInterval,
        parameters: BlobatarMotionParameters,
        amplitude: Double
    ) -> Double {
        let duration = Double(max(parameters.blinkDurationMilliseconds, 1))
        let progress = cycle(
            time * 1_000 - Double(parameters.blinkPhaseMilliseconds),
            duration: duration
        )
        let closed = 1 - 0.92 * amplitude
        if progress <= 0.972 { return 1 }
        if progress <= 0.986 {
            let local = (progress - 0.972) / 0.014
            return mix(1, closed, cssEaseIn(local))
        }
        let local = (progress - 0.986) / 0.014
        return mix(closed, 1, cssEaseOut(local))
    }

    static func shakeOffset(at time: TimeInterval, amplitude: Double) -> BlobatarPoint {
        let points: [(Double, BlobatarPoint)] = [
            (0, .init(x: 0.62, y: -0.34)),
            (0.25, .init(x: -0.7, y: 0.22)),
            (0.5, .init(x: 0.38, y: 0.66)),
            (0.75, .init(x: -0.44, y: -0.6)),
            (1, .init(x: 0.62, y: -0.34)),
        ]
        return interpolate(points, at: cycle(time * 1_000, duration: 112)) * amplitude
    }

    static func rockPhase(at time: TimeInterval) -> Double {
        let progress = cycle(time * 1_000, duration: 900)
        if progress <= 0.5 {
            return mix(1, -1, cssEaseInOut(progress / 0.5))
        }
        return mix(-1, 1, cssEaseInOut((progress - 0.5) / 0.5))
    }

    static func saccade(
        at time: TimeInterval,
        parameters: BlobatarMotionParameters,
        amplitude: Double
    ) -> SaccadeFrame {
        let progress = cycle(
            time * 1_000 - Double(parameters.saccadePhaseMilliseconds),
            duration: Double(max(parameters.saccadeDurationMilliseconds, 1))
        )
        var lower = saccadeKeyframes[0]
        var upper = saccadeKeyframes[saccadeKeyframes.count - 1]
        for index in 1..<saccadeKeyframes.count where progress <= saccadeKeyframes[index].0 {
            lower = saccadeKeyframes[index - 1]
            upper = saccadeKeyframes[index]
            break
        }
        if lower.1 == upper.1 {
            return fixation(lower.1, parameters: parameters, amplitude: amplitude)
        }
        let span = upper.0 - lower.0
        let amount = span == 0 ? 0 : (progress - lower.0) / span
        return interpolate(
            fixation(lower.1, parameters: parameters, amplitude: amplitude),
            fixation(upper.1, parameters: parameters, amplitude: amplitude),
            amount
        )
    }

    static func fixation(
        _ index: Int,
        parameters: BlobatarMotionParameters,
        amplitude: Double
    ) -> SaccadeFrame {
        guard index != 0 else { return .identity }
        let coefficients: (tx: Double, ty: Double, xs: Double, xd: Double, ys: Double, r: Double)
        switch index {
        case 1: coefficients = (-0.8, -0.9, 0.0176, 0.008, 0.027, 0.648)
        case 2: coefficients = (1, 0.1, 0.022, -0.01, 0.003, 0.09)
        case 3: coefficients = (-0.15, 0.85, 0.0033, 0.0015, 0.0255, -0.115)
        case 4: coefficients = (0.75, -0.8, 0.0165, -0.0075, 0.024, -0.54)
        case 5: coefficients = (-1, -0.15, 0.022, 0.01, 0.0045, 0.135)
        default: return .identity
        }
        let offset = BlobatarPoint(
            x: coefficients.tx * parameters.lookX * amplitude,
            y: coefficients.ty * parameters.lookY * amplitude
        )
        let wraps = [-1.0, 1.0].map { side in
            BlobatarPoint(
                x: 1 - coefficients.xs * parameters.lookXMagnitude * amplitude
                    + coefficients.xd * parameters.lookX * side * amplitude,
                y: 1 - coefficients.ys * parameters.lookYMagnitude * amplitude
            )
        }
        let rotations = [-1.0, 1.0].map { side in
            coefficients.r * parameters.lookX * parameters.lookY * side * amplitude
        }
        return SaccadeFrame(offset: offset, wrap: wraps, rotation: rotations)
    }

    static func interpolate(_ a: SaccadeFrame, _ b: SaccadeFrame, _ t: Double) -> SaccadeFrame {
        SaccadeFrame(
            offset: interpolate(a.offset, b.offset, t),
            wrap: [
                interpolate(a.wrap[0], b.wrap[0], t),
                interpolate(a.wrap[1], b.wrap[1], t),
            ],
            rotation: [mix(a.rotation[0], b.rotation[0], t), mix(a.rotation[1], b.rotation[1], t)]
        )
    }

    static func gazeOffset(at time: TimeInterval, gaze: BlobatarGaze?) -> BlobatarPoint {
        guard let gaze else { return .zero }
        let magnitude = hypot(gaze.target.x, gaze.target.y)
        let limit = max(gaze.maximumOffset, 0)
        let scale = magnitude > limit && magnitude > 0 ? limit / magnitude : 1
        let target = BlobatarPoint(x: gaze.target.x * scale, y: gaze.target.y * scale)
        let elapsed = max(0, time - gaze.startedAt)
        return BlobatarPoint(
            x: spring(
                time: elapsed,
                initial: gaze.initial.x,
                velocity: gaze.initialVelocity.x,
                target: target.x,
                stiffness: gaze.stiffness,
                damping: gaze.damping
            ),
            y: spring(
                time: elapsed,
                initial: gaze.initial.y,
                velocity: gaze.initialVelocity.y,
                target: target.y,
                stiffness: gaze.stiffness,
                damping: gaze.damping
            )
        )
    }

    static func spring(
        time: Double,
        initial: Double,
        velocity: Double,
        target: Double,
        stiffness: Double,
        damping: Double
    ) -> Double {
        guard stiffness > 0 else { return target }
        let omega = sqrt(stiffness)
        let decay = max(damping, 0) / 2
        let displacement = initial - target
        if decay < omega {
            let damped = sqrt(omega * omega - decay * decay)
            let sine = (velocity + decay * displacement) / damped
            return target + exp(-decay * time)
                * (displacement * cos(damped * time) + sine * sin(damped * time))
        }
        if abs(decay - omega) < 1e-12 {
            return target + exp(-omega * time)
                * (displacement + (velocity + omega * displacement) * time)
        }
        let root = sqrt(decay * decay - omega * omega)
        let r1 = -decay + root
        let r2 = -decay - root
        let c1 = (velocity - r2 * displacement) / (r1 - r2)
        let c2 = displacement - c1
        return target + c1 * exp(r1 * time) + c2 * exp(r2 * time)
    }

    static func interpolate(
        _ points: [(Double, BlobatarPoint)],
        at progress: Double
    ) -> BlobatarPoint {
        for index in 1..<points.count where progress <= points[index].0 {
            let lower = points[index - 1]
            let upper = points[index]
            let amount = (progress - lower.0) / (upper.0 - lower.0)
            return interpolate(lower.1, upper.1, amount)
        }
        return points.last?.1 ?? .zero
    }

    static func interpolate(_ a: BlobatarPoint, _ b: BlobatarPoint, _ t: Double) -> BlobatarPoint {
        .init(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t))
    }

    static func cycle(_ value: Double, duration: Double) -> Double {
        let position = value / duration
        return position - floor(position)
    }

    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func cssEaseIn(_ progress: Double) -> Double {
        cubicBezier(progress, x1: 0.42, y1: 0, x2: 1, y2: 1)
    }

    static func cssEaseOut(_ progress: Double) -> Double {
        cubicBezier(progress, x1: 0, y1: 0, x2: 0.58, y2: 1)
    }

    static func cssEaseInOut(_ progress: Double) -> Double {
        cubicBezier(progress, x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    }

    /// Solves CSS cubic-bezier by x and returns y, rather than treating the
    /// parameter as time directly.
    static func cubicBezier(
        _ progress: Double,
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double
    ) -> Double {
        let x = clamp(progress)
        if x == 0 || x == 1 { return x }
        var low = 0.0
        var high = 1.0
        var t = x
        for _ in 0..<16 {
            let sampled = bezierComponent(t, x1, x2)
            if abs(sampled - x) < 1e-12 { break }
            if sampled < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return bezierComponent(t, y1, y2)
    }

    static func bezierComponent(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * p1
            + 3 * inverse * t * t * p2
            + t * t * t
    }

    static let saccadeKeyframes: [(Double, Int)] = [
        (0, 0), (0.15, 0), (0.165, 1), (0.31, 1),
        (0.325, 2), (0.47, 2), (0.485, 3), (0.63, 3),
        (0.645, 4), (0.79, 4), (0.805, 5), (0.985, 5), (1, 0),
    ]
}

public extension BlobatarPoint {
    static let zero = BlobatarPoint(x: 0, y: 0)
}

private extension BlobatarPoint {
    static let unit = BlobatarPoint(x: 1, y: 1)

    static func * (point: BlobatarPoint, scalar: Double) -> BlobatarPoint {
        .init(x: point.x * scalar, y: point.y * scalar)
    }
}

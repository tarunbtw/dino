import SwiftUI

/// A deterministic Blobatar rendered entirely with native SwiftUI vectors.
public struct BlobatarView: View {
    public let configuration: BlobatarConfiguration
    public let accessibilityLabel: String
    public let tracksPointerGaze: Bool

    private let model: BlobatarModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @Environment(\.blobatarRenderProbe) private var renderProbe
    #endif
    @State private var pointerInteraction: BlobatarPointerInteraction
    @State private var hoverTransition: BlobatarHoverTransition?
    @State private var poseTransition: BlobatarPoseTransition?
    @State private var paletteTransition: BlobatarPaletteTransition?

    public init(
        _ configuration: BlobatarConfiguration,
        pointerGaze: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        precondition(configuration.size > 0, "Blobatar size must be greater than zero")
        self.configuration = configuration
        self.accessibilityLabel = accessibilityLabel
            ?? configuration.title
            ?? "Blobatar for \(configuration.seed)"
        tracksPointerGaze = pointerGaze
        model = BlobatarGenerator.generate(configuration)
        _pointerInteraction = State(initialValue: .init(
            supportsHover: Self.platformInitiallySupportsHover
        ))
    }

    public init(
        seed: String,
        hue: Double? = nil,
        size: Double = 100,
        background: Bool = false,
        animation: BlobatarAnimation = .none,
        expression: BlobatarExpression? = nil,
        pointerGaze: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.init(
            .init(
                seed: seed,
                hue: hue,
                size: size,
                background: background,
                animation: animation,
                expression: expression
            ),
            pointerGaze: pointerGaze,
            accessibilityLabel: accessibilityLabel
        )
    }

    public init(
        seed: String,
        hue: Double? = nil,
        size: Double = 100,
        backdrop: BlobatarBackdropShape?,
        animation: BlobatarAnimation = .none,
        expression: BlobatarExpression? = nil,
        pointerGaze: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.init(
            .init(
                seed: seed,
                hue: hue,
                size: size,
                backdrop: backdrop,
                animation: animation,
                expression: expression
            ),
            pointerGaze: pointerGaze,
            accessibilityLabel: accessibilityLabel
        )
    }

    public var body: some View {
        TimelineView(.animation(
            minimumInterval: 1 / 60,
            paused: timelineIsPaused
        )) { timeline in
            let active = activeMotion(at: timeline.date)
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
                #if DEBUG
                renderProbe?.record(
                    configuration.seed,
                    timeline.date.timeIntervalSinceReferenceDate
                )
                #endif
                let layout: BlobatarLayout
                let state: BlobatarSceneState
                let palette: BlobatarPalette
                if active {
                    layout = model.layout
                    state = BlobatarSceneState(
                        motion: motionSample(at: timeline.date),
                        layout: layout
                    )
                    palette = animatedPalette(at: timeline.date)
                } else {
                    layout = model.displayLayout
                    state = .display(layout: layout)
                    palette = model.palette
                }
                BlobatarCanvasRenderer.draw(
                    model: model,
                    layout: layout,
                    palette: palette,
                    state: state,
                    in: context,
                    size: size
                )
            }
        }
        .frame(width: configuration.size, height: configuration.size)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case let .active(location):
                handlePointer(.active(location: location))
            case .ended:
                handlePointer(.ended)
            }
        }
        .onChange(of: configuration.expression ?? .idle) { oldValue, newValue in
            guard configuration.animation != .none, oldValue != newValue else {
                return
            }
            let startedAt = Date.timeIntervalSinceReferenceDate
            poseTransition = BlobatarTransitionResolver.poseTransition(
                at: startedAt,
                existing: poseTransition,
                current: oldValue,
                target: newValue,
                parameters: model.motion,
                eyeLeans: model.layout.eyes.map(\.rotation)
            )
            paletteTransition = BlobatarTransitionResolver.paletteTransition(
                at: startedAt,
                existing: paletteTransition,
                fallback: oldValue.applyingTint(to: model.basePalette),
                target: newValue.applyingTint(to: model.basePalette),
                returningToIdle: newValue == .idle
            )
            clearPoseTransition(startedAt: startedAt)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isImage)
    }

    private var supportsHover: Bool {
        pointerInteraction.supportsHover
    }

    private static var platformInitiallySupportsHover: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private var timelineIsPaused: Bool {
        if reduceMotion || configuration.animation == .none { return true }
        if configuration.animation == .always { return false }
        return !pointerInteraction.isHovered
            && hoverTransition == nil
            && poseTransition == nil
            && pointerInteraction.gaze == nil
            && !expressionRequiresTimeline
    }

    private func activeMotion(at date: Date) -> Bool {
        guard !reduceMotion, configuration.animation != .none else { return false }
        if configuration.animation == .always { return true }
        return pointerInteraction.isHovered
            || hoverTransition != nil
            || poseTransition != nil
            || pointerInteraction.gaze != nil
            || expressionRequiresTimeline
    }

    private func motionSample(at date: Date) -> BlobatarMotionState {
        BlobatarMotion.sample(
            at: date.timeIntervalSinceReferenceDate,
            parameters: model.motion,
            input: BlobatarMotionInput(
                animation: configuration.animation,
                isHovered: pointerInteraction.isHovered,
                supportsHover: supportsHover,
                reduceMotion: reduceMotion,
                expression: configuration.expression ?? .idle,
                poseTransition: poseTransition,
                hoverTransition: hoverTransition,
                gaze: pointerInteraction.gaze,
                eyeLeans: model.layout.eyes.map(\.rotation),
                poseIsBaked: false
            )
        )
    }

    private var expressionRequiresTimeline: Bool {
        let pose = (configuration.expression ?? .idle).pose
        if configuration.animation == .always || supportsHover {
            return pose.shake != 0 || pose.rock != 0
        }
        return pose.rock != 0
    }

    private func animatedPalette(at date: Date) -> BlobatarPalette {
        paletteTransition?.sampled(at: date.timeIntervalSinceReferenceDate) ?? model.palette
    }

    private func clearHoverTransition(startedAt: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            if hoverTransition?.startedAt == startedAt {
                hoverTransition = nil
            }
        }
    }

    private func handlePointer(_ phase: BlobatarPointerPhase) {
        let now = Date.timeIntervalSinceReferenceDate
        let current = motionSample(at: Date(timeIntervalSinceReferenceDate: now))
        let wasHovered = pointerInteraction.isHovered
        pointerInteraction.update(
            phase: phase,
            at: now,
            size: CGSize(width: configuration.size, height: configuration.size),
            currentGazeOffset: current.gazeOffset,
            tracksPointerGaze: tracksPointerGaze && configuration.animation != .none
        )

        if configuration.animation != .none,
           wasHovered != pointerInteraction.isHovered {
            hoverTransition = BlobatarHoverTransition(
                startedAt: now,
                amplitudeAtStart: current.amplitude,
                reactionAtStart: min(max((current.body.hoverScale - 1) / 0.04, 0), 1)
            )
            clearHoverTransition(startedAt: now)
        }
        if case .ended = phase, let startedAt = pointerInteraction.gaze?.startedAt {
            clearReturnedGaze(startedAt: startedAt)
        }
    }

    private func clearReturnedGaze(startedAt: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if !pointerInteraction.isHovered,
               pointerInteraction.gaze?.startedAt == startedAt {
                pointerInteraction.gaze = nil
            }
        }
    }

    private func clearPoseTransition(startedAt: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            if poseTransition?.startedAt == startedAt {
                poseTransition = nil
                paletteTransition = nil
            }
        }
    }

}

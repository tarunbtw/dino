import Foundation

/// Deterministic Blobatar 2.4.0 generation-two model assembly.
public enum BlobatarGenerator {
    /// Frozen half-open weighted bands. Moving one changes existing identities.
    public static let generationTwoBands: [(shape: BlobatarShape, upperBound: Double)] = [
        (.round, 0.22),
        (.organic, 0.48),
        (.boxy, 0.60),
        (.capsule, 0.70),
        (.nub, 0.79),
        (.cloud, 0.86),
        (.droplet, 0.915),
        (.hexagon, 0.95),
        (.sun, 0.98),
        (.triangle, 1),
    ]

    public static func generate(_ configuration: BlobatarConfiguration) -> BlobatarModel {
        let traits = BlobatarTraits(
            name: configuration.seed,
            normalize: configuration.normalize,
            overrides: configuration.traits
        )
        let basePalette = configuration.palette ?? BlobatarColor.palette(
            hue: configuration.hue ?? traits.number("hue", in: 0..<360),
            enforce: configuration.enforceContrast,
            tone: configuration.tone ?? traits.value("tone")
        )
        let baseLayout = layout(traits: traits)
        let displayLayout = configuration.expression.map { baseLayout.applying($0.pose) } ?? baseLayout
        let palette = configuration.expression?.applyingTint(to: basePalette) ?? basePalette
        let backdrop = makeBackdrop(shape: configuration.backdropShape, fill: palette.background)
        let render = renderModel(layout: displayLayout, palette: palette, backdrop: backdrop)

        return BlobatarModel(
            configuration: configuration,
            basePalette: basePalette,
            palette: palette,
            layout: baseLayout,
            displayLayout: displayLayout,
            backdrop: backdrop,
            motion: BlobatarMotionParameters(traits: traits),
            render: render
        )
    }

    /// Numeric layout without color, expression, or rendering work.
    public static func layout(traits: BlobatarTraits) -> BlobatarLayout {
        let shape = shape(for: traits.value("shape"))
        let core = coreScale(for: shape)
        let radius = traits.number("body.r", in: 31..<38) * core
        let pointCount = traits.integer("body.pts", in: 6...8)
        var body = BlobatarBody(
            cx: 50 + traits.jitter("body.x", amount: 1.5),
            cy: 50 + traits.jitter("body.y", amount: 1.5),
            rx: radius,
            ry: radius * traits.number("body.ratio", in: 0.92..<1.08),
            exponent: traits.number("body.n", in: 1.9..<2.5),
            rotation: 0,
            radii: (0..<pointCount).map { 1 + traits.jitter("body.r\($0)", amount: 0.16) }
        )

        patchBody(&body, shape: shape, traits: traits)
        let face = faceRegion(for: shape, body: body)
        let decoration = decorate(shape: shape, body: body, traits: traits)
        let eyes = faceFit(traits: traits, body: body, face: face)
        let path = bodyPath(for: shape, body: body)

        return BlobatarLayout(
            shape: shape,
            body: body,
            face: face,
            petals: decoration.petals,
            extra: decoration.extra,
            eyes: eyes,
            bodyPath: path
        )
    }

    public static func layout(
        seed: String,
        normalize: Bool = true,
        traits overrides: [String: BlobatarTraitOverride] = [:]
    ) -> BlobatarLayout {
        layout(traits: BlobatarTraits(name: seed, normalize: normalize, overrides: overrides))
    }

    public static func shape(for value: Double) -> BlobatarShape {
        generationTwoBands.first(where: { value < $0.upperBound })?.shape ?? .triangle
    }

    private static func coreScale(for shape: BlobatarShape) -> Double {
        switch shape {
        case .round: 1
        case .organic: 0.98
        case .boxy: 0.86
        case .capsule: 1.02
        case .nub: 0.88
        case .cloud, .droplet: 0.78
        case .hexagon: 1.05
        case .sun: 0.70
        case .triangle: 1.15
        }
    }

    private static func patchBody(
        _ body: inout BlobatarBody,
        shape: BlobatarShape,
        traits: BlobatarTraits
    ) {
        switch shape {
        case .boxy:
            body.exponent = traits.number("body.n", in: 3.4..<6)
            body.rotation = traits.number("body.rot", in: -20..<20)
        case .capsule:
            body.ry *= traits.number("capsule.squat", in: 0.55..<0.68)
        case .droplet:
            body.cy += 0.22 * body.ry
            body.exponent = 2
        case .hexagon:
            body.sides = 6
            body.rotation = traits.number("body.rot", in: -12..<12)
            body.rounding = traits.number("poly.round", in: 0.24..<0.5)
        case .triangle:
            body.sides = 3
            body.rotation = traits.number("body.rot", in: -5..<5)
            body.rounding = traits.number("poly.round", in: 0.24..<0.5)
        case .round, .organic, .nub, .cloud, .sun:
            break
        }
    }

    private static func faceRegion(for shape: BlobatarShape, body: BlobatarBody) -> BlobatarEllipse {
        switch shape {
        case .organic, .cloud:
            return shrink(body, by: (body.radii.min() ?? 1) * 0.95)
        case .capsule:
            return shrink(body, by: 0.94)
        case .droplet:
            return .init(
                cx: body.cx,
                cy: body.cy + body.ry * 0.05,
                rx: body.rx * 0.88,
                ry: body.ry * 0.88
            )
        case .hexagon:
            return shrink(body, by: 0.84)
        case .triangle:
            return .init(
                cx: body.cx,
                cy: body.cy + body.ry * 0.1,
                rx: body.rx * 0.54,
                ry: body.ry * 0.36
            )
        case .round, .boxy, .nub, .sun:
            return .init(cx: body.cx, cy: body.cy, rx: body.rx, ry: body.ry)
        }
    }

    private static func shrink(_ body: BlobatarBody, by scale: Double) -> BlobatarEllipse {
        .init(cx: body.cx, cy: body.cy, rx: body.rx * scale, ry: body.ry * scale)
    }

    private static func decorate(
        shape: BlobatarShape,
        body: BlobatarBody,
        traits: BlobatarTraits
    ) -> (petals: [BlobatarCircle], extra: [BlobatarPath]) {
        var petals: [BlobatarCircle] = []
        var extra: [BlobatarPath] = []

        switch shape {
        case .capsule:
            for sign in [-1.0, 1.0] {
                petals.append(.init(
                    cx: body.cx + sign * (body.rx - body.ry),
                    cy: body.cy,
                    radius: body.ry
                ))
            }
        case .nub:
            let count = traits.integer("nub.n", in: 1...2)
            for index in 0..<count {
                let angle = traits.number("nub.a\(index)", in: 0..<(2 * .pi))
                petals.append(.init(
                    cx: body.cx + cos(angle) * body.rx * 0.88,
                    cy: body.cy + sin(angle) * body.rx * 0.88,
                    radius: body.rx * traits.number("nub.r\(index)", in: 0.24..<0.4)
                ))
            }
        case .cloud:
            let count = traits.integer("cloud.n", in: 4...6)
            for index in 0..<count {
                let angle = Double.pi + Double.pi * (Double(index) + 0.5) / Double(count)
                petals.append(.init(
                    cx: body.cx + cos(angle) * body.rx * 0.8,
                    cy: body.cy + sin(angle) * body.rx * 0.5,
                    radius: body.rx * traits.number("cloud.r\(index)", in: 0.44..<0.62)
                ))
            }
        case .droplet:
            extra.append(BlobatarGeometry.taper(
                cx: body.cx,
                cy: body.cy,
                rx: body.rx,
                ry: body.ry,
                tip: traits.number("droplet.tip", in: 1.4..<1.65)
            ))
        case .sun:
            let count = traits.integer("sun.n", in: 6...9)
            let distance = body.rx * traits.number("sun.dist", in: 1..<1.08)
            let radius = body.rx * traits.number("sun.r", in: 0.2..<0.26)
            let offset = traits.number("sun.rot", in: 0..<(2 * .pi))
            for index in 0..<count {
                let angle = offset + 2 * .pi * Double(index) / Double(count)
                petals.append(.init(
                    cx: body.cx + cos(angle) * distance,
                    cy: body.cy + sin(angle) * distance,
                    radius: radius
                ))
            }
        case .round, .organic, .boxy, .hexagon, .triangle:
            break
        }

        return (petals, extra)
    }

    private static func bodyPath(for shape: BlobatarShape, body: BlobatarBody) -> BlobatarPath {
        switch shape {
        case .organic, .cloud:
            return BlobatarGeometry.blobPath(
                cx: body.cx,
                cy: body.cy,
                rx: body.rx,
                ry: body.ry,
                radii: body.radii,
                rotation: body.rotation
            )
        case .capsule:
            return BlobatarGeometry.box(
                cx: body.cx,
                cy: body.cy,
                rx: body.rx - body.ry,
                ry: body.ry
            )
        case .hexagon, .triangle:
            return BlobatarGeometry.polygon(.init(
                cx: body.cx,
                cy: body.cy,
                rx: body.rx,
                ry: body.ry,
                sides: body.sides ?? (shape == .hexagon ? 6 : 3),
                rounding: body.rounding ?? 0.3,
                rotation: body.rotation
            ))
        case .round, .boxy, .nub, .droplet, .sun:
            return BlobatarGeometry.superellipse(body.superellipse)
        }
    }

    private static func faceFit(
        traits: BlobatarTraits,
        body: BlobatarBody,
        face: BlobatarEllipse
    ) -> [BlobatarEye] {
        let radius = body.rx
        let initialEyeRadius = traits.number("eye.rx", in: 0.075..<0.105) * radius
        let ratio = traits.number("eye.ratio", in: 1.9..<3.2)
        let scale = traits.number("eye.scale", in: 0.78..<1.24)
        let stretch = traits.number("eye.stretch", in: 0.85..<1.18)
        let clearance = traits.number("eye.gap", in: 0.1..<0.24) * radius
        let wide = initialEyeRadius * max(1, scale)
        let tall = initialEyeRadius * ratio * max(1, scale * stretch)
        let initialGap = wide + radius * 0.03 + clearance

        let gazeX = traits.jitter("gaze.x", amount: 0.09) * face.rx
        let gazeY = traits.number("gaze.y", in: -0.2..<0.08) * face.ry
        let differentialY = traits.jitter("eye.dy", amount: 0.04) * face.ry
        let reach = hypot(wide, tall)
        let need = hypot(
            (abs(gazeX) + initialGap + reach) / face.rx,
            (abs(gazeY) + abs(differentialY) + reach) / face.ry
        )
        let fit = need > 0.9 ? 0.9 / need : 1

        let eyeRadius = initialEyeRadius * fit
        let eyeRadiusY = eyeRadius * ratio
        let gap = initialGap * fit
        let room = max(0, min(1, clearance / tall))
        let bound = min(12, asin(room) * 180 / .pi)
        let lean = traits.number("eye.lean", in: -1..<1) * bound
        let secondLean = max(-12, min(12, lean + traits.jitter("eye.lean2", amount: 3.5)))
        let exponent = traits.number("eye.n", in: 3.5..<6)
        let centerX = face.cx + gazeX * fit
        let centerY = face.cy + gazeY * fit

        return [
            .init(
                cx: centerX - gap,
                cy: centerY,
                rx: eyeRadius,
                ry: eyeRadiusY,
                exponent: exponent,
                rotation: lean
            ),
            .init(
                cx: centerX + gap,
                cy: centerY + differentialY * fit,
                rx: eyeRadius * scale,
                ry: eyeRadiusY * scale * stretch,
                exponent: exponent,
                rotation: secondLean
            ),
        ]
    }

    private static func makeBackdrop(
        shape: BlobatarBackdropShape?,
        fill: String
    ) -> BlobatarBackdrop? {
        guard let shape else { return nil }
        let path: BlobatarPath
        switch shape {
        case .square:
            path = BlobatarPath(commands: [
                .move(to: .init(x: 0, y: 0)),
                .horizontal(to: 100),
                .vertical(to: 100),
                .horizontal(to: 0),
                .close,
            ])
        case .circle:
            path = BlobatarGeometry.superellipse(.init(
                cx: 50, cy: 50, rx: 50, ry: 50, exponent: 2
            ))
        case .squircle:
            path = BlobatarGeometry.superellipse(.init(
                cx: 50, cy: 50, rx: 50, ry: 50, exponent: 6
            ))
        }
        return BlobatarBackdrop(shape: shape, path: path, fill: fill)
    }

    private static func renderModel(
        layout: BlobatarLayout,
        palette: BlobatarPalette,
        backdrop: BlobatarBackdrop?
    ) -> BlobatarRenderModel {
        var layers: [BlobatarRenderLayer] = []
        if let backdrop {
            layers.append(.init(
                identity: .backdrop,
                fill: backdrop.fill,
                primitives: [.path(backdrop.path)]
            ))
        }
        for (index, petal) in layout.petals.enumerated() {
            layers.append(.init(
                identity: .petal(index),
                fill: palette.head,
                primitives: [.circle(petal)]
            ))
        }
        for (index, path) in layout.extra.enumerated() {
            layers.append(.init(
                identity: .extra(index),
                fill: palette.head,
                primitives: [.path(path)]
            ))
        }
        layers.append(.init(
            identity: .body,
            fill: palette.head,
            primitives: [.path(layout.bodyPath)]
        ))
        for (index, eye) in layout.eyes.enumerated() {
            layers.append(.init(
                identity: .eye(index),
                fill: palette.eye,
                primitives: [.path(BlobatarGeometry.superellipse(eye.superellipse))],
                transformOrigin: .init(x: eye.cx, y: eye.cy)
            ))
        }
        return BlobatarRenderModel(layers: layers)
    }
}

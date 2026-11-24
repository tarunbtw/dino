import SwiftUI

struct BlobatarSceneState {
    var bodyTransform = CGAffineTransform.identity
    var eyeTransforms: [CGAffineTransform] = []

    static let identity = BlobatarSceneState()

    static func display(layout: BlobatarLayout) -> BlobatarSceneState {
        BlobatarSceneState(
            bodyTransform: .init(translationX: 0, y: layout.expressionBodyOffsetY),
            eyeTransforms: []
        )
    }

    init(
        bodyTransform: CGAffineTransform = .identity,
        eyeTransforms: [CGAffineTransform] = []
    ) {
        self.bodyTransform = bodyTransform
        self.eyeTransforms = eyeTransforms
    }

    init(motion: BlobatarMotionState, layout: BlobatarLayout) {
        let body = motion.body
        let center = CGPoint(x: 50, y: 50)
        // Preserve the authored SVG hierarchy rather than flattening channels:
        // root(hover/shake) -> breathe(scale) -> bob(expression/bob translation).
        // A child translation is therefore scaled by both parent scales.
        let bobAndExpression = CGAffineTransform(
            translationX: 0,
            y: body.bobOffsetY + body.expressionOffsetY
        )
        let breathe = Self.anchoredScale(
            center: center,
            scaleX: body.breatheScaleX,
            scaleY: body.breatheScaleY
        )
        let hoverScale = Self.anchoredScale(
            center: center,
            scaleX: body.hoverScale,
            scaleY: body.hoverScale
        )
        let hoverLift = CGAffineTransform(translationX: 0, y: body.hoverOffsetY)
        let rootShake = CGAffineTransform(
            translationX: body.shakeOffset.x,
            y: body.shakeOffset.y
        )
        let bodyTransform = bobAndExpression
            .concatenating(breathe)
            .concatenating(hoverScale)
            .concatenating(hoverLift)
            .concatenating(rootShake)

        let group = motion.combinedEyeGroupOffset
        let eyeTransforms = layout.eyes.enumerated().map { index, eye in
            guard motion.eyes.indices.contains(index) else {
                return CGAffineTransform(translationX: group.x, y: group.y)
            }
            let state = motion.eyes[index]
            return Self.eyeTransform(state: state, eye: eye, groupOffset: group)
        }

        self.init(bodyTransform: bodyTransform, eyeTransforms: eyeTransforms)
    }

    static func eyeTransform(
        state: BlobatarEyeMotionState,
        eye: BlobatarEye,
        groupOffset: BlobatarPoint = .zero
    ) -> CGAffineTransform {
        let center = CGPoint(x: eye.cx, y: eye.cy)
        // The eye path already contains its seeded lean. Every anisotropic scale
        // must therefore be bracketed into that local capsule frame; folding the
        // scales together in screen coordinates shears nearly every generated eye.
        let blink = localAxisScale(
            center: center,
            leanDegrees: eye.rotation,
            x: 1,
            y: state.blinkScaleY
        )
        let wrapScale = anchoredScale(
            center: center,
            scaleX: state.wrapScaleX,
            scaleY: state.wrapScaleY
        )
        let wrapRotation = anchoredRotation(
            center: center,
            degrees: state.wrapRotationDegrees
        )
        let poseScale = localAxisScale(
            center: center,
            leanDegrees: eye.rotation,
            x: state.poseScaleX,
            y: state.poseScaleY
        )
        let poseRotation = anchoredRotation(
            center: center,
            degrees: state.poseRotationDegrees
        )
        let translation = CGAffineTransform(
            translationX: groupOffset.x + state.poseOffset.x,
            y: groupOffset.y + state.poseOffset.y
        )
        return blink
            .concatenating(wrapScale)
            .concatenating(wrapRotation)
            .concatenating(poseScale)
            .concatenating(poseRotation)
            .concatenating(translation)
    }

    static func localAxisScale(
        center: CGPoint,
        leanDegrees: Double,
        x: Double,
        y: Double
    ) -> CGAffineTransform {
        anchoredRotation(center: center, degrees: -leanDegrees)
            .concatenating(anchoredScale(center: center, scaleX: x, scaleY: y))
            .concatenating(anchoredRotation(center: center, degrees: leanDegrees))
    }

    private static func anchoredScale(
        center: CGPoint,
        scaleX: Double,
        scaleY: Double
    ) -> CGAffineTransform {
        CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(.init(scaleX: scaleX, y: scaleY))
            .concatenating(.init(translationX: center.x, y: center.y))
    }

    private static func anchoredRotation(
        center: CGPoint,
        degrees: Double
    ) -> CGAffineTransform {
        CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(.init(rotationAngle: degrees * .pi / 180))
            .concatenating(.init(translationX: center.x, y: center.y))
    }
}

enum BlobatarCanvasRenderer {
    static func draw(
        model: BlobatarModel,
        layout: BlobatarLayout,
        palette: BlobatarPalette,
        state: BlobatarSceneState,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let side = min(size.width, size.height)
        let scale = side / BlobatarRenderModel.viewBoxSize
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)

        var canvas = context
        canvas.translateBy(x: origin.x, y: origin.y)
        canvas.scaleBy(x: scale, y: scale)

        if let backdrop = model.backdrop {
            canvas.fill(Path(blobatar: backdrop.path), with: .color(Color(blobatarHex: backdrop.fill)))
        }

        var creature = canvas
        creature.concatenate(state.bodyTransform)
        let bodyColor = Color(blobatarHex: palette.head)
        let eyeColor = Color(blobatarHex: palette.eye)

        for petal in layout.petals {
            let rect = CGRect(
                x: petal.cx - petal.radius,
                y: petal.cy - petal.radius,
                width: petal.radius * 2,
                height: petal.radius * 2
            )
            creature.fill(Path(ellipseIn: rect), with: .color(bodyColor))
        }
        for path in layout.extra {
            creature.fill(Path(blobatar: path), with: .color(bodyColor))
        }
        creature.fill(Path(blobatar: layout.bodyPath), with: .color(bodyColor))

        for (index, path) in layout.eyePaths.enumerated() {
            var eyeContext = creature
            if state.eyeTransforms.indices.contains(index) {
                eyeContext.concatenate(state.eyeTransforms[index])
            }
            eyeContext.fill(Path(blobatar: path), with: .color(eyeColor))
        }
    }
}

enum BlobatarCanvasPalette {
    static func resolved(
        base: BlobatarPalette,
        tint: BlobatarTint?,
        heat: Double
    ) -> BlobatarPalette {
        guard let tint else { return base }
        let endpoint = BlobatarColor.tinted(head: base.head, eye: base.eye, tint: tint)
        return BlobatarPalette(
            background: base.background,
            head: BlobatarColor.mixHex(base.head, endpoint.head, t: heat),
            eye: BlobatarColor.mixHex(base.eye, endpoint.eye, t: heat)
        )
    }

    static func interpolated(
        from: BlobatarPalette,
        to: BlobatarPalette,
        progress: Double
    ) -> BlobatarPalette {
        BlobatarPalette(
            background: cssInterpolatedHex(from.background, to.background, progress: progress),
            head: cssInterpolatedHex(from.head, to.head, progress: progress),
            eye: cssInterpolatedHex(from.eye, to.eye, progress: progress)
        )
    }

    /// CSS transitions between legacy hex colors in encoded sRGB channel
    /// space. This intentionally differs from BlobatarColor.mixHex, whose
    /// OKLab blend is the source palette's explicit color-mix behavior.
    private static func cssInterpolatedHex(
        _ from: String,
        _ to: String,
        progress: Double
    ) -> String {
        guard let start = rgbBytes(from), let end = rgbBytes(to) else {
            return progress < 0.5 ? from : to
        }
        let amount = min(max(progress, 0), 1)
        let channels = zip(start, end).map { start, end in
            Int((Double(start) + (Double(end) - Double(start)) * amount).rounded())
        }
        return String(format: "#%02x%02x%02x", channels[0], channels[1], channels[2])
    }

    private static func rgbBytes(_ hex: String) -> [Int]? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return [
            Int((value >> 16) & 255),
            Int((value >> 8) & 255),
            Int(value & 255),
        ]
    }
}

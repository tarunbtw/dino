import Foundation

/// The ten silhouettes whose weighted bands define Blobatar generation two.
public enum BlobatarShape: String, CaseIterable, Sendable, Hashable, Codable {
    case round
    case organic
    case boxy
    case capsule
    case nub
    case cloud
    case droplet
    case hexagon
    case sun
    case triangle
}

public struct BlobatarPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Absolute path commands used by Blobatar 2.4.0.
public enum BlobatarPathCommand: Sendable, Hashable, Codable {
    case move(to: BlobatarPoint)
    case line(to: BlobatarPoint)
    case horizontal(to: Double)
    case vertical(to: Double)
    case cubic(control1: BlobatarPoint, control2: BlobatarPoint, end: BlobatarPoint)
    case quadratic(control: BlobatarPoint, end: BlobatarPoint)
    case close

    public var svg: String {
        switch self {
        case let .move(point):
            return "M\(BlobatarPath.number(point.x)) \(BlobatarPath.number(point.y))"
        case let .line(point):
            return "L\(BlobatarPath.number(point.x)) \(BlobatarPath.number(point.y))"
        case let .horizontal(value):
            return "H\(BlobatarPath.number(value))"
        case let .vertical(value):
            return "V\(BlobatarPath.number(value))"
        case let .cubic(control1, control2, end):
            return "C\(BlobatarPath.number(control1.x)) \(BlobatarPath.number(control1.y)) "
                + "\(BlobatarPath.number(control2.x)) \(BlobatarPath.number(control2.y)) "
                + "\(BlobatarPath.number(end.x)) \(BlobatarPath.number(end.y))"
        case let .quadratic(control, end):
            return "Q\(BlobatarPath.number(control.x)) \(BlobatarPath.number(control.y)) "
                + "\(BlobatarPath.number(end.x)) \(BlobatarPath.number(end.y))"
        case .close:
            return "Z"
        }
    }
}

/// A render-neutral vector path with deterministic SVG serialization.
public struct BlobatarPath: Sendable, Hashable, Codable {
    public var commands: [BlobatarPathCommand]

    public init(commands: [BlobatarPathCommand]) {
        self.commands = commands
    }

    public var svg: String {
        commands.map(\.svg).joined()
    }

    /// JavaScript's `Math.round(v * 100) / 100`, including its negative-tie rule.
    static func roundedToHundredth(_ value: Double) -> Double {
        let rounded = floor(value * 100 + 0.5) / 100
        return rounded == 0 ? 0 : rounded
    }

    static func number(_ value: Double) -> String {
        let rounded = roundedToHundredth(value)
        if rounded == 0 { return "0" }
        if rounded.rounded(.towardZero) == rounded {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        }
        var result = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
}

public struct BlobatarSuperellipse: Sendable, Hashable, Codable {
    public var cx: Double
    public var cy: Double
    public var rx: Double
    public var ry: Double
    public var exponent: Double
    public var rotation: Double

    public init(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double,
        exponent: Double = 4,
        rotation: Double = 0
    ) {
        self.cx = cx
        self.cy = cy
        self.rx = rx
        self.ry = ry
        self.exponent = exponent
        self.rotation = rotation
    }

    public init(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double,
        n: Double,
        rot: Double = 0
    ) {
        self.init(cx: cx, cy: cy, rx: rx, ry: ry, exponent: n, rotation: rot)
    }

    public var n: Double {
        get { exponent }
        set { exponent = newValue }
    }
}

public struct BlobatarPolygon: Sendable, Hashable, Codable {
    public var cx: Double
    public var cy: Double
    public var rx: Double
    public var ry: Double
    public var sides: Int
    public var rounding: Double
    public var rotation: Double

    public init(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double,
        sides: Int,
        rounding: Double = 0.3,
        rotation: Double = 0
    ) {
        precondition(sides >= 3, "A polygon requires at least three sides")
        self.cx = cx
        self.cy = cy
        self.rx = rx
        self.ry = ry
        self.sides = sides
        self.rounding = rounding
        self.rotation = rotation
    }

    public init(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double,
        sides: Int,
        round: Double,
        rot: Double = 0
    ) {
        self.init(
            cx: cx,
            cy: cy,
            rx: rx,
            ry: ry,
            sides: sides,
            rounding: round,
            rotation: rot
        )
    }

    public var round: Double {
        get { rounding }
        set { rounding = newValue }
    }
}

public struct BlobatarEllipse: Sendable, Hashable, Codable {
    public var cx: Double
    public var cy: Double
    public var rx: Double
    public var ry: Double

    public init(cx: Double, cy: Double, rx: Double, ry: Double) {
        self.cx = cx
        self.cy = cy
        self.rx = rx
        self.ry = ry
    }
}

public struct BlobatarCircle: Sendable, Hashable, Codable {
    public var cx: Double
    public var cy: Double
    public var radius: Double

    public init(cx: Double, cy: Double, radius: Double) {
        self.cx = cx
        self.cy = cy
        self.radius = radius
    }

    public var r: Double {
        get { radius }
        set { radius = newValue }
    }
}

public struct BlobatarBody: Sendable, Hashable, Codable {
    public var cx: Double
    public var cy: Double
    public var rx: Double
    public var ry: Double
    public var exponent: Double
    public var rotation: Double
    public var radii: [Double]
    public var sides: Int?
    public var rounding: Double?

    public init(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double,
        exponent: Double,
        rotation: Double,
        radii: [Double],
        sides: Int? = nil,
        rounding: Double? = nil
    ) {
        self.cx = cx
        self.cy = cy
        self.rx = rx
        self.ry = ry
        self.exponent = exponent
        self.rotation = rotation
        self.radii = radii
        self.sides = sides
        self.rounding = rounding
    }

    public var n: Double {
        get { exponent }
        set { exponent = newValue }
    }

    public var rot: Double {
        get { rotation }
        set { rotation = newValue }
    }

    public var round: Double? {
        get { rounding }
        set { rounding = newValue }
    }

    public var superellipse: BlobatarSuperellipse {
        .init(cx: cx, cy: cy, rx: rx, ry: ry, exponent: exponent, rotation: rotation)
    }
}

public struct BlobatarEye: Sendable, Hashable, Codable {
    public var cx: Double
    public var cy: Double
    public var rx: Double
    public var ry: Double
    public var exponent: Double
    public var rotation: Double

    public init(
        cx: Double,
        cy: Double,
        rx: Double,
        ry: Double,
        exponent: Double,
        rotation: Double
    ) {
        self.cx = cx
        self.cy = cy
        self.rx = rx
        self.ry = ry
        self.exponent = exponent
        self.rotation = rotation
    }

    public var n: Double {
        get { exponent }
        set { exponent = newValue }
    }

    public var rot: Double {
        get { rotation }
        set { rotation = newValue }
    }

    public var superellipse: BlobatarSuperellipse {
        .init(cx: cx, cy: cy, rx: rx, ry: ry, exponent: exponent, rotation: rotation)
    }
}

/// The complete numeric output of the generation-two layout pass.
public struct BlobatarLayout: Sendable, Hashable, Codable {
    public var shape: BlobatarShape
    public var body: BlobatarBody
    public var face: BlobatarEllipse
    public var petals: [BlobatarCircle]
    public var extra: [BlobatarPath]
    public var eyes: [BlobatarEye]
    public var bodyPath: BlobatarPath
    /// Static expression translation applied to the whole creature, never the backdrop.
    public var expressionBodyOffsetY: Double

    public init(
        shape: BlobatarShape,
        body: BlobatarBody,
        face: BlobatarEllipse,
        petals: [BlobatarCircle],
        extra: [BlobatarPath],
        eyes: [BlobatarEye],
        bodyPath: BlobatarPath,
        expressionBodyOffsetY: Double = 0
    ) {
        self.shape = shape
        self.body = body
        self.face = face
        self.petals = petals
        self.extra = extra
        self.eyes = eyes
        self.bodyPath = bodyPath
        self.expressionBodyOffsetY = expressionBodyOffsetY
    }

    public var eyePaths: [BlobatarPath] {
        eyes.map { BlobatarGeometry.superellipse($0.superellipse) }
    }
}

public enum BlobatarAnimation: String, CaseIterable, Sendable, Hashable, Codable {
    case none
    case hover
    case always
}

public enum BlobatarBackdropShape: String, CaseIterable, Sendable, Hashable, Codable {
    case square
    case circle
    case squircle
}

public struct BlobatarBackdrop: Sendable, Hashable, Codable {
    public var shape: BlobatarBackdropShape
    public var path: BlobatarPath
    public var fill: String

    public init(shape: BlobatarBackdropShape, path: BlobatarPath, fill: String) {
        self.shape = shape
        self.path = path
        self.fill = fill
    }
}

public struct BlobatarConfiguration: Sendable, Hashable {
    public var seed: String
    public var hue: Double?
    public var tone: Double?
    public var size: Double
    public var backdropShape: BlobatarBackdropShape?
    public var animation: BlobatarAnimation
    public var expression: BlobatarExpression?
    public var traits: [String: BlobatarTraitOverride]
    public var normalize: Bool
    public var enforceContrast: Bool
    public var palette: BlobatarPalette?
    public var title: String?

    public init(
        seed: String,
        hue: Double? = nil,
        tone: Double? = nil,
        size: Double = 100,
        background: Bool = false,
        animation: BlobatarAnimation = .none,
        expression: BlobatarExpression? = nil,
        traits: [String: BlobatarTraitOverride] = [:],
        normalize: Bool = true,
        enforceContrast: Bool = true,
        palette: BlobatarPalette? = nil,
        title: String? = nil
    ) {
        self.seed = seed
        self.hue = hue
        self.tone = tone
        self.size = size
        backdropShape = background ? .squircle : nil
        self.animation = animation
        self.expression = expression
        self.traits = traits
        self.normalize = normalize
        self.enforceContrast = enforceContrast
        self.palette = palette
        self.title = title
    }

    public init(
        seed: String,
        hue: Double? = nil,
        tone: Double? = nil,
        size: Double = 100,
        background: BlobatarBackdropShape,
        animation: BlobatarAnimation = .none,
        expression: BlobatarExpression? = nil,
        traits: [String: BlobatarTraitOverride] = [:],
        normalize: Bool = true,
        enforceContrast: Bool = true,
        palette: BlobatarPalette? = nil,
        title: String? = nil
    ) {
        self.init(
            seed: seed,
            hue: hue,
            tone: tone,
            size: size,
            backdrop: background,
            animation: animation,
            expression: expression,
            traits: traits,
            normalize: normalize,
            enforceContrast: enforceContrast,
            palette: palette,
            title: title
        )
    }

    public init(
        seed: String,
        hue: Double? = nil,
        tone: Double? = nil,
        size: Double = 100,
        backdrop: BlobatarBackdropShape?,
        animation: BlobatarAnimation = .none,
        expression: BlobatarExpression? = nil,
        traits: [String: BlobatarTraitOverride] = [:],
        normalize: Bool = true,
        enforceContrast: Bool = true,
        palette: BlobatarPalette? = nil,
        title: String? = nil
    ) {
        self.seed = seed
        self.hue = hue
        self.tone = tone
        self.size = size
        backdropShape = backdrop
        self.animation = animation
        self.expression = expression
        self.traits = traits
        self.normalize = normalize
        self.enforceContrast = enforceContrast
        self.palette = palette
        self.title = title
    }

    public var background: Bool {
        get { backdropShape != nil }
        set { backdropShape = newValue ? .squircle : nil }
    }
}

public enum BlobatarLayerIdentity: Sendable, Hashable, Codable {
    case backdrop
    case body
    case petal(Int)
    case extra(Int)
    case eye(Int)
}

public enum BlobatarRenderPrimitive: Sendable, Hashable, Codable {
    case path(BlobatarPath)
    case circle(BlobatarCircle)
}

public struct BlobatarRenderLayer: Sendable, Hashable, Codable {
    public var identity: BlobatarLayerIdentity
    public var fill: String
    public var primitives: [BlobatarRenderPrimitive]
    public var transformOrigin: BlobatarPoint?

    public init(
        identity: BlobatarLayerIdentity,
        fill: String,
        primitives: [BlobatarRenderPrimitive],
        transformOrigin: BlobatarPoint? = nil
    ) {
        self.identity = identity
        self.fill = fill
        self.primitives = primitives
        self.transformOrigin = transformOrigin
    }
}

/// Layered geometry consumed identically by SwiftUI, AppKit, or an SVG exporter.
public struct BlobatarRenderModel: Sendable, Hashable, Codable {
    public static let viewBoxSize = 100.0
    public var layers: [BlobatarRenderLayer]

    public init(layers: [BlobatarRenderLayer]) {
        self.layers = layers
    }
}

public struct BlobatarModel: Sendable, Hashable {
    public var configuration: BlobatarConfiguration
    /// Untinted generated (or explicitly supplied) palette.
    public var basePalette: BlobatarPalette
    /// Palette after the selected expression's tint has been applied.
    public var palette: BlobatarPalette
    /// Frozen seed identity before any expression channels are applied.
    public var layout: BlobatarLayout
    /// Static/reduced-motion layout with the selected expression baked once.
    public var displayLayout: BlobatarLayout
    public var backdrop: BlobatarBackdrop?
    public var motion: BlobatarMotionParameters
    public var render: BlobatarRenderModel

    public init(
        configuration: BlobatarConfiguration,
        basePalette: BlobatarPalette,
        palette: BlobatarPalette,
        layout: BlobatarLayout,
        displayLayout: BlobatarLayout,
        backdrop: BlobatarBackdrop?,
        motion: BlobatarMotionParameters,
        render: BlobatarRenderModel
    ) {
        self.configuration = configuration
        self.basePalette = basePalette
        self.palette = palette
        self.layout = layout
        self.displayLayout = displayLayout
        self.backdrop = backdrop
        self.motion = motion
        self.render = render
    }

    public var layers: [BlobatarRenderLayer] { render.layers }
}

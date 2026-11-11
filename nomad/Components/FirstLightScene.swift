//
//  FirstLightScene.swift
//  nomad
//
//  Ported from Firn ("First light", calm empty page).
//  Gradients, shapes, snow bands and drifting flakes with zero CPU idle draw.
//

import SwiftUI
import AppKit

struct FirstLightScene: View {
    let spaceColor: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                FirstLightSky()
                FirstLightSun()
                FirstLightFlakes(reduceMotion: reduceMotion)

                FirstLightSnow(colors: Theme.FirstLight.snow(spaceColor))
                    .frame(height: proxy.size.height * 0.25)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: spaceColor)

                Image("FirstLightGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(Theme.FirstLight.grainOpacity)
                    .blendMode(.softLight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.page)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FirstLightSky: View {
    var body: some View {
        Canvas { context, size in
            typealias FL = Theme.FirstLight
            let (w, h) = (size.width, size.height)
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(stops: [.init(color: FL.skyTop, location: 0), .init(color: Theme.page, location: 0.7)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: h)
                )
            )

            Self.glow(context, size, color: FL.warm2, center: CGPoint(x: 0.10 * w, y: 0.56 * h),
                      radii: CGSize(width: 0.44 * w, height: 0.50 * h), fade: 0.70)
            Self.glow(context, size, color: FL.warm, center: CGPoint(x: 0.86 * w, y: 0.62 * h),
                      radii: CGSize(width: 0.56 * w, height: 0.60 * h), fade: 0.68)
            Self.glow(context, size, color: FL.cool, center: CGPoint(x: 0.50 * w, y: -0.12 * h),
                      radii: CGSize(width: 0.70 * w, height: 0.58 * h), fade: 0.70)
        }
    }

    private static func glow(_ context: GraphicsContext, _ size: CGSize, color: Color,
                             center: CGPoint, radii: CGSize, fade: CGFloat) {
        ellipse(context, size, Gradient(stops: [
            .init(color: color, location: 0), .init(color: color.opacity(0), location: fade)
        ]), center: center, radii: radii)
    }

    fileprivate static func ellipse(_ context: GraphicsContext, _ size: CGSize, _ gradient: Gradient,
                                    center: CGPoint, radii: CGSize) {
        guard radii.width > 0, radii.height > 0 else { return }
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.scaleBy(x: radii.width, y: radii.height)
        let whole = CGRect(x: -center.x / radii.width, y: -center.y / radii.height,
                           width: size.width / radii.width, height: size.height / radii.height)
        layer.fill(Path(whole), with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
    }
}

private struct FirstLightSun: View {
    var body: some View {
        GeometryReader { proxy in
            let (w, h) = (proxy.size.width, proxy.size.height)
            let box = CGSize(width: min(1200, 0.94 * w), height: 0.52 * h)
            ZStack {
                Self.glow([
                    .init(color: Theme.FirstLight.sun, location: 0),
                    .init(color: Theme.FirstLight.sunMid, location: 0.5),
                    .init(color: Theme.FirstLight.sunMid.opacity(0), location: 1)
                ])
            }
            .frame(width: box.width, height: box.height)
            .position(x: w / 2, y: 1.075 * h - box.height / 2)
        }
    }

    private static func glow(_ stops: [Gradient.Stop]) -> some View {
        Canvas { context, size in
            FirstLightSky.ellipse(context, size, Gradient(stops: stops),
                                  center: CGPoint(x: size.width / 2, y: size.height / 2),
                                  radii: CGSize(width: size.width / 2, height: size.height / 2))
        }
    }
}

private struct FirstLightSnow: View {
    let colors: [Color]

    var body: some View {
        ZStack {
            ForEach(SnowBand.paths.indices, id: \.self) { index in
                if colors.indices.contains(index) {
                    SnowBand(index: index).fill(colors[index])
                }
            }
        }
    }
}

private struct SnowBand: Shape {
    let index: Int

    static let paths: [Path] = [
        "M0,200 L0,26.6 C106.7,26.6 106.7,42.3 213.3,42.3 C320,42.3 320,33.3 426.7,33.3 C533.3,33.3 533.3,45.3 640,45.3 C746.7,45.3 746.7,46.4 853.3,46.4 C960,46.4 960,17.8 1066.7,17.8 C1173.3,17.8 1173.3,15.1 1280,15.1 L1280,200 Z",
        "M0,200 L0,76.2 C106.7,76.2 106.7,81.2 213.3,81.2 C320,81.2 320,97.9 426.7,97.9 C533.3,97.9 533.3,76.8 640,76.8 C746.7,76.8 746.7,78.8 853.3,78.8 C960,78.8 960,82.4 1066.7,82.4 C1173.3,82.4 1173.3,63.9 1280,63.9 L1280,200 Z",
        "M0,200 L0,121.8 C106.7,121.8 106.7,126.7 213.3,126.7 C320,126.7 320,128.9 426.7,128.9 C533.3,128.9 533.3,134.9 640,134.9 C746.7,134.9 746.7,126.6 853.3,126.6 C960,126.6 960,134.1 1066.7,134.1 C1173.3,134.1 1173.3,97.5 1280,97.5 L1280,200 Z",
        "M0,200 L0,152.8 C106.7,152.8 106.7,163 213.3,163 C320,163 320,168.5 426.7,168.5 C533.3,168.5 533.3,144.5 640,144.5 C746.7,144.5 746.7,161.5 853.3,161.5 C960,161.5 960,159.3 1066.7,159.3 C1173.3,159.3 1173.3,157.8 1280,157.8 L1280,200 Z",
        "M0,200 L0,191.7 C106.7,191.7 106.7,192.3 213.3,192.3 C320,192.3 320,190.8 426.7,190.8 C533.3,190.8 533.3,170.1 640,170.1 C746.7,170.1 746.7,183.2 853.3,183.2 C960,183.2 960,178.8 1066.7,178.8 C1173.3,178.8 1173.3,181.6 1280,181.6 L1280,200 Z"
    ].map { Path(SVGPath.cgPath($0)) }

    func path(in rect: CGRect) -> Path {
        Self.paths[index].applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / 1280, y: rect.height / 200)
        )
    }
}

private struct FirstLightFlakes: NSViewRepresentable {
    let reduceMotion: Bool

    func makeNSView(context: Context) -> FlakesView { FlakesView() }

    func updateNSView(_ view: FlakesView, context: Context) {
        view.drifts = !reduceMotion
    }
}

private final class FlakesView: NSView {
    private static let flakes: [(left: CGFloat, top: CGFloat, size: CGFloat, turn: CGFloat, start: Double)] = [
        (0.117, 0.175, 30, -12, 0),
        (0.859, 0.138, 22, 18, 6),
        (0.813, 0.413, 14, 0, 12),
        (0.172, 0.525, 14, 40, 3)
    ]
    private static let drift: (seconds: Double, distance: CGFloat) = (20, 6)

    private var flakeLayers: [CALayer] = []

    var drifts = false {
        didSet { if drifts != oldValue { updateDrift() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for flake in Self.flakes {
            let layer = CALayer()
            layer.backgroundColor = Theme.FirstLight.flake.cgColor
            layer.opacity = Theme.FirstLight.flakeOpacity
            layer.mask = CALayer()
            layer.mask?.contentsGravity = .resizeAspect
            layer.bounds = CGRect(x: 0, y: 0, width: flake.size, height: flake.size)
            layer.mask?.frame = layer.bounds
            layer.transform = Self.turn(flake.turn)
            self.layer?.addSublayer(layer)
            flakeLayers.append(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, flake) in zip(flakeLayers, Self.flakes) {
            layer.position = CGPoint(
                x: flake.left * bounds.width + flake.size / 2,
                y: bounds.height - flake.top * bounds.height - flake.size / 2
            )
        }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        let mark = NSImage(named: "NomadMark") ?? NSImage(named: "FirnMarkSmall")
        for layer in flakeLayers {
            layer.mask?.contentsScale = scale
            layer.mask?.contents = mark?.layerContents(forContentsScale: scale)
        }
    }

    private static func turn(_ degrees: CGFloat) -> CATransform3D {
        CATransform3DMakeRotation(-degrees * .pi / 180, 0, 0, 1)
    }

    private func updateDrift() {
        for (layer, flake) in zip(flakeLayers, Self.flakes) {
            layer.removeAnimation(forKey: "drift")
            guard drifts else { continue }
            let rest = Self.turn(flake.turn)
            let drift = CABasicAnimation(keyPath: "transform")
            drift.fromValue = rest
            drift.toValue = CATransform3DTranslate(rest, 0, -Self.drift.distance, 0)
            drift.duration = Self.drift.seconds
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drift.timeOffset = flake.start
            layer.add(drift, forKey: "drift")
        }
    }
}


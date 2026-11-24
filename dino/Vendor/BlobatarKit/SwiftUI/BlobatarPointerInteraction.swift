import CoreGraphics
import Foundation

enum BlobatarPointerPhase: Hashable {
    case active(location: CGPoint)
    case ended
}

struct BlobatarPointerInteraction: Hashable {
    var supportsHover: Bool
    var isHovered = false
    var gaze: BlobatarGaze?

    init(supportsHover: Bool) {
        self.supportsHover = supportsHover
    }

    mutating func update(
        phase: BlobatarPointerPhase,
        at time: TimeInterval,
        size: CGSize,
        currentGazeOffset: BlobatarPoint,
        tracksPointerGaze: Bool
    ) {
        switch phase {
        case let .active(location):
            // Continuous-hover callbacks only arrive from a real pointer. This
            // promotes pointer-equipped iPad at runtime without treating touch
            // taps as latched hover.
            supportsHover = true
            isHovered = true
            gaze = tracksPointerGaze ? BlobatarGaze(
                target: Self.target(location: location, size: size),
                initial: currentGazeOffset,
                startedAt: time
            ) : nil
        case .ended:
            isHovered = false
            gaze = tracksPointerGaze ? BlobatarGaze(
                target: .zero,
                initial: currentGazeOffset,
                startedAt: time
            ) : nil
        }
    }

    static func target(
        location: CGPoint,
        size: CGSize,
        maximumOffset: Double = 1.2
    ) -> BlobatarPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        let normalizedX = min(max(Double(location.x / size.width) * 2 - 1, -1), 1)
        let normalizedY = min(max(Double(location.y / size.height) * 2 - 1, -1), 1)
        return BlobatarPoint(
            x: normalizedX * maximumOffset,
            y: normalizedY * maximumOffset
        )
    }
}

import Foundation

public enum BlobatarTraitOverride: Sendable, Hashable {
    case value(Double)
    case choices([Double])
}

/// Read-only keyed traits. Every key is independent, so new keys do not redraw old blobatars.
public struct BlobatarTraits: Sendable {
    public let state: UInt32
    public var overrides: [String: BlobatarTraitOverride]

    public init(
        name: String,
        normalize: Bool = true,
        overrides: [String: BlobatarTraitOverride] = [:]
    ) {
        state = BlobatarHash.seedState(name, normalize: normalize)
        self.overrides = overrides
    }

    public func value(_ key: String) -> Double {
        let streamed = BlobatarHash.stream(state: state, key: key)
        let selected: Double?
        switch overrides[key] {
        case let .value(value):
            selected = value
        case let .choices(values):
            selected = values.isEmpty ? nil : values[min(Int(streamed * Double(values.count)), values.count - 1)]
        case nil:
            selected = nil
        }
        guard let selected else { return streamed }
        if selected > 0 {
            return selected < 1 ? selected : 0.999999
        }
        return 0
    }

    public func number(_ key: String, in range: Range<Double>) -> Double {
        range.lowerBound + value(key) * (range.upperBound - range.lowerBound)
    }

    public func integer(_ key: String, in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(floor(value(key) * Double(range.count)))
    }

    public func pick<Value>(_ key: String, from values: [Value]) -> Value {
        precondition(!values.isEmpty, "A trait cannot pick from an empty option set")
        return values[min(Int(floor(value(key) * Double(values.count))), values.count - 1)]
    }

    public func boolean(_ key: String, probability: Double = 0.5) -> Bool {
        value(key) < probability
    }

    public func jitter(_ key: String, amount: Double) -> Double {
        (value(key) * 2 - 1) * amount
    }
}

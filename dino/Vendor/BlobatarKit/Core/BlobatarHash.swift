import Foundation

/// Exact port of Blobatar 2.4.0's UTF-8 keyed hash.
public enum BlobatarHash {
    private static let separator: UInt8 = 0xff

    public static func normalize(_ name: String) -> String {
        name
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func seedState(_ name: String, normalize shouldNormalize: Bool = true) -> UInt32 {
        let seed = shouldNormalize ? normalize(name) : name
        return feed(1_779_033_703 ^ UInt32(truncatingIfNeeded: seed.utf16.count), bytes: seed.utf8)
    }

    public static func stream(state: UInt32, key: String) -> Double {
        let separated = feed(state, bytes: CollectionOfOne(separator))
        return Double(finalize(feed(separated, bytes: key.utf8))) / 4_294_967_296
    }

    private static func feed<Bytes: Collection>(
        _ initial: UInt32,
        bytes: Bytes
    ) -> UInt32 where Bytes.Element == UInt8 {
        var hash = initial
        for byte in bytes {
            hash = (hash ^ UInt32(byte)) &* 3_432_918_353
            hash = (hash << 13) | (hash >> 19)
        }
        return hash
    }

    private static func finalize(_ initial: UInt32) -> UInt32 {
        var hash = (initial ^ (initial >> 16)) &* 2_246_822_507
        hash = (hash ^ (hash >> 13)) &* 3_266_489_909
        return hash ^ (hash >> 16)
    }
}

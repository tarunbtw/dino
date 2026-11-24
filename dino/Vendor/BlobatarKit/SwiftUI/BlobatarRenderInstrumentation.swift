import SwiftUI

#if DEBUG
struct BlobatarRenderProbe: Sendable {
    var record: @Sendable (_ seed: String, _ timestamp: TimeInterval) -> Void

    init(record: @escaping @Sendable (String, TimeInterval) -> Void) {
        self.record = record
    }
}

private struct BlobatarRenderProbeKey: EnvironmentKey {
    static let defaultValue: BlobatarRenderProbe? = nil
}

extension EnvironmentValues {
    var blobatarRenderProbe: BlobatarRenderProbe? {
        get { self[BlobatarRenderProbeKey.self] }
        set { self[BlobatarRenderProbeKey.self] = newValue }
    }
}
#endif

//
//  DinoRouteCache.swift
//  dino
//
//  Deterministic session trajectory journal for agent automation debugging.
//

import Foundation

/// An individual trace event captured in the deterministic trajectory journal.
struct TrajectoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let tabId: String?
    let eventType: String
    let message: String
    let metadata: [String: String]

    init(id: UUID = UUID(), timestamp: Date = Date(), tabId: String? = nil, eventType: String, message: String, metadata: [String: String] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.tabId = tabId
        self.eventType = eventType
        self.message = message
        self.metadata = metadata
    }
}

/// Thread-safe trajectory journal recording agent steps and navigation events.
final class DinoRouteCache: @unchecked Sendable {
    static let shared = DinoRouteCache()

    private let lock = NSLock()
    private var trajectories: [TrajectoryEntry] = []
    private let maxTrajectoryCount = 1000

    private init() {}

    /// Records an execution step into the trajectory journal.
    func record(eventType: String, message: String, tabId: String? = nil, metadata: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }

        let entry = TrajectoryEntry(tabId: tabId, eventType: eventType, message: message, metadata: metadata)
        if trajectories.count >= maxTrajectoryCount {
            trajectories.removeFirst(100)
        }
        trajectories.append(entry)
    }

    /// Exports the chronological trajectory journal.
    func exportTrajectory(tabId: String? = nil) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        let filtered = trajectories.filter { entry in
            if let tid = tabId, !tid.isEmpty {
                return entry.tabId == tid
            }
            return true
        }

        return filtered.map { e in
            [
                "id": e.id.uuidString,
                "timestamp": e.timestamp.timeIntervalSince1970 * 1000.0,
                "tabId": (e.tabId as Any?) ?? NSNull(),
                "type": e.eventType,
                "message": e.message,
                "metadata": e.metadata
            ] as [String: Any]
        }
    }

    /// Clears trajectory entries.
    func clearTrajectory() {
        lock.lock()
        defer { lock.unlock() }
        trajectories.removeAll()
    }
}

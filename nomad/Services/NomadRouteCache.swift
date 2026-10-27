//
//  NomadRouteCache.swift
//  nomad
//
//  Created by tarun on 27/10/26.
//

import Foundation

/// Represents a learned action selector cached for recurring agent tasks.
struct CachedRoute: Codable, Identifiable, Sendable {
    let id: UUID
    let domain: String
    let intent: String
    let selector: String
    let action: String
    var successCount: Int
    var lastUsed: Date

    init(id: UUID = UUID(), domain: String, intent: String, selector: String, action: String = "click", successCount: Int = 1, lastUsed: Date = Date()) {
        self.id = id
        self.domain = domain.lowercased()
        self.intent = intent.lowercased()
        self.selector = selector
        self.action = action
        self.successCount = successCount
        self.lastUsed = lastUsed
    }
}

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

/// Manages agentic runtime route caching and deterministic session trajectories.
final class NomadRouteCache: @unchecked Sendable {
    static let shared = NomadRouteCache()

    private let lock = NSLock()
    private var routes: [CachedRoute] = []
    private var trajectories: [TrajectoryEntry] = []
    private let maxTrajectoryCount = 1000

    private init() {}

    // MARK: - Learned Route Cache

    /// Stores or updates a learned selector for recurring action intents.
    func recordSuccess(domain: String, intent: String, selector: String, action: String = "click") {
        lock.lock()
        defer { lock.unlock() }

        let cleanDomain = domain.lowercased()
        let cleanIntent = intent.lowercased()

        if let idx = routes.firstIndex(where: { $0.domain == cleanDomain && $0.intent == cleanIntent && $0.selector == selector }) {
            routes[idx].successCount += 1
            routes[idx].lastUsed = Date()
        } else {
            let route = CachedRoute(domain: cleanDomain, intent: cleanIntent, selector: selector, action: action)
            routes.append(route)
        }
    }

    /// Queries learned routes matching an intent on a specific domain.
    func lookup(domain: String, intent: String? = nil) -> [CachedRoute] {
        lock.lock()
        defer { lock.unlock() }

        let cleanDomain = domain.lowercased()
        return routes.filter { r in
            guard r.domain == cleanDomain || cleanDomain.hasSuffix("." + r.domain) else { return false }
            if let targetIntent = intent?.lowercased(), !targetIntent.isEmpty {
                return r.intent == targetIntent
            }
            return true
        }.sorted(by: { $0.successCount > $1.successCount })
    }

    /// Returns all cached routes.
    func allRoutes() -> [CachedRoute] {
        lock.lock()
        defer { lock.unlock() }
        return routes
    }

    /// Clears cached routes.
    func clearRoutes() {
        lock.lock()
        defer { lock.unlock() }
        routes.removeAll()
    }

    // MARK: - Trajectory Recording

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

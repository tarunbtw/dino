//
//  SessionManager.swift
//  dino
//
//  Created by tarun on 10/12/26.
//

import Foundation

extension FileManager {
    /// Guaranteed ~/Library/Application Support/dino directory URL.
    static var dinoApplicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dinoDir = base.appendingPathComponent("dino", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dinoDir.path) {
            try? FileManager.default.createDirectory(at: dinoDir, withIntermediateDirectories: true)
        }
        return dinoDir
    }
}

/// Metadata snapshot for a single tab during session persistence.
struct StoredTabRecord: Codable {
    let url: URL
    let spaceId: UUID?
    let place: Tab.TabPlace
    let groupId: UUID?
    let homeURL: URL?
}

/// Structured session container.
struct StoredSession: Codable {
    let tabs: [StoredTabRecord]
    let groups: [TabGroup]
}

/// Coordinates persisting and restoring open tabs across app launches.
@MainActor
final class SessionManager {
    static let shared = SessionManager()

    private static var sessionFileURL: URL {
        FileManager.dinoApplicationSupportDirectory.appendingPathComponent("session.json")
    }

    private init() {}

    /// Saves the current list of open tabs and groups to disk.
    func save(tabs: [Tab], groups: [TabGroup] = [], activeTabId: UUID?) {
        let records = tabs.compactMap { tab -> StoredTabRecord? in
            guard !tab.isIncognito, let url = tab.url, url.scheme == "http" || url.scheme == "https" else { return nil }
            return StoredTabRecord(
                url: url,
                spaceId: tab.spaceId,
                place: tab.place,
                groupId: tab.groupId,
                homeURL: tab.homeURL
            )
        }

        guard !records.isEmpty else {
            try? FileManager.default.removeItem(at: SessionManager.sessionFileURL)
            return
        }

        let session = StoredSession(tabs: records, groups: groups)
        let url = SessionManager.sessionFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Loads previously open tab URLs from disk.
    func restore() -> [URL] {
        let url = SessionManager.sessionFileURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let session = try? JSONDecoder().decode(StoredSession.self, from: data) {
            return session.tabs.map(\.url)
        }
        if let urls = try? JSONDecoder().decode([URL].self, from: data) {
            return urls
        }
        if let legacy = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return legacy.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }
        }
        return []
    }

    /// Restores full session snapshot if available.
    func restoreSession() -> StoredSession? {
        let url = SessionManager.sessionFileURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }
}

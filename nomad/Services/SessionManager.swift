//
//  SessionManager.swift
//  nomad
//
//  Created by tarun on 10/12/26.
//

import Foundation

extension FileManager {
    /// Guaranteed ~/Library/Application Support/nomad directory URL.
    static var nomadApplicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let nomadDir = base.appendingPathComponent("nomad", isDirectory: true)
        if !FileManager.default.fileExists(atPath: nomadDir.path) {
            try? FileManager.default.createDirectory(at: nomadDir, withIntermediateDirectories: true)
        }
        return nomadDir
    }
}

/// Coordinates persisting and restoring open tabs across app launches.
@MainActor
final class SessionManager {
    static let shared = SessionManager()

    private static var sessionFileURL: URL {
        FileManager.nomadApplicationSupportDirectory.appendingPathComponent("session.json")
    }

    private init() {}

    /// Saves the current list of open tabs to disk.
    func save(tabs: [Tab], activeTabId: UUID?) {
        let toSave = tabs.compactMap { tab -> URL? in
            guard !tab.isIncognito, let url = tab.url, url.scheme == "http" || url.scheme == "https" else { return nil }
            return url
        }

        guard !toSave.isEmpty else {
            try? FileManager.default.removeItem(at: SessionManager.sessionFileURL)
            return
        }

        let url = SessionManager.sessionFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(toSave) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Loads previously open tab URLs from disk.
    func restore() -> [URL] {
        let url = SessionManager.sessionFileURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let urls = try? JSONDecoder().decode([URL].self, from: data) {
            return urls
        }
        // Backwards compatibility with legacy session format
        if let legacy = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return legacy.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }
        }
        return []
    }
}

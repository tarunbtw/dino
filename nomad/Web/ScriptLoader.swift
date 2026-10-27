//
//  ScriptLoader.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import Foundation

/// Fast, cached loader for external JavaScript resources bundled with Nomad.
enum ScriptLoader {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    /// Loads the specified JavaScript file by name (without .js extension).
    /// Searches Bundle.main resources, bundle subdirectories, and development fallbacks.
    static func load(named name: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[name] {
            return cached
        }

        // 1. Primary: Locate via standard Bundle.main resource search
        if let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Scripts")
            ?? Bundle.main.url(forResource: name, withExtension: "js")
            ?? Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Resources/Scripts"),
           let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
            cache[name] = content
            return content
        }

        // 2. Fallback: Locate relative to runtime binary or working directory (dev & CLI runs)
        let fileManager = FileManager.default
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Scripts/\(name).js"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).js"),
            Bundle.main.bundleURL.appendingPathComponent("Resources/Scripts/\(name).js"),
            currentDir.appendingPathComponent("nomad/Resources/Scripts/\(name).js"),
            currentDir.appendingPathComponent("Resources/Scripts/\(name).js")
        ]

        for candidate in candidates {
            if fileManager.fileExists(atPath: candidate.path),
               let content = try? String(contentsOf: candidate, encoding: .utf8), !content.isEmpty {
                cache[name] = content
                return content
            }
        }

        fatalError("ScriptLoader could not find '\(name).js'. Ensure it is bundled into Resources/Scripts/ or present in nomad/Resources/Scripts/.")
    }
}

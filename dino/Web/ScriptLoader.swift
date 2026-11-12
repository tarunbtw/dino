//
//  ScriptLoader.swift
//  dino
//
//  Created by tarun on 10/10/26.
//

import Foundation

/// Fast, cached loader for external JavaScript resources bundled with Dino.
nonisolated enum ScriptLoader {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    /// Loads the specified JavaScript file by name (without .js extension).
    /// Searches Bundle.main resources, bundle subdirectories, and development fallbacks.
    nonisolated static func load(named name: String) -> String {
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

        // 2. Locate relative to runtime binary (resolving symlinks like /opt/homebrew/bin/dino -> /Applications/Dino.app)
        let fileManager = FileManager.default
        var searchRoots: [URL] = []

        if let res = Bundle.main.resourceURL {
            searchRoots.append(res)
        }
        searchRoots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        searchRoots.append(Bundle.main.bundleURL.appendingPathComponent("Resources"))

        let execArg = CommandLine.arguments.first ?? ""
        if !execArg.isEmpty {
            let execURL = URL(fileURLWithPath: execArg).resolvingSymlinksInPath()
            // e.g. /Applications/Dino.app/Contents/MacOS/dino -> /Applications/Dino.app
            let appBundle = execURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            searchRoots.append(appBundle.appendingPathComponent("Contents/Resources"))
            searchRoots.append(appBundle.appendingPathComponent("Resources"))
            searchRoots.append(execURL.deletingLastPathComponent())
        }

        // Hardcoded standard installation paths
        searchRoots.append(URL(fileURLWithPath: "/Applications/Dino.app/Contents/Resources"))

        // Development & current working directory fallbacks
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        searchRoots.append(currentDir.appendingPathComponent("dino/Resources"))
        searchRoots.append(currentDir.appendingPathComponent("Resources"))
        searchRoots.append(currentDir)

        for root in searchRoots {
            let candidates = [
                root.appendingPathComponent("Scripts/\(name).js"),
                root.appendingPathComponent("\(name).js"),
                root.appendingPathComponent("Resources/Scripts/\(name).js"),
                root.appendingPathComponent("dino/Resources/Scripts/\(name).js")
            ]
            for candidate in candidates {
                if fileManager.fileExists(atPath: candidate.path),
                   let content = try? String(contentsOf: candidate, encoding: .utf8), !content.isEmpty {
                    cache[name] = content
                    return content
                }
            }
        }

        print("[dino] ScriptLoader: '\(name).js' not found in bundle, using empty fallback")
        return ""
    }
}

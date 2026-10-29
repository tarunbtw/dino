//
//  NomadVersion.swift
//  nomad
//
//  Single source of truth for Nomad version and build metadata across the app, daemon, and CLI.
//

import Foundation

public enum NomadVersion {
    public static let version = "0.13"
    public static let build = "1"

    /// Resolves the actual runtime version string, inspecting the enclosing bundle if running from a symlinked CLI binary.
    public static var currentVersion: String {
        if let infoVer = resolvedBundle?.infoDictionary?["CFBundleShortVersionString"] as? String, !infoVer.isEmpty, infoVer != "0.1" {
            return infoVer
        }
        return version
    }

    /// Resolves the actual runtime build integer.
    public static var currentBuild: Int {
        if let buildStr = resolvedBundle?.infoDictionary?["CFBundleVersion"] as? String, let b = Int(buildStr) {
            return b
        }
        return Int(build) ?? 1
    }

    /// Resolves the bundle even when the CLI is executed via symlink (e.g. /opt/homebrew/bin/nomad -> /Applications/Nomad.app/Contents/MacOS/nomad).
    public static var resolvedBundle: Bundle? {
        if let dict = Bundle.main.infoDictionary, dict["CFBundleShortVersionString"] != nil {
            return Bundle.main
        }
        // Try resolving real executable path and its enclosing .app bundle
        guard !CommandLine.arguments.isEmpty else { return Bundle.main }
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        // Nomad.app/Contents/MacOS/nomad -> 3 levels up is Nomad.app
        let appBundleURL = execURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: appBundleURL.appendingPathComponent("Contents/Info.plist").path) {
            return Bundle(url: appBundleURL)
        }
        return Bundle.main
    }
}

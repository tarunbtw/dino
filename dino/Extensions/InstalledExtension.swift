//
//  InstalledExtension.swift
//  dino
//
//  Created by tarun on 10/12/26.
//

import Foundation

/// Represents an installed WebExtension in Dino.
/// Stored in ~/Library/Application Support/dino/Extensions/installed.json
struct InstalledExtension: Codable, Identifiable, Equatable {
    /// 32-character Chrome extension ID (or SHA-256 derived ID for unpacked folders).
    let id: String
    /// Human-readable name from manifest.json.
    var name: String
    /// Extension version string.
    var version: String
    /// Whether the extension is currently active in WebKit.
    var enabled: Bool
    /// True if installed from the Chrome Web Store, false if unpacked local folder.
    var fromStore: Bool
    /// True if pinned to Dino's top toolbar next to navigation controls.
    var pinned: Bool
    /// Declared manifest permissions (e.g. storage, alarms, declarativeNetRequest).
    var permissions: [String]
    /// Original file path if loaded unpacked from disk.
    var sourcePath: String?
    /// Relative path to extension action popup HTML (e.g. "popup.html") if declared.
    var popupPath: String?
    /// Relative path to options page HTML (e.g. "options.html") if declared.
    var optionsPath: String?
    /// Chromium-only APIs declared in manifest.json that WebKit does not support.
    var compatibilityWarnings: [String] = []

    init(
        id: String,
        name: String,
        version: String,
        enabled: Bool,
        fromStore: Bool,
        pinned: Bool,
        permissions: [String],
        sourcePath: String?,
        popupPath: String?,
        optionsPath: String?,
        compatibilityWarnings: [String] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.enabled = enabled
        self.fromStore = fromStore
        self.pinned = pinned
        self.permissions = permissions
        self.sourcePath = sourcePath
        self.popupPath = popupPath
        self.optionsPath = optionsPath
        self.compatibilityWarnings = compatibilityWarnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        fromStore = try c.decode(Bool.self, forKey: .fromStore)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        permissions = try c.decode([String].self, forKey: .permissions)
        sourcePath = try c.decodeIfPresent(String.self, forKey: .sourcePath)
        popupPath = try c.decodeIfPresent(String.self, forKey: .popupPath)
        optionsPath = try c.decodeIfPresent(String.self, forKey: .optionsPath)
        compatibilityWarnings = try c.decodeIfPresent([String].self, forKey: .compatibilityWarnings) ?? []
    }
}

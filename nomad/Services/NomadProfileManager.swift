//
//  NomadProfileManager.swift
//  nomad
//
//  Created by tarun on 04/11/26.
//

import Foundation
import WebKit

/// Defines the operating profile partition for browser instances and tabs.
enum NomadProfileType: String, CaseIterable, Codable, Sendable {
    case user
    case agent
    case ephemeral
}

/// Manages isolated WebKit website data stores and profile environments.
/// Prevents automated agent queries, cookies, cache, and history from polluting the user's browsing profile.
enum NomadProfileManager {
    /// Deterministic RFC 4122 v4 UUID for the persistent agent profile partition.
    static let agentProfileUUID = UUID(uuidString: "A9E77C20-562F-4C2E-8E28-861A7C20719A")!

    @MainActor
    static var defaultProfile: NomadProfileType = .user

    @MainActor
    static func websiteDataStore(for profile: NomadProfileType) -> WKWebsiteDataStore {
        switch profile {
        case .user:
            return WKWebsiteDataStore.default()
        case .ephemeral:
            return WKWebsiteDataStore.nonPersistent()
        case .agent:
            if #available(macOS 14.0, *) {
                return WKWebsiteDataStore(forIdentifier: agentProfileUUID)
            } else {
                return WKWebsiteDataStore.default()
            }
        }
    }
}


//
//  TabGroup.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//

import Foundation

/// A persistent named bundle of everyday tabs kept together in the sidebar.
/// Tabs inside a group are immune to automatic drift/archiving.
public struct TabGroup: Identifiable, Codable, Hashable, Sendable {
    public nonisolated static let defaultName = "New Group"
    public nonisolated static let nameLimit = 100

    public let id: UUID
    public let spaceId: UUID
    public var name: String
    public var isFolded: Bool

    public init(id: UUID = UUID(), spaceId: UUID, name: String = defaultName, isFolded: Bool = false) {
        self.id = id
        self.spaceId = spaceId
        self.name = Self.cleanName(name) ?? Self.defaultName
        self.isFolded = isFolded
    }

    public nonisolated static func cleanName(_ raw: String) -> String? {
        let line = raw.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(nameLimit)).trimmingCharacters(in: .whitespaces)
    }
}

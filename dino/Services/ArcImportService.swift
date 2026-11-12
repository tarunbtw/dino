//
//  ArcImportService.swift
//  dino
//
//  Created by tarun on 10/11/26.
//  Imports spaces, pinned folders (groups), Basecamp favorites, and tabs from Arc's StorableSidebar.json.
//

import Foundation

enum ArcImportError: Error, Equatable {
    case tooLarge
    case damaged
    case notRecognized
}

nonisolated struct ArcImportPlan: Sendable {
    struct Site: Hashable, Sendable {
        let url: URL
        let title: String
    }

    struct Group: Hashable, Sendable {
        let name: String
        let sites: [Site]
    }

    struct Space: Hashable, Sendable {
        let name: String
        let profile: String
        let basecamp: [Site]
        let groups: [Group]
    }

    nonisolated static let sizeLimit = 50_000_000
    nonisolated static let itemLimit = 100_000
    nonisolated static let spaceLimit = 50
    nonisolated static let addressLimit = 2048
    nonisolated static let titleLimit = 500
    nonisolated static let depthLimit = 32

    let spaces: [Space]
    let skipped: Int

    var tabCount: Int {
        spaces.reduce(0) { $0 + $1.basecamp.count + $1.groups.reduce(0) { $0 + $1.sites.count } }
    }

    nonisolated init(_ data: Data) throws {
        guard data.count <= Self.sizeLimit else { throw ArcImportError.tooLarge }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw ArcImportError.damaged }
        guard let containers = ((root as? [String: Any])?["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let main = containers.lazy.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil }),
              let spaceList = main["spaces"] as? [Any],
              let itemList = main["items"] as? [Any]
        else { throw ArcImportError.notRecognized }
        guard itemList.count <= Self.itemLimit * 2 else { throw ArcImportError.tooLarge }

        // Arc's lists alternate an ID and its dictionary record
        var items: [String: [String: Any]] = [:]
        for case let item as [String: Any] in itemList {
            if let id = item["id"] as? String, items[id] == nil {
                items[id] = item
            }
        }

        // topAppsContainerIDs alternates profile descriptor and favorites container ID
        var favoritesByProfile: [String: String] = [:]
        let topApps = main["topAppsContainerIDs"] as? [Any] ?? []
        for (profile, id) in zip(topApps, topApps.dropFirst()) {
            if let id = id as? String, !(profile is String) {
                let key = Self.profileKey(profile)
                if favoritesByProfile[key] == nil {
                    favoritesByProfile[key] = id
                }
            }
        }

        var skippedCount = 0

        func site(_ item: [String: Any]) -> Site? {
            guard let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any] else { return nil }
            guard let address = tab["savedURL"] as? String, address.utf8.count <= Self.addressLimit,
                  let url = URL(string: address), Self.isWebURL(url) else {
                skippedCount += 1
                return nil
            }
            let named = (item["title"] as? String).flatMap(Self.cleanTitle)
            let title = named ?? (tab["savedTitle"] as? String).flatMap(Self.cleanTitle) ?? ""
            return Site(url: url, title: title)
        }

        func children(of id: String) -> [[String: Any]] {
            (items[id]?["childrenIds"] as? [Any] ?? []).compactMap { ($0 as? String).flatMap { items[$0] } }
        }

        var visited = Set<String>()
        func sites(under item: [String: Any], depth: Int = 0) -> [Site] {
            guard depth <= Self.depthLimit, let id = item["id"] as? String, visited.insert(id).inserted else { return [] }
            if let one = site(item) { return [one] }
            return children(of: id).flatMap { sites(under: $0, depth: depth + 1) }
        }

        var favoritesCache: [String: [Site]] = [:]
        func favorites(of profile: String) -> [Site] {
            if let cached = favoritesCache[profile] { return cached }
            visited.removeAll()
            let found = favoritesByProfile[profile].map { id in children(of: id).flatMap { sites(under: $0) } } ?? []
            favoritesCache[profile] = found
            return found
        }

        var parsedSpaces: [Space] = []
        for case let record as [String: Any] in spaceList where parsedSpaces.count < Self.spaceLimit {
            guard record["id"] is String else { continue }
            let profile = Self.profileKey(record["profile"] ?? ["default": true])
            let favorites = favorites(of: profile)

            var groups: [Group] = []
            if favorites.count > 12 {
                groups.append(Group(name: "Favorites", sites: Array(favorites.dropFirst(12))))
            }

            let containerIDs = record["containerIDs"] as? [Any] ?? []
            let pinnedID = zip(containerIDs, containerIDs.dropFirst())
                .first { ($0.0 as? String) == "pinned" }?.1 as? String

            visited.removeAll()
            var loose: [Site] = []
            var looseAt: Int?

            if let pinnedID = pinnedID {
                for item in children(of: pinnedID) {
                    if let one = site(item) {
                        loose.append(one)
                        if looseAt == nil { looseAt = groups.count }
                    } else if (item["data"] as? [String: Any])?["list"] != nil {
                        let inner = children(of: item["id"] as? String ?? "").flatMap { sites(under: $0) }
                        if !inner.isEmpty {
                            let groupName = (item["title"] as? String).flatMap(Self.cleanTitle) ?? "Group"
                            groups.append(Group(name: groupName, sites: inner))
                        }
                    }
                }
            }

            if !loose.isEmpty {
                groups.insert(Group(name: "Pinned", sites: loose), at: looseAt ?? 0)
            }

            let spaceName = (record["title"] as? String).flatMap(Self.cleanTitle) ?? "Arc Space"
            parsedSpaces.append(Space(
                name: spaceName,
                profile: profile,
                basecamp: Array(favorites.prefix(12)),
                groups: groups
            ))
        }

        self.spaces = parsedSpaces
        self.skipped = skippedCount
    }

    private nonisolated static func profileKey(_ raw: Any) -> String {
        guard let dict = raw as? [String: Any] else { return "default" }
        if dict["default"] != nil { return "default" }
        if let custom = dict["custom"] as? [String: Any],
           let inner = custom["_0"] as? [String: Any],
           let name = inner["directoryBasename"] as? String {
            return name
        }
        return "custom"
    }

    private nonisolated static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private nonisolated static func cleanTitle(_ raw: String) -> String? {
        let line = raw.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(Self.titleLimit)).trimmingCharacters(in: .whitespaces)
    }
}

/// Service managing Arc browser data import into Dino.
@MainActor
final class ArcImportService {
    static let shared = ArcImportService()

    enum Stage: Sendable {
        case notFound
        case problem(String)
        case ready(ArcImportPlan)
        case done(spaceCount: Int, tabCount: Int)
    }

    /// Arc's default Application Support folder.
    static var arcFolder: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appending(path: "Library/Application Support/Arc", directoryHint: .isDirectory)
    }

    /// Locates and reads Arc's StorableSidebar.json if present on this Mac.
    func readArc() async -> Stage {
        guard let url = Self.arcFolder?.appending(path: "StorableSidebar.json", directoryHint: .notDirectory),
              FileManager.default.isReadableFile(atPath: url.path) else {
            return .notFound
        }
        return await read(url)
    }

    /// Reads and validates any user-provided Arc sidebar JSON file.
    func read(_ url: URL) async -> Stage {
        await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                return .problem("Dino couldn't open that file.")
            }
            do {
                return .ready(try ArcImportPlan(data))
            } catch let error as ArcImportError {
                switch error {
                case .tooLarge: return .problem("That file is too large to be an Arc sidebar.")
                case .damaged: return .problem("That file looks damaged and cannot be parsed.")
                case .notRecognized: return .problem("Dino doesn't recognize this file. Please choose StorableSidebar.json.")
                }
            } catch {
                return .problem("Dino couldn't read that file.")
            }
        }.value
    }

    /// Applies the parsed Arc import plan directly into Dino's BrowserStore.
    func apply(plan: ArcImportPlan, into store: BrowserStore) {
        var totalSpaces = 0
        var totalTabs = 0

        for (index, arcSpace) in plan.spaces.enumerated() {
            // Assign a theme color
            let colorHex = Theme.spaceColors[index % Theme.spaceColors.count].hex

            // Create new Space
            let spaceId = UUID()
            let newSpace = Space(
                id: spaceId,
                name: arcSpace.name,
                icon: "square.stack",
                colorHex: colorHex
            )
            store.spaces.append(newSpace)
            totalSpaces += 1

            // 1. Add Basecamp favorites
            for site in arcSpace.basecamp {
                let tab = Tab(initialURL: site.url)
                tab.spaceId = spaceId
                tab.title = site.title
                tab.place = .basecamp
                tab.isPinned = true
                store.tabs.append(tab)
                totalTabs += 1
            }

            // 2. Add Tab Groups and their sites
            for group in arcSpace.groups {
                let groupId = UUID()
                let tabGroup = TabGroup(
                    id: groupId,
                    spaceId: spaceId,
                    name: group.name,
                    isFolded: false
                )
                store.tabGroups.append(tabGroup)

                for site in group.sites {
                    let tab = Tab(initialURL: site.url)
                    tab.spaceId = spaceId
                    tab.title = site.title
                    tab.groupId = groupId
                    tab.place = .open
                    store.tabs.append(tab)
                    totalTabs += 1
                }
            }
        }

        store.persistSession()
    }
}

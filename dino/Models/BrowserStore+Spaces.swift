//
//  BrowserStore+Spaces.swift
//  dino
//
//  Created for Dino Browser.
//  Encapsulates contextual workspaces (Spaces) and basecamp pinned tab management.
//

import SwiftUI

extension BrowserStore {
    // MARK: - Pinned Tabs & Spaces (Contextual Workspaces)

    /// Toggles the pinned status of a tab.
    func togglePin(tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let tab = tabs[index]
        if tab.place == .basecamp || tab.isPinned {
            removeFromBasecamp(tab: tab)
        } else {
            addToBasecamp(tab: tab)
        }
    }

    /// Switches the active space, bringing its contextual tabs to view.
    func switchSpace(id: UUID) {
        guard spaces.contains(where: { $0.id == id }), activeSpaceId != id else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            activeSpaceId = id
            let spaceTabs = tabs.filter { $0.spaceId == id }
            if let first = spaceTabs.first {
                activeTabId = first.id
            } else {
                activeTabId = nil
            }
        }
    }

    /// Cycles to the next space (or loops around).
    func switchNextSpace() {
        guard spaces.count > 1, let currentIndex = spaces.firstIndex(where: { $0.id == activeSpaceId }) else { return }
        let nextIndex = (currentIndex + 1) % spaces.count
        switchSpace(id: spaces[nextIndex].id)
    }

    /// Switches to the space at the given 0-based index.
    func switchSpace(at index: Int) {
        guard index >= 0 && index < spaces.count else { return }
        switchSpace(id: spaces[index].id)
    }

    /// Creates a new workspace with name, icon, and color.
    func createSpace(name: String, icon: String = "folder.fill", colorHex: String = "#8AB4F8", sharesWithId: UUID? = nil) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? "New Space" : cleanName
        let newSpace = Space(id: UUID(), name: finalName, icon: icon, colorHex: colorHex, sharesWithId: sharesWithId)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            spaces.append(newSpace)
            switchSpace(id: newSpace.id)
        }
    }

    /// Removes a workspace and reparents its tabs to the first space.
    func deleteSpace(id: UUID) {
        guard spaces.count > 1, let idx = spaces.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            spaces.remove(at: idx)
            let fallbackId = spaces[0].id
            for tab in tabs where tab.spaceId == id {
                tab.spaceId = fallbackId
            }
            if activeSpaceId == id {
                switchSpace(id: fallbackId)
            }
        }
    }
}

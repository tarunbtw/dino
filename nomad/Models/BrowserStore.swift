//
//  BrowserStore.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI
import Combine
import WebKit

/// Pair of tabs displayed side-by-side in Split View.
struct SplitPair: Identifiable, Codable, Equatable {
    let id: UUID
    var leftTabId: UUID
    var rightTabId: UUID
    var ratio: Double // 0.2 ... 0.8, default 0.5

    init(id: UUID = UUID(), leftTabId: UUID, rightTabId: UUID, ratio: Double = 0.5) {
        self.id = id
        self.leftTabId = leftTabId
        self.rightTabId = rightTabId
        self.ratio = min(0.8, max(0.2, ratio.isFinite ? ratio : 0.5))
    }

    func contains(_ tabId: UUID) -> Bool {
        leftTabId == tabId || rightTabId == tabId
    }

    func partner(of tabId: UUID) -> UUID? {
        if leftTabId == tabId { return rightTabId }
        if rightTabId == tabId { return leftTabId }
        return nil
    }

    mutating func swap() {
        let temp = leftTabId
        leftTabId = rightTabId
        rightTabId = temp
    }
}

/// Named contextual workspace grouping tabs with an icon and accent color.
struct Space: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var icon: String // SF Symbol: e.g. "person.fill", "briefcase.fill", "sparkles", "globe"
    var colorHex: String

    static let defaultFirstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    static let defaultSecondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()

    static let defaultSpaces: [Space] = [
        Space(id: defaultFirstID, name: "Personal", icon: "person.fill", colorHex: "#3B82F6"),
        Space(id: defaultSecondID, name: "Work", icon: "briefcase.fill", colorHex: "#10B981")
    ]
}

/// Root state container for Nomad browser window.
/// Manages open tabs, the currently focused tab, and browser actions.
@MainActor
final class BrowserStore: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTabId: UUID?
    @Published var isAddressBarFocused: Bool = false
    @Published var isOmniboxEditing: Bool = false
    @Published var omniboxText: String = ""
    @Published var splitPairs: [SplitPair] = []
    @Published var spaces: [Space] = Space.defaultSpaces
    @Published var activeSpaceId: UUID = Space.defaultFirstID
    @Published var peekTab: Tab? = nil
    @Published var peekFromTabId: UUID? = nil

    struct ClosedTabSnapshot {
        let url: URL?
        let title: String
        let isIncognito: Bool
    }

    @Published var recentlyClosedTabs: [ClosedTabSnapshot] = []

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabId }
    }

    var activeSplitPair: SplitPair? {
        guard let currentId = activeTabId else { return nil }
        return splitPairs.first { $0.contains(currentId) }
    }

    var activeSpace: Space {
        spaces.first { $0.id == activeSpaceId } ?? spaces[0]
    }

    /// Tabs visible in the current view context: all pinned tabs + unpinned tabs belonging to the active space (excluding background ghost tabs).
    var visibleTabs: [Tab] {
        tabs.filter { tab in
            !tab.isGhost && (tab.isPinned || tab.spaceId == activeSpaceId || tab.spaceId == nil)
        }
    }

    var pinnedTabs: [Tab] {
        tabs.filter { $0.isPinned && !$0.isGhost }
    }

    var unpinnedTabsForActiveSpace: [Tab] {
        tabs.filter { !$0.isPinned && !$0.isGhost && ($0.spaceId == activeSpaceId || $0.spaceId == nil) }
    }

    var ghostTabs: [Tab] {
        tabs.filter { $0.isGhost }
    }

    init() {
        let restoredURLs = NomadHeadlessManager.isHeadless ? [] : SessionManager.shared.restore()
        if !restoredURLs.isEmpty {
            for (idx, url) in restoredURLs.enumerated() {
                _ = newTab(url: url, select: idx == 0, lazy: idx != 0)
            }
        } else {
            // Start with an initial clean blank tab
            _ = newTab(url: nil, select: true, lazy: false)
        }
        ExtensionManager.shared.start(with: self)
        NomadAgentServer.shared.start(store: self)

        NotificationCenter.default.addObserver(
            forName: .nomadThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            MainActor.assumeIsolated {
                let appearance = notif.object as? NSAppearance
                self?.tabs.forEach { $0.webView.appearance = appearance }
            }
        }
    }

    /// Persists open session tabs to disk (excluding background ghost tabs and incognito tabs).
    private func persistSession() {
        let persistentTabs = tabs.filter { !$0.isGhost && !$0.isIncognito }
        SessionManager.shared.save(tabs: persistentTabs, activeTabId: activeTabId)
    }

    /// Creates and appends a new tab.
    @discardableResult
    func newTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil, isIncognito: Bool = false, isGhost: Bool = false, select: Bool = true, lazy: Bool = false) -> Tab {
        // Prevent opening duplicate empty blank tabs (non-ghost only):
        // If requesting a blank new tab (url == nil) and a blank tab already exists, select it instead of duplicating.
        if url == nil && configuration == nil && !isGhost {
            if let active = activeTab, active.isBlank && active.isIncognito == isIncognito && !active.isGhost {
                return active
            } else if let existingBlank = tabs.first(where: { $0.isBlank && $0.isIncognito == isIncognito && !$0.isGhost }) {
                if select {
                    selectTab(id: existingBlank.id)
                }
                return existingBlank
            }
        }

        // Prevent opening duplicate settings tabs: switch to existing settings tab if present
        if let targetURL = url, targetURL.scheme == "nomad", targetURL.host == "settings", !isGhost {
            if let existingSettings = tabs.first(where: { $0.isInternalPage && !$0.isGhost }) {
                if select {
                    selectTab(id: existingSettings.id)
                }
                return existingSettings
            }
        }

        let tab = Tab(initialURL: url, configuration: configuration, isIncognito: isIncognito, isGhost: isGhost, lazy: lazy)
        tab.spaceId = activeSpaceId
        
        tab.onOpenURLInNewTab = { [weak self, weak tab] targetURL in
            guard let self else { return }
            let isIncog = (tab?.wantsNextNewTabIncognito == true) || (tab?.isIncognito ?? false)
            tab?.wantsNextNewTabIncognito = false
            if tab?.wantsNextNewTabInSplit == true {
                tab?.wantsNextNewTabInSplit = false
                let newCreated = self.newTab(url: targetURL, isIncognito: isIncog, select: true)
                if let tab = tab {
                    self.splitTab(primaryId: tab.id, secondaryId: newCreated.id)
                }
            } else {
                self.newTab(url: targetURL, isIncognito: isIncog, select: true)
            }
        }

        tab.onOpenTabWithWebView = { [weak self, weak tab] config, action in
            guard let self else { return nil }
            let targetURL = action.request.url
            let isIncog = (tab?.wantsNextNewTabIncognito == true) || (tab?.isIncognito ?? false)
            tab?.wantsNextNewTabIncognito = false
            let newCreated = self.newTab(url: targetURL, configuration: config, isIncognito: isIncog, select: true)
            if tab?.wantsNextNewTabInSplit == true {
                tab?.wantsNextNewTabInSplit = false
                if let tab = tab {
                    self.splitTab(primaryId: tab.id, secondaryId: newCreated.id)
                }
            }
            return newCreated.webView
        }

        tab.onRequestCloseTab = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.closeTab(id: tab.id)
        }

        tab.onRequestNewTab = { [weak self] url in
            self?.newTab(url: url, select: true)
        }

        tab.onRequestPeek = { [weak self, weak tab] targetURL in
            guard let self = self, let tab = tab else { return }
            self.peek(targetURL, from: tab)
        }

        tab.onRequestDuplicateTab = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.newTab(url: tab.url, isIncognito: tab.isIncognito, select: true)
        }

        tab.onDidFocus = { [weak self, weak tab] in
            guard let self, let id = tab?.id else { return }
            if self.activeTabId != id && !(tab?.isGhost ?? false) {
                self.activeTabId = id
            }
        }
        
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            tabs.append(tab)
            if select && !isGhost {
                activeTabId = tab.id
            }
        }
        
        ExtensionManager.shared.didOpenTab(tab)
        if select {
            ExtensionManager.shared.didActivateTab(tab)
        }
        enforceMemoryGovernor()
        persistSession()
        
        return tab
    }

    // MARK: - Memory Governor (Tiered Tab Virtualization)
    static let maxActiveWarmTabs = 8

    /// Enforces the concurrency memory governor: preserves active and recent tabs in Hot/Warm tiers
    /// while virtualizing oldest idle background tabs to Cold tier to cap RAM usage.
    func enforceMemoryGovernor() {
        guard tabs.count > Self.maxActiveWarmTabs else { return }
        let inactiveTabs = tabs.filter { $0.id != activeTabId && !$0.isBlank && !$0.isInternalPage }
            .sorted(by: { $0.lastActiveTime > $1.lastActiveTime })
        let demoteCandidates = inactiveTabs.dropFirst(Self.maxActiveWarmTabs - 1)
        for tab in demoteCandidates {
            tab.dehydrateToCold()
        }
    }

    /// Creates and opens a new private / incognito tab with isolated ephemeral storage.
    @discardableResult
    func newIncognitoTab(url: URL? = nil) -> Tab {
        newTab(url: url, isIncognito: true, select: true, lazy: false)
    }

    /// Closes the specified tab with smooth spring removal.
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        
        let isClosingActive = (activeTabId == id)
        let tab = tabs[index]
        AgentPiPManager.shared.landIfTab(id: id)
        if !tab.isGhost && !tab.isIncognito && !tab.isBlank {
            recentlyClosedTabs.insert(ClosedTabSnapshot(url: tab.url, title: tab.title, isIncognito: tab.isIncognito), at: 0)
            if recentlyClosedTabs.count > 25 {
                recentlyClosedTabs.removeLast()
            }
        }
        tab.cleanup()
        ExtensionManager.shared.didCloseTab(id: id)

        // Dissolve any split pair containing this tab and record partner
        var nextActiveFromSplit: UUID? = nil
        if let pairIndex = splitPairs.firstIndex(where: { $0.contains(id) }) {
            let pair = splitPairs.remove(at: pairIndex)
            nextActiveFromSplit = pair.partner(of: id)
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            tabs.remove(at: index)
            
            // If the closed tab was active, choose split partner first, else adjacent tab
            if isClosingActive {
                if let partnerId = nextActiveFromSplit, tabs.contains(where: { $0.id == partnerId }) {
                    activeTabId = partnerId
                } else {
                    let visible = visibleTabs
                    if visible.isEmpty {
                        // Keep at least one visible tab open
                        newTab(url: nil, select: true)
                    } else {
                        let nextIndex = min(index, visible.count - 1)
                        activeTabId = visible[nextIndex].id
                    }
                }
            }
        }
        persistSession()
    }

    /// Reopens the most recently closed tab (⇧⌘T).
    @discardableResult
    func reopenLastClosedTab() -> Tab? {
        guard !recentlyClosedTabs.isEmpty else { return nil }
        let snapshot = recentlyClosedTabs.removeFirst()
        return newTab(url: snapshot.url, isIncognito: snapshot.isIncognito, select: true)
    }

    /// Selects a tab by ID with smooth content transition.
    func selectTab(id: UUID) {
        if tabs.contains(where: { $0.id == id }), activeTabId != id {
            withAnimation(.easeInOut(duration: 0.18)) {
                activeTabId = id
            }
            if let tab = tabs.first(where: { $0.id == id }) {
                tab.ensureLoaded()
                tab.hydrateToHot()
                ExtensionManager.shared.didActivateTab(tab)
            }
            enforceMemoryGovernor()
            persistSession()
        }
    }

    /// Opens a link in an Arc-style floating peek preview over the current tab.
    func peek(_ url: URL, from sourceTab: Tab) {
        let page = Tab(initialURL: url, isIncognito: sourceTab.isIncognito)
        page.onRequestPeek = { [weak self, weak page] u in
            guard let self = self, let p = page else { return }
            self.peek(u, from: p)
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            self.peekTab = page
            self.peekFromTabId = sourceTab.id
        }
    }

    /// Dismisses the floating peek preview.
    func closePeek() {
        withAnimation(.easeInOut(duration: 0.16)) {
            self.peekTab = nil
            self.peekFromTabId = nil
        }
    }

    /// Promotes the peek preview to a full tab or split view pane.
    func keepPeek(beside: Bool = false) {
        guard let page = peekTab else { return }
        let fromId = peekFromTabId
        closePeek()
        tabs.append(page)
        if beside, let fromId = fromId, let fromTab = tabs.first(where: { $0.id == fromId }) {
            splitTab(primaryId: fromTab.id, secondaryId: page.id)
        } else {
            selectTab(id: page.id)
        }
    }

    /// Reorders a tab from one index to another with animated sliding.
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tabs.indices.contains(sourceIndex),
              tabs.indices.contains(destinationIndex) else { return }
        
        var updated = tabs
        let tab = updated.remove(at: sourceIndex)
        updated.insert(tab, at: destinationIndex)
        tabs = updated
    }

    /// Selects the previous tab (⌘{ or Ctrl+Shift+Tab)
    func selectPreviousTab() {
        guard let currentId = activeTabId, let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let prevIndex = (currentIndex - 1 + tabs.count) % tabs.count
        withAnimation(.easeInOut(duration: 0.18)) {
            activeTabId = tabs[prevIndex].id
        }
    }

    /// Selects the next tab (⌘} or Ctrl+Tab)
    func selectNextTab() {
        guard let currentId = activeTabId, let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        withAnimation(.easeInOut(duration: 0.18)) {
            activeTabId = tabs[nextIndex].id
        }
    }

    // MARK: - Navigation convenience forwards
    func goBack() {
        activeTab?.goBack()
    }

    func goForward() {
        activeTab?.goForward()
    }

    func reload() {
        activeTab?.reload()
    }

    /// Opens or switches to the settings internal page (nomad://settings).
    func openSettings(section: String? = nil) {
        if let section = section {
            SettingsStore.shared.activeSection = section
        }
        let settingsURL = URL(string: "nomad://settings")!
        if let existing = tabs.first(where: { $0.isInternalPage }) {
            selectTab(id: existing.id)
        } else if let current = activeTab, current.isBlank {
            current.load(url: settingsURL)
        } else {
            newTab(url: settingsURL, select: true)
        }
    }

    /// Toggles bookmark state for the specified tab (defaults to active tab).
    func toggleBookmark(for targetTab: Tab? = nil) {
        guard let tab = targetTab ?? activeTab,
              let urlString = tab.url?.absoluteString,
              !tab.isBlank, !tab.isInternalPage, !urlString.isEmpty, urlString != "about:blank" else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            if SettingsStore.shared.isBookmarked(urlString) {
                SettingsStore.shared.removeBookmark(url: urlString)
            } else {
                let title = tab.title.isEmpty ? (tab.url?.host ?? urlString) : tab.title
                SettingsStore.shared.addBookmark(title: title, url: urlString)
            }
        }
    }

    /// Opens a bookmark in the current or new tab.
    func openBookmark(_ bookmark: Bookmark) {
        if let destination = URL(string: bookmark.url) {
            if destination.scheme == "nomad" && destination.host == "settings" {
                openSettings()
            } else if let current = activeTab, current.isBlank {
                current.load(url: destination)
            } else {
                newTab(url: destination, select: true)
            }
        }
    }

    // MARK: - Split View (Side-by-Side Dual Browsing)

    /// Pairs two tabs side-by-side in Split View.
    func splitTab(primaryId: UUID, secondaryId: UUID, ratio: Double = 0.5) {
        guard primaryId != secondaryId,
              tabs.contains(where: { $0.id == primaryId }),
              tabs.contains(where: { $0.id == secondaryId }) else { return }

        // Dissolve any previous split pairs containing either tab
        splitPairs.removeAll { $0.contains(primaryId) || $0.contains(secondaryId) }

        // Reposition secondary tab immediately adjacent to primary tab in tab list
        if let primIdx = tabs.firstIndex(where: { $0.id == primaryId }),
           let secIdx = tabs.firstIndex(where: { $0.id == secondaryId }) {
            if secIdx != primIdx + 1 {
                let secTab = tabs.remove(at: secIdx)
                let newPrimIdx = tabs.firstIndex(where: { $0.id == primaryId }) ?? primIdx
                tabs.insert(secTab, at: min(tabs.count, newPrimIdx + 1))
            }
        }

        let pair = SplitPair(leftTabId: primaryId, rightTabId: secondaryId, ratio: ratio)
        withAnimation(.easeInOut(duration: 0.22)) {
            splitPairs.append(pair)
            activeTabId = secondaryId
        }
        persistSession()
    }

    /// Toggles split view for current active tab (splits if single, ungroups if already split).
    func toggleSplitCurrentTab() {
        guard let activeId = activeTabId else { return }
        if activeSplitPair != nil {
            closeSplit(for: activeId)
        } else {
            // If there is another open unpinned tab in this space (e.g. GitHub + Settings), pair with it directly
            let otherUnpinned = unpinnedTabsForActiveSpace.filter { $0.id != activeId }
            if otherUnpinned.count == 1, let partner = otherUnpinned.first {
                splitTab(primaryId: activeId, secondaryId: partner.id)
            } else {
                splitCurrentTab()
            }
        }
    }

    /// Creates a new tab and splits it with the current active tab.
    @discardableResult
    func splitCurrentTab(with url: URL? = nil) -> Tab? {
        guard let currentTab = activeTab else { return nil }
        let newT = newTab(url: url, isIncognito: currentTab.isIncognito, select: false)
        splitTab(primaryId: currentTab.id, secondaryId: newT.id)
        selectTab(id: newT.id)
        return newT
    }

    /// Pairs an agent ghost tab side-by-side with the current active tab for live co-browsing.
    func splitGhostTab(id: UUID, ratio: Double = 0.5) {
        guard let currentTab = activeTab, currentTab.id != id,
              tabs.contains(where: { $0.id == id }) else { return }
        splitTab(primaryId: currentTab.id, secondaryId: id, ratio: ratio)
    }

    /// Promotes an agent background ghost tab to a full visible tab in the human workspace.
    func promoteGhostTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isGhost = false
        selectTab(id: tab.id)
        persistSession()
    }

    /// Ungroups the split pair for the given tab, returning both tabs to standalone status (never closes tabs).
    func closeSplit(for tabId: UUID) {
        withAnimation(.easeInOut(duration: 0.22)) {
            splitPairs.removeAll { $0.contains(tabId) }
        }
        activeTabId = tabId
        persistSession()
    }

    /// Swaps the left and right positions in the active split pair.
    func swapSplit(splitPairId: UUID? = nil) {
        let targetId = splitPairId ?? activeSplitPair?.id
        guard let targetId = targetId,
              let idx = splitPairs.firstIndex(where: { $0.id == targetId }) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            splitPairs[idx].swap()
        }
        persistSession()
    }

    /// Updates the split ratio (clamped between 0.2 and 0.8).
    func setSplitRatio(splitPairId: UUID? = nil, ratio: Double) {
        let targetId = splitPairId ?? activeSplitPair?.id
        guard let targetId = targetId,
              let idx = splitPairs.firstIndex(where: { $0.id == targetId }) else { return }
        splitPairs[idx].ratio = min(0.8, max(0.2, ratio.isFinite ? ratio : 0.5))
    }

    // MARK: - Pinned Tabs & Spaces (Contextual Workspaces)

    /// Toggles the pinned status of a tab.
    func togglePin(tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            let tab = tabs[index]
            tab.isPinned.toggle()
            if tab.isPinned {
                let t = tabs.remove(at: index)
                let pinnedCount = tabs.filter { $0.isPinned }.count
                tabs.insert(t, at: max(0, pinnedCount - 1))
            }
        }
        persistSession()
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
                let newT = newTab(url: nil, select: true)
                newT.spaceId = id
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
    func createSpace(name: String, icon: String = "folder.fill", colorHex: String = "#8B5CF6") {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? "Space \(spaces.count + 1)" : cleanName
        let newSpace = Space(id: UUID(), name: finalName, icon: icon, colorHex: colorHex)
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

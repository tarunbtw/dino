//
//  BrowserStore+SplitView.swift
//  dino
//
//  Created for Dino Browser.
//  Encapsulates Split View pairing, side-by-side layout, and visual split picker logic.
//

import SwiftUI

extension BrowserStore {
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
            let otherUnpinned = openTabs.filter { $0.id != activeId }
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

    /// Returns the split pair containing this tab, if any.
    func split(of tab: Tab) -> SplitPair? {
        splitPairs.first { $0.contains(tab.id) }
    }

    // MARK: - Visual Split Picker

    /// Initiates picking a split beside `tab`. The active tab glides to half width
    /// and the command bar / omnibox opens over the empty half to pick what goes there.
    func pickSplit(beside tab: Tab, on side: SplitSide = .left) {
        selectTab(id: tab.id)
        withAnimation(Theme.glide) {
            splitPickAnchor = tab
            splitPickSide = side
            isAddressBarFocused = true
        }
    }

    /// Cancels split picking and glides the anchor tab back to full width.
    func cancelSplitPick() {
        withAnimation(Theme.glide) {
            splitPickAnchor = nil
            isAddressBarFocused = false
        }
    }

    /// Opens `incoming` beside `anchor` on `side`.
    func openSplit(_ incoming: Tab, beside anchor: Tab, on side: SplitSide = .right) {
        let left = side == .left ? incoming : anchor
        let right = side == .left ? anchor : incoming
        splitTab(primaryId: left.id, secondaryId: right.id)
        withAnimation(Theme.glide) {
            splitPickAnchor = nil
            isAddressBarFocused = false
        }
    }

    /// Commits the active split pick by creating a new blank tab and pairing it in a persistent SplitPair.
    @discardableResult
    func commitSplitPickWithNewTab(selectAnchor: Bool = false) -> Tab? {
        guard let anchor = splitPickAnchor else { return nil }
        let newT = Tab(initialURL: nil, isIncognito: anchor.isIncognito)
        newT.spaceId = activeSpaceId
        wireTabCallbacks(newT)
        tabs.append(newT)
        openSplit(newT, beside: anchor, on: splitPickSide.other)
        if selectAnchor {
            selectTab(id: anchor.id)
        } else {
            selectTab(id: newT.id)
        }
        persistSession()
        return newT
    }
}

//
//  BrowserWebView.swift
//  dino
//
//  Created by tarun on 10/10/26.
//

import AppKit
import WebKit
import SwiftUI

/// Custom subclass of WKWebView that integrates mouse tracking and two-finger fluid swipe gestures.
@MainActor
final class BrowserWebView: WKWebView {
    weak var tab: Tab?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        appearance = SettingsStore.shared.currentAppearance
    }

    override func mouseMoved(with event: NSEvent) {
        let sel = NSSelectorFromString("_simulateMouseMove:")
        if responds(to: sel) {
            perform(sel, with: event)
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        tab?.onDidFocus?()
        super.mouseDown(with: event)
    }

    private var swipeAccumulatedX: CGFloat = 0
    private var isTrackingSwipe = false
    private var swipeDirection: Tab.SwipeDirection? = nil
    private let triggerThreshold: CGFloat = 65.0

    @discardableResult
    private func tryBeginSwipe(dx: CGFloat, dy: CGFloat, ratio: CGFloat, minDx: CGFloat, updateUI: Bool = false) -> Bool {
        guard abs(dx) > abs(dy) * ratio && abs(dx) > minDx, let tab = tab else { return false }
        if dx > 0 && tab.webView.canGoBack {
            swipeDirection = .back
        } else if dx < 0 && tab.webView.canGoForward {
            swipeDirection = .forward
        } else {
            return false
        }
        isTrackingSwipe = true
        swipeAccumulatedX = dx
        if updateUI {
            let distance = abs(swipeAccumulatedX)
            tab.updateSwipeGesture(
                direction: swipeDirection!,
                progress: min(distance / triggerThreshold, 1.0),
                distance: distance,
                isTriggered: distance >= triggerThreshold
            )
        }
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        guard let tab = tab, event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        let phase = event.phase
        let momentumPhase = event.momentumPhase

        // Ignore momentum scrolling for gesture triggers
        if momentumPhase != [] {
            if isTrackingSwipe {
                tab.cancelSwipeGesture()
                isTrackingSwipe = false
                swipeDirection = nil
                swipeAccumulatedX = 0
            }
            super.scrollWheel(with: event)
            return
        }

        if phase == .began {
            swipeAccumulatedX = 0
            isTrackingSwipe = false
            swipeDirection = nil

            tryBeginSwipe(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, ratio: 1.5, minDx: 2.0)
        } else if phase == .changed {
            if isTrackingSwipe, let dir = swipeDirection {
                swipeAccumulatedX += event.scrollingDeltaX

                // Reverse movement aborts the gesture
                if (dir == .back && swipeAccumulatedX < -10) || (dir == .forward && swipeAccumulatedX > 10) {
                    tab.cancelSwipeGesture()
                    isTrackingSwipe = false
                    swipeDirection = nil
                    swipeAccumulatedX = 0
                    super.scrollWheel(with: event)
                    return
                }

                let distance = abs(swipeAccumulatedX)
                let progress = min(distance / triggerThreshold, 1.0)
                let isTriggered = distance >= triggerThreshold

                tab.updateSwipeGesture(
                    direction: dir,
                    progress: progress,
                    distance: distance,
                    isTriggered: isTriggered
                )
                return
            } else if !isTrackingSwipe && swipeAccumulatedX == 0 {
                // If gesture started with subtle initial delta but is clearly a horizontal swipe
                if tryBeginSwipe(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, ratio: 2.0, minDx: 5.0, updateUI: true) {
                    return
                }
            }
        } else if phase == .ended {
            if isTrackingSwipe, let dir = swipeDirection {
                let distance = abs(swipeAccumulatedX)
                let commit = distance >= triggerThreshold
                tab.finishSwipeGesture(commit: commit, direction: dir)
                isTrackingSwipe = false
                swipeDirection = nil
                swipeAccumulatedX = 0
                return
            }
        } else if phase == .cancelled {
            if isTrackingSwipe {
                tab.cancelSwipeGesture()
                isTrackingSwipe = false
                swipeDirection = nil
                swipeAccumulatedX = 0
                return
            }
        }

        super.scrollWheel(with: event)
    }

    // MARK: - Native Context Menu Customization
    private var openLinkAction: Selector?
    private weak var openLinkTarget: AnyObject?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // 1. Link Context Menu: "Open Link in New Tab", "Open Link in Split View", "Open Link in Incognito Window"
        if let linkIndex = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" }) {
            let item = menu.items[linkIndex]
            self.openLinkAction = item.action
            self.openLinkTarget = item.target
            item.title = "Open Link in New Tab"

            if let splitItem = item.copy() as? NSMenuItem {
                splitItem.title = "Open Link in Split View"
                splitItem.identifier = NSUserInterfaceItemIdentifier("DinoOpenLinkInSplitView")
                splitItem.target = self
                splitItem.action = #selector(openLinkInSplitViewAction(_:))
                menu.insertItem(splitItem, at: linkIndex + 1)
            }

            if let incogItem = item.copy() as? NSMenuItem {
                incogItem.title = "Open Link in Incognito Window"
                incogItem.identifier = NSUserInterfaceItemIdentifier("DinoOpenLinkInIncognito")
                incogItem.target = self
                incogItem.action = #selector(openLinkInIncognitoAction(_:))
                menu.insertItem(incogItem, at: linkIndex + 2)
            }

            if let copyIndex = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierCopyLink" }) {
                menu.items[copyIndex].title = "Copy Link Address"
            }
            return
        }

        // 2. Image Context Menu: "Open Image in New Tab", "Save Image As...", "Copy Image", "Copy Image Address"
        let isImage = menu.items.contains(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierCopyImage" || $0.identifier?.rawValue == "WKMenuItemIdentifierDownloadImage" })
        if isImage {
            if let openImageIndex = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenImageInNewWindow" }) {
                menu.items[openImageIndex].title = "Open Image in New Tab"
            }
            return
        }

        // 3. Text Selection / Editable Text: keep WebKit's native Copy/Cut/Paste, add Select All if missing
        let hasCopy = menu.items.contains(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierCopy" })
        let hasPaste = menu.items.contains(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierPaste" })
        if hasCopy || hasPaste {
            if !menu.items.contains(where: { $0.action == #selector(NSText.selectAll(_:)) }) {
                let selectAll = NSMenuItem(title: "Select All", action: #selector(menuSelectAll(_:)), keyEquivalent: "a")
                selectAll.keyEquivalentModifierMask = .command
                selectAll.target = self
                menu.addItem(.separator())
                menu.addItem(selectAll)
            }
            return
        }

        // 4. General Page Context Menu (Blank page / body / background):
        // Build the full modern browser right-click menu: Back, Forward, Reload, New Tab, Duplicate Tab, Cut, Copy, Paste, Select All, Print, Inspect.
        var insertIdx = 0

        // Navigation: Back & Forward
        let backItem = NSMenuItem(title: "Back", action: #selector(menuGoBack(_:)), keyEquivalent: "[")
        backItem.keyEquivalentModifierMask = .command
        backItem.target = self
        backItem.isEnabled = tab?.canGoBack ?? false
        menu.insertItem(backItem, at: insertIdx)
        insertIdx += 1

        let fwdItem = NSMenuItem(title: "Forward", action: #selector(menuGoForward(_:)), keyEquivalent: "]")
        fwdItem.keyEquivalentModifierMask = .command
        fwdItem.target = self
        fwdItem.isEnabled = tab?.canGoForward ?? false
        menu.insertItem(fwdItem, at: insertIdx)
        insertIdx += 1

        // Reload: position right after navigation
        if let existingReloadIdx = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierReload" }) {
            let reloadItem = menu.items.remove(at: existingReloadIdx)
            reloadItem.keyEquivalent = "r"
            reloadItem.keyEquivalentModifierMask = .command
            menu.insertItem(reloadItem, at: insertIdx)
            insertIdx += 1
        } else {
            let reloadItem = NSMenuItem(title: "Reload", action: #selector(menuReload(_:)), keyEquivalent: "r")
            reloadItem.keyEquivalentModifierMask = .command
            reloadItem.target = self
            menu.insertItem(reloadItem, at: insertIdx)
            insertIdx += 1
        }

        menu.insertItem(.separator(), at: insertIdx)
        insertIdx += 1

        // Tab Management: New Tab & Duplicate Tab
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(menuNewTab(_:)), keyEquivalent: "t")
        newTabItem.keyEquivalentModifierMask = .command
        newTabItem.target = self
        menu.insertItem(newTabItem, at: insertIdx)
        insertIdx += 1

        let dupTabItem = NSMenuItem(title: "Duplicate Tab", action: #selector(menuDuplicateTab(_:)), keyEquivalent: "")
        dupTabItem.target = self
        menu.insertItem(dupTabItem, at: insertIdx)
        insertIdx += 1

        menu.insertItem(.separator(), at: insertIdx)
        insertIdx += 1

        // Clipboard: Cut, Copy, Paste, Select All
        let cutItem = NSMenuItem(title: "Cut", action: #selector(menuCut(_:)), keyEquivalent: "x")
        cutItem.keyEquivalentModifierMask = .command
        cutItem.target = self
        menu.insertItem(cutItem, at: insertIdx)
        insertIdx += 1

        let copyItem = NSMenuItem(title: "Copy", action: #selector(menuCopy(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.target = self
        menu.insertItem(copyItem, at: insertIdx)
        insertIdx += 1

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(menuPaste(_:)), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = .command
        pasteItem.target = self
        menu.insertItem(pasteItem, at: insertIdx)
        insertIdx += 1

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(menuSelectAll(_:)), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        selectAllItem.target = self
        menu.insertItem(selectAllItem, at: insertIdx)
        insertIdx += 1

        menu.insertItem(.separator(), at: insertIdx)
        insertIdx += 1

        // Page Utilities: Print…
        let printItem = NSMenuItem(title: "Print…", action: #selector(menuPrint(_:)), keyEquivalent: "p")
        printItem.keyEquivalentModifierMask = .command
        printItem.target = self
        menu.insertItem(printItem, at: insertIdx)
        insertIdx += 1

        // Check if there is an Inspect Element item; hook up to Dino's developer tools drawer
        if let inspectIdx = menu.items.firstIndex(where: {
            $0.identifier?.rawValue == "WKMenuItemIdentifierInspectElement" ||
            $0.title.localizedCaseInsensitiveContains("inspect")
        }) {
            let inspectItem = menu.items[inspectIdx]
            inspectItem.target = self
            inspectItem.action = #selector(handleInspectAction)
            inspectItem.keyEquivalent = "i"
            inspectItem.keyEquivalentModifierMask = [.command, .option]
            if inspectIdx > 0 && !menu.items[inspectIdx - 1].isSeparatorItem {
                menu.insertItem(.separator(), at: inspectIdx)
            }
        } else {
            menu.addItem(.separator())
            let inspectItem = NSMenuItem(title: "Inspect Element", action: #selector(handleInspectAction), keyEquivalent: "i")
            inspectItem.keyEquivalentModifierMask = [.command, .option]
            inspectItem.target = self
            menu.addItem(inspectItem)
        }
    }

    @objc private func handleInspectAction(_ sender: Any?) {
        guard let tab = tab else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            tab.isDevDrawerVisible.toggle()
        }
    }

    @objc private func openLinkInSplitViewAction(_ sender: Any?) {
        guard let action = openLinkAction else { return }
        tab?.wantsNextNewTabInSplit = true
        NSApp.sendAction(action, to: openLinkTarget, from: sender)
    }

    @objc private func openLinkInIncognitoAction(_ sender: Any?) {
        guard let action = openLinkAction else { return }
        tab?.wantsNextNewTabIncognito = true
        NSApp.sendAction(action, to: openLinkTarget, from: sender)
    }

    @objc private func menuGoBack(_ sender: Any?) {
        tab?.goBack()
    }

    @objc private func menuGoForward(_ sender: Any?) {
        tab?.goForward()
    }

    @objc private func menuReload(_ sender: Any?) {
        tab?.reload()
    }

    @objc private func menuNewTab(_ sender: Any?) {
        tab?.onRequestNewTab?(nil)
    }

    @objc private func menuDuplicateTab(_ sender: Any?) {
        tab?.onRequestDuplicateTab?()
    }

    @objc private func menuCut(_ sender: Any?) {
        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: sender)
    }

    @objc private func menuCopy(_ sender: Any?) {
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: sender)
    }

    @objc private func menuPaste(_ sender: Any?) {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
    }

    @objc private func menuSelectAll(_ sender: Any?) {
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: sender)
    }

    @objc private func menuPrint(_ sender: Any?) {
        tab?.printPage()
    }
}

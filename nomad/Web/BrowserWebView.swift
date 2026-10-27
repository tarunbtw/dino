//
//  BrowserWebView.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import AppKit
import WebKit

/// Custom subclass of WKWebView that integrates mouse tracking and two-finger fluid swipe gestures.
@MainActor
final class BrowserWebView: WKWebView {
    weak var tab: Tab?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseMoved(with event: NSEvent) {
        let winPoint = event.locationInWindow
        let leaf = window?.contentView?.hitTest(winPoint)
        if let leaf = leaf, leaf !== self {
            leaf.mouseMoved(with: event)
        } else if let sub = subviews.first(where: { NSStringFromClass(type(of: $0)).contains("WKContentView") }) {
            sub.mouseMoved(with: event)
        } else {
            super.mouseMoved(with: event)
        }
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
}

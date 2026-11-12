//
//  Lights.swift
//  dino
//
//  Created by tarun on 10/10/26.
//

import AppKit
import SwiftUI

/// Window lights: macOS's close, miniaturize, and zoom buttons placed directly in the sidebar's top row.
struct WindowLights: NSViewRepresentable {
    static let origin = CGPoint(x: 11, y: 11)
    static let spacing: CGFloat = 23

    func makeNSView(context: Context) -> LightsView { LightsView() }
    func updateNSView(_ view: LightsView, context: Context) {}

    final class LightsView: NSView {
        private var buttons: [NSButton] = []
        private var observers: [NSObjectProtocol] = []
        private var pointerInside = false

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let hit = super.hitTest(point)
            return hit === self ? nil : hit
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            buttons.forEach { $0.removeFromSuperview() }
            buttons = []
            guard let window else { return }
            let kinds: [(NSWindow.ButtonType, Selector)] = [
                (.closeButton, #selector(NSWindow.performClose(_:))),
                (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:))),
                (.zoomButton, #selector(NSWindow.toggleFullScreen(_:))),
            ]
            for (index, (type, action)) in kinds.enumerated() {
                guard let button = NSWindow.standardWindowButton(type, for: window.styleMask) else { continue }
                button.target = window
                button.action = action
                button.setFrameOrigin(NSPoint(x: WindowLights.origin.x + CGFloat(index) * WindowLights.spacing, y: WindowLights.origin.y))
                addSubview(button)
                buttons.append(button)
            }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.redrawButtons() }
                })
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { pointerMoved(event) }
        override func mouseMoved(with event: NSEvent) { pointerMoved(event) }
        override func mouseExited(with event: NSEvent) { setPointerInside(false) }

        private func pointerMoved(_ event: NSEvent) {
            guard let first = buttons.first, let last = buttons.last else { return }
            setPointerInside(first.frame.union(last.frame).contains(convert(event.locationInWindow, from: nil)))
        }

        private func setPointerInside(_ inside: Bool) {
            guard inside != pointerInside else { return }
            pointerInside = inside
            redrawButtons()
        }

        private func redrawButtons() {
            for button in buttons {
                if let cell = button.cell { button.updateCell(cell) }
                button.needsDisplay = true
            }
        }

        @objc func _mouseInGroup(_ button: NSButton) -> Bool { pointerInside }

        deinit {
            MainActor.assumeIsolated { observers.forEach(NotificationCenter.default.removeObserver) }
        }
    }
}

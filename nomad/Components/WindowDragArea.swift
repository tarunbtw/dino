//
//  WindowDragArea.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI
import AppKit

/// An AppKit view that supports native window dragging and double-click to zoom.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView {
        DragNSView()
    }

    func updateNSView(_ nsView: DragNSView, context: Context) {}
}

final class DragNSView: NSView {
    private static var didApplyInitialSize = false
    private var pressedEvent: NSEvent?
    private var hasMoved = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window else { return }
        Lights.keep(window)
        
        if !Self.didApplyInitialSize {
            Self.didApplyInitialSize = true
            window.setContentSize(NSSize(width: 1180, height: 780))
            window.center()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
        pressedEvent = event
        hasMoved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window, let pressed = pressedEvent, !hasMoved else { return }
        let dx = event.locationInWindow.x - pressed.locationInWindow.x
        let dy = event.locationInWindow.y - pressed.locationInWindow.y
        if abs(dx) < 3 && abs(dy) < 3 { return }
        hasMoved = true
        window.isMovable = true
        window.performDrag(with: pressed)
        window.isMovable = false
    }

    override func mouseUp(with event: NSEvent) {
        guard let window = window, !hasMoved, event.clickCount == 2 else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.miniaturize(nil)
        case "None": break
        default: window.zoom(nil)
        }
    }
}

//
//  QuickSwitchKeyMonitor.swift
//  dino
//
//  Created by tarun on 10/11/26.
//

import SwiftUI
import AppKit

/// Transparent AppKit event monitor intercepting ⌃Tab key combinations.
struct QuickSwitchKeyMonitor: NSViewRepresentable {
    @ObservedObject var store: BrowserStore

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.store = store
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.store = store
    }

    final class KeyView: NSView {
        weak var store: BrowserStore?
        private var monitor: Any?
        private var resignObserver: (any NSObjectProtocol)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            monitor = nil
            resignObserver = nil
            guard let window else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                let caught = MainActor.assumeIsolated { self?.handleEvent(event) ?? false }
                return caught ? nil : event
            }

            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.store?.cancelTabSwitch() }
            }
        }

        private func handleEvent(_ event: NSEvent) -> Bool {
            guard let store = store, let window = self.window, event.window === window else { return false }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let switching = store.isQuickSwitcherVisible

            if event.type == .flagsChanged {
                if switching && !flags.contains(.control) {
                    store.finishTabSwitch()
                }
                return false
            }

            switch event.keyCode {
            case 48 where flags.contains(.control): // Tab key with Control held
                if !switching {
                    store.startTabSwitch(backward: flags.contains(.shift))
                } else {
                    store.cycleTabSwitch(forward: !flags.contains(.shift))
                }
                return true
            case 53 where switching: // Esc
                store.cancelTabSwitch()
                return true
            case 36 where switching, 76 where switching: // Return or Enter
                store.finishTabSwitch()
                return true
            case 123 where switching: // Left arrow
                store.cycleTabSwitch(forward: false)
                return true
            case 124 where switching: // Right arrow
                store.cycleTabSwitch(forward: true)
                return true
            default:
                break
            }
            return switching
        }
    }
}

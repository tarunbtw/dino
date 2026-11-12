//
//  WindowChrome.swift
//  dino
//
//  Created by tarun on 10/11/26.
//  Dynamic corner radius nesting, fullscreen menu bar glide, and quiet window chrome.
//

import AppKit
import SwiftUI
import Combine

/// Observable store holding the real window's measured corner radius.
@MainActor
final class WindowCorners: ObservableObject {
    static let shared = WindowCorners()
    @Published var radius: CGFloat? = nil
}

/// AppKit bridge configuring the window chrome:
/// - Strips standard toolbar and hides real traffic lights
/// - Measures window's actual `_cornerRadius` for concentric page nesting
/// - Hooks fullscreen transitions and menu bar slide events to glide content smoothly
struct WindowSetup: NSViewRepresentable {
    let store: BrowserStore

    init(store: BrowserStore) {
        self.store = store
    }

    func makeNSView(context: Context) -> SetupView {
        SetupView(store: store)
    }

    func updateNSView(_ nsView: SetupView, context: Context) {}

    final class SetupView: NSView {
        private let store: BrowserStore
        private var observers: [NSObjectProtocol] = []
        private var stripObserver: NSObjectProtocol?
        private var lastStripTop: CGFloat = 0
        private var menuBarHeight: CGFloat = 24

        init(store: BrowserStore) {
            self.store = store
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("not used")
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil // clicks pass through to content
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window = window else { return }

            window.toolbar = nil
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovable = true
            window.isMovableByWindowBackground = false
            window.isOpaque = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(hex: 0x3A3734)

            hideRealLights()
            readMenuBarHeight()
            readCornerRadius()

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.readCornerRadius()
                }
            }

            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] note in
                    let entered = note.name == NSWindow.didEnterFullScreenNotification
                    MainActor.assumeIsolated {
                        self?.store.setFullScreen(entered)
                    }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.hideRealLights()
                            if entered {
                                self?.quietStrip()
                            }
                        }
                    }
                })
            }

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.readMenuBarHeight()
                }
            })

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopWatchingStrip()
                    self?.store.menuBarMoved(to: 0, animated: false)
                }
            })
        }

        private func readMenuBarHeight() {
            guard let window = window, !window.styleMask.contains(.fullScreen) else { return }
            let height = NSApp.mainMenu?.menuBarHeight ?? 0
            if height > 0 {
                menuBarHeight = height
            }
        }

        private func readCornerRadius() {
            guard let window = window, !window.styleMask.contains(.fullScreen),
                  window.responds(to: NSSelectorFromString("_cornerRadius")),
                  let value = window.value(forKey: "_cornerRadius") as? NSNumber
            else { return }
            let radius = CGFloat(value.doubleValue)
            guard (8...40).contains(radius) else { return }
            if WindowCorners.shared.radius != radius {
                WindowCorners.shared.radius = radius
            }
        }

        private func hideRealLights() {
            guard let window = window else { return }
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = true
            }
        }

        /// Quiets the macOS full-screen drop strip (`NSToolbarFullScreenWindow`)
        private func quietStrip() {
            guard let strip = window?.childWindows?.first(where: {
                String(describing: type(of: $0)).contains("ToolbarFullScreen")
            }) else { return }
            strip.isOpaque = false
            strip.backgroundColor = .clear
            strip.hasShadow = false
            strip.ignoresMouseEvents = true
            strip.contentView?.isHidden = true
            watch(strip)
        }

        private func watch(_ strip: NSWindow) {
            stopWatchingStrip()
            guard let window = window else { return }
            lastStripTop = window.frame.maxY - strip.frame.maxY
            stripObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: strip, queue: .main
            ) { [weak self, weak strip] _ in
                MainActor.assumeIsolated {
                    guard let self = self, let strip = strip, let window = self.window else { return }
                    let top = window.frame.maxY - strip.frame.maxY
                    if top > self.lastStripTop {
                        self.store.menuBarMoved(to: self.menuBarHeight, animated: true)
                    } else if top < self.lastStripTop {
                        self.store.menuBarMoved(to: 0, animated: true)
                    }
                    self.lastStripTop = top
                }
            }
        }

        private func stopWatchingStrip() {
            if let stripObserver = stripObserver {
                NotificationCenter.default.removeObserver(stripObserver)
            }
            stripObserver = nil
        }

        deinit {
            MainActor.assumeIsolated {
                observers.forEach(NotificationCenter.default.removeObserver)
                stopWatchingStrip()
            }
        }
    }
}

//
//  NomadHeadlessManager.swift
//  nomad
//
//  Created by tarun on 27/10/26.
//

import AppKit
import WebKit
import Combine

/// Manages headless daemon execution for Nomad.
/// Eliminates the Dock icon and application menu (.accessory activation policy)
/// while hosting WKWebView in an off-screen buffered window so CoreAnimation,
/// WebKit GPU compositing, layout calculations, and screenshot captures remain fully operational.
@MainActor
final class NomadHeadlessManager: ObservableObject {
    static let shared = NomadHeadlessManager()

    /// Determines if Nomad was launched in headless mode via CLI argument or environment variable.
    static let isHeadless: Bool = {
        let args = CommandLine.arguments
        if args.contains("--headless") || args.contains("headless") {
            return true
        }
        if ProcessInfo.processInfo.environment["NOMAD_HEADLESS"] == "1" {
            return true
        }
        return false
    }()

    private(set) var store: BrowserStore?
    private(set) var offscreenWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    private init() {}

    /// Starts headless execution, spins up the offscreen window host, and initializes the BrowserStore.
    func start() {
        guard Self.isHeadless, !isStarted else { return }
        isStarted = true

        // Configure activation policy to accessory (runs as background daemon without Dock icon or Menu bar)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Create an off-screen borderless window with buffered backing store
        // so WebKit's full rendering pipeline and CoreAnimation compositing remain active.
        let windowRect = NSRect(x: -20000, y: -20000, width: 1280, height: 800)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.hasShadow = false
        window.title = "Nomad Headless Host"
        // Order out so it remains invisible to the user while keeping backing store alive
        window.orderOut(nil)
        self.offscreenWindow = window

        // Initialize dedicated headless BrowserStore
        let browserStore = BrowserStore()
        self.store = browserStore

        // Bind active tab's webView to the offscreen window's contentView
        if let activeTab = browserStore.activeTab {
            attachWebView(activeTab.webView)
        }

        // Listen for active tab changes to keep offscreen window contentView synchronized
        browserStore.$activeTabId
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak browserStore] _ in
                guard let self = self, let store = browserStore else { return }
                if let activeTab = store.activeTab {
                    self.attachWebView(activeTab.webView)
                }
            }
            .store(in: &cancellables)

        // Start agent server bound to headless store
        NomadAgentServer.shared.start(store: browserStore)
        print("🟢 [NomadHeadlessManager] Headless daemon initialized. Off-screen window: 1280x800.")
    }

    /// Attaches the webView to the offscreen window so layout and screenshots work identically to GUI mode.
    private func attachWebView(_ webView: BrowserWebView) {
        guard let window = offscreenWindow else { return }
        if window.contentView != webView {
            webView.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
            webView.autoresizingMask = [.width, .height]
            window.contentView = webView
        }
    }
}

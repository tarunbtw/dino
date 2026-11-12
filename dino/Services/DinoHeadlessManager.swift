//
//  DinoHeadlessManager.swift
//  dino
//
//  Created by tarun on 27/10/26.
//

import AppKit
import WebKit
import Combine

private final class HeadlessHostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// Manages headless daemon execution for Dino.
/// Eliminates the Dock icon and application menu (.accessory activation policy)
/// while hosting WKWebView in an off-screen buffered window so CoreAnimation,
/// WebKit GPU compositing, layout calculations, and screenshot captures remain fully operational.
@MainActor
final class DinoHeadlessManager: ObservableObject {
    static let shared = DinoHeadlessManager()

    /// Determines if Dino was launched in headless mode via CLI argument, executable name, or environment variable.
    static var isHeadless: Bool = {
        let args = CommandLine.arguments
        let execName = (args.first as NSString?)?.lastPathComponent.lowercased() ?? ""
        if execName == "dinod" || execName.contains("dinod") {
            return true
        }
        if args.contains("--headless") || args.contains("headless") {
            return true
        }
        if ProcessInfo.processInfo.environment["DINO_HEADLESS"] == "1" || ProcessInfo.processInfo.environment["DINO_HEADLESS"] == "1" {
            return true
        }
        return false
    }()

    private(set) var store: BrowserStore?
    private(set) var offscreenWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    var profile: DinoProfileType = .agent
    var idleTimeoutSeconds: TimeInterval = 60.0
    var autoReapEnabled: Bool = true
    var proxyURLString: String? = nil
    private(set) var lastActivityDate: Date = Date()
    private var reaperTimer: Timer?

    private init() {}

    /// Records recent automation or network activity, resetting the idle countdown.
    func recordActivity() {
        lastActivityDate = Date()
    }

    /// Evaluates worker idle duration and cleanly shuts down if idle threshold is met.
    private func checkIdleTimeout() {
        guard autoReapEnabled, idleTimeoutSeconds > 0 else { return }
        let idle = Date().timeIntervalSince(lastActivityDate)
        if idle >= idleTimeoutSeconds {
            print("[dino] Worker idle for \(Int(idle))s (threshold: \(Int(idleTimeoutSeconds))s). Auto-reaping to conserve RAM and energy.")
            DinoCLIManager.cleanupOnExit()
            exit(0)
        }
    }

    /// Parses CLI flags and environment variables for profile and auto-reaping configurations.
    private func parseCLIConfiguration() {
        let args = CommandLine.arguments

        // Profile configuration
        if let idx = args.firstIndex(of: "--profile"), idx + 1 < args.count {
            let val = args[idx + 1].lowercased()
            if let p = DinoProfileType(rawValue: val) {
                self.profile = p
            }
        } else if let envProf = ProcessInfo.processInfo.environment["DINO_PROFILE"]?.lowercased(),
                  let p = DinoProfileType(rawValue: envProf) {
            self.profile = p
        }

        // Auto-reap configuration
        if args.contains("--no-reap") || ProcessInfo.processInfo.environment["DINO_IDLE_TIMEOUT"] == "0" {
            self.autoReapEnabled = false
        } else if let idx = args.firstIndex(of: "--idle-timeout"), idx + 1 < args.count,
                  let sec = Double(args[idx + 1]) {
            if sec <= 0 {
                self.autoReapEnabled = false
            } else {
                self.idleTimeoutSeconds = sec
            }
        } else if let envSec = ProcessInfo.processInfo.environment["DINO_IDLE_TIMEOUT"],
                  let sec = Double(envSec) {
            if sec <= 0 {
                self.autoReapEnabled = false
            } else {
                self.idleTimeoutSeconds = sec
            }
        }

        // Proxy configuration
        if let idx = args.firstIndex(of: "--proxy"), idx + 1 < args.count {
            self.proxyURLString = args[idx + 1]
        } else if let envProxy = ProcessInfo.processInfo.environment["DINO_PROXY"] ?? ProcessInfo.processInfo.environment["ALL_PROXY"] ?? ProcessInfo.processInfo.environment["HTTPS_PROXY"] {
            self.proxyURLString = envProxy
        }
    }

    /// Starts headless execution, spins up the offscreen window host, and initializes the BrowserStore.
    func start() {
        guard Self.isHeadless, !isStarted else { return }
        isStarted = true

        parseCLIConfiguration()
        DinoProfileManager.defaultProfile = self.profile

        // Configure activation policy to accessory (runs as background daemon without Dock icon or Menu bar)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Create an off-screen borderless window with buffered backing store
        // so WebKit's full rendering pipeline and CoreAnimation compositing remain active.
        let windowRect = NSRect(x: -20000, y: -20000, width: 1280, height: 800)
        let window = HeadlessHostWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.hasShadow = false
        window.title = "Dino Headless Host"
        // Ensure offscreen window is strictly excluded from Mission Control, Exposé, and Spaces
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.isExcludedFromWindowsMenu = true
        window.canHide = false
        window.hidesOnDeactivate = false
        window.sharingType = .none
        window.animationBehavior = .none
        window.orderBack(nil)
        window.makeKey()
        self.offscreenWindow = window

        // Initialize dedicated headless BrowserStore
        let browserStore = BrowserStore()
        self.store = browserStore

        // Ensure headless worker boots with an initial tab ready for automation
        if browserStore.tabs.isEmpty {
            _ = browserStore.newTab(url: nil, isIncognito: false, isGhost: false, select: true)
        }

        // Bind active tab's webView to the offscreen window's contentView
        if let activeTab = browserStore.activeTab {
            attachWebView(activeTab.webView)
        }

        // Listen for active tab changes to keep offscreen window contentView synchronized
        browserStore.$activeTabId
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak browserStore] _ in
                guard let self = self, let store = browserStore else { return }
                self.recordActivity()
                if let activeTab = store.activeTab {
                    self.attachWebView(activeTab.webView)
                }
            }
            .store(in: &cancellables)

        // Start agent server bound to headless store
        DinoAgentServer.shared.start(store: browserStore)

        // Schedule auto-reaper timer if enabled
        if autoReapEnabled && idleTimeoutSeconds > 0 {
            reaperTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                MainActor.assumeIsolated {
                    DinoHeadlessManager.shared.checkIdleTimeout()
                }
            }
        }

        print("[dino] Headless runtime initialized (1280x800, Profile: \(profile.rawValue), Auto-reap: \(autoReapEnabled ? "\(Int(idleTimeoutSeconds))s" : "disabled"))")
    }

    /// Attaches any tab's webView to the offscreen host window so windowNumber and WebKit rendering are active.
    func attachTabWebView(_ webView: BrowserWebView) {
        guard let window = offscreenWindow else { return }
        if webView.window != window {
            webView.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
            webView.autoresizingMask = [.width, .height]
            if window.contentView == nil {
                window.contentView = webView
            } else {
                window.contentView?.addSubview(webView)
            }
        }
    }

    /// Attaches the active webView as the primary offscreen content view.
    private func attachWebView(_ webView: BrowserWebView) {
        guard let window = offscreenWindow else { return }
        if window.contentView != webView {
            webView.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
            webView.autoresizingMask = [.width, .height]
            window.contentView = webView
        }
    }
}

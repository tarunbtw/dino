//
//  dinoApp.swift
//  dino
//
//  Created by tarun on 10/10/26.
//

import SwiftUI

@main
struct DinoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        signal(SIGPIPE, SIG_IGN)
        if DinoCLIManager.run() {
            exit(0)
        }

        if DinoHeadlessManager.isHeadless {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    var body: some Scene {
        Window("Dino", id: "main") {
            if !DinoHeadlessManager.isHeadless {
                ContentView()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Updater.shared.checkByHand()
                }
            }
            CommandGroup(replacing: .printItem) {
                // Replaces standard Print and Page Setup so ⌘P belongs directly to browser view and ⇧⌘P belongs to Picture-in-Picture
            }
            CommandGroup(after: .newItem) {
                Button("Bring Things Over...") {
                    SettingsStore.shared.promptBringThingsOver()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DinoCLIManager.recordCurrentPID()

        if DinoHeadlessManager.isHeadless {
            NSApplication.shared.setActivationPolicy(.accessory)
            DinoHeadlessManager.shared.start()
            for window in NSApplication.shared.windows where window != DinoHeadlessManager.shared.offscreenWindow {
                window.orderOut(nil)
            }
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows where window != DinoHeadlessManager.shared.offscreenWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }

        DinoAgentServer.shared.start()
        Updater.shared.checkIfDue()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if DinoHeadlessManager.isHeadless {
            // A headless background worker was running, and the human user clicked the Dock icon or launched Dino!
            // Ensure worker retains its background accessory status:
            NSApplication.shared.setActivationPolicy(.accessory)

            // If a regular GUI app is already running, activate it:
            if let guiPid = DinoCLIManager.getRunningGUIPID(),
               let guiApp = NSRunningApplication(processIdentifier: guiPid) {
                if #available(macOS 14.0, *) {
                    guiApp.activate()
                } else {
                    guiApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                }
                return true
            }

            // Spawn the visible GUI browser instance for the human user:
            let appURL = DinoCLIManager.appBundleURL
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            config.arguments = ["--gui"]
            var env = ProcessInfo.processInfo.environment
            env["DINO_HEADLESS"] = "0"
            config.environment = env
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error = error {
                    NSLog("[dino] Failed to open GUI browser: %@", error.localizedDescription)
                }
            }
            return true
        }

        if !flag {
            var restored = false
            for window in sender.windows where window != DinoHeadlessManager.shared.offscreenWindow {
                window.makeKeyAndOrderFront(self)
                restored = true
            }
            if !restored {
                let appURL = DinoCLIManager.appBundleURL
                let config = NSWorkspace.OpenConfiguration()
                config.arguments = []
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        DinoAgentServer.shared.stop()
        DinoCLIManager.cleanupOnExit()
    }
}

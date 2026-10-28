//
//  nomadApp.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI

@main
struct nomadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if NomadCLIManager.run() {
            exit(0)
        }

        if NomadHeadlessManager.isHeadless {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    var body: some Scene {
        Window("Nomad", id: "main") {
            if !NomadHeadlessManager.isHeadless {
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
        NomadCLIManager.recordCurrentPID()

        if NomadHeadlessManager.isHeadless {
            NomadHeadlessManager.shared.start()
            // Close or hide any GUI windows spawned by SwiftUI
            for window in NSApplication.shared.windows where window != NomadHeadlessManager.shared.offscreenWindow {
                window.orderOut(nil)
                window.close()
            }
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows where window != NomadHeadlessManager.shared.offscreenWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }

        NomadAgentServer.shared.start()
        Updater.shared.checkIfDue()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if NomadHeadlessManager.isHeadless {
            return false
        }
        if !flag {
            for window in sender.windows where window != NomadHeadlessManager.shared.offscreenWindow {
                window.makeKeyAndOrderFront(self)
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        FloatingVideoManager.shared.land()
        NomadAgentServer.shared.stop()
        NomadCLIManager.cleanupOnExit()
    }
}

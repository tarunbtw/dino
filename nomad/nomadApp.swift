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
        let args = CommandLine.arguments.dropFirst().map { $0.lowercased() }

        // nomad version, nomad --version, nomad -v
        if args.contains("version") || args.contains("--version") || args.contains("-v") {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            print("nomad version \(version) (build \(build))")
            exit(0)
        }

        // nomad help, nomad --help, nomad -h
        if args.contains("help") || args.contains("--help") || args.contains("-h") {
            let help = """
            Nomad - Native macOS browser engine and agent runtime

            Usage:
              nomad [command] [options]

            Commands:
              version       Print version information
              help          Show available commands and options
              headless      Run as an off-screen background browser daemon
              mcp           Run stdio Model Context Protocol (MCP) server

            Options:
              --port <port>       Set agent HTTP server port (default: 9222)
              --socket <path>     Set agent IPC Unix domain socket path
              --version, -v       Alias for 'version'
              --help, -h          Alias for 'help'
            """
            print(help)
            exit(0)
        }

        if args.contains("mcp") || args.contains("--mcp") {
            NomadMCPServer.run()
            exit(0)
        }

        if NomadHeadlessManager.isHeadless {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    var body: some Scene {
        Window("Nomad", id: "main") {
            ContentView()
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
        if NomadHeadlessManager.isHeadless {
            NomadHeadlessManager.shared.start()
            // Close or hide any GUI windows spawned by SwiftUI
            for window in NSApplication.shared.windows where window != NomadHeadlessManager.shared.offscreenWindow {
                window.orderOut(nil)
                window.close()
            }
            return
        }

        NomadAgentServer.shared.start()
        Updater.shared.checkIfDue()
    }

    func applicationWillTerminate(_ notification: Notification) {
        FloatingVideoManager.shared.land()
        NomadAgentServer.shared.stop()
    }
}

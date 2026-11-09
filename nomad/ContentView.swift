//
//  ContentView.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        if NomadHeadlessManager.isHeadless {
            Color.clear.frame(width: 0, height: 0)
        } else {
            BrowserMainView()
        }
    }
}

private struct BrowserMainView: View {
    @StateObject private var store = BrowserStore()
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        ZStack {
            BrowserView(store: store)
                .ignoresSafeArea()

            if !settings.hasCompletedOnboarding {
                OnboardingView(settings: settings)
                    .transition(.opacity.combined(with: .scale(scale: 1.01)))
                    .zIndex(500)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(WindowConfigurator())
        .preferredColorScheme(settings.colorScheme)
        .tint(settings.accentColor)
        .onAppear {
            NomadAgentServer.shared.start(store: store)
        }
    }
}

/// Permanently disables automatic window dragging so tabs can be dragged freely without moving the window,
/// and ensures window is always solid and non-translucent.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfigNSView {
        ConfigNSView()
    }

    func updateNSView(_ nsView: ConfigNSView, context: Context) {}

    final class ConfigNSView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window = window else { return }
            window.isMovable = true
            window.isMovableByWindowBackground = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.invalidateShadow()
            SettingsStore.shared.applyTheme()
        }
    }
}


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
                WelcomeView(settings: settings, store: store)
                    .transition(.opacity.combined(with: .scale(scale: 1.01)))
                    .zIndex(500)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(WindowSetup(store: store))
        .preferredColorScheme(.dark)
        .tint(settings.accentColor)
        .onAppear {
            NomadAgentServer.shared.start(store: store)
        }
    }
}



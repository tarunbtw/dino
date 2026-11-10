//
//  WebStoreInstallPill.swift
//  nomad
//
//  Created by tarun on 10/12/26.
//

import SwiftUI

/// Contextual 1-click install button that appears in the top toolbar whenever
/// the user is visiting a Chrome Web Store extension detail page.
struct WebStoreInstallPill: View {
    @ObservedObject var tab: Tab
    @ObservedObject var store: BrowserStore
    @ObservedObject private var manager = ExtensionManager.shared
    @ObservedObject private var settings = SettingsStore.shared

    @State private var isHovered: Bool = false
    @State private var localIsInstalling: Bool = false
    @State private var installError: String? = nil

    var body: some View {
        if let extensionId = tab.chromeWebStoreExtensionId {
            let isInstalled = manager.installed.contains(where: { $0.id == extensionId })
            let name = tab.chromeWebStoreExtensionName ?? "Extension"

            Button(action: {
                guard !isInstalled && !localIsInstalling else { return }
                install(id: extensionId)
            }) {
                HStack(spacing: 6) {
                    if localIsInstalling || manager.busy != nil {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Installing…")
                            .font(.system(size: 11, weight: .medium))
                    } else if isInstalled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Added to Nomad")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add to Nomad")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isInstalled
                                ? Theme.hover
                                : (isHovered ? Theme.ink.opacity(0.88) : Theme.ink)
                        )
                )
                .foregroundStyle(isInstalled ? Theme.muted : Theme.page)
                .shadow(color: isInstalled ? Color.clear : Color.black.opacity(0.18), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(isInstalled || localIsInstalling)
            .onHover { isHovered = $0 }
            .help(isInstalled ? "\(name) is already installed" : "Install \(name) directly from the Chrome Web Store")
            .alert("Installation Failed", isPresented: Binding(
                get: { installError != nil },
                set: { if !$0 { installError = nil } }
            )) {
                Button("OK") { installError = nil }
            } message: {
                Text(installError ?? "Unknown error")
            }
        }
    }

    private func install(id: String) {
        localIsInstalling = true
        installError = nil
        Task {
            do {
                try await manager.installFromWebStore(idOrURL: id)
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                }
            }
            await MainActor.run {
                localIsInstalling = false
            }
        }
    }
}

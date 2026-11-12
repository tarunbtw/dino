//
//  SettingsView+Extensions.swift
//  dino
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit

extension SettingsView {
    var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "Extensions", subtitle: "Manage your extensions and add-ons.")

            // Add from Chrome Web Store Card
            card(title: "Add from Chrome Web Store") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Chrome Web Store URL or extension ID", text: $webStoreInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit { installFromWebStore() }

                        Button(action: { installFromWebStore() }) {
                            if isInstallingExtension {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 60)
                            } else {
                                Text("Install")
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isInstallingExtension || webStoreInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Open Store") {
                            let storeURL = URL(string: "https://chromewebstore.google.com")!
                            store.newTab(url: storeURL, select: true)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let errorMessage = extensionErrorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            // Developer Mode Card
            card(title: "Developer Mode") {
                HStack(spacing: 12) {
                    Text("Load unpacked extension")
                        .font(.system(size: 13))

                    Spacer()

                    Button("Choose Folder…") {
                        loadUnpackedFolder()
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Installed Extensions List Card
            card(title: "Installed Extensions (\(extensionManager.installed.count))") {
                if extensionManager.installed.isEmpty {
                    Text("No extensions installed.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(extensionManager.installed) { ext in
                            HStack(spacing: 12) {
                                Image(systemName: "puzzlepiece.extension")
                                    .font(.system(size: 16))
                                    .foregroundStyle(ext.enabled ? Color.accentColor : Color.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(ext.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("v\(ext.version)")
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(.secondary)
                                        if !ext.fromStore {
                                            Text("Unpacked")
                                                .font(.system(size: 9, weight: .semibold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.primary.opacity(0.08), in: Capsule())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                if ext.optionsPath != nil {
                                    Button(action: {
                                        extensionManager.openOptionsPage(for: ext.id)
                                    }) {
                                        Image(systemName: "gearshape")
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Extension Options")
                                }

                                Button(action: {
                                    extensionManager.togglePinned(id: ext.id)
                                }) {
                                    Image(systemName: ext.pinned ? "pin.fill" : "pin")
                                        .font(.system(size: 12))
                                        .foregroundStyle(ext.pinned ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(ext.pinned ? "Unpin from Toolbar" : "Pin to Toolbar")

                                Toggle("", isOn: Binding(
                                    get: { ext.enabled },
                                    set: { _ in extensionManager.toggleEnabled(id: ext.id) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)

                                Button(action: {
                                    extensionManager.remove(id: ext.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .help("Remove Extension")
                            }
                            .padding(.vertical, 6)

                            if ext.id != extensionManager.installed.last?.id {
                                Divider().opacity(0.1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func installFromWebStore() {
        let input = webStoreInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isInstallingExtension = true
        extensionErrorMessage = nil
        Task {
            do {
                try await extensionManager.installFromWebStore(idOrURL: input)
                webStoreInput = ""
                isInstallingExtension = false
            } catch {
                extensionErrorMessage = error.localizedDescription
                isInstallingExtension = false
            }
        }
    }

    private func loadUnpackedFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Unpacked Extension Folder"
        panel.message = "Choose a directory containing manifest.json"
        panel.prompt = "Load"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let folderURL = panel.url {
            isInstallingExtension = true
            extensionErrorMessage = nil
            Task {
                do {
                    try await extensionManager.installUnpacked(folderURL: folderURL)
                    isInstallingExtension = false
                } catch {
                    extensionErrorMessage = error.localizedDescription
                    isInstallingExtension = false
                }
            }
        }
    }
}

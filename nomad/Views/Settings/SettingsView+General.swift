//
//  SettingsView+General.swift
//  nomad
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit

extension SettingsView {
    var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "General", subtitle: "")

            // Search
            card(title: "Search") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Search with")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text("Your preferred search engine for the command bar.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }

                        Spacer()

                        Menu {
                            ForEach(searchEngines, id: \.id) { engine in
                                Button(action: {
                                    settings.searchEngine = engine.id
                                }) {
                                    if settings.searchEngine == engine.id {
                                        Label(engine.label, systemImage: "checkmark")
                                    } else {
                                        Text(engine.label)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(settings.searchEngineLabel)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.ink)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.press)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Theme.activeTabHairline, lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider()

                    Toggle(isOn: $settings.searchSuggestions) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show suggestions as you type")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text("With suggestions on, your search engine sees what you type.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                }
            }

            // Software Updates
            card(title: "Software Updates") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Nomad \(Updater.currentVersion)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("Build \(Updater.currentBuild)")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Theme.press, in: Capsule())
                            }

                            switch updater.stage {
                            case .none:
                                Text(updater.statusMessage.isEmpty ? "Nomad is up to date" : updater.statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            case .checking:
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.mini)
                                    Text("Checking for updates...")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.muted)
                                }
                            case .fetching(let release, let progress):
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Downloading Nomad \(release.version)...")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.muted)
                                        Spacer()
                                        Text("\(Int(progress * 100))%")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Theme.accent)
                                    }
                                    ProgressView(value: progress)
                                        .progressViewStyle(.linear)
                                }
                            case .ready(let release):
                                Text("Nomad \(release.version) is ready — restart to use it")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.green)
                            case .waiting(let release):
                                Text("Nomad \(release.version) is available")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                            case .failed(let error):
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                        }

                        Spacer()

                        switch updater.stage {
                        case .ready:
                            Button("Relaunch to Update") {
                                updater.relaunch()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.green)
                            .controlSize(.small)
                        case .waiting:
                            Button("Install Update") {
                                updater.install()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .controlSize(.small)
                        case .fetching:
                            EmptyView()
                        default:
                            Button("Check for Updates") {
                                updater.checkByHand()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(updater.checking)
                        }
                    }

                    Divider()

                    Toggle(isOn: Binding(
                        get: { updater.autoInstall },
                        set: { updater.autoInstall = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check for updates automatically")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text("Once a day, Nomad checks whether a new version is out.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                }
            }

            // Import from Arc & Other Browsers
            card(title: "Import from Other Browsers") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Arc")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text("Brings over Arc's spaces, favorites, and pinned tabs, as new spaces.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer()

                    Button("Import…") {
                        settings.promptBringThingsOver()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

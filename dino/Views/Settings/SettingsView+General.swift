//
//  SettingsView+General.swift
//  dino
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension SettingsView {
    var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "General", subtitle: "")

            // Search
            card(title: "Search") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Search engine")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)

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
                                    .fill(Theme.surfaceHover)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider()

                    Toggle(isOn: $settings.searchSuggestions) {
                        Text("Search suggestions")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                }
            }

            // Backdrop
            card(title: "Backdrop") {
                HStack(spacing: 14) {
                    backdropThumbnail

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Empty tab image")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text(settings.customBackdropPath.isEmpty ? "Default" : "Custom (image or GIF)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer()

                    if !settings.customBackdropPath.isEmpty {
                        Button("Reset") {
                            settings.resetCustomBackdrop()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("Choose…") {
                        pickCustomBackdrop()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Software Updates
            card(title: "Software Updates") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Dino \(Updater.currentVersion)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("Build \(Updater.currentBuild)")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Theme.surfaceHover, in: Capsule())
                            }

                            switch updater.stage {
                            case .none:
                                Text(updater.statusMessage.isEmpty ? "Up to date" : updater.statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            case .checking:
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.mini)
                                    Text("Checking…")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.muted)
                                }
                            case .fetching(let release, let progress):
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Downloading \(release.version)…")
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
                                Text("Dino \(release.version) ready")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                            case .waiting(let release):
                                Text("Dino \(release.version) available")
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
                            Button("Relaunch") {
                                updater.relaunch()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .controlSize(.small)
                        case .waiting:
                            Button("Install") {
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
                        Text("Check automatically")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                }
            }

            // Import
            card(title: "Import") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Arc")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text("Spaces, favorites, and pinned tabs")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer()

                    Button("Import…") {
                        store.isShowingArcImportModal = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var backdropThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let customPath = settings.customBackdropPath
        let customImage = (!customPath.isEmpty && FileManager.default.fileExists(atPath: customPath))
            ? NSImage(contentsOfFile: customPath)
            : nil

        Group {
            if let img = customImage {
                let imgSize = img.size.width > 0 && img.size.height > 0 ? img.size : CGSize(width: 64, height: 40)
                BackdropImageView(image: img, animates: true)
                    .id(customPath)
                    .aspectRatio(imgSize, contentMode: .fill)
            } else {
                Image("DinoBackdrop")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 64, height: 40)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Theme.borderHover, lineWidth: 1)
        }
    }

    private func pickCustomBackdrop() {
        let panel = NSOpenPanel()
        panel.title = "Choose Backdrop"
        panel.prompt = "Set Backdrop"
        panel.allowedContentTypes = [.image, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.setCustomBackdrop(from: url)
        }
    }
}

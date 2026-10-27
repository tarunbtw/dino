//
//  SettingsView+General.swift
//  nomad
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension SettingsView {
    var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "General", subtitle: "Personalize theme, start canvas atmosphere, translucency, and search defaults.")

            // Theme Mode
            card(title: "Theme Mode") {
                HStack(spacing: 10) {
                    themeOption(id: "system", label: "System", icon: "circle.lefthalf.filled")
                    themeOption(id: "dark", label: "Dark", icon: "moon.fill")
                    themeOption(id: "light", label: "Light", icon: "sun.max.fill")
                }
            }

            // Start Canvas Atmosphere (Solid Theme, Custom Hex, or Wallpaper Image)
            card(title: "Start Canvas Atmosphere") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        bgStyleOption(id: "default", label: "Theme Solid", previewColor: Color(nsColor: .windowBackgroundColor))
                        bgStyleOption(id: "hex", label: "Hex Color", previewColor: settings.customBgColor)
                        imageStyleOption
                    }

                    if settings.backgroundStyle == "hex" {
                        Divider().opacity(0.12).padding(.vertical, 2)
                        hexConfigurationView
                    } else if settings.backgroundStyle == "customImage" {
                        Divider().opacity(0.12).padding(.vertical, 2)
                        imageConfigurationView
                    }
                }
            }

            // Window Vibrancy / Acrylic Glass
            card(title: "Translucent Vibrancy") {
                Toggle(isOn: $settings.isVibrant) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Window Blur & Transparency")
                            .font(.system(size: 13, weight: .medium))
                        Text("Applies native behind-window acrylic glass blur across the window canvas")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            // Default Search Engine
            card(title: "Default Search Engine") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search Engine")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("Select your preferred search engine for the address bar.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
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
                                .foregroundStyle(Color.primary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            // Welcome Experience
            card(title: "Welcome Experience") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replay Welcome Screen")
                            .font(.system(size: 13, weight: .medium))
                        Text("View the first-run introduction screen and core principles.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Replay") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            settings.hasCompletedOnboarding = false
                        }
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
                                Text("Nomad \(Updater.currentVersion)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Build \(Updater.currentBuild)")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }

                            switch updater.stage {
                            case .none:
                                Text(updater.statusMessage.isEmpty ? "Nomad is up to date" : updater.statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            case .checking:
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.mini)
                                    Text("Checking for updates...")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            case .fetching(let release, let progress):
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Downloading Nomad \(release.version)...")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(progress * 100))%")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(settings.accentColor)
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
                                    .foregroundStyle(settings.accentColor)
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
                            .tint(settings.accentColor)
                            .controlSize(.small)
                        case .waiting:
                            Button("Install Update") {
                                updater.install()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(settings.accentColor)
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

                    Divider().opacity(0.12)

                    Toggle(isOn: Binding(
                        get: { updater.autoInstall },
                        set: { updater.autoInstall = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatically Download and Prepare Updates")
                                .font(.system(size: 12, weight: .medium))
                            Text("Checks hourly and downloads releases in the background so updates are ready when you restart.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - History Section


    // MARK: - Appearance & Atmosphere Helpers
    private func themeOption(id: String, label: String, icon: String) -> some View {
        let isSelected = settings.theme == id
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                settings.theme = id
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? settings.accentColor.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func bgStyleOption(id: String, label: String, previewColor: Color) -> some View {
        let isSelected = settings.backgroundStyle == id
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                settings.backgroundStyle = id
            }
        }) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(previewColor)
                    .frame(width: 70, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isSelected ? settings.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    )

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var imageStyleOption: some View {
        let isSelected = settings.backgroundStyle == "customImage"
        let nsImage = settings.cachedCustomBgImage
        let hasImage = nsImage != nil

        return Button(action: {
            if hasImage {
                withAnimation(.easeInOut(duration: 0.12)) {
                    settings.backgroundStyle = "customImage"
                }
            } else {
                chooseCustomImage()
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    if let nsImage = nsImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 70, height: 44)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                            .frame(width: 70, height: 44)
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 70, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? settings.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                )

                Text("Image")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hexConfigurationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Color Hex:")
                    .font(.system(size: 12, weight: .medium))

                HStack(spacing: 2) {
                    Text("#")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("1E1E2E", text: $hexInputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 70)
                        .onChange(of: hexInputText) { _, val in
                            applyHex(val)
                        }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )

                Circle()
                    .fill(settings.customBgColor)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))

                Spacer()

                // Preset Swatches
                HStack(spacing: 6) {
                    ForEach(["1E1E2E", "0F172A", "18181B", "282C34", "000000"], id: \.self) { hex in
                        Button(action: {
                            hexInputText = hex
                            applyHex(hex)
                        }) {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("#" + hex)
                    }
                }
            }
        }
    }

    private var imageConfigurationView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.customBgPath.isEmpty ? "No custom wallpaper chosen" : URL(fileURLWithPath: settings.customBgPath).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                if !settings.customBgPath.isEmpty {
                    Text(settings.customBgPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !settings.customBgPath.isEmpty {
                Button("Remove") {
                    settings.customBgPath = ""
                    settings.backgroundStyle = "default"
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            Button(settings.customBgPath.isEmpty ? "Choose Image…" : "Change Image…") {
                chooseCustomImage()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func applyHex(_ text: String) {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6 else { return }
        settings.customBgHex = "#" + clean.uppercased()
    }

    private func chooseCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Set Wallpaper"
        if panel.runModal() == .OK, let url = panel.url {
            settings.customBgPath = url.path
            settings.backgroundStyle = "customImage"
        }
    }
}

//
//  WelcomeView.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//  Editorial first-launch experience over FirstLightScene with serif typography,
//  default browser selection, and Arc migration.
//

import SwiftUI
import AppKit

struct WelcomeView: View {
    @ObservedObject var settings: SettingsStore
    var store: BrowserStore? = nil
    var onComplete: (() -> Void)? = nil

    @State private var offersArc: Bool = false
    @State private var arcPlan: ArcImportPlan? = nil
    @State private var isImportingArc: Bool = false
    @State private var isDefaultBrowser: Bool = false
    @State private var hasImportedArc: Bool = false

    init(settings: SettingsStore, store: BrowserStore? = nil, onComplete: (() -> Void)? = nil) {
        self.settings = settings
        self.store = store
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            // Calm First Light backdrop with sunrise and drifting snowflakes
            FirstLightScene(spaceColor: "glacier")
                .ignoresSafeArea()

            // Window drag clearance across top edge
            VStack {
                WindowDragArea()
                    .frame(height: 38)
                Spacer()
            }
            .zIndex(10)

            // Centered Editorial Welcome Card
            VStack(spacing: 24) {
                // Editorial Typography
                VStack(spacing: 6) {
                    Text("Welcome in.")
                        .font(.system(size: 42, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)

                    Text("A calm, minimal browser built natively for macOS.")
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.muted)
                }

                // Frosted Action Card
                let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                VStack(alignment: .leading, spacing: 20) {
                    // Default Browser Toggle Row
                    HStack(spacing: 12) {
                        Image(systemName: isDefaultBrowser ? "checkmark.circle.fill" : "safari")
                            .font(.system(size: 20))
                            .foregroundStyle(isDefaultBrowser ? Theme.frost : Theme.muted)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Browser")
                                .font(Theme.tabFont)
                                .foregroundStyle(Theme.ink)
                            Text(isDefaultBrowser ? "Nomad is currently your default browser" : "Open links from other apps in Nomad")
                                .font(Theme.hintFont)
                                .foregroundStyle(Theme.muted)
                        }

                        Spacer()

                        if !isDefaultBrowser {
                            Button("Make Default") {
                                makeDefaultBrowser()
                            }
                            .buttonStyle(.plain)
                            .font(Theme.labelFont)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }

                    // Arc Import Row (if detected on this Mac)
                    if offersArc, let plan = arcPlan {
                        Divider()
                            .background(Theme.activeTabHairline)

                        HStack(spacing: 12) {
                            Image(systemName: hasImportedArc ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 20))
                                .foregroundStyle(hasImportedArc ? Theme.frost : Theme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coming from Arc?")
                                    .font(Theme.tabFont)
                                    .foregroundStyle(Theme.ink)
                                Text(hasImportedArc ? "Imported \(plan.spaces.count) spaces into Nomad" : "Bring over \(plan.spaces.count) spaces and \(plan.tabCount) tabs in 1 click")
                                    .font(Theme.hintFont)
                                    .foregroundStyle(Theme.muted)
                            }

                            Spacer()

                            if !hasImportedArc {
                                Button(action: importArcSpaces) {
                                    HStack(spacing: 6) {
                                        if isImportingArc {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Text("Import")
                                            .font(Theme.labelFont)
                                            .foregroundStyle(Theme.ink)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 28)
                                    .background(Theme.press, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isImportingArc)
                            }
                        }
                    }

                    Divider()
                        .background(Theme.activeTabHairline)

                    // Get Started Button
                    Button(action: finish) {
                        HStack(spacing: 8) {
                            Text("Start Exploring")
                                .font(Theme.groupHeaderFont)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Theme.spaceColor("glacier"), in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
                .frame(width: 440)
                .background {
                    CommandBarGlass(shape: shape, color: Theme.spaceColor("glacier"))
                        .clipShape(shape)
                        .shadow(color: Theme.shadowPeek, radius: 24, y: 12)
                        .shadow(color: Theme.shadowPeek.opacity(0.4), radius: 3, y: 1)
                }
            }
            .padding(.top, 40)
        }
        .task {
            checkDefaultBrowser()
            await checkForArc()
        }
    }

    private func checkDefaultBrowser() {
        if let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://apple.com")!) {
            isDefaultBrowser = defaultAppURL.lastPathComponent.contains("Nomad")
        }
    }

    private func makeDefaultBrowser() {
        if let bundleId = Bundle.main.bundleIdentifier {
            let cfBundleId = bundleId as CFString
            LSSetDefaultHandlerForURLScheme("http" as CFString, cfBundleId)
            LSSetDefaultHandlerForURLScheme("https" as CFString, cfBundleId)
            checkDefaultBrowser()
        }
    }

    private func checkForArc() async {
        let stage = await ArcImportService.shared.readArc()
        if case .ready(let plan) = stage {
            self.arcPlan = plan
            self.offersArc = true
        }
    }

    private func importArcSpaces() {
        guard let plan = arcPlan, let store = store else { return }
        isImportingArc = true
        ArcImportService.shared.apply(plan: plan, into: store)
        hasImportedArc = true
        isImportingArc = false
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.35)) {
            settings.hasCompletedOnboarding = true
            onComplete?()
        }
    }
}

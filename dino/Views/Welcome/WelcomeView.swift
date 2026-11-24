//
//  WelcomeView.swift
//  dino
//
//  Minimal first-launch onboarding over the atmospheric stage backdrop.
//

import SwiftUI
import AppKit

struct WelcomeView: View {
    @ObservedObject var settings: SettingsStore
    var store: BrowserStore? = nil
    var onComplete: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offersArc: Bool = false
    @State private var arcPlan: ArcImportPlan? = nil
    @State private var isImportingArc: Bool = false
    @State private var hasImportedArc: Bool = false
    @State private var isButtonHovering: Bool = false

    @State private var showTitle: Bool = false
    @State private var showSubtitle: Bool = false
    @State private var showAction: Bool = false

    init(settings: SettingsStore, store: BrowserStore? = nil, onComplete: (() -> Void)? = nil) {
        self.settings = settings
        self.store = store
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            DinoStageScene(spaceColor: "blue")
                .ignoresSafeArea()

            // Subtle radial center scrim for text contrast over any custom image or GIF
            RadialGradient(
                stops: [
                    .init(color: Color.black.opacity(0.42), location: 0.0),
                    .init(color: Color.black.opacity(0.18), location: 0.65),
                    .init(color: Color.clear, location: 1.0)
                ],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                WindowDragArea()
                    .frame(height: 38)
                Spacer()
            }
            .zIndex(10)

            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    Text("Welcome to Dino")
                        .font(.system(size: 40, weight: .semibold, design: .default))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 10)
                        .blur(radius: showTitle ? 0 : 4)

                    Text("A quiet, keyboard-first browser built natively for macOS.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Theme.ink.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .opacity(showSubtitle ? 1 : 0)
                        .offset(y: showSubtitle ? 0 : 8)
                        .blur(radius: showSubtitle ? 0 : 3)
                }

                VStack(spacing: 12) {
                    Button(action: finish) {
                        HStack(spacing: 8) {
                            Text("Start Browsing")
                                .font(.system(size: 13.5, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(Theme.frame)
                        .padding(.horizontal, 24)
                        .frame(height: 40)
                        .background(
                            isButtonHovering ? Theme.accent.opacity(0.9) : Theme.accent,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(isButtonHovering ? 0.25 : 0.1), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
                        .scaleEffect(isButtonHovering ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .onHover { isButtonHovering = $0 }
                    .animation(.easeOut(duration: 0.16), value: isButtonHovering)

                    if offersArc, let plan = arcPlan {
                        Button(action: importArcSpaces) {
                            HStack(spacing: 6) {
                                if isImportingArc {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: hasImportedArc ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11))
                                }
                                Text(hasImportedArc
                                     ? "Imported \(plan.spaces.count) spaces from Arc"
                                     : "Import \(plan.spaces.count) spaces from Arc")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Theme.ink.opacity(0.85))
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Theme.borderHover, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isImportingArc || hasImportedArc)
                    }
                }
                .opacity(showAction ? 1 : 0)
                .offset(y: showAction ? 0 : 8)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            if reduceMotion {
                showTitle = true
                showSubtitle = true
                showAction = true
            } else {
                withAnimation(.easeOut(duration: 0.55)) {
                    showTitle = true
                }
                withAnimation(.easeOut(duration: 0.55).delay(0.14)) {
                    showSubtitle = true
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.28)) {
                    showAction = true
                }
            }
        }
        .task {
            await checkForArc()
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

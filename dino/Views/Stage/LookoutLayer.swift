//
//  LookoutLayer.swift
//  dino
//
//  Created by tarun on 10/11/26.
//

import SwiftUI
import AppKit

/// Elevated Lookout card over the active web page (Little Arc).
/// Displays a link preview with no bulky window frame, paired with smooth scale-up growth when kept as a tab.
struct LookoutLayer: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore
    let tab: Tab

    @State private var growth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Inset margins interpolate to 0 as growth reaches 1
            let insetX = max(0, (w * 0.12) * (1 - growth))
            let insetY = max(0, (h * 0.10) * (1 - growth))
            let cornerRadius = 14 * (1 - growth)

            ZStack {
                // Dimmed backdrop
                Theme.commandDim
                    .ignoresSafeArea()
                    .opacity(Double(1 - growth))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        close()
                    }

                // Lookout Elevated Card
                ZStack(alignment: .topTrailing) {
                    WebStage(tab: tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
                                .opacity(Double(1 - growth))
                        }
                        .shadow(color: Color.black.opacity(Double(0.35 * (1 - growth))), radius: 24, y: 12)

                    // Floating Action Buttons (beside top-trailing corner of the card)
                    if growth == 0 {
                        HStack(spacing: 4) {
                            LookoutButton(icon: "rectangle.split.2x1", help: "Open beside in Split View") {
                                keep(beside: true)
                            }
                            LookoutButton(icon: "arrow.up.left.and.arrow.down.right", help: "Open as Tab") {
                                keep(beside: false)
                            }
                            LookoutButton(icon: "xmark", help: "Close Lookout (Esc)") {
                                close()
                            }
                        }
                        .padding(10)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, insetX)
                .padding(.vertical, insetY)
            }
            .frame(width: w, height: h)
        }
    }

    private func close() {
        guard growth == 0 else { return }
        store.closePeek()
    }

    private func keep(beside: Bool) {
        guard growth == 0 else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
            growth = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            store.keepPeek(beside: beside)
        }
    }
}

/// Small frosted circular button for Lookout actions.
private struct LookoutButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? Theme.ink : Theme.muted)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(isHovered ? Theme.press : Theme.page)
                }
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}


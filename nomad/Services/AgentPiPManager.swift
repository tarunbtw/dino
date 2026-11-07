//
//  AgentPiPManager.swift
//  nomad
//
//  Created by tarun on 15/10/26.
//

import AppKit
import WebKit
import SwiftUI
import Combine

/// Manages native floating Picture-in-Picture viewer for monitoring AI agent ghost tabs.
/// Enables human users to observe agent automation live in a corner window without stealing active tab focus.
@MainActor
final class AgentPiPManager: ObservableObject {
    static let shared = AgentPiPManager()

    private var panel: AgentFloatPanel?
    private weak var activeTab: Tab?
    private weak var store: BrowserStore?

    @Published var isFloating: Bool = false
    @Published var floatingTabId: UUID? = nil

    private init() {}

    func toggle(tab: Tab, store: BrowserStore) {
        if isFloating && floatingTabId == tab.id {
            dismiss()
        } else {
            present(tab: tab, store: store)
        }
    }

    func present(tab: Tab, store: BrowserStore) {
        if isFloating {
            dismiss()
        }
        self.activeTab = tab
        self.store = store
        self.floatingTabId = tab.id
        self.isFloating = true

        let defaultSize = NSSize(width: 480, height: 320)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defaultOrigin = NSPoint(
            x: screen.maxX - defaultSize.width - 24,
            y: screen.minY + 24
        )
        let spot = NSRect(origin: defaultOrigin, size: defaultSize)

        let panel = AgentFloatPanel(
            contentRect: spot,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 320, height: 200)

        let rootView = AgentPiPHostView(
            tab: tab,
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onSplit: { [weak self, weak tab, weak store] in
                guard let tab = tab, let store = store else { return }
                self?.dismiss()
                store.splitGhostTab(id: tab.id)
            },
            onPromote: { [weak self, weak tab, weak store] in
                guard let tab = tab, let store = store else { return }
                self?.dismiss()
                store.promoteGhostTab(id: tab.id)
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true

        panel.contentView = hosting
        panel.invalidateShadow()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        if let tab = activeTab {
            tab.webView.removeFromSuperview()
        }
        panel?.orderOut(nil)
        panel = nil
        activeTab = nil
        floatingTabId = nil
        isFloating = false
    }

    func landIfTab(id: UUID) {
        if floatingTabId == id {
            dismiss()
        }
    }
}

private final class AgentFloatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// SwiftUI container for the floating agent viewer: live WebStage + overlay header controls.
struct AgentPiPHostView: View {
    @ObservedObject var tab: Tab
    var onDismiss: () -> Void
    var onSplit: () -> Void
    var onPromote: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // Live WebKit View
            WebStage(tab: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Header Overlay Toolbar
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.purple)
                    Text("Agent Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())

                let title = tab.title.isEmpty ? (tab.url?.host ?? "Automating...") : tab.title
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Split Button
                Button(action: onSplit) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open in Split View")

                // Promote Button
                Button(action: onPromote) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Promote to Tab")

                // Close Button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Dismiss PiP")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.45), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(isHovered ? 1.0 : 0.85)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onHover { isHovered = $0 }
    }
}

//
//  TabItemView.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI
import AppKit
import WebKit

/// An individual tab pill in the horizontal tab strip.
/// Resting tabs have zero borders and zero backgrounds.
/// Active tab sits on the shared matched-geometry sliding wash pill.
struct TabItemView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: Tab
    let isActive: Bool
    let isDragging: Bool
    let tabWidth: CGFloat
    let index: Int
    let count: Int
    let step: CGFloat
    let offsetX: CGFloat
    let pillNamespace: Namespace.ID
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    @State private var isHovered: Bool = false
    @State private var lastClickTime: TimeInterval = 0

    var body: some View {
        HStack(spacing: 0) {
            if tabWidth < 50 {
                // Compact favicon-only mode
                ZStack {
                    if isHovered {
                        Button(action: { store.closeTab(id: tab.id) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Close Tab (⌘W)")
                    } else {
                        tabIconView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Standard mode: Icon + Title + Close button
                HStack(spacing: 6) {
                    tabIconView
                    tabTitleView
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if isHovered || isActive {
                    HStack(spacing: 2) {
                        if isTabSplit {
                            Button(action: {
                                store.closeSplit(for: tab.id)
                            }) {
                                Image(systemName: "rectangle.split.2x1")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .help("Separate Tabs")
                        }

                        Button(action: {
                            store.closeTab(id: tab.id)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Close Tab (⌘W)")
                    }
                    .padding(.trailing, 6)
                } else if tabWidth >= 70 {
                    Spacer().frame(width: 14)
                }
            }
        }
        .frame(height: 28)
        .frame(width: tabWidth)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.wash)
                    .matchedGeometryEffect(id: "slidingTabPill", in: pillNamespace)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.hover)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { isHovered = $0 }
        .offset(x: offsetX, y: 0)
        .zIndex(isDragging ? 100 : (isActive ? 1 : 0))
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("TabStripSpace"))
                .onChanged { value in
                    onDragChanged(value.translation.width)
                }
                .onEnded { value in
                    onDragEnded(value.translation.width)
                }
        )
        .onTapGesture {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastClickTime < 0.35 {
                // Double click opens the centered Omnibox
                store.isAddressBarFocused = true
            } else {
                store.selectTab(id: tab.id)
            }
            lastClickTime = now
        }
        .contextMenu {
            if let split = store.splitPairs.first(where: { $0.contains(tab.id) }) {
                Button("Swap Split Panes") {
                    store.swapSplit(splitPairId: split.id)
                }
                Button("Separate Tabs (Ungroup)") {
                    store.closeSplit(for: tab.id)
                }
            } else {
                Button("Split with New Tab") {
                    store.splitCurrentTab()
                }

                let candidateTabs = store.tabs.filter { $0.id != tab.id && !$0.isPinned }
                if !candidateTabs.isEmpty {
                    Menu("Split with Tab") {
                        ForEach(candidateTabs) { other in
                            Button(other.title.isEmpty ? "Blank Tab" : other.title) {
                                store.splitTab(primaryId: tab.id, secondaryId: other.id)
                            }
                        }
                    }
                }
            }
            Divider()
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                store.togglePin(tabId: tab.id)
            }
            Button("Reload") {
                tab.reload()
            }
            Button("Duplicate Tab") {
                store.newTab(url: tab.url, isIncognito: tab.isIncognito, select: true)
            }
            Button("Close Other Tabs") {
                let others = store.tabs.filter { $0.id != tab.id }
                for other in others {
                    store.closeTab(id: other.id)
                }
            }
            Divider()
            Button("Close Tab") {
                store.closeTab(id: tab.id)
            }
        }
    }

    private var isTabSplit: Bool {
        store.splitPairs.contains { $0.contains(tab.id) }
    }

    @ViewBuilder
    private var tabTitleView: some View {
        if tabWidth >= 70 {
            Text(displayTitle)
                .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? Palette.ink : Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isTabSplit {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 8.5))
                    .foregroundStyle(isActive ? Palette.ink : Palette.muted)
            }
        }
    }

    @ViewBuilder
    private var tabIconView: some View {
        if tab.isLoading {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.65)
                .frame(width: 14, height: 14)
        } else if tab.isIncognito && (tab.favicon == nil || tab.isBlank) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.purple.opacity(0.85))
                .frame(width: 14, height: 14)
        } else if let scheme = tab.url?.scheme, (scheme == ExtensionManager.scheme || scheme == "webkit-extension"),
                  let host = tab.url?.host,
                  let context = ExtensionManager.shared.contexts[host],
                  let icon = context.action(for: nil)?.icon(for: CGSize(width: 16, height: 16)) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else if let favicon = tab.favicon {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(isActive ? Palette.ink : Palette.muted)
                .frame(width: 14, height: 14)
        }
    }

    private var iconName: String {
        if tab.isInternalPage {
            return "gearshape.fill"
        }
        if tab.isIncognito {
            return "eye.slash.fill"
        }
        if let scheme = tab.url?.scheme, (scheme == ExtensionManager.scheme || scheme == "webkit-extension") {
            return "puzzlepiece.extension"
        }
        return tab.isBlank ? "sparkles" : "globe"
    }

    private var displayTitle: String {
        if tab.isInternalPage {
            return tab.title
        }
        if tab.isIncognito && (tab.url == nil || tab.isBlank) {
            return "Private Tab"
        }
        if let scheme = tab.url?.scheme, (scheme == ExtensionManager.scheme || scheme == "webkit-extension") {
            if let host = tab.url?.host, let ext = ExtensionManager.shared.installed.first(where: { $0.id == host }) {
                return ext.name
            }
            return tab.title
        }
        let trimmedTitle = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty && trimmedTitle != "New Tab" {
            return trimmedTitle
        }
        if let host = tab.url?.host, !host.isEmpty, !tab.isBlank {
            return host
        }
        return tab.isBlank ? "New Tab" : (trimmedTitle.isEmpty ? "New Tab" : trimmedTitle)
    }
}

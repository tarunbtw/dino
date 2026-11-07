//
//  NavigationControls.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI

/// Minimal navigation control buttons: Back, Forward, Reload, Bookmark, Settings.
struct NavigationControls: View {
    @ObservedObject var tab: Tab
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore = SettingsStore.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var updater = Updater.shared
    @State private var isShowingExtensionsMenu: Bool = false
    @State private var isShowingDownloadsMenu: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if !settings.isVerticalTabs {
                Button(action: { tab.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!tab.canGoBack)
                .opacity(tab.canGoBack ? 1.0 : 0.35)
                .help("Back (⌘[)")

                Button(action: { tab.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!tab.canGoForward)
                .opacity(tab.canGoForward ? 1.0 : 0.35)
                .help("Forward (⌘])")

                Button(action: {
                    if tab.isLoading {
                        tab.stopLoading()
                    } else {
                        tab.reload()
                    }
                }) {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.isLoading ? "Stop Loading" : "Reload (⌘R)")
            }

            // 1-Click Chrome Web Store install button when visiting an extension page
            WebStoreInstallPill(tab: tab, store: store)

            // Pinned WebExtension action buttons (e.g. uBlock Origin Lite)
            ExtensionActionBar(store: store)

            // Extensions Menu button (Puzzle icon)
            Button(action: { isShowingExtensionsMenu.toggle() }) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isShowingExtensionsMenu ? Color.primary : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        isShowingExtensionsMenu ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(ExtensionAnchor(id: "extensions_menu_anchor"))
            .help("Extensions")
            .popover(isPresented: $isShowingExtensionsMenu, arrowEdge: .bottom) {
                ExtensionsMenuPopover(tab: tab, store: store, isPresented: $isShowingExtensionsMenu)
            }

            // Downloads Button (appears when downloads are active or completed)
            if !downloadManager.downloads.isEmpty {
                Button(action: { isShowingDownloadsMenu.toggle() }) {
                    ZStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(downloadManager.hasActiveDownloads ? Color.primary : Color.secondary)

                        if downloadManager.hasActiveDownloads {
                            Circle()
                                .trim(from: 0, to: downloadManager.overallProgress)
                                .stroke(Color.primary, lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .background(
                        isShowingDownloadsMenu ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Downloads")
                .popover(isPresented: $isShowingDownloadsMenu, arrowEdge: .bottom) {
                    DownloadsMenuPopover(store: store, isPresented: $isShowingDownloadsMenu)
                }
            }

            // Agent Co-Browsing Indicator (appears when background ghost tabs are running)
            if !store.ghostTabs.isEmpty {
                AgentGhostTabsPill(store: store)
            }

            let urlString = tab.url?.absoluteString ?? ""
            let canBookmark = !tab.isBlank && !tab.isInternalPage && !urlString.isEmpty && urlString != "about:blank"
            let isBookmarked = canBookmark && settings.isBookmarked(urlString)

            Button(action: {
                store.toggleBookmark(for: tab)
            }) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isBookmarked ? Color.primary : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canBookmark)
            .opacity(canBookmark ? 1.0 : 0.35)
            .help(isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark Tab (⌘D)")

            let canInspect = !tab.isBlank && !tab.isInternalPage

            Button(action: {
                guard canInspect else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    tab.isDevDrawerVisible.toggle()
                }
            }) {
                Image(systemName: tab.isDevDrawerVisible ? "curlybraces.square.fill" : "curlybraces")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tab.isDevDrawerVisible ? Color.primary : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        tab.isDevDrawerVisible ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canInspect)
            .opacity(canInspect ? 1.0 : 0.35)
            .help("Developer Tools (⌘⌥I)")

            Button(action: {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    store.isAutopilotRailVisible.toggle()
                }
            }) {
                Image(systemName: store.isAutopilotRailVisible ? "sparkles.rectangle.stack.fill" : "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.isAutopilotRailVisible ? settings.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        store.isAutopilotRailVisible ? settings.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Autopilot Rail (⌘⇧A)")

            if !settings.isVerticalTabs {
                let isSettingsActive = tab.isInternalPage

                Button(action: { store.openSettings() }) {
                    Image(systemName: isSettingsActive ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSettingsActive ? Color.primary : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            isSettingsActive ? Color.primary.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings (nomad://settings, ⌘,)")

                Button(action: {
                    settings.toggleTabLayout()
                }) {
                    Image(systemName: settings.isVerticalTabs ? "rectangle.topthird.inset.filled" : "sidebar.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(settings.isVerticalTabs ? Color.primary : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            settings.isVerticalTabs ? Color.primary.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(settings.isVerticalTabs ? "Switch to Top Tab Strip (⌥⌘T)" : "Switch to Vertical Sidebar (⌥⌘T)")
            }

            if case .ready(let release) = updater.stage {
                Button(action: { updater.relaunch() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Restart")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Nomad \(release.version) is ready to install. Click to restart.")
            }
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Agent Ghost Tabs Indicator & Popover

struct AgentGhostTabsPill: View {
    @ObservedObject var store: BrowserStore
    @State private var isShowingPopover: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: { isShowingPopover.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("\(store.ghostTabs.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isHovered || isShowingPopover
                    ? Color.purple.opacity(0.18)
                    : Color.purple.opacity(0.10),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(Color.purple.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Agent background tabs active (\(store.ghostTabs.count))")
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            AgentGhostTabsPopover(store: store, isPresented: $isShowingPopover)
        }
    }
}

struct AgentGhostTabsPopover: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("Agent Background Tabs")
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                Text("\(store.ghostTabs.count) running")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(store.ghostTabs) { ghostTab in
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                let title = ghostTab.title.isEmpty ? (ghostTab.url?.host ?? "Automating...") : ghostTab.title
                                Text(title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                if let host = ghostTab.url?.host {
                                    Text(host)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 4)

                            HStack(spacing: 3) {
                                Button(action: {
                                    AgentPiPManager.shared.toggle(tab: ghostTab, store: store)
                                    isPresented = false
                                }) {
                                    Image(systemName: "pip.enter")
                                        .font(.system(size: 10, weight: .medium))
                                        .frame(width: 20, height: 20)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Watch in Picture-in-Picture")

                                Button(action: {
                                    store.splitGhostTab(id: ghostTab.id)
                                    isPresented = false
                                }) {
                                    Image(systemName: "rectangle.split.2x1")
                                        .font(.system(size: 10, weight: .medium))
                                        .frame(width: 20, height: 20)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Open side-by-side in Split View")

                                Button(action: {
                                    store.promoteGhostTab(id: ghostTab.id)
                                    isPresented = false
                                }) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10, weight: .medium))
                                        .frame(width: 20, height: 20)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Promote to regular tab")

                                Button(action: {
                                    store.closeTab(id: ghostTab.id)
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .medium))
                                        .frame(width: 20, height: 20)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Stop and close ghost tab")
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(10)
        .frame(width: 320)
    }
}



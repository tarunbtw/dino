//
//  BrowserView.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI
import AppKit

/// Main browser window view coordinating the top bar, loading progress, tab stage, and settings.
struct BrowserView: View {
    @ObservedObject var store: BrowserStore
    @StateObject private var settings = SettingsStore.shared
    @State private var isCommandPaletteVisible: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                if settings.isVerticalTabs {
                    VerticalSidebarView(store: store, settings: settings)
                        .zIndex(200)
                }

                VStack(spacing: 0) {
                    // Top browser chrome (includes bottom progress bar overlay)
                    TopBarView(store: store, settings: settings)
                        .frame(height: 50)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                        .zIndex(100)

                    // Tab Stage (observes activeTab or activeSplitPair directly)
                    if let split = store.activeSplitPair,
                       let leftTab = store.tabs.first(where: { $0.id == split.leftTabId }),
                       let rightTab = store.tabs.first(where: { $0.id == split.rightTabId }) {
                        SplitStageView(store: store, split: split, leftTab: leftTab, rightTab: rightTab, settings: settings)
                            .id(split.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .zIndex(0)
                    } else if let activeTab = store.activeTab {
                        TabStageView(store: store, tab: activeTab, settings: settings)
                            .id(activeTab.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .zIndex(0)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            if isCommandPaletteVisible {
                CommandPaletteView(store: store, settings: settings, onDismiss: {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                        isCommandPaletteVisible = false
                    }
                })
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(300)
            }
        }
        .background {
            if settings.isVibrant {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(settings.colorScheme)
        .tint(settings.accentColor)
        .onExitCommand {
            if let tab = store.activeTab, tab.isZapperActive {
                tab.stopElementZapper()
            }
        }
        .background {
            keyboardShortcutBridge
        }
    }

    @ViewBuilder
    private var keyboardShortcutBridge: some View {
        Group {
            Button("New Tab") { store.newTab() }.keyboardShortcut("t", modifiers: .command)
            Button("Reopen Closed Tab") { store.reopenLastClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Button("New Incognito") { store.newIncognitoTab() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Close Tab") { if let activeId = store.activeTabId { store.closeTab(id: activeId) } }.keyboardShortcut("w", modifiers: .command)
            Button("Address Bar") { store.isAddressBarFocused = true }.keyboardShortcut("l", modifiers: .command)
            Button("Reload") { store.reload() }.keyboardShortcut("r", modifiers: .command)
            Button("Back") { store.goBack() }.keyboardShortcut("[", modifiers: .command)
            Button("Forward") { store.goForward() }.keyboardShortcut("]", modifiers: .command)
            Button("Prev Tab") { store.selectPreviousTab() }.keyboardShortcut("{", modifiers: .command)
            Button("Next Tab") { store.selectNextTab() }.keyboardShortcut("}", modifiers: .command)
            Button("Settings") { store.openSettings() }.keyboardShortcut(",", modifiers: .command)
            Button("History") { store.openSettings(section: "History") }.keyboardShortcut("y", modifiers: .command)
            Button("Bookmark") { store.toggleBookmark() }.keyboardShortcut("d", modifiers: .command)
            Button("Zoom In") { store.activeTab?.zoomIn() }.keyboardShortcut("+", modifiers: .command)
            Button("Zoom In Eq") { store.activeTab?.zoomIn() }.keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { store.activeTab?.zoomOut() }.keyboardShortcut("-", modifiers: .command)
            Button("Zoom Reset") { store.activeTab?.resetZoom() }.keyboardShortcut("0", modifiers: .command)
            Button("Find") { toggleFindBar() }.keyboardShortcut("f", modifiers: .command)
            Button("Print") { store.activeTab?.printPage() }.keyboardShortcut("p", modifiers: .command)
            Button("Dev Drawer") { toggleDevDrawer() }.keyboardShortcut("i", modifiers: [.command, .option])
            Button("Command Palette") { withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) { isCommandPaletteVisible.toggle() } }.keyboardShortcut("k", modifiers: .command)
            Button("Element Zapper") { store.activeTab?.toggleElementZapper() }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Reader Mode") { store.activeTab?.toggleReaderMode() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Picture in Picture") { store.activeTab?.togglePictureInPicture() }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Toggle Split View") { store.toggleSplitCurrentTab() }.keyboardShortcut("s", modifiers: [.command, .option])
            Button("Swap Split Panes") { store.swapSplit() }.keyboardShortcut("s", modifiers: [.command, .control])
            Button("Toggle Tab Layout") { settings.toggleTabLayout() }.keyboardShortcut("t", modifiers: [.command, .option])
            Button("Toggle Sidebar") { settings.toggleSidebarCollapsed() }.keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Toggle Pin Tab") { if let id = store.activeTabId { store.togglePin(tabId: id) } }.keyboardShortcut("p", modifiers: [.command, .option])
            Button("Next Space") { store.switchNextSpace() }.keyboardShortcut("]", modifiers: [.command, .control])
            Button("Prev Space") { store.switchNextSpace() }.keyboardShortcut("[", modifiers: [.command, .control])
            Button("Space 1") { store.switchSpace(at: 0) }.keyboardShortcut("1", modifiers: .control)
            Button("Space 2") { store.switchSpace(at: 1) }.keyboardShortcut("2", modifiers: .control)
            Button("Space 3") { store.switchSpace(at: 2) }.keyboardShortcut("3", modifiers: .control)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }


    private func toggleFindBar() {
        guard let tab = store.activeTab, !tab.isInternalPage && !tab.isBlank else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            tab.isFindBarVisible.toggle()
        }
    }

    private func toggleDevDrawer() {
        guard let tab = store.activeTab, !tab.isInternalPage && !tab.isBlank else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            tab.isDevDrawerVisible.toggle()
        }
    }
}

/// Stage hosting the active tab: renders native SettingsView for internal pages, WebStage for web URLs, or EmptyStateView for blank tabs.
private struct TabStageView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: Tab
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ZStack {
            if tab.isInternalPage {
                SettingsView(store: store, settings: settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if tab.isBlank {
                // Calm empty start state when tab has no URL loaded
                EmptyStateView(tab: tab, store: store, settings: settings)
                    .transition(.opacity)
            } else if tab.isFloatingVideo {
                VStack(spacing: 14) {
                    Image(systemName: "pip.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(settings.accentColor)

                    VStack(spacing: 4) {
                        Text("Video is Playing in Floating Window")
                            .font(.system(size: 15, weight: .semibold))
                        Text("The video continues playing in a borderless window above other apps.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Button("Return to Tab") {
                        FloatingVideoManager.shared.land()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(settings.accentColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    WebStage(tab: tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if tab.isDevDrawerVisible {
                        DevDrawerView(tab: tab, store: store)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.26, dampingFraction: 0.86), value: tab.isDevDrawerVisible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Distraction-Free Reading Mode (⌘⇧R)
            if tab.isReaderModeActive, let article = tab.readerArticle {
                ReaderView(article: article, onClose: {
                    tab.toggleReaderMode()
                })
                .transition(.opacity)
                .zIndex(150)
            }

            // Chrome/Arc-style Floating Swipe Gesture Indicator
            if let swipe = tab.swipeState {
                SwipeIndicatorView(swipe: swipe, accentColor: settings.accentColor)
                    .transition(.opacity)
            }

            // Sleek Floating Find in Page Bar (⌘F)
            if tab.isFindBarVisible {
                FindInPageView(tab: tab)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            // Element Zapper Mode Floating Translucent Capsule Bar (⇧⌘H)
            if tab.isZapperActive {
                ZapperFloatingBar(tab: tab)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(200)
            }
            // Sleek Arc/Safari-style Link Hover Bubble
            if let link = tab.hoveredLink, !link.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Text(link)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.92), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                            .frame(maxWidth: 480, alignment: .leading)
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
                .zIndex(250)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Dual-pane stage for side-by-side tab browsing with an interactive draggable divider.
private struct SplitStageView: View {
    @ObservedObject var store: BrowserStore
    let split: SplitPair
    @ObservedObject var leftTab: Tab
    @ObservedObject var rightTab: Tab
    @ObservedObject var settings: SettingsStore

    private let dividerWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let usableW = max(100, totalW - dividerWidth)
            let leftW = max(120, min(usableW - 120, usableW * CGFloat(split.ratio)))
            let rightW = max(120, usableW - leftW)

            HStack(spacing: 0) {
                // Left Pane
                paneView(for: leftTab, width: leftW)

                // Divider
                SplitDividerView(
                    store: store,
                    split: split,
                    totalWidth: usableW
                )
                .frame(width: dividerWidth)

                // Right Pane
                paneView(for: rightTab, width: rightW)
            }
        }
        .coordinateSpace(name: "SplitStageCoordinateSpace")
    }

    @ViewBuilder
    private func paneView(for tab: Tab, width: CGFloat) -> some View {
        let isFocused = store.activeTabId == tab.id
        ZStack(alignment: .topTrailing) {
            TabStageView(store: store, tab: tab, settings: settings)
                .frame(width: width)

            // Pane Active Highlight
            if isFocused {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(settings.accentColor.opacity(0.35), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }

            // Quick Separate / Ungroup button in top-trailing corner of each pane
            Button(action: {
                store.closeSplit(for: tab.id)
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .help("Separate Tabs (Ungroup)")
        }
        .frame(width: width)
        .clipped()
    }
}

/// Draggable divider between two split view panes with resize cursor, double-click to reset, and context menu.
private struct SplitDividerView: View {
    @ObservedObject var store: BrowserStore
    let split: SplitPair
    let totalWidth: CGFloat

    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())

            // Hairline separator
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.65))
                .frame(width: 1)

            // Pill Grab Handle
            Capsule()
                .fill(isHovered ? Color.secondary.opacity(0.65) : Color.secondary.opacity(0.25))
                .frame(width: 3.5, height: 28)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("SplitStageCoordinateSpace"))
                .onChanged { value in
                    let newRatio = min(0.8, max(0.2, Double(value.location.x / totalWidth)))
                    store.setSplitRatio(splitPairId: split.id, ratio: newRatio)
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                store.setSplitRatio(splitPairId: split.id, ratio: 0.5)
            }
        }
        .contextMenu {
            Button("Swap Panes") {
                store.swapSplit(splitPairId: split.id)
            }
            Button("Reset to 50 / 50") {
                store.setSplitRatio(splitPairId: split.id, ratio: 0.5)
            }
            Divider()
            Button("Separate Tabs (Ungroup)") {
                store.closeSplit(for: split.leftTabId)
            }
        }
    }
}

/// Sleek floating swipe gesture navigation indicator (inspired by Chrome and Arc).
private struct SwipeIndicatorView: View {
    let swipe: Tab.SwipeGestureState
    let accentColor: Color

    var body: some View {
        HStack {
            if swipe.direction == .forward {
                Spacer()
            }

            ZStack {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(swipe.isTriggered ? accentColor.opacity(0.85) : Color.primary.opacity(0.12), lineWidth: swipe.isTriggered ? 2 : 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)

                Image(systemName: swipe.direction == .back ? "chevron.left" : "chevron.right")
                    .font(.system(size: 15, weight: swipe.isTriggered ? .bold : .semibold))
                    .foregroundStyle(swipe.isTriggered ? accentColor : Color.primary)
                    .scaleEffect(swipe.isTriggered ? 1.15 : 1.0)
            }
            .offset(x: swipeOffset)
            .scaleEffect(swipeScale)
            .opacity(swipeOpacity)
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.78), value: swipe.distance)
            .animation(.easeInOut(duration: 0.15), value: swipe.isTriggered)

            if swipe.direction == .back {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var swipeOffset: CGFloat {
        let maxTravel: CGFloat = 32
        let travel = min(swipe.distance * 0.45, maxTravel)
        return swipe.direction == .back ? travel : -travel
    }

    private var swipeScale: CGFloat {
        let minScale: CGFloat = 0.8
        let scale = minScale + (min(swipe.progress, 1.0) * 0.2)
        return swipe.isTriggered ? scale * 1.08 : scale
    }

    private var swipeOpacity: Double {
        return Double(min(swipe.progress * 1.4, 1.0))
    }
}

/// Minimal start canvas for blank tabs: clean centered URL input field, quick bookmarks, and custom atmosphere.
private struct EmptyStateView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Atmosphere Canvas (Theme Solid, Custom Hex, or Custom Image)
            atmosphereView

            // Centered omnibox and quick bookmarks
            VStack(spacing: 16) {
                // Incognito Private Browsing Badge & Notice
                if tab.isIncognito {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(Color.purple.opacity(0.85))

                        Text("Private Browsing")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Nomad does not save your history, cookies, or site data for this tab.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 6)
                }

                // Centered "Enter a web address" field
                HStack(spacing: 8) {
                    TextField(tab.isIncognito ? "Search privately or enter address" : "Enter a web address", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(.primary)
                        .focused($isFocused)
                        .onSubmit {
                            submit()
                        }

                    if !text.isEmpty {
                        Button(action: { text = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(width: 480, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isFocused ? settings.accentColor.opacity(0.5) : Color.primary.opacity(0.12), lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    // Floating autocomplete suggestions dropdown directly beneath the field without jumping layout
                    if isFocused && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        OmniboxSuggestionsView(query: text, width: 480) { url in
                            tab.load(url: url)
                        }
                        .offset(y: 46)
                        .zIndex(100)
                    }
                }

                // Quick Bookmarks row below the field
                if !settings.bookmarks.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(settings.bookmarks.prefix(6)) { bookmark in
                            Button(action: { store.openBookmark(bookmark) }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(settings.accentColor)
                                    Text(bookmark.title)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.04), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }

                // Quick Open Tabs Pairing Pills when in Split View
                if let split = store.splitPairs.first(where: { $0.contains(tab.id) }),
                   let partnerId = split.partner(of: tab.id) {
                    let candidateTabs = store.tabs.filter { $0.id != tab.id && $0.id != partnerId && !$0.isPinned }
                    if !candidateTabs.isEmpty {
                        VStack(spacing: 8) {
                            Text("Pair with an open tab:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(candidateTabs) { candidate in
                                    Button(action: {
                                        store.splitTab(primaryId: partnerId, secondaryId: candidate.id)
                                        store.closeTab(id: tab.id)
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: candidate.isInternalPage ? "gearshape.fill" : "globe")
                                                .font(.system(size: 10))
                                                .foregroundStyle(settings.accentColor)
                                            Text(candidate.title.isEmpty ? "Blank Tab" : candidate.title)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }

            // Bottom-right Customize / Tune Canvas icon button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { store.openSettings(section: "General") }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(Color.primary.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Customize Appearance (nomad://settings, ⌘,)")
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
        .onChange(of: store.isAddressBarFocused) { _, focused in
            if focused {
                isFocused = true
                store.isAddressBarFocused = false
            }
        }
    }

    @ViewBuilder
    private var atmosphereView: some View {
        Group {
            switch settings.backgroundStyle {
            case "hex":
                settings.customBgColor
            case "customImage":
                if let nsImage = settings.cachedCustomBgImage {
                    GeometryReader { geo in
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .overlay(Color.black.opacity(0.35))
                    }
                } else {
                    themeSolidBackground
                }
            default:
                themeSolidBackground
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var themeSolidBackground: some View {
        if settings.isVibrant {
            Color(nsColor: .windowBackgroundColor).opacity(0.15)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parsed = URLParser.parse(trimmed)
        if parsed.scheme == "nomad" && (parsed.host == "settings" || parsed.host == "tune") {
            store.openSettings()
        } else {
            tab.load(text: trimmed)
        }
    }
}

// MARK: - AppKit Window Vibrancy & Visual Effects

/// Native AppKit visual effect view providing blurred vibrancy behind windows.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.material = material
        effectView.blendingMode = blendingMode
        effectView.state = .active
        return effectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

/// Sleek floating translucent capsule banner for Element Zapper mode (⇧⌘H)
private struct ZapperFloatingBar: View {
    @ObservedObject var tab: Tab
    @ObservedObject var zapperStore = ZapperStore.shared
    @State private var isDoneHovered: Bool = false
    @State private var isUnhideHovered: Bool = false

    var body: some View {
        let host = tab.url?.host ?? ""
        let zappedCount = zapperStore.count(for: host)

        HStack(spacing: 10) {
            // Accent icon badge
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.16))
                    .frame(width: 20, height: 20)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.red)
            }

            // Description text
            HStack(spacing: 5) {
                Text("Element Zapper")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("— Click elements to hide")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Hidden count & Unhide All button
            if zappedCount > 0 {
                HStack(spacing: 4) {
                    Text("\(zappedCount)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("hidden")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.primary.opacity(0.08)))

                Button(action: {
                    tab.unhideAllZappedElements()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Unhide All")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isUnhideHovered ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .systemCursor(.pointingHand)
                .onHover { isUnhideHovered = $0 }
            }

            Divider()
                .frame(height: 14)
                .opacity(0.25)

            // Done Button (Custom capsule pill, comfortable vertical padding, never chopped)
            Button(action: {
                tab.stopElementZapper()
            }) {
                HStack(spacing: 4) {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Esc")
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.25)))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(isDoneHovered ? Color.red.opacity(0.95) : Color.red.opacity(0.85))
                        .shadow(color: Color.red.opacity(0.35), radius: 4, y: 1.5)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .systemCursor(.pointingHand)
            .keyboardShortcut(.escape, modifiers: [])
            .onHover { isDoneHovered = $0 }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 6)
                .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .systemCursor(.arrow)
    }
}

/// AppKit cursor rect provider for SwiftUI views on macOS.
private struct CursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorNSView {
        let view = CursorNSView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorNSView, context: Context) {
        if nsView.cursor !== cursor {
            nsView.cursor = cursor
            nsView.window?.invalidateCursorRects(for: nsView)
        }
    }
}

private final class CursorNSView: NSView {
    var cursor: NSCursor = .arrow

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }
}

private extension View {
    func systemCursor(_ cursor: NSCursor) -> some View {
        background(CursorRectView(cursor: cursor))
    }
}


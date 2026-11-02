//
//  TopBarView.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI

/// Top browser chrome housing traffic lights spacer, tab strip, or unified address bar in vertical tabs mode.
/// Seamlessly blends into the window canvas with zero bottom margin or divider lines.
struct TopBarView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore
    @State private var isEditingAddress: Bool = false
    @State private var addressText: String = ""
    @FocusState private var isAddressFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            if settings.isVerticalTabs {
                verticalModeBar
            } else {
                horizontalModeBar
            }
        }
        .frame(height: 50)
        .background {
            if settings.isVibrant {
                Color.clear
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            if let activeTab = store.activeTab {
                ProgressBarView(tab: activeTab)
            }
        }
    }

    @ViewBuilder
    private var horizontalModeBar: some View {
        WindowDragArea()
            .frame(width: 80, height: 50)

        TabStripView(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let activeTab = store.activeTab {
            NavigationControls(tab: activeTab, store: store, settings: settings)
                .padding(.trailing, 14)
        }
    }

    @ViewBuilder
    private var verticalModeBar: some View {
        HStack(spacing: 8) {
            if let activeTab = store.activeTab {
                // Navigation history buttons
                HStack(spacing: 2) {
                    Button(action: { activeTab.goBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(!activeTab.canGoBack)
                    .opacity(activeTab.canGoBack ? 1.0 : 0.35)
                    .help("Back (⌘[)")

                    Button(action: { activeTab.goForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(!activeTab.canGoForward)
                    .opacity(activeTab.canGoForward ? 1.0 : 0.35)
                    .help("Forward (⌘])")

                    Button(action: {
                        if activeTab.isLoading { activeTab.stopLoading() } else { activeTab.reload() }
                    }) {
                        Image(systemName: activeTab.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help(activeTab.isLoading ? "Stop Loading" : "Reload (⌘R)")
                }
                .padding(.leading, 8)

                // Omnibox Address Pill
                omniboxPill(tab: activeTab)
                    .frame(maxWidth: 520)

                // Free space window drag area (supports window dragging and double-click to zoom/fullscreen)
                WindowDragArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                NavigationControls(tab: activeTab, store: store, settings: settings)
                    .padding(.trailing, 14)
            } else {
                WindowDragArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func omniboxPill(tab: Tab) -> some View {
        HStack(spacing: 6) {
            if isEditingAddress {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)

                TextField("Search or enter web address", text: $addressText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isAddressFieldFocused)
                    .onChange(of: addressText) { _, newText in
                        store.omniboxText = newText
                    }
                    .onSubmit {
                        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            tab.load(text: trimmed)
                        }
                        isEditingAddress = false
                        store.isOmniboxEditing = false
                    }
                    .onExitCommand {
                        isEditingAddress = false
                        store.isOmniboxEditing = false
                    }

                Button(action: {
                    isEditingAddress = false
                    store.isOmniboxEditing = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: tab.url?.scheme == "https" ? "lock.fill" : (tab.isBlank ? "sparkles" : "globe"))
                        .font(.system(size: 10))
                        .foregroundStyle(tab.url?.scheme == "https" ? Color.secondary : Color.secondary.opacity(0.6))
                        .padding(.leading, 10)

                    Text(pillDisplayText(for: tab))
                        .font(.system(size: 12, weight: .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    addressText = tab.url?.absoluteString ?? ""
                    store.omniboxText = addressText
                    isEditingAddress = true
                    store.isOmniboxEditing = true
                    DispatchQueue.main.async {
                        isAddressFieldFocused = true
                    }
                }
            }
        }
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isEditingAddress ? settings.accentColor.opacity(0.4) : Color.primary.opacity(0.04), lineWidth: 1)
        )
        .onChange(of: isAddressFieldFocused) { _, focused in
            if !focused && isEditingAddress {
                isEditingAddress = false
                store.isOmniboxEditing = false
            }
        }
        .onChange(of: store.isAddressBarFocused) { _, focused in
            if focused {
                addressText = tab.url?.absoluteString ?? ""
                store.omniboxText = addressText
                isEditingAddress = true
                store.isOmniboxEditing = true
                store.isAddressBarFocused = false
                DispatchQueue.main.async {
                    isAddressFieldFocused = true
                }
            }
        }
    }

    private func pillDisplayText(for tab: Tab) -> String {
        if tab.isInternalPage {
            return "nomad://settings"
        }
        if let host = tab.url?.host, !host.isEmpty {
            let path = tab.url?.path ?? ""
            return host + (path == "/" ? "" : path)
        }
        return tab.isBlank ? "Search or enter address" : tab.title
    }
}

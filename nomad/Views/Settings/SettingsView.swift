//
//  SettingsView.swift
//  nomad
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Native developer-style Settings page (nomad://settings).
/// Focuses on browser configuration: Bookmarks, General preferences, and WebExtensions.
struct SettingsView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore

    var selectedSection: Section {
        get { Section(rawValue: settings.activeSection) ?? .general }
        nonmutating set { settings.activeSection = newValue.rawValue }
    }
    @State var hexInputText: String = ""
    @ObservedObject var updater = Updater.shared
    @ObservedObject var extensionManager = ExtensionManager.shared
    @ObservedObject var historyStore = HistoryStore.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @State var historySearchQuery: String = ""
    @State var showingClearHistoryAlert: Bool = false
    @State var hoveredOpenId: UUID? = nil
    @State var hoveredDeleteId: UUID? = nil
    @State var webStoreInput: String = ""
    @State var extensionErrorMessage: String? = nil
    @State var isInstallingExtension: Bool = false
    let searchEngines: [(id: String, label: String)] = [
        ("duckduckgo", "DuckDuckGo (Privacy)"),
        ("google", "Google"),
        ("kagi", "Kagi"),
        ("bing", "Bing")
    ]

    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case passwords = "Passwords"
        case history = "History"
        case bookmarks = "Bookmarks"
        case downloads = "Downloads"
        case extensions = "Extensions"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .passwords: return "key.fill"
            case .history: return "clock.arrow.circlepath"
            case .bookmarks: return "bookmark"
            case .downloads: return "arrow.down.circle"
            case .extensions: return "puzzlepiece.extension"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Navigation Rail
            sidebarRail
                .frame(width: 180)

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(width: 1)

            // Right Main Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    switch selectedSection {
                    case .general:
                        generalSection
                    case .passwords:
                        passwordsSection
                    case .history:
                        historySection
                    case .bookmarks:
                        bookmarksSection
                    case .downloads:
                        downloadsSection
                    case .extensions:
                        extensionsSection
                    }
                }
                .padding(32)
                .frame(maxWidth: 680, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.colorScheme)
        .tint(settings.accentColor)
        .onAppear {
            hexInputText = settings.customBgHex.replacingOccurrences(of: "#", with: "")
        }
    }

    // MARK: - Sidebar Rail
    private var sidebarRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ForEach(Section.allCases) { section in
                Button(action: { selectedSection = section }) {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 16)
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: selectedSection == section ? .medium : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedSection == section ? Color.primary.opacity(0.08) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }

            Spacer()

            Text("nomad://settings")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
                .padding(16)
        }
    }

    // MARK: - Bookmarks Section

    func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

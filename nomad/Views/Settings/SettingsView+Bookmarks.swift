//
//  SettingsView+Bookmarks.swift
//  nomad
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Bookmarks Heading with Import Button on the right
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bookmarks")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Manage saved links or import existing bookmarks from Chrome, Firefox, or Safari.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { settings.promptBringThingsOver() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Import")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Import bookmarks from Chrome, Firefox, or Safari (HTML or JSON)")
            }

            // Bookmarks List
            card(title: "Saved Bookmarks (\(settings.bookmarks.count))") {
                if settings.bookmarks.isEmpty {
                    Text("No bookmarks saved yet. Save pages using the bookmark icon in the top bar or import from another browser.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(settings.bookmarks) { bookmark in
                            HStack {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(settings.accentColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(bookmark.url)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Open") {
                                    store.openBookmark(bookmark)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(settings.accentColor)
                                .padding(.horizontal, 8)

                                Button(action: { settings.removeBookmark(id: bookmark.id) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Delete bookmark")
                            }
                            .padding(.vertical, 8)

                            if bookmark.id != settings.bookmarks.last?.id {
                                Divider().opacity(0.1)
                            }
                        }
                    }
                }
            }
        }
    }
}

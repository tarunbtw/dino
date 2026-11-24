//
//  SettingsView+Bookmarks.swift
//  dino
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
                header(title: "Bookmarks", subtitle: "")

                Spacer()

                Button(action: { settings.promptBringThingsOver() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Import")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Import bookmarks (HTML or JSON)")
            }

            // Bookmarks List
            card(title: "Saved (\(settings.bookmarks.count))") {
                if settings.bookmarks.isEmpty {
                    Text("No bookmarks yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(settings.bookmarks) { bookmark in
                            HStack {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.ink)
                                    Text(bookmark.url)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.muted)
                                }

                                Spacer()

                                Button("Open") {
                                    store.openBookmark(bookmark)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 8)

                                Button(action: { settings.removeBookmark(id: bookmark.id) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.faint)
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

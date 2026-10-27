//
//  SettingsView+Downloads.swift
//  nomad
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit

extension SettingsView {
    var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "Downloads", subtitle: "Manage downloaded files.")

            // Downloads List Card
            card(title: "Recent Downloads (\(downloadManager.downloads.count))") {
                if downloadManager.downloads.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.top, 8)
                        Text("No downloaded files yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button("Clear All") {
                                downloadManager.clearCompleted()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 8)

                        ForEach(downloadManager.downloads) { item in
                            downloadSettingsRow(item: item)
                            if item.id != downloadManager.downloads.last?.id {
                                Divider().opacity(0.1).padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
        }
    }

    private func downloadSettingsRow(item: DownloadItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconName)
                .font(.system(size: 20))
                .foregroundStyle(item.statusColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.suggestedFilename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.state.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(item.statusColor)

                    if !item.formattedSize.isEmpty {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(item.formattedSize)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if let err = item.errorMessage {
                        Text("— \(err)")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if item.state == .downloading {
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 80)

                Button(action: { item.cancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if item.state == .completed {
                Button("Open") {
                    downloadManager.openFile(item)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Finder") {
                    downloadManager.showInFinder(item)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(action: { downloadManager.removeDownload(item) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from history")
        }
        .padding(.vertical, 4)
    }

    // MARK: - General Section

}

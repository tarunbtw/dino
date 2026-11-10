//
//  DownloadsButton.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//

import SwiftUI
import AppKit

/// Frosted Downloads button with circular progress ring and popover file inspector.
struct DownloadsButton: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var downloadManager = DownloadManager.shared

    @State private var isShowingPopover = false
    @State private var isHovering = false

    private var activeDownloads: [DownloadItem] {
        downloadManager.downloads.filter { $0.state == .downloading }
    }

    private var overallProgress: Double {
        let active = activeDownloads
        guard !active.isEmpty else { return 0 }
        let total = active.reduce(0.0) { $0 + $1.progress }
        return total / Double(active.count)
    }

    var body: some View {
        let hasDownloads = !downloadManager.downloads.isEmpty
        let isDownloading = !activeDownloads.isEmpty

        Group {
            if hasDownloads {
                Button {
                    isShowingPopover.toggle()
                } label: {
                    ZStack {
                        // Background
                        Circle()
                            .fill(isHovering ? Theme.hover : Color.clear)
                            .frame(width: 28, height: 28)

                        // Circular Progress Ring when downloading
                        if isDownloading {
                            Circle()
                                .stroke(Theme.activeTabHairline, lineWidth: 2)
                                .frame(width: 22, height: 22)

                            Circle()
                                .trim(from: 0, to: CGFloat(max(0.05, overallProgress)))
                                .stroke(
                                    Theme.spaceColor(store.activeSpace.colorHex),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 22, height: 22)
                        }

                        // Arrow Icon
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isHovering || isDownloading ? Theme.ink : Theme.faint)
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help("Downloads")
                .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
                    DownloadsPopoverPanel(store: store, downloadManager: downloadManager)
                }
                .transition(.opacity)
            }
        }
    }
}

/// Glass popover panel displaying recently downloaded files with open, reveal, and clear controls.
private struct DownloadsPopoverPanel: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var downloadManager: DownloadManager

    var body: some View {
        let downloads = downloadManager.downloads.prefix(15)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Downloads")
                    .font(Theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Spacer()

                Button("Clear List") {
                    downloadManager.clearCompleted()
                }
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.faint)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            // Downloads List
            if downloads.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.faint)
                    Text("No recent downloads")
                        .font(Theme.font(size: 12))
                        .foregroundStyle(Theme.faint)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(Array(downloads), id: \.id) { item in
                            DownloadRow(item: item)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 300)
        .background {
            shape.fill(Theme.page)
        }
        .clipShape(shape)
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        HStack(spacing: 8) {
            // File Icon
            Image(systemName: item.iconName)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: 24)

            // Name and Details
            VStack(alignment: .leading, spacing: 1) {
                Text(item.suggestedFilename)
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.formattedSize)
                    .font(Theme.font(size: 10.5))
                    .foregroundStyle(Theme.faint)
            }

            Spacer(minLength: 4)

            // Reveal in Finder Button
            if let dest = item.destinationURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(isHovering ? Theme.ink : Theme.faint)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovering ? Theme.hover : Color.clear, in: shape)
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            if let dest = item.destinationURL {
                NSWorkspace.shared.open(dest)
            }
        }
    }
}

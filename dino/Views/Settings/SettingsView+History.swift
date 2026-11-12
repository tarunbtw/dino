//
//  SettingsView+History.swift
//  dino
//
//  Created by tarun on 11/10/26.
//

import SwiftUI

extension SettingsView {
    var historySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // History Header & Clear Action
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Sites you've visited across tabs and browsing sessions.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !historyStore.items.isEmpty {
                    Button(action: { showingClearHistoryAlert = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Clear History")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Clear Browsing History?", isPresented: $showingClearHistoryAlert, titleVisibility: .visible) {
                        Button("Clear All History", role: .destructive) {
                            historyStore.clear()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove all \(historyStore.items.count) visited pages from local history.")
                    }
                }
            }

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Search history by title or domain...", text: $historySearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !historySearchQuery.isEmpty {
                    Button(action: { historySearchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Date Groups List
            let groups = historyStore.grouped(matching: historySearchQuery)

            if groups.isEmpty {
                emptyHistoryView
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            // Date Section Header
                            HStack {
                                Text(group.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text("\(group.items.count) visit\(group.items.count == 1 ? "" : "s")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 2)

                            // Group Items Container Card
                            VStack(spacing: 0) {
                                ForEach(group.items) { item in
                                    historyRow(item: item)
                                    if item.id != group.items.last?.id {
                                        Divider().opacity(0.08)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private func historyRow(item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            // Localized Time (e.g. 18:30)
            Text(formattedTime(for: item.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .leading)

            // Favicon or Globe
            if let cached = FaviconService.shared.cachedFavicon(for: item.host) {
                Image(nsImage: cached)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }

            // Title & Domain (clickable to open)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.host.isEmpty ? item.url : item.host)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: item.url) {
                    store.newTab(url: url, select: true)
                }
            }

            Spacer()

            // Open Action
            Button(action: {
                if let url = URL(string: item.url) {
                    store.newTab(url: url, select: true)
                }
            }) {
                Text("Open")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(settings.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        hoveredOpenId == item.id ? settings.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .onHover { isHovered in
                hoveredOpenId = isHovered ? item.id : nil
            }

            // Delete Visit Record Action
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    historyStore.removeItem(id: item.id)
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hoveredDeleteId == item.id ? .primary : .tertiary)
                    .frame(width: 20, height: 20)
                    .background(
                        hoveredDeleteId == item.id ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                hoveredDeleteId = isHovered ? item.id : nil
            }
            .help("Remove from history")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open in New Tab") {
                if let url = URL(string: item.url) {
                    store.newTab(url: url, select: true)
                }
            }
            Button("Copy Link Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url, forType: .string)
            }
            Divider()
            Button("Delete from History", role: .destructive) {
                historyStore.removeItem(id: item.id)
            }
        }
    }

    private func formattedTime(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Image(systemName: historySearchQuery.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.top, 24)

            Text(historySearchQuery.isEmpty ? "No Browsing History" : "No Matching Results")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(
                historySearchQuery.isEmpty
                    ? "Websites you visit in regular browsing will appear here, grouped by date."
                    : "No visits matched \"\(historySearchQuery)\". Try searching by another keyword or host."
            )
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Extensions Section

}

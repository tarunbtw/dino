//
//  ArcImportModal.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//  In-process glass modal displaying detected Arc spaces and 1-click import.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ArcImportModal: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool

    @State private var stage: ArcImportService.Stage = .notFound
    @State private var isChoosingFile: Bool = false
    @State private var isImporting: Bool = false

    init(store: BrowserStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import from Arc")
                        .font(Theme.panelTitleFont)
                        .foregroundStyle(Theme.ink)

                    Text("Bring over your Arc spaces, pinned tabs, and favorites.")
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 24, height: 24)
                        .background(Theme.hover, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Theme.activeTabHairline)

            // Content Stage
            Group {
                switch stage {
                case .notFound:
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.folder")
                                .font(.system(size: 24))
                                .foregroundStyle(Theme.muted)

                            Text("Arc wasn't found in your standard Library folder.")
                                .font(Theme.tabFont)
                                .foregroundStyle(Theme.ink)
                        }

                        Text("If you keep Arc in another location or have a backup of StorableSidebar.json, you can select it directly.")
                            .font(Theme.hintFont)
                            .foregroundStyle(Theme.muted)

                        Button("Choose StorableSidebar.json…") {
                            isChoosingFile = true
                        }
                        .buttonStyle(.plain)
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Theme.press, in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
                    }

                case .problem(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(message)
                                .font(Theme.tabFont)
                                .foregroundStyle(Theme.ink)
                        }

                        Button("Choose Another File…") {
                            isChoosingFile = true
                        }
                        .buttonStyle(.plain)
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.muted)
                    }

                case .ready(let plan):
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Found \(plan.spaces.count) spaces with \(plan.tabCount) tabs & favorites:")
                            .font(Theme.labelFont)
                            .foregroundStyle(Theme.muted)

                        VStack(spacing: 6) {
                            ForEach(plan.spaces.prefix(6), id: \.name) { space in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Theme.frost)
                                        .frame(width: 8, height: 8)

                                    Text(space.name)
                                        .font(Theme.tabFont)
                                        .foregroundStyle(Theme.ink)

                                    Spacer()

                                    Text("\(space.basecamp.count + space.groups.reduce(0) { $0 + $1.sites.count }) tabs")
                                        .font(Theme.hintFont)
                                        .foregroundStyle(Theme.faint)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            if plan.spaces.count > 6 {
                                Text("and \(plan.spaces.count - 6) more spaces…")
                                    .font(Theme.hintFont)
                                    .foregroundStyle(Theme.faint)
                                    .padding(.leading, 18)
                            }
                        }

                        HStack {
                            Spacer()

                            Button(action: {
                                isPresented = false
                            }) {
                                Text("Cancel")
                                    .font(Theme.tabFont)
                                    .foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 14)
                                    .frame(height: 32)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                isImporting = true
                                ArcImportService.shared.apply(plan: plan, into: store)
                                stage = .done(spaceCount: plan.spaces.count, tabCount: plan.tabCount)
                                isImporting = false
                            }) {
                                HStack(spacing: 6) {
                                    if isImporting {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text("Import All to Nomad")
                                        .font(Theme.tabFont)
                                        .foregroundStyle(Theme.ink)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 32)
                                .background(Theme.spaceColor(store.activeSpace.colorHex), in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isImporting)
                        }
                    }

                case .done(let spaceCount, let tabCount):
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Theme.frost)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import Complete")
                                    .font(Theme.groupHeaderFont)
                                    .foregroundStyle(Theme.ink)

                                Text("Added \(spaceCount) spaces and \(tabCount) tabs into your sidebar.")
                                    .font(Theme.hintFont)
                                    .foregroundStyle(Theme.muted)
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Done") {
                                isPresented = false
                            }
                            .buttonStyle(.plain)
                            .font(Theme.tabFont)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 20)
                            .frame(height: 32)
                            .background(Theme.press, in: RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
            CommandBarGlass(shape: shape, color: Theme.spaceColor(store.activeSpace.colorHex))
                .clipShape(shape)
                .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
                .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
        }
        .task {
            stage = await ArcImportService.shared.readArc()
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            Task {
                stage = await ArcImportService.shared.read(url)
            }
        }
    }
}

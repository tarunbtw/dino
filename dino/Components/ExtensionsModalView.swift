//
//  ExtensionsModalView.swift
//  dino
//
//  Firn-style centered modal command bar for extensions (⌘E).
//  Follows the exact card geometry, typography, and simplicity of OmniboxModalView.
//

import SwiftUI
import AppKit
import WebKit

struct ExtensionsModalView: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool

    @ObservedObject private var manager = ExtensionManager.shared
    @State private var text: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFieldFocused: Bool

    private var filteredExtensions: [InstalledExtension] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return manager.installed
        }
        return manager.installed.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        let items = filteredExtensions
        let totalCount = items.count + 2 // extensions + 2 action items (Manage & Web Store)

        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Dimming backdrop
                Theme.commandDim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }

                // Centered modal card matching OmniboxModalView
                VStack(spacing: 0) {
                    // Search Field
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)

                        TextField("Search extensions", text: $text)
                            .textFieldStyle(.plain)
                            .font(Theme.font(size: 16))
                            .foregroundStyle(Theme.ink)
                            .focused($isFieldFocused)
                            .onSubmit { submit(items: items) }
                            .onExitCommand { dismiss() }
                            .onChange(of: text) {
                                selectedIndex = 0
                            }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)

                    Rectangle()
                        .fill(Theme.activeTabHairline)
                        .frame(height: 0.5)
                        .padding(.horizontal, 12)

                    // Rows List
                    VStack(spacing: 2) {
                        if items.isEmpty && !manager.installed.isEmpty {
                            // Filter had no match
                            HStack(spacing: 10) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 14))
                                    .frame(width: 16, height: 16)
                                    .foregroundStyle(Theme.faint)

                                Text("No matching extensions")
                                    .font(Theme.tabFont)
                                    .foregroundStyle(Theme.faint)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                        } else if manager.installed.isEmpty {
                            // No extensions installed
                            HStack(spacing: 10) {
                                Image(systemName: "puzzlepiece.extension")
                                    .font(.system(size: 14))
                                    .frame(width: 16, height: 16)
                                    .foregroundStyle(Theme.faint)

                                Text("No extensions installed")
                                    .font(Theme.tabFont)
                                    .foregroundStyle(Theme.faint)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                        }

                        // Installed Extensions Rows
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, ext in
                            let isSelected = index == selectedIndex
                            extensionRow(ext: ext, isSelected: isSelected, index: index)
                        }

                        // Action 1: Manage Extensions in Settings
                        let manageIndex = items.count
                        actionRow(
                            icon: "gearshape",
                            title: "Manage Extensions…",
                            hint: "⌘,",
                            isSelected: selectedIndex == manageIndex,
                            index: manageIndex
                        ) {
                            dismiss()
                            store.openSettings(section: "Extensions")
                        }

                        // Action 2: Open Chrome Web Store
                        let storeIndex = items.count + 1
                        actionRow(
                            icon: "arrow.down.circle",
                            title: "Open Chrome Web Store",
                            hint: "Web Store",
                            isSelected: selectedIndex == storeIndex,
                            index: storeIndex
                        ) {
                            dismiss()
                            store.newTab(url: URL(string: "https://chromewebstore.google.com")!, select: true)
                        }
                    }
                    .padding(6)
                }
                .frame(width: min(560, max(0, proxy.size.width - 64)))
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.page)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.activeTabHairline, lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 24, y: 8)
                .shadow(color: Color.black.opacity(0.20), radius: 3, y: 1)
                .padding(.top, max(48, proxy.size.height * 0.22))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background {
            ArrowCatcher { offset in
                guard totalCount > 0 else { return }
                selectedIndex = min(max(selectedIndex + offset, 0), totalCount - 1)
            }
        }
        .onAppear {
            selectedIndex = 0
            text = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
        .onMoveCommand { direction in
            guard totalCount > 0 else { return }
            switch direction {
            case .up:
                selectedIndex = max(0, selectedIndex - 1)
            case .down:
                selectedIndex = min(totalCount - 1, selectedIndex + 1)
            default:
                break
            }
        }
    }

    // MARK: - Extension Row
    @ViewBuilder
    private func extensionRow(ext: InstalledExtension, isSelected: Bool, index: Int) -> some View {
        let context = manager.contexts[ext.id]
        let action = context?.action(for: nil)

        Button(action: {
            activate(ext)
        }) {
            HStack(spacing: 10) {
                if let nsImage = action?.icon(for: CGSize(width: 16, height: 16)) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 14))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(ext.enabled ? Theme.muted : Theme.faint)
                }

                Text(ext.name)
                    .font(Theme.font(size: 13))
                    .foregroundStyle(ext.enabled ? Theme.ink : Theme.muted)
                    .lineLimit(1)

                Spacer(minLength: 12)

                // Pin / Unpin button
                Button(action: {
                    manager.togglePinned(id: ext.id)
                }) {
                    Image(systemName: ext.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(ext.pinned ? Theme.ink : Theme.faint)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(ext.pinned ? "Unpin from toolbar" : "Pin to toolbar")

                // Enable / Disable switch
                Toggle("", isOn: Binding(
                    get: { ext.enabled },
                    set: { _ in manager.toggleEnabled(id: ext.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.press : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHover in
            if isHover { selectedIndex = index }
        }
        .contextMenu {
            if ext.optionsPath != nil {
                Button("Options") {
                    dismiss()
                    manager.openOptionsPage(for: ext.id)
                }
            }
            Button(ext.pinned ? "Unpin from Toolbar" : "Pin to Toolbar") {
                manager.togglePinned(id: ext.id)
            }
            Divider()
            Button(ext.enabled ? "Disable" : "Enable") {
                manager.toggleEnabled(id: ext.id)
            }
            Button("Remove Extension", role: .destructive) {
                manager.remove(id: ext.id)
            }
        }
    }

    // MARK: - Action Row
    @ViewBuilder
    private func actionRow(icon: String, title: String, hint: String, isSelected: Bool, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.muted)

                Text(title)
                    .font(Theme.font(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if !hint.isEmpty {
                    Text(hint)
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.press : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHover in
            if isHover { selectedIndex = index }
        }
    }

    private func submit(items: [InstalledExtension]) {
        if selectedIndex < items.count {
            activate(items[selectedIndex])
        } else if selectedIndex == items.count {
            dismiss()
            store.openSettings(section: "Extensions")
        } else if selectedIndex == items.count + 1 {
            dismiss()
            store.newTab(url: URL(string: "https://chromewebstore.google.com")!, select: true)
        }
    }

    private func activate(_ ext: InstalledExtension) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            manager.activate(ext.id)
        }
    }

    private func dismiss() {
        isPresented = false
        store.isShowingExtensionsModal = false
    }
}

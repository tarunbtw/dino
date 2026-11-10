//
//  TabGroupCardView.swift
//  nomad
//
//  Foldable Tab Group Card ported from Firn's sidebar tab groups.
//  Keeps intentional collections together; immune to tab drift.
//

import SwiftUI

struct TabGroupCardView: View {
    @ObservedObject var store: BrowserStore
    let group: TabGroup

    @State private var isHoveringHeader = false
    @State private var draft: String = ""
    @FocusState private var isFieldFocused: Bool

    private var isRenaming: Bool {
        store.renamingGroupId == group.id
    }

    var body: some View {
        let memberTabs = store.tabs(in: group)
        VStack(spacing: 2) {
            // Group Header
            HStack(spacing: 6) {
                // Smooth rotating fold chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .rotationEffect(.degrees(group.isFolded ? -90 : 0))
                    .frame(width: 14, height: 14)
                    .animation(.spring(response: 0.22, dampingFraction: 0.88), value: group.isFolded)

                if isRenaming {
                    TextField("Group Name", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Theme.groupHeaderFont)
                        .foregroundStyle(Theme.ink)
                        .focused($isFieldFocused)
                        .onSubmit {
                            store.renameGroup(id: group.id, name: draft)
                        }
                        .onExitCommand {
                            store.renamingGroupId = nil
                        }
                        .onChange(of: isFieldFocused) { _, focused in
                            if !focused {
                                store.renameGroup(id: group.id, name: draft)
                            }
                        }
                        .onAppear {
                            draft = group.name
                            isFieldFocused = true
                        }
                } else {
                    Text(group.name)
                        .font(Theme.groupHeaderFont)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Close Group Button on Hover, or Tab Count Badge
                if isHoveringHeader && !isRenaming {
                    Button(action: {
                        store.removeGroup(id: group.id)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Close Group")
                } else if group.isFolded {
                    // Tab Count Badge when folded
                    Text("\(memberTabs.count)")
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.faint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.hover, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isHoveringHeader && !isRenaming ? Theme.hover.opacity(0.8) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if !isRenaming {
                    store.toggleFoldGroup(id: group.id)
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    draft = group.name
                    store.renamingGroupId = group.id
                }
            )
            .onHover { isHoveringHeader = $0 }
            .contextMenu {
                Button("Rename Group", systemImage: "pencil") {
                    draft = group.name
                    store.renamingGroupId = group.id
                }
                Button("New Tab in Group", systemImage: "plus") {
                    let tab = store.newTab(url: nil, select: true)
                    tab.groupId = group.id
                    store.isAddressBarFocused = true
                }
                Divider()
                Button("Ungroup", systemImage: "rectangle.stack.badge.minus") {
                    store.removeGroup(id: group.id)
                }
                Button("Close Group", systemImage: "trash", role: .destructive) {
                    for tab in memberTabs {
                        store.closeTab(id: tab.id)
                    }
                    store.removeGroup(id: group.id)
                }
            }

            // Member Tabs (shown only when not folded)
            if !group.isFolded {
                VStack(spacing: Theme.rowSpacing) {
                    ForEach(memberTabs) { tab in
                        VerticalTabRowView(
                            store: store,
                            tab: tab,
                            isActive: tab.id == store.activeTabId,
                            isDragging: false,
                            offsetY: 0,
                            onDragChanged: { _ in },
                            onDragEnded: { _ in }
                        )
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.hover.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.activeTabHairline.opacity(0.35), lineWidth: 0.5)
        )
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: group.isFolded)
    }
}

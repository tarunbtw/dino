//
//  OverflowButton.swift
//  nomad
//
//  Ported from Firn's Overflow / Archive Box:
//  Subtle button in the space bar that holds tidied-away tabs.
//

import SwiftUI

struct OverflowButton: View {
    @ObservedObject var store: BrowserStore
    @State private var showsPopover: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        let drifted = store.driftedTabs
        let unseen = store.hasUnseenTidied

        if !drifted.isEmpty {
            Button(action: {
                showsPopover.toggle()
            }) {
                ZStack(alignment: .topTrailing) {
                    ArchiveBoxIcon(lidOpen: showsPopover || isHovering)
                        .frame(width: 22, height: 22)
                        .padding(4)
                        .background(isHovering ? Theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    // Unseen notification dot in active space color
                    if unseen {
                        Circle()
                            .fill(Theme.spaceColor(store.activeSpace.colorHex))
                            .frame(width: 6, height: 6)
                            .offset(x: 1, y: 1)
                            .transition(.opacity)
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("Tidied tabs (\(drifted.count))")
            .popover(isPresented: $showsPopover, arrowEdge: .top) {
                OverflowPanel(store: store, isPresented: $showsPopover)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Animated Archive Box Icon
struct ArchiveBoxIcon: View {
    var lidOpen: Bool = false

    var body: some View {
        ZStack {
            BoxShape()
                .stroke(Theme.muted, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            LidShape()
                .stroke(Theme.muted, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(lidOpen ? -28 : 0), anchor: LidShape.hinge)
                .animation(.spring(response: 0.32, dampingFraction: 0.7), value: lidOpen)
        }
        .frame(width: 18, height: 18)
    }
}

private struct BoxShape: Shape {
    func path(in rect: CGRect) -> Path {
        Self.path.applying(fitGrid(rect))
    }

    private static let path: Path = {
        var path = Path()
        for data in [
            "M5.5 9.5v8a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2v-8",
            "M10 13.5h4"
        ] {
            path.addPath(Path(SVGPath.cgPath(data)))
        }
        return path
    }()
}

private struct LidShape: Shape {
    static let hinge = UnitPoint(x: 19 / 24, y: 9.5 / 24)

    func path(in rect: CGRect) -> Path {
        Self.path.applying(fitGrid(rect))
    }

    private static let path = Path(SVGPath.cgPath("M5.5 4.5h13a1.5 1.5 0 0 1 1.5 1.5v3.5H4V6a1.5 1.5 0 0 1 1.5-1.5Z"))
}

private func fitGrid(_ rect: CGRect) -> CGAffineTransform {
    let scale = min(rect.width, rect.height) / 24
    return CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
        .scaledBy(x: scale, y: scale)
}

// MARK: - Overflow Panel Popover
private struct OverflowPanel: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool

    var body: some View {
        let drifted = store.driftedTabs
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tidied away")
                        .font(Theme.groupHeaderFont)
                        .foregroundStyle(Theme.ink)

                    Text("Tabs you haven’t looked at in 12 hours.")
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.muted)
                }

                Spacer(minLength: 8)

                Button("Restore All") {
                    store.restoreAllDrifted()
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(Theme.hintFont)
                .foregroundStyle(Theme.frost)
            }
            .padding(.bottom, 4)

            Divider()
                .background(Theme.activeTabHairline)

            // Drifted Tab Rows
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 4) {
                    ForEach(drifted) { tab in
                        DriftedRowView(tab: tab, onRestore: {
                            store.restoreDrifted(tab: tab)
                            if store.driftedTabs.isEmpty {
                                isPresented = false
                            }
                        }, onClose: {
                            store.closeTab(id: tab.id)
                            if store.driftedTabs.isEmpty {
                                isPresented = false
                            }
                        })
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(14)
        .frame(width: 290)
        .background(Theme.frame)
        .onAppear {
            store.markTidiedSeen()
        }
    }
}

private struct DriftedRowView: View {
    @ObservedObject var tab: Tab
    let onRestore: () -> Void
    let onClose: () -> Void
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onRestore) {
                HStack(spacing: 8) {
                    if let favicon = tab.favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 14, height: 14)
                    }

                    Text(tab.title.isEmpty ? (tab.url?.host ?? "Tab") : tab.title)
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovering ? Theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovering = $0 }
    }
}


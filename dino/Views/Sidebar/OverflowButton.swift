//
//  OverflowButton.swift
//  dino
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
        var p = Path()
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        p.move(to: pt(5.5, 9.5))
        p.addLine(to: pt(5.5, 17.5))
        p.addQuadCurve(to: pt(7.5, 19.5), control: pt(5.5, 19.5))
        p.addLine(to: pt(16.5, 19.5))
        p.addQuadCurve(to: pt(18.5, 17.5), control: pt(18.5, 19.5))
        p.addLine(to: pt(18.5, 9.5))

        p.move(to: pt(10, 13.5))
        p.addLine(to: pt(14, 13.5))
        return p
    }
}

private struct LidShape: Shape {
    static let hinge = UnitPoint(x: 19 / 24, y: 9.5 / 24)

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        p.move(to: pt(5.5, 4.5))
        p.addLine(to: pt(18.5, 4.5))
        p.addQuadCurve(to: pt(20, 6), control: pt(20, 4.5))
        p.addLine(to: pt(20, 9.5))
        p.addLine(to: pt(4, 9.5))
        p.addLine(to: pt(4, 6))
        p.addQuadCurve(to: pt(5.5, 4.5), control: pt(4, 4.5))
        p.closeSubpath()
        return p
    }
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


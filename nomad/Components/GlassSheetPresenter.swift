//
//  GlassSheetPresenter.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//  In-process frosted glass modals replacing macOS native sheet auxiliary windows.
//  Shares space tint, continuous curvature, and avoids window detaching.
//

import SwiftUI
import AppKit
import Combine

/// In-process glass sheet presenter.
@MainActor
final class GlassSheetPresenter: ObservableObject {
    struct Shown {
        let id: AnyHashable
        let content: AnyView
        let onDismiss: () -> Void
    }

    @Published fileprivate(set) var shown: Shown?
    @Published fileprivate(set) var colorHex: String = "#7F9CB0"

    func show(_ sheet: Shown) {
        shown = sheet
    }

    func close(_ id: AnyHashable? = nil) {
        guard let current = shown, id == nil || current.id == id else { return }
        shown = nil
        current.onDismiss()
    }
}

/// Closure delivered via environment for dismissing an in-process glass sheet.
struct DismissGlassSheet: Sendable {
    fileprivate var action: @MainActor () -> Void = {}
    @MainActor func callAsFunction() {
        action()
    }
}

private struct DismissGlassSheetKey: EnvironmentKey {
    static let defaultValue = DismissGlassSheet()
}

extension EnvironmentValues {
    var dismissGlassSheet: DismissGlassSheet {
        get { self[DismissGlassSheetKey.self] }
        set { self[DismissGlassSheetKey.self] = newValue }
    }
}

extension View {
    /// Mounts the GlassSheetPresenter in the environment with space color tinting.
    func glassSheetHost(colorHex: String) -> some View {
        modifier(GlassSheetHostModifier(colorHex: colorHex))
    }

    /// Presents content as an in-process glass sheet while `item` is non-nil.
    func glassSheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        modifier(GlassSheetModifier(item: item, onDismiss: onDismiss, sheet: content))
    }
}

private struct GlassSheetHostModifier: ViewModifier {
    let colorHex: String
    @StateObject private var presenter = GlassSheetPresenter()

    func body(content: Content) -> some View {
        content
            .environmentObject(presenter)
            .onChange(of: colorHex) { _, newHex in
                presenter.colorHex = newHex
            }
            .onAppear {
                presenter.colorHex = colorHex
            }
    }
}

private struct GlassSheetModifier<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let sheet: (Item) -> Sheet

    @EnvironmentObject private var presenter: GlassSheetPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id) { oldId, newId in
                if let old = oldId, old != newId {
                    presenter.close(AnyHashable(old))
                }
                guard let currentItem = item, let id = newId else { return }
                let hashableId = AnyHashable(id)
                let dismissAction = DismissGlassSheet {
                    presenter.close(hashableId)
                }
                let sheetView = sheet(currentItem).environment(\.dismissGlassSheet, dismissAction)
                presenter.show(GlassSheetPresenter.Shown(
                    id: hashableId,
                    content: AnyView(sheetView),
                    onDismiss: {
                        if self.item?.id == id {
                            self.item = nil
                        }
                        onDismiss?()
                    }
                ))
            }
    }
}

/// Dense frosted glass backdrop with space tint and hairline rim.
struct CommandBarGlass: View {
    let shape: RoundedRectangle
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            shape.fill(Theme.page)
                .overlay { shape.fill(color.opacity(0.18)) }
                .overlay { shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5) }
        } else {
            shape.fill(.regularMaterial)
                .overlay { shape.fill(Theme.commandVeil) }
                .overlay { shape.fill(color.opacity(0.18)) }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .overlay { shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5) }
        }
    }
}

/// Frosted backdrop and container card rendered within the host window.
struct GlassSheetLayer: View {
    var cornerRadius: CGFloat = 0
    @EnvironmentObject private var presenter: GlassSheetPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(cornerRadius: CGFloat = 0) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            if let sheet = presenter.shown {
                // Dimmed translucent backdrop absorbing clicks
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.commandDim)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                    .transition(.opacity)

                GlassCard(colorHex: presenter.colorHex) {
                    sheet.content
                }
                .id(sheet.id)
                .padding(24)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: presenter.shown?.id)
    }
}

/// Styled frosted glass card container with space tint and dual soft shadows.
struct GlassCard<Content: View>: View {
    let colorHex: String
    @ViewBuilder let content: Content

    init(colorHex: String, @ViewBuilder content: () -> Content) {
        self.colorHex = colorHex
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        content
            .background {
                CommandBarGlass(shape: shape, color: Theme.spaceColor(colorHex))
            }
            .clipShape(shape)
            .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
            .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}

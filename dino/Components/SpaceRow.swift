//
//  SpaceRow.swift
//  dino
//
//  HeroUI Space switcher capsule paired with deterministic Blobatar avatars.
//

import SwiftUI
import AppKit

/// Deterministic Blobatar character avatar tinted to a Space's configured color hue.
struct BlobatarAvatar: View {
    let seed: String
    let colorHex: String
    var size: CGFloat = 20
    var animated: Bool = false

    private var derivedHue: Double? {
        let clean = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let val = UInt32(clean, radix: 16) else { return nil }
        let nsColor = NSColor(hex: val).usingColorSpace(.sRGB) ?? NSColor(hex: val)
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        var alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        return sat >= 0.08 ? Double(hue * 360.0) : nil
    }

    var body: some View {
        BlobatarView(
            seed: seed,
            hue: derivedHue,
            size: Double(size),
            background: false,
            animation: animated ? .always : .hover
        )
        .frame(width: size, height: size)
    }
}

struct SpaceRow: View {
    @ObservedObject var store: BrowserStore
    @State private var isHovering = false
    @State private var isShowingSpaces = false

    var body: some View {
        let space = store.activeSpace

        HStack(spacing: 4) {
            Button {
                isShowingSpaces.toggle()
            } label: {
                HStack(spacing: 7) {
                    BlobatarAvatar(
                        seed: space.id.uuidString,
                        colorHex: space.colorHex,
                        size: 20
                    )

                    Text(space.name)
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.leading, 6)
                .padding(.trailing, 10)
                .frame(height: 30)
                .background(isHovering || isShowingSpaces ? Theme.surfaceHover : Theme.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(isHovering || isShowingSpaces ? Theme.borderHover : Theme.border, lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .help("Switch Space")
            .popover(isPresented: $isShowingSpaces, arrowEdge: .top) {
                SpacesPopoverPanel(store: store, isPresented: $isShowingSpaces)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpacesPopoverPanel: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool
    @State private var hoveredRowId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, s in
                let isSelected = s.id == store.activeSpaceId
                let rowId = s.id.uuidString
                Button {
                    store.switchSpace(id: s.id)
                    isPresented = false
                } label: {
                    HStack(spacing: 9) {
                        BlobatarAvatar(
                            seed: rowId,
                            colorHex: s.colorHex,
                            size: 20
                        )

                        Text(s.name)
                            .font(Theme.font(size: 12.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)

                        Spacer(minLength: 16)

                        if index < 9 {
                            Text("⌃\(index + 1)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                        }

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Theme.surfaceHover : (hoveredRowId == rowId ? Theme.hover : Color.clear))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredRowId = $0 ? rowId : (hoveredRowId == rowId ? nil : hoveredRowId) }
            }

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.vertical, 4)

            popoverAction(id: "new-space", icon: "plus", title: "New Space…") {
                isPresented = false
                store.isShowingNewSpaceSheet = true
            }

            popoverAction(id: "space-settings", icon: "slider.horizontal.3", title: "Space Settings…") {
                isPresented = false
                store.openSettings(section: "Spaces")
            }
        }
        .padding(8)
        .frame(width: 216)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }

    private func popoverAction(id: String, icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)

                Text(title)
                    .font(Theme.font(size: 12.5, weight: .regular))
                    .foregroundStyle(Theme.ink)

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hoveredRowId == id ? Theme.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredRowId = $0 ? id : (hoveredRowId == id ? nil : hoveredRowId) }
    }
}

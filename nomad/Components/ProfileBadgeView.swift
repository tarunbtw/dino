//
//  ProfileBadgeView.swift
//  nomad
//
//  Created by tarun on 11/10/26.
//

import SwiftUI

/// Profile badge button that sits in the vertical sidebar foot.
/// Clicking it presents a popover with profile names and color dots.
/// Selecting a color immediately transforms the profile badge to that color.
struct ProfileBadgeView: View {
    @ObservedObject var settings: SettingsStore
    @State private var isShowingMenu: Bool = false
    @State private var isHovering: Bool = false

    private let colorPalette: [(name: String, hex: String)] = [
        ("Blue", "#007AFF"),
        ("Purple", "#5856D6"),
        ("Pink", "#FF2D55"),
        ("Red", "#FF3B30"),
        ("Orange", "#FF9500"),
        ("Yellow", "#FFCC00"),
        ("Green", "#34C759"),
        ("Mint", "#00C7BE"),
        ("Graphite", "#8E8E93")
    ]

    private let profiles: [String] = [
        "Personal",
        "Work",
        "Development",
        "Research"
    ]

    var body: some View {
        let activeColor = Color(hex: settings.profileColorHex)

        Button(action: { isShowingMenu.toggle() }) {
            ZStack {
                Circle()
                    .fill(activeColor.opacity(0.18))
                    .frame(width: 20, height: 20)

                Circle()
                    .fill(activeColor)
                    .frame(width: 14, height: 14)

                Text(String(settings.profileName.prefix(1)).uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Palette.sideHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Profile: \(settings.profileName)")
        .popover(isPresented: $isShowingMenu, arrowEdge: .trailing) {
            profilePopoverContent
        }
    }

    private var profilePopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile Name Header
            HStack(spacing: 8) {
                let activeColor = Color(hex: settings.profileColorHex)
                Circle()
                    .fill(activeColor)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text(String(settings.profileName.prefix(1)).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )

                Text(settings.profileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Spacer()
            }
            .padding(.horizontal, 2)

            Divider()

            // Color Dots Palette
            VStack(alignment: .leading, spacing: 6) {
                Text("Profile Color")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.muted)

                HStack(spacing: 6) {
                    ForEach(colorPalette, id: \.hex) { item in
                        let isSelected = settings.profileColorHex.caseInsensitiveCompare(item.hex) == .orderedSame
                        let col = Color(hex: item.hex)

                        Button(action: {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                                settings.profileColorHex = item.hex
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(col)
                                    .frame(width: 18, height: 18)

                                if isSelected {
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 2)
                                        .frame(width: 18, height: 18)
                                        .shadow(color: .black.opacity(0.35), radius: 2)
                                }
                            }
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
            }

            Divider()

            // Profiles list
            VStack(alignment: .leading, spacing: 4) {
                Text("Switch Profile")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.muted)

                ForEach(profiles, id: \.self) { name in
                    let isCurrent = settings.profileName == name
                    Button(action: {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                            settings.profileName = name
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isCurrent ? "checkmark" : "")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 14)

                            Text(name)
                                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? Palette.ink : Palette.muted)

                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .background(
                            isCurrent ? Palette.sideWash : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}

//
//  NewSpaceSheetView.swift
//  dino
//
//  Created by tarun on 11/10/26.
//

import SwiftUI

/// Firn-inspired modal card for creating a new contextual space.
struct NewSpaceSheetView: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var selectedColorHex: String = Theme.spaceColors[0].hex
    @State private var sharesSignIns: Bool = false
    @FocusState private var isNameFocused: Bool

    private var activeSpace: Space {
        store.activeSpace
    }

    var body: some View {
        ZStack {
            // Dimmed page backdrop
            Theme.commandDim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    isPresented = false
                }
                .transition(.opacity)

            // Centered Modal Card
            let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                // Header
                Text("New space")
                    .font(Theme.panelTitleFont)
                    .foregroundStyle(Theme.ink)

                // Name Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.muted)

                    TextField("New Space", text: $name)
                        .textFieldStyle(.plain)
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.ink)
                        .focused($isNameFocused)
                        .onSubmit(finish)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                                .fill(Theme.hover)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                                .strokeBorder(isNameFocused ? Theme.frost : Theme.activeTabHairline, lineWidth: isNameFocused ? 1.5 : 1)
                        )
                }

                // Color Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.muted)

                    HStack(spacing: 8) {
                        ForEach(Theme.spaceColors, id: \.name) { item in
                            let isSelected = selectedColorHex.caseInsensitiveCompare(item.hex) == .orderedSame
                            Button(action: {
                                selectedColorHex = item.hex
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Theme.spaceColor(item.hex))
                                        .frame(width: 20, height: 20)

                                    if isSelected {
                                        Circle()
                                            .strokeBorder(Theme.spaceColor(item.hex), lineWidth: 2)
                                            .frame(width: 28, height: 28)
                                    }
                                }
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(item.name.capitalized)
                        }
                    }
                }

                // Sign-ins Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sign-ins")
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.muted)

                    choiceRow(
                        isSelected: !sharesSignIns,
                        title: "Keep this space separate",
                        caption: "Recommended. It starts signed out of everything."
                    ) {
                        sharesSignIns = false
                    }

                    choiceRow(
                        isSelected: sharesSignIns,
                        title: "Share sign-ins with “\(activeSpace.name)”",
                        caption: "It starts signed in wherever “\(activeSpace.name)” is. Its tabs and Basecamp are still its own."
                    ) {
                        sharesSignIns = true
                    }
                }

                // Buttons
                HStack(spacing: 8) {
                    Spacer()

                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                            .fill(Theme.hover)
                    )
                    .buttonStyle(.plain)

                    Button("Create Space") {
                        finish()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.page)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                            .fill(Theme.ink)
                    )
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(width: 380)
            .background(
                shape
                    .fill(Theme.page)
            )
            .overlay(
                shape
                    .strokeBorder(Theme.spaceColor(selectedColorHex).opacity(0.35), lineWidth: 1)
            )
            .clipShape(shape)
            .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
            .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedColorHex = nextAvailableColor()
            isNameFocused = true
        }
        .onExitCommand {
            isPresented = false
        }
    }

    private func choiceRow(isSelected: Bool, title: String, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .strokeBorder(isSelected ? Theme.ink : Theme.faint, lineWidth: 1.5)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Theme.ink : .clear)
                            .padding(3.5)
                    )
                    .frame(width: 14, height: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.ink)
                    Text(caption)
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(isSelected ? Theme.hover.opacity(0.6) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = clean.isEmpty ? "New Space" : clean
        store.createSpace(
            name: finalName,
            colorHex: selectedColorHex,
            sharesWithId: sharesSignIns ? activeSpace.id : nil
        )
        isPresented = false
    }

    private func nextAvailableColor() -> String {
        let usedHexes = Set(store.spaces.map { $0.colorHex.lowercased() })
        for item in Theme.spaceColors {
            if !usedHexes.contains(item.hex.lowercased()) {
                return item.hex
            }
        }
        return Theme.spaceColors[0].hex
    }
}


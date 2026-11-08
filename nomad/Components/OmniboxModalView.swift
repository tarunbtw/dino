//
//  OmniboxModalView.swift
//  nomad
//
//  Centered floating omnibox plate inspired by officecommun.com/search.
//  Summoned via ⌘L or blank tabs; floats cleanly above page with zero layout shift.
//

import SwiftUI
import AppKit

struct OmniboxModalView: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool
    @State private var queryText: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            // Soft background dimming veil
            Rectangle()
                .fill(Palette.ground.opacity(0.74))
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Floating Input Plate & Hanging Suggestions
            VStack(spacing: 0) {
                inputPlate
                    .frame(width: Metrics.fieldWidth)
                    .overlay(alignment: .top) {
                        if !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            OmniboxSuggestionsView(query: queryText, width: Metrics.fieldWidth) { selectedURL in
                                store.activeTab?.load(url: selectedURL)
                                dismiss()
                            }
                            .offset(y: 58)
                        }
                    }
            }
            .padding(.bottom, 60)
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: isPresented)
        .onAppear {
            if let activeTab = store.activeTab, !activeTab.isBlank, let currentURL = activeTab.url?.absoluteString {
                queryText = currentURL
            } else {
                queryText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
    }

    private var inputPlate: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.muted)

            TextField("Search DuckDuckGo or enter address", text: $queryText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.ink)
                .focused($isFieldFocused)
                .onSubmit {
                    submit()
                }
                .onExitCommand {
                    dismiss()
                }

            if !queryText.isEmpty {
                Button(action: { queryText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.faint)
                }
                .buttonStyle(.plain)
            } else {
                Text("esc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.faint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.hairline, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.ground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 28, x: 0, y: 8)
    }

    private func submit() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismiss()
            return
        }

        if let tab = store.activeTab {
            let parsed = URLParser.parse(trimmed)
            if parsed.scheme == "nomad" && parsed.host == "settings" {
                store.openSettings()
            } else {
                tab.load(text: trimmed)
            }
        } else {
            let parsed = URLParser.parse(trimmed)
            store.newTab(url: parsed, select: true)
        }
        dismiss()
    }

    private func dismiss() {
        isPresented = false
        store.isAddressBarFocused = false
    }
}


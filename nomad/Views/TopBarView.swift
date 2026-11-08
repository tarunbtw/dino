//
//  TopBarView.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI

/// Top browser chrome housing traffic lights spacer, tab strip, and minimal navigation doors.
/// Seamlessly blends into the window canvas with zero divider lines matching officecommun.com/search.
struct TopBarView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var settings: SettingsStore
    @State private var isEditingAddress: Bool = false
    @State private var addressText: String = ""
    @FocusState private var isAddressFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            horizontalModeBar
        }
        .frame(height: Metrics.strip)
        .background(Palette.ground)
        .overlay(alignment: .bottom) {
            if let activeTab = store.activeTab {
                ProgressBarView(tab: activeTab)
            }
        }
    }

    @ViewBuilder
    private var horizontalModeBar: some View {
        // Reserved traffic lights breathing room (100pt measured clearance)
        WindowDragArea()
            .frame(width: Metrics.lights, height: Metrics.strip)

        TabStripView(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let activeTab = store.activeTab {
            NavigationControls(tab: activeTab, store: store, settings: settings)
                .padding(.trailing, 12)
        }
    }
}

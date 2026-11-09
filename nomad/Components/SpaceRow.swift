//
//  SpaceRow.swift
//  nomad
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit

/// The row at the bottom of the sidebar: the active space's name, centered,
/// with a native pop-up menu for switching or creating spaces.
struct SpaceRow: View {
    @ObservedObject var store: BrowserStore
    @State private var isShowingNewSpaceAlert = false
    @State private var newSpaceName = ""
    @State private var isHovering = false

    var body: some View {
        let space = store.activeSpace
        VStack(spacing: 3) {
            Button(action: showMenu) {
                Text(space.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.spaceInk(space.colorHex))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        isHovering ? Theme.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("Spaces")

            if store.spaces.count > 1 {
                HStack(spacing: 4) {
                    ForEach(store.spaces) { s in
                        Circle()
                            .fill(s.id == store.activeSpaceId ? Theme.ink : Theme.faint)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $isShowingNewSpaceAlert) {
            newSpaceSheet
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var currentItem: NSMenuItem?

        for (index, space) in store.spaces.enumerated() {
            let item = NSMenuItem(
                title: space.name,
                action: #selector(MenuHandler.selectSpace(_:)),
                keyEquivalent: index < 9 ? "\(index + 1)" : ""
            )
            item.keyEquivalentModifierMask = .control
            item.target = MenuHandler.shared
            item.representedObject = { [weak store] in
                store?.switchSpace(id: space.id)
            }
            if space.id == store.activeSpaceId {
                item.state = .on
                currentItem = item
            }
            let hexStr = space.colorHex.replacingOccurrences(of: "#", with: "")
            let colorVal = UInt32(hexStr, radix: 16) ?? 0x7F9CB0
            item.image = circleDot(color: NSColor(hex: colorVal))
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let newItem = NSMenuItem(
            title: "New Space…",
            action: #selector(MenuHandler.runAction(_:)),
            keyEquivalent: ""
        )
        newItem.target = MenuHandler.shared
        newItem.representedObject = {
            newSpaceName = ""
            isShowingNewSpaceAlert = true
        }
        menu.addItem(newItem)

        let settingsItem = NSMenuItem(
            title: "Space Settings…",
            action: #selector(MenuHandler.runAction(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = MenuHandler.shared
        settingsItem.representedObject = { [weak store] in
            store?.openSettings(section: "General")
        }
        menu.addItem(settingsItem)

        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let mouseLocation = window.mouseLocationOutsideOfEventStream
            menu.popUp(positioning: currentItem, at: mouseLocation, in: contentView)
        }
    }

    private func circleDot(color: NSColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 8, height: 8))
        path.fill()
        image.unlockFocus()
        return image
    }

    private var newSpaceSheet: some View {
        VStack(spacing: 16) {
            Text("Create New Space")
                .font(.headline)
            TextField("Space Name (e.g. Work, Research)", text: $newSpaceName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack(spacing: 12) {
                Button("Cancel") {
                    isShowingNewSpaceAlert = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    let name = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        store.createSpace(name: name)
                    }
                    isShowingNewSpaceAlert = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

private final class MenuHandler: NSObject {
    static let shared = MenuHandler()

    @objc func selectSpace(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? () -> Void {
            action()
        }
    }

    @objc func runAction(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? () -> Void {
            action()
        }
    }
}


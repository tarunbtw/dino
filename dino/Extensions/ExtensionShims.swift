import AppKit
import WebKit
import Combine
import NaturalLanguage
import UserNotifications
import IOKit.pwr_mgt
import CryptoKit

// The Chrome APIs WebKit doesn't have, filled in by the browser itself.
//
// Safari's extension engine covers tabs, storage, scripting, request rules,
// cookies, menus, alarms and messaging. Chrome extensions also reach for
// bookmarks, history, downloads, the side panel, offscreen documents, tab
// groups and OAuth — and fall over when those are undefined.
//
// So when an extension is installed, a small script is put at the front of
// its background and of every page it ships: `chrome.bookmarks` and the rest
// are defined there, and every call becomes a native message to this app,
// which answers from its own bookmarks, history and downloads. To the
// extension it looks like Chrome. The files are changed after the store's
// signature has been checked, and only by adding.

@available(macOS 15.4, *)
@MainActor
enum ExtensionShims {
    /// The name native messages to the browser itself go to.
    static let application = "dino"
    nonisolated static let file = "dino-shim.js"
    nonisolated static let passkeys = "dino-passkeys.js"
    /// The first line of a worker that already carries the shim.
    nonisolated static let marker = "/* Dino: Chrome APIs WebKit lacks, filled in (ExtensionShims.swift) */"
    nonisolated static let ender = "/* Dino: end of shim */"

    // MARK: - at install

    /// Written beside a prepared extension: which shim it carries. The same
    /// one needs nothing redone, which matters at launch — preparing reads
    /// every script and page an extension ships.
    nonisolated static let stamp = ".dino-shim"
    /// Raised when `prepare` changes what it does to a package, so that
    /// extensions prepared before are prepared again.
    nonisolated private static let preparation = "4"
    nonisolated static let version: String = {
        SHA256.hash(data: Data((script + preparation).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }()

    /// `fresh`: a package just unpacked or copied in.
    nonisolated static func prepare(_ folder: URL, fresh: Bool = false) throws {
        let files = FileManager.default
        if fresh {
            for name in [stamp, ".dino-added"] { try? files.removeItem(at: folder.appendingPathComponent(name)) }
        }
        let stampURL = folder.appendingPathComponent(stamp)
        if (try? String(contentsOf: stampURL, encoding: .utf8)) == version { return }
        defer { try? version.write(to: stampURL, atomically: true, encoding: .utf8) }
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        else { return }

        let script = shim(for: folder)
        try script.write(to: folder.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try "".write(to: folder.appendingPathComponent(passkeys), atomically: true, encoding: .utf8)

        var permissions = manifest["permissions"] as? [Any] ?? []
        let asked = Set(permissions.compactMap { $0 as? String })
        var added = (try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(".dino-added")))) as? [String] ?? []
        for needed in ["nativeMessaging"] + (asked.contains("userScripts") ? ["scripting"] : []) where !asked.contains(needed) {
            permissions.append(needed)
            added.append(needed)
        }
        manifest["permissions"] = permissions
        if let data = try? JSONSerialization.data(withJSONObject: Array(Set(added)).sorted()) {
            try? data.write(to: folder.appendingPathComponent(".dino-added"))
        }

        // The background, whichever kind it is, gets the shim first. A
        // classic service worker gets it written at the top of its own file;
        // a module one imports it first, as its imports run before anything
        // written above them.
        if var background = manifest["background"] as? [String: Any] {
            // A manifest is not a way out of its own package: a worker path
            // that resolves outside the folder, or is a link, is left alone.
            if let worker = background["service_worker"] as? String { unlink(worker, in: folder) }
            if let worker = background["service_worker"] as? String,
               let path = inside(worker, of: folder) {
                if var source = try? String(contentsOf: path, encoding: .utf8) {
                    // Already carrying one: take the old one off, so a newer
                    // Search puts its newer shim in its place.
                    if source.hasPrefix(marker), let end = source.range(of: ender) {
                        source = String(source[end.upperBound...]).trimmingPrefix("\n").description
                    }
                    // A copy from before there was an end marker: it ends
                    // where its function does, the first `})();` that
                    // starts a line.
                    while source.hasPrefix(marker), let end = source.range(of: "\n})();\n") {
                        source = String(source[end.upperBound...])
                    }
                    let first = "import \"/\(file)\";\n"
                    while source.hasPrefix(first) { source.removeFirst(first.count) }
                    let module = (background["type"] as? String) == "module"
                    try (module ? first + source : marker + "\n" + script + "\n" + ender + "\n" + source).write(to: path, atomically: true, encoding: .utf8)
                }
            }
            // Scripts, alone or beside a worker — WebKit runs them as a page
            // when a manifest names both.
            if var scripts = background["scripts"] as? [String] {
                if scripts.first != file { scripts.insert(file, at: 0) }
                background["scripts"] = scripts
            }
            manifest["background"] = background
        }

        // Content scripts too — there only Chrome's behaviour is mended. One
        // that runs in the page's own world has Dino's passkey patch before
        // it: a password manager's there keeps a reference to
        // navigator.credentials as it finds it, and that has to be Dino's,
        // not WebKit's (see Passkeys.swift).
        if let entries = manifest["content_scripts"] as? [[String: Any]] {
            manifest["content_scripts"] = entries.map { entry -> [String: Any] in
                var entry = entry
                if var js = entry["js"] as? [String] {
                    if !js.contains(file) { js.insert(file, at: 0) }
                    if (entry["world"] as? String)?.uppercased() == "MAIN", !js.contains(passkeys) { js.insert(passkeys, at: 0) }
                    entry["js"] = js
                }
                return entry
            }
        }

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: manifestURL, options: .atomic)

        // Every page it ships — popup, options, background page, side panel.
        let walker = files.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  ["html", "htm"].contains(url.pathExtension.lowercased()),
                  var html = try? String(contentsOf: url, encoding: .utf8),
                  !html.contains(file)
            else { continue }
            let tag = "<script src=\"/\(file)\"></script>"
            if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
                html.insert(contentsOf: tag, at: head.upperBound)
            } else {
                html = tag + html
            }
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// A worker that is a link to another file of its own package
    /// (StopTheMadness ships `background-143.js` → `background.js`) is made
    /// a copy of that file, so it can carry the shim. A link that leads out
    /// of the package is left as it is, and so left alone.
    nonisolated private static func unlink(_ name: String, in folder: URL) {
        let path = folder.appendingPathComponent(name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard path.path.hasPrefix(folder.standardizedFileURL.path + "/"),
              (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        else { return }
        let root = folder.resolvingSymlinksInPath().path
        let parent = path.deletingLastPathComponent().resolvingSymlinksInPath().path
        let target = path.resolvingSymlinksInPath()
        guard parent == root || parent.hasPrefix(root + "/"),
              target.path.hasPrefix(root + "/"),
              (try? target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let data = try? Data(contentsOf: target)
        else { return }
        try? FileManager.default.removeItem(at: path)
        try? data.write(to: path)
    }

    /// A path a package names, resolved and kept inside the folder it came
    /// in: `..` in a manifest is not a way out of the package. Nor is a
    /// symbolic link, which a folder install keeps as it is: the worker is
    /// read through it and written back over it as a regular file, so a
    /// link to a file elsewhere would put that file's bytes in the package.
    /// A folder on the way that is a link is caught by where it resolves.
    nonisolated private static func inside(_ name: String, of folder: URL) -> URL? {
        let path = folder.appendingPathComponent(name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard path.path.hasPrefix(folder.standardizedFileURL.path + "/"),
              (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              path.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
        else { return nil }
        return path
    }

    /// The shim as this extension gets it: with the events its code mentions
    /// — `chrome.tabs.onUpdated`, `e.runtime.onInstalled` — so its worker
    /// can take their listeners late (see the end of the script).
    nonisolated static func shim(for folder: URL) -> String {
        var found = Set<String>()
        let pattern = try! NSRegularExpression(pattern: #"\.([a-zA-Z]+)\.(on[A-Z][A-Za-z]+)\b"#)
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "js", url.lastPathComponent != file,
                  var text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // Not the shim's own words, in a worker that already carries it.
            if text.hasPrefix(marker), let end = text.range(of: ender) { text = String(text[end.upperBound...]) }
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text) else { continue }
                found.insert("\(text[a]).\(text[b])")
            }
        }
        let list = (try? JSONSerialization.data(withJSONObject: found.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        // And the scripts it ships, so its worker can be told at once that
        // one isn't there (see importScripts in the script).
        var scripts: [String] = []
        let all = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = all?.nextObject() as? URL {
            guard url.pathExtension == "js" else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count))
            // An empty one is marked: there is nothing to run in it.
            let empty = ((try? String(contentsOf: url, encoding: .utf8)) ?? "x").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            scripts.append((empty ? "-" : "") + path)
        }
        let shipped = (try? JSONSerialization.data(withJSONObject: scripts.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return script.replacingOccurrences(of: "__SEARCH_EVENTS__", with: list)
            .replacingOccurrences(of: "__SEARCH_SCRIPTS__", with: shipped)
            .replacingOccurrences(of: "__SEARCH_CHROME__", with: "134.0.0.0")
            .replacingOccurrences(of: "__SEARCH_VERBOSE__", with: "false")
    }

    /// Defines only what is missing, so the day WebKit implements an API,
    /// WebKit's is the one used.
    nonisolated static var script: String {
        ScriptLoader.load(named: "extension-shims")
    }

    // MARK: - answering

    /// Remembered per extension: the side panel it set, and whether its
    /// button should open it.
    static var panelPath: [String: String] = [:]
    static var panelOnClick: Set<String> = []
    static var popups: [String: [String: String]] = [:]

    static func answer(_ message: Any, from context: WKWebExtensionContext, manager: ExtensionManager) async throws -> Any? {
        guard let body = message as? [String: Any], let api = body["api"] as? String else {
            return ["error": "Not a Dino message"]
        }
        let args = body["args"] as? [Any] ?? []
        do {
            return ["value": try await run(api, args, context: context, manager: manager) ?? NSNull()]
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    struct Unsupported: LocalizedError {
        let what: String
        var errorDescription: String? { what }
    }

    static func page(_ path: String, in context: WKWebExtensionContext) -> URL? {
        let base = context.baseURL
        guard let url = URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host == base.host
        else { return nil }
        return url
    }

    static func defaultPanel(_ context: WKWebExtensionContext) -> String? {
        let manifest = context.webExtension.manifest
        let panel = manifest["side_panel"] as? [String: Any]
        return panel?["default_path"] as? String
    }

    static func openPanel(_ context: WKWebExtensionContext, manager: ExtensionManager) {
        guard let path = panelPath[context.uniqueIdentifier] ?? defaultPanel(context) else { return }
        guard let url = ExtensionShims.page(path, in: context) else { return }
        manager.store?.newTab(url: url, select: true)
    }

    private static func run(_ api: String, _ args: [Any], context: WKWebExtensionContext, manager: ExtensionManager) async throws -> Any? {
        let first = args.first
        let id = context.uniqueIdentifier

        switch api {
        // MARK: logging
        case "debug.error":
            let msg = first as? String ?? "?"
            NSLog("[Dino Extension Error - %@]: %@", id, msg)
            return nil

        // MARK: platform info
        case "runtime.getPlatformInfo":
            return ["os": "mac", "arch": "arm", "nacl_arch": "arm"]

        // MARK: side panel
        case "sidePanel.setOptions":
            if let path = (first as? [String: Any])?["path"] as? String { panelPath[id] = path }
            return nil
        case "sidePanel.getOptions":
            return ["enabled": true, "path": panelPath[id] ?? defaultPanel(context) ?? ""]
        case "sidePanel.setPanelBehavior":
            if let on = (first as? [String: Any])?["openPanelOnActionClick"] as? Bool {
                if on { panelOnClick.insert(id) } else { panelOnClick.remove(id) }
            }
            return nil
        case "sidePanel.getPanelBehavior":
            return ["openPanelOnActionClick": panelOnClick.contains(id)]
        case "sidePanel.open":
            openPanel(context, manager: manager)
            return nil

        // MARK: offscreen documents
        case "offscreen.createDocument":
            guard let path = (first as? [String: Any])?["url"] as? String
            else { throw Unsupported(what: "No page for the offscreen document") }
            let reasons = (first as? [String: Any])?["reasons"] as? [String] ?? []
            try await ExtensionOffscreen.create(path, reasons: reasons, for: context)
            return nil
        case "offscreen.closeDocument":
            ExtensionOffscreen.close(for: id)
            return nil
        case "offscreen.hasDocument":
            return ExtensionOffscreen.hasDocument(for: id)
        case "offscreen.sendMessage":
            guard args.count == 3, let token = first as? String,
                  let sender = args[2] as? [String: Any] else { return ["handled": false] }
            return try await ExtensionOffscreen.send(args[1], sender: sender, token: token, for: id)

        // MARK: contexts
        case "runtime.getContexts":
            let filter = first as? [String: Any] ?? [:]
            let types = filter["contextTypes"] as? [String]
            let urls = filter["documentUrls"] as? [String]
            var found: [[String: Any]] = []
            func add(_ type: String, _ url: URL?) {
                guard types == nil || types!.contains(type) else { return }
                let address = url?.absoluteString ?? ""
                guard urls == nil || urls!.contains(address) else { return }
                found.append([
                    "contextType": type, "contextId": "\(id)-\(type)", "tabId": -1, "windowId": -1,
                    "frameId": type == "BACKGROUND" ? -1 : 0, "documentUrl": address,
                    "documentOrigin": url.map { "\($0.scheme ?? "")://\($0.host ?? "")" } ?? "",
                    "incognito": false,
                ])
            }
            if context.webExtension.hasBackgroundContent {
                let manifest = context.webExtension.manifest["background"] as? [String: Any] ?? [:]
                let script = manifest["service_worker"] as? String ?? manifest["page"] as? String
                add("BACKGROUND", script.map { context.baseURL.appendingPathComponent($0) })
            }
            if ExtensionPopup.shared.extensionID == id { add("POPUP", ExtensionPopup.shared.view?.url) }
            found += ExtensionOffscreen.contexts(for: id, matching: filter)
            return found

        // MARK: clients.pages (for clients.matchAll)
        case "clients.pages":
            var pages: [[String: Any]] = []
            if let popup = ExtensionPopup.shared.client(of: id) { pages.append(popup) }
            if let store = manager.store {
                for tab in store.tabs {
                    guard let web = tab.webView as WKWebView?, let url = web.url, url.host == id else { continue }
                    let shown = tab.id == store.activeTabId
                    pages.append(["id": tab.id.uuidString, "url": url.absoluteString, "visible": shown, "focused": shown])
                }
            }
            if let url = ExtensionOffscreen.url(for: id) {
                pages.append(["id": "offscreen", "url": url.absoluteString, "visible": false, "focused": false])
            }
            return pages

        // MARK: background lifecycle
        case "background.wake":
            guard context.webExtension.hasBackgroundContent else { return nil }
            try? await context.loadBackgroundContent()
            return nil
        case "background.loadedBefore":
            return true
        case "background.revive":
            try? await context.loadBackgroundContent()
            return nil

        // MARK: fonts
        case "fontSettings.getFontList":
            return NSFontManager.shared.availableFontFamilies.map { ["fontId": $0, "displayName": $0] }
        case "fontSettings.getFont":
            return ["fontId": "", "levelOfControl": "not_controllable"]
        case "fontSettings.getDefaultFontSize":
            return ["pixelSize": 16, "levelOfControl": "not_controllable"]
        case "fontSettings.getDefaultFixedFontSize":
            return ["pixelSize": 13, "levelOfControl": "not_controllable"]
        case "fontSettings.getMinimumFontSize":
            return ["pixelSize": 0, "levelOfControl": "not_controllable"]

        // MARK: management
        case "management.getSelf", "management.get":
            let found = context.webExtension
            return ["id": id, "name": found.displayName ?? "", "shortName": found.displayShortName ?? "",
                    "version": found.version ?? "", "description": found.displayDescription ?? "",
                    "enabled": true, "type": "extension", "installType": "normal",
                    "mayDisable": true, "offlineEnabled": true, "isApp": false, "hostPermissions": [], "permissions": []]
        case "management.getAll":
            return []

        // MARK: language
        case "i18n.detectLanguage":
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(first as? String ?? "")
            let guesses = recognizer.languageHypotheses(withMaximum: 3)
            return ["isReliable": (guesses.values.max() ?? 0) > 0.6,
                    "languages": guesses.sorted { $0.value > $1.value }.map { ["language": $0.key.rawValue, "percentage": Int($0.value * 100)] }]

        // MARK: notifications
        case "notifications.create":
            let named = first as? String
            let options = (named == nil ? first : (args.count > 1 ? args[1] : nil)) as? [String: Any] ?? [:]
            let key = named ?? UUID().uuidString
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = options["title"] as? String ?? (context.webExtension.displayName ?? "")
            content.body = options["message"] as? String ?? ""
            content.subtitle = context.webExtension.displayName ?? ""
            try? await center.add(UNNotificationRequest(identifier: "\(id).\(key)", content: content, trigger: nil))
            return key
        case "notifications.clear":
            if let key = first as? String {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["\(id).\(key)"])
            }
            return true
        case "notifications.getAll":
            return [String: Any]()
        case "notifications.getPermissionLevel":
            return "granted"
        case "notifications.update":
            return false

        // MARK: speech
        case "tts.speak", "tts.stop", "tts.pause", "tts.resume":
            return nil
        case "tts.isSpeaking":
            return false
        case "tts.getVoices":
            return []

        // MARK: action popup
        case "action.popup":
            let path = first as? String ?? ""
            popups[id, default: [:]]["*"] = path
            return nil

        // MARK: permissions
        case "permissions.granted":
            return true
        case "permissions.request":
            return true
        case "permissions.afterClick":
            return true
        case "permissions.remove":
            return true

        // MARK: idle & power
        case "idle.queryState":
            return "active"
        case "idle.getAutoLockDelay":
            return 0
        case "power.requestKeepAwake", "power.releaseKeepAwake", "power.reportActivity":
            return nil

        // MARK: identity
        case "identity.launchWebAuthFlow":
            if let options = first as? [String: Any], let urlString = options["url"] as? String, let url = URL(string: urlString) {
                manager.store?.newTab(url: url, select: true)
            }
            return nil
        case "identity.getProfileUserInfo":
            return ["email": "", "id": ""]
        case "identity.removeCachedAuthToken", "identity.clearAllCachedAuthTokens":
            return nil
        case "identity.getAuthToken":
            return nil

        // MARK: tabs
        case "tabs.describe":
            let places = first as? [Any] ?? []
            let tabs = manager.store?.tabs ?? []
            return places.map { place -> Any in
                let spec = place as? [String: Any]
                guard let index = (place as? NSNumber)?.intValue ?? (spec?["i"] as? NSNumber)?.intValue,
                      tabs.indices.contains(index) else {
                    return ["url": "", "title": ""]
                }
                let tab = tabs[index]
                return [
                    "url": tab.url?.absoluteString ?? "",
                    "title": tab.title
                ]
            }

        case "tabs.groups":
            let places = first as? [Any] ?? []
            return places.map { _ in -1 }

        case "tabs.move", "tabs.discard", "tabs.activate":
            let spec = first as? [String: Any]
            let tabs = manager.store?.tabs ?? []
            if let index = (first as? NSNumber)?.intValue ?? (spec?["i"] as? NSNumber)?.intValue,
               tabs.indices.contains(index) {
                let tab = tabs[index]
                if api == "tabs.activate" {
                    manager.store?.activeTabId = tab.id
                }
            }
            return nil

        // MARK: user scripts
        case "userScripts.file":
            return nil
        case "userScripts.list":
            return []
        case "userScripts.save":
            return nil
        case "userScripts.world", "userScripts.worlds":
            return api == "userScripts.worlds" ? [] : nil

        // MARK: system
        case "system.cpu.getInfo":
            return [
                "numOfProcessors": ProcessInfo.processInfo.processorCount,
                "archName": "arm64",
                "modelName": "Apple Silicon",
                "features": [],
                "processors": []
            ]
        case "system.memory.getInfo":
            return [
                "capacity": Double(ProcessInfo.processInfo.physicalMemory),
                "availableCapacity": Double(ProcessInfo.processInfo.physicalMemory / 2)
            ]
        case "system.storage.getInfo":
            return []
        case "system.display.getInfo":
            if let screen = NSScreen.main {
                let f = screen.frame
                return [[
                    "id": "screen-main",
                    "name": "Main Display",
                    "isPrimary": true,
                    "bounds": ["left": 0, "top": 0, "width": Int(f.width), "height": Int(f.height)],
                    "workArea": ["left": 0, "top": 0, "width": Int(f.width), "height": Int(f.height)]
                ]]
            }
            return []

        // MARK: privacy & proxy
        case "privacy.services.passwordSavingEnabled":
            return true
        case "privacy.network.webRTCIPHandlingPolicy":
            return "default"
        case "privacy.websites.doNotTrackEnabled", "privacy.websites.adMeasurementEnabled":
            return false
        case "proxy.settings":
            return ["mode": "system"]

        // MARK: bookmarks & history & other stubs
        case _ where api.hasPrefix("bookmarks."):
            return []
        case _ where api.hasPrefix("history."):
            return []
        case _ where api.hasPrefix("downloads."):
            return nil
        case _ where api.hasPrefix("tabGroups."):
            return nil
        case _ where api.hasPrefix("sessions."):
            return []
        case _ where api.hasPrefix("topSites."):
            return []
        case _ where api.hasPrefix("readingList."):
            return []

        default:
            NSLog("[Dino Extension Shim] Unhandled API: %@", api)
            return nil
        }
    }
}

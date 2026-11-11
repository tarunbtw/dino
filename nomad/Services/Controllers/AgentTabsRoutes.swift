//
//  AgentTabsRoutes.swift
//  nomad
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import WebKit

extension NomadAgentServer {
    func handleTabsRoute(method: String, cleanPath: String, bodyData: Data?, queryItem: ((String) -> String?)? = nil, connection: NWConnection, origin: String?) -> Bool {
        guard let store = self.store else { return false }

        let segments = cleanPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let isTabPrefix = segments.first == "tabs" || segments.first == "tab"

        func extractTargetTabId(json: [String: Any]?) -> String? {
            if isTabPrefix && segments.count >= 2 {
                let seg1 = segments[1]
                let reserved: Set<String> = ["new", "switch", "close", "tier", "split", "promote", "pip", "kill", "reap"]
                if !reserved.contains(seg1.lowercased()) {
                    return seg1
                }
            }
            if let json = json {
                if let s = json["id"] as? String, !s.isEmpty { return s }
                if let n = json["id"] as? Int { return String(n) }
                if let s = json["tabId"] as? String, !s.isEmpty { return s }
                if let n = json["tabId"] as? Int { return String(n) }
                if let s = json["tab"] as? String, !s.isEmpty { return s }
                if let n = json["tab"] as? Int { return String(n) }
                if let s = json["index"] as? String, !s.isEmpty { return s }
                if let n = json["index"] as? Int { return String(n) }
            }
            if let qi = queryItem {
                if let s = qi("id"), !s.isEmpty { return s }
                if let s = qi("tabId"), !s.isEmpty { return s }
                if let s = qi("tab"), !s.isEmpty { return s }
                if let s = qi("index"), !s.isEmpty { return s }
            }
            return nil
        }

        switch (method, cleanPath) {
        case ("GET", "/tabs"), ("GET", "/tab"):
            let hotCount = store.tabs.filter { $0.tier == .hot }.count
            let warmCount = store.tabs.filter { $0.tier == .warm }.count
            let coldCount = store.tabs.filter { $0.tier == .cold }.count
            let tabsList: [[String: Any]] = store.tabs.map { tab -> [String: Any] in
                let title = (tab.webView.title?.isEmpty == false ? tab.webView.title : tab.title) ?? ""
                let urlStr = (tab.webView.url?.absoluteString ?? tab.url?.absoluteString) ?? ""
                let isActive = tab.id == store.activeTabId
                return [
                    "id": tab.id.uuidString,
                    "title": title,
                    "url": urlStr,
                    "isIncognito": tab.isIncognito,
                    "isGhost": tab.isGhost,
                    "active": isActive,
                    "isActive": isActive,
                    "isLoading": tab.isLoading,
                    "tier": tab.tier.rawValue,
                    "tabVirtualization": [
                        "tier": tab.tier.rawValue,
                        "isSuspended": tab.tier == .cold,
                        "lastActive": tab.lastActiveTime.timeIntervalSince1970 * 1000.0
                    ]
                ]
            }
            sendJSON(connection: connection, object: [
                "tabs": tabsList,
                "tabsCount": store.tabs.count,
                "tabCount": store.tabs.count,
                "ghostTabsCount": store.ghostTabs.count,
                "tabVirtualization": [
                    "hot": hotCount,
                    "warm": warmCount,
                    "cold": coldCount,
                    "supportedTiers": ["hot", "warm", "cold"]
                ]
            ], origin: origin)
            return true

        case ("POST", "/tabs/new"), ("POST", "/tab/new"):
            var targetURL: URL? = nil
            var select = true
            var isIncognito = false
            var isGhost = false

            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let urlStr = json["url"] as? String, let parsed = URL(string: urlStr) {
                    targetURL = parsed
                }
                if let sel = json["select"] as? Bool { select = sel }
                if let inc = json["isIncognito"] as? Bool { isIncognito = inc }
                if let gh = json["isGhost"] as? Bool { isGhost = gh } else if let gh = json["ghost"] as? Bool { isGhost = gh }
                if isGhost && json["select"] == nil { select = false }
            }

            let newTab = store.newTab(url: targetURL, isIncognito: isIncognito, isGhost: isGhost, select: select)
            NomadCDPSessionManager.shared.notifyTargetCreated(tab: newTab, serverPort: self.port)
            let newTitle = (newTab.webView.title?.isEmpty == false ? newTab.webView.title : newTab.title) ?? ""
            let newURL = (newTab.webView.url?.absoluteString ?? newTab.url?.absoluteString) ?? ""
            sendJSON(connection: connection, object: [
                "success": true,
                "tabId": newTab.id.uuidString,
                "title": newTitle,
                "url": newURL,
                "isGhost": newTab.isGhost,
                "tabsCount": store.tabs.count,
                "tabCount": store.tabs.count,
                "ghostTabsCount": store.ghostTabs.count
            ], origin: origin)
            return true

        case ("POST", "/tabs/switch"), ("POST", "/tab/switch"):
            var json: [String: Any]? = nil
            if let bodyData = bodyData {
                json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            }
            guard let targetId = extractTargetTabId(json: json),
                  let tab = self.resolveTab(id: targetId) else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Tab not found: \(extractTargetTabId(json: json) ?? "unknown")\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            store.selectTab(id: tab.id)
            sendJSON(connection: connection, object: ["success": true, "activeTabId": tab.id.uuidString, "tabsCount": store.tabs.count, "tabCount": store.tabs.count], origin: origin)
            return true

        case ("POST", "/tabs/close"), ("DELETE", "/tabs/close"), ("DELETE", "/tabs"), ("DELETE", "/tab"), ("POST", "/tab/close"):
            var json: [String: Any]? = nil
            if let bodyData = bodyData {
                json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            }
            let targetTab: Tab?
            if let targetId = extractTargetTabId(json: json) {
                targetTab = self.resolveTab(id: targetId)
            } else {
                targetTab = store.activeTab
            }
            guard let tab = targetTab else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Tab not found\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            let closedId = tab.id.uuidString
            store.closeTab(id: tab.id)
            NomadCDPSessionManager.shared.notifyTargetDestroyed(tabId: closedId)
            sendJSON(connection: connection, object: ["success": true, "closedTabId": closedId, "tabsCount": store.tabs.count, "tabCount": store.tabs.count], origin: origin)
            return true

        case ("POST", "/tabs/tier"):
            var json: [String: Any]? = nil
            if let bodyData = bodyData {
                json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            }
            let targetTabId = extractTargetTabId(json: json)
            let targetTab = targetTabId.flatMap { self.resolveTab(id: $0) } ?? store.activeTab
            guard let tab = targetTab else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Tab not found: \(targetTabId ?? "unknown")\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            guard let tierStr = (json?["tier"] as? String) ?? queryItem?("tier"),
                  let newTier = TabTier(rawValue: tierStr.lowercased()) else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid 'tier' (expected 'hot', 'warm', or 'cold')\",\"code\":\"INVALID_PAYLOAD\",\"success\":false}", origin: origin)
                return true
            }
            tab.tier = newTier
            sendJSON(connection: connection, object: ["success": true, "tabId": tab.id.uuidString, "tier": newTier.rawValue], origin: origin)
            return true

        case ("POST", "/tabs/split"):
            var json: [String: Any]? = nil
            if let bodyData = bodyData {
                json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            }
            let targetTabId = extractTargetTabId(json: json)
            let targetTab = targetTabId.flatMap { self.resolveTab(id: $0) } ?? store.ghostTabs.first
            guard let tab = targetTab else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"No tab found to split: \(targetTabId ?? "unknown")\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            let ratio = (json?["ratio"] as? Double) ?? 0.5
            store.splitGhostTab(id: tab.id, ratio: ratio)
            sendJSON(connection: connection, object: [
                "success": true,
                "splitTabId": tab.id.uuidString,
                "activeTabId": store.activeTabId?.uuidString ?? "",
                "isSplitActive": store.activeSplitPair != nil
            ], origin: origin)
            return true

        case ("POST", "/tabs/promote"):
            var json: [String: Any]? = nil
            if let bodyData = bodyData {
                json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            }
            let targetTabId = extractTargetTabId(json: json)
            let targetTab = targetTabId.flatMap { self.resolveTab(id: $0) } ?? store.ghostTabs.first
            guard let tab = targetTab else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"No ghost tab found to promote: \(targetTabId ?? "unknown")\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            store.promoteGhostTab(id: tab.id)
            sendJSON(connection: connection, object: [
                "success": true,
                "tabId": tab.id.uuidString,
                "isGhost": false,
                "tabsCount": store.tabs.count,
                "ghostTabsCount": store.ghostTabs.count
            ], origin: origin)
            return true

        case ("POST", "/tabs/pip"), ("POST", "/agent/pip"):
            var json: [String: Any]? = nil
            if let bodyData = bodyData {
                json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            }
            let actionStr = (json?["action"] as? String)?.lowercased() ?? "toggle"
            if actionStr == "dismiss" || actionStr == "close" {
                AgentPiPManager.shared.dismiss()
                sendJSON(connection: connection, object: ["success": true, "isFloating": false], origin: origin)
                return true
            }
            let targetTabId = extractTargetTabId(json: json)
            let targetTab = targetTabId.flatMap { self.resolveTab(id: $0) } ?? store.ghostTabs.first ?? store.activeTab
            guard let tab = targetTab else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"No tab found for PiP: \(targetTabId ?? "unknown")\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            if actionStr == "present" {
                AgentPiPManager.shared.present(tab: tab, store: store)
            } else {
                AgentPiPManager.shared.toggle(tab: tab, store: store)
            }
            sendJSON(connection: connection, object: [
                "success": true,
                "tabId": tab.id.uuidString,
                "isFloating": AgentPiPManager.shared.isFloating
            ], origin: origin)
            return true

        case ("GET", "/extensions"):
            let exts: [[String: Any]] = ExtensionManager.shared.installed.map { ext in
                var dict: [String: Any] = [
                    "id": ext.id,
                    "name": ext.name,
                    "version": ext.version,
                    "enabled": ext.enabled,
                    "fromStore": ext.fromStore,
                    "pinned": ext.pinned,
                    "permissions": ext.permissions
                ]
                if let p = ext.popupPath { dict["popupPath"] = p }
                if let o = ext.optionsPath { dict["optionsPath"] = o }
                return dict
            }
            sendJSON(connection: connection, object: ["extensions": exts, "count": exts.count, "success": true], origin: origin)
            return true

        case ("POST", "/extensions/toggle"):
            guard let bodyData = bodyData,
                  let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                  let id = json["id"] as? String, !id.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing extension 'id'\",\"code\":\"MISSING_ID\",\"success\":false}", origin: origin)
                return true
            }
            let mgr = ExtensionManager.shared
            guard let existing = mgr.installed.first(where: { $0.id == id }) else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Extension not found: \(id)\",\"code\":\"EXTENSION_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            if let reqEnabled = json["enabled"] as? Bool {
                if existing.enabled != reqEnabled {
                    mgr.toggleEnabled(id: id)
                }
            } else {
                mgr.toggleEnabled(id: id)
            }
            let updated = mgr.installed.first(where: { $0.id == id })
            sendJSON(connection: connection, object: ["success": true, "id": id, "enabled": updated?.enabled ?? false], origin: origin)
            return true

        default:
            if isTabPrefix && segments.count == 2 {
                let targetId = segments[1]
                let reserved: Set<String> = ["new", "switch", "close", "tier", "split", "promote", "pip", "kill", "reap"]
                if !reserved.contains(targetId.lowercased()) {
                    guard let tab = self.resolveTab(id: targetId) else {
                        sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Tab not found: \(targetId)\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                        return true
                    }
                    if method == "GET" {
                        let title = (tab.webView.title?.isEmpty == false ? tab.webView.title : tab.title) ?? ""
                        let urlStr = (tab.webView.url?.absoluteString ?? tab.url?.absoluteString) ?? ""
                        let isActive = tab.id == store.activeTabId
                        sendJSON(connection: connection, object: [
                            "success": true,
                            "tab": [
                                "id": tab.id.uuidString,
                                "title": title,
                                "url": urlStr,
                                "isIncognito": tab.isIncognito,
                                "isGhost": tab.isGhost,
                                "active": isActive,
                                "isActive": isActive,
                                "isLoading": tab.isLoading,
                                "tier": tab.tier.rawValue,
                                "tabVirtualization": [
                                    "tier": tab.tier.rawValue,
                                    "isSuspended": tab.tier == .cold,
                                    "lastActive": tab.lastActiveTime.timeIntervalSince1970 * 1000.0
                                ]
                            ]
                        ], origin: origin)
                        return true
                    } else if method == "DELETE" {
                        let closedId = tab.id.uuidString
                        store.closeTab(id: tab.id)
                        NomadCDPSessionManager.shared.notifyTargetDestroyed(tabId: closedId)
                        sendJSON(connection: connection, object: [
                            "success": true,
                            "closedTabId": closedId,
                            "tabsCount": store.tabs.count,
                            "tabCount": store.tabs.count
                        ], origin: origin)
                        return true
                    }
                }
            } else if isTabPrefix && segments.count == 3 {
                let targetId = segments[1]
                let action = segments[2].lowercased()
                guard let tab = self.resolveTab(id: targetId) else {
                    sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Tab not found: \(targetId)\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                    return true
                }
                if action == "close" && (method == "POST" || method == "DELETE") {
                    let closedId = tab.id.uuidString
                    store.closeTab(id: tab.id)
                    NomadCDPSessionManager.shared.notifyTargetDestroyed(tabId: closedId)
                    sendJSON(connection: connection, object: [
                        "success": true,
                        "closedTabId": closedId,
                        "tabsCount": store.tabs.count,
                        "tabCount": store.tabs.count
                    ], origin: origin)
                    return true
                } else if (action == "switch" || action == "select") && (method == "POST" || method == "GET") {
                    store.selectTab(id: tab.id)
                    sendJSON(connection: connection, object: [
                        "success": true,
                        "activeTabId": tab.id.uuidString,
                        "tabsCount": store.tabs.count,
                        "tabCount": store.tabs.count
                    ], origin: origin)
                    return true
                } else if action == "tier" && method == "POST" {
                    var json: [String: Any]? = nil
                    if let bodyData = bodyData {
                        json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
                    }
                    guard let tierStr = (json?["tier"] as? String) ?? queryItem?("tier"),
                          let newTier = TabTier(rawValue: tierStr.lowercased()) else {
                        sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid 'tier' (expected 'hot', 'warm', or 'cold')\",\"code\":\"INVALID_PAYLOAD\",\"success\":false}", origin: origin)
                        return true
                    }
                    tab.tier = newTier
                    sendJSON(connection: connection, object: [
                        "success": true,
                        "tabId": tab.id.uuidString,
                        "tier": newTier.rawValue
                    ], origin: origin)
                    return true
                }
            }
            return false
        }
    }
}

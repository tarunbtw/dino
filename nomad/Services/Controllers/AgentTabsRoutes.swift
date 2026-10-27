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
    func handleTabsRoute(method: String, cleanPath: String, bodyData: Data?, connection: NWConnection, origin: String?) -> Bool {
        guard let store = self.store else { return false }

        switch (method, cleanPath) {
        case ("GET", "/tabs"):
            let tabsList: [[String: Any]] = store.tabs.map { tab -> [String: Any] in
                let title = (tab.webView.title?.isEmpty == false ? tab.webView.title : tab.title) ?? ""
                let urlStr = (tab.webView.url?.absoluteString ?? tab.url?.absoluteString) ?? ""
                let isActive = tab.id == store.activeTabId
                return [
                    "id": tab.id.uuidString,
                    "title": title,
                    "url": urlStr,
                    "isIncognito": tab.isIncognito,
                    "active": isActive,
                    "isActive": isActive,
                    "isLoading": tab.isLoading
                ]
            }
            sendJSON(connection: connection, object: [
                "tabs": tabsList,
                "tabsCount": store.tabs.count,
                "tabCount": store.tabs.count
            ], origin: origin)
            return true

        case ("POST", "/tabs/new"):
            var targetURL: URL? = nil
            var select = true
            var isIncognito = false

            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let urlStr = json["url"] as? String, let parsed = URL(string: urlStr) {
                    targetURL = parsed
                }
                if let sel = json["select"] as? Bool { select = sel }
                if let inc = json["isIncognito"] as? Bool { isIncognito = inc }
            }

            let newTab = store.newTab(url: targetURL, isIncognito: isIncognito, select: select)
            let newTitle = (newTab.webView.title?.isEmpty == false ? newTab.webView.title : newTab.title) ?? ""
            let newURL = (newTab.webView.url?.absoluteString ?? newTab.url?.absoluteString) ?? ""
            sendJSON(connection: connection, object: [
                "success": true,
                "tabId": newTab.id.uuidString,
                "title": newTitle,
                "url": newURL,
                "tabsCount": store.tabs.count,
                "tabCount": store.tabs.count
            ], origin: origin)
            return true

        case ("POST", "/tabs/switch"):
            guard let bodyData = bodyData,
                  let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                  let idStr = json["id"] as? String,
                  let id = UUID(uuidString: idStr) else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid tab id\",\"code\":\"INVALID_TAB_ID\",\"success\":false}", origin: origin)
                return true
            }
            guard store.tabs.contains(where: { $0.id == id }) else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Tab not found: \(id.uuidString)\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            store.selectTab(id: id)
            sendJSON(connection: connection, object: ["success": true, "activeTabId": id.uuidString, "tabsCount": store.tabs.count, "tabCount": store.tabs.count], origin: origin)
            return true

        case ("POST", "/tabs/close"):
            guard let bodyData = bodyData,
                  let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                  let idStr = json["id"] as? String,
                  let id = UUID(uuidString: idStr) else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid tab id\",\"code\":\"INVALID_TAB_ID\",\"success\":false}", origin: origin)
                return true
            }
            guard store.tabs.contains(where: { $0.id == id }) else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Tab not found: \(id.uuidString)\",\"code\":\"TAB_NOT_FOUND\",\"success\":false}", origin: origin)
                return true
            }
            store.closeTab(id: id)
            sendJSON(connection: connection, object: ["success": true, "closedTabId": id.uuidString, "tabsCount": store.tabs.count, "tabCount": store.tabs.count], origin: origin)
            return true

        default:
            return false
        }
    }
}

//
//  AgentTelemetryRoutes.swift
//  nomad
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import WebKit

extension NomadAgentServer {
    func executeClearCookies(tab: Tab, targetDomain: String?, allDomains: Bool, connection: NWConnection, origin: String?) async {
        let cookieStore = tab.webView.configuration.websiteDataStore.httpCookieStore
        let host = (targetDomain?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? tab.url?.host ?? ""
        var deletedCount = 0

        if allDomains {
            let all = await cookieStore.allCookies()
            deletedCount = all.count
            for c in all {
                await cookieStore.deleteCookie(c)
            }
            await tab.webView.configuration.websiteDataStore.removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
            sendJSON(connection: connection, object: ["success": true, "deletedCount": deletedCount, "allDomains": true], origin: origin)
            return
        }

        let allCookies = await cookieStore.allCookies()
        let cleanHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        for cookie in allCookies {
            let cleanDomain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let matches = cleanHost.isEmpty || cleanDomain == cleanHost || cleanHost.hasSuffix("." + cleanDomain) || cleanDomain.hasSuffix("." + cleanHost)
            if matches {
                await cookieStore.deleteCookie(cookie)
                deletedCount += 1
            }
        }
        sendJSON(connection: connection, object: ["success": true, "deletedCount": deletedCount, "domain": host], origin: origin)
    }

    func executeGetCookies(tab: Tab, targetDomain: String?, allDomains: Bool, connection: NWConnection, origin: String?) async {
        let cookieStore = tab.webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await cookieStore.allCookies()
        let host = (targetDomain?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? tab.url?.host ?? ""
        let cleanHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let matched = allCookies.filter { cookie in
            if allDomains { return true }
            let cleanDomain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return cleanHost.isEmpty || cleanDomain == cleanHost || cleanHost.hasSuffix("." + cleanDomain) || cleanDomain.hasSuffix("." + cleanHost)
        }.map { cookie -> [String: Any] in
            var dict: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "isSecure": cookie.isSecure,
                "isHTTPOnly": cookie.isHTTPOnly
            ]
            if let exp = cookie.expiresDate {
                dict["expires"] = exp.timeIntervalSince1970
            }
            return dict
        }
        sendJSON(connection: connection, object: ["cookies": matched, "domain": host, "allDomains": allDomains], origin: origin)
    }

    func handleTelemetryRoute(method: String, cleanPath: String, bodyData: Data?, queryItem: (String) -> String?, connection: NWConnection, origin: String?) async -> Bool {
        func queryBool(_ name: String, default defaultValue: Bool = false) -> Bool {
            guard let val = queryItem(name) else { return defaultValue }
            return val == "true" || val == "1"
        }

        switch (method, cleanPath) {
        case ("GET", "/cookies"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            await executeGetCookies(tab: activeTab, targetDomain: queryItem("domain"), allDomains: queryBool("allDomains"), connection: connection, origin: origin)
            return true

        case ("POST", "/cookies"):
            guard let bodyData = bodyData, !bodyData.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing cookie JSON body\",\"code\":\"MISSING_BODY\",\"success\":false}", origin: origin)
                return true
            }
            guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed JSON in cookie request body\",\"code\":\"MALFORMED_JSON\",\"success\":false}", origin: origin)
                return true
            }
            let tid = (json["tabId"] as? String) ?? queryItem("tabId")
            guard let activeTab = requireTab(id: tid, connection: connection, origin: origin) else { return true }

            let action = (json["action"] as? String)?.lowercased()
            let allDomains = queryBool("allDomains") || (json["allDomains"] as? Bool == true)
            let domainParam = (json["domain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? queryItem("domain")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetDomain = (domainParam?.isEmpty == false ? domainParam : nil) ?? (activeTab.url?.host ?? "")

            if action == "clear" || action == "delete" {
                await executeClearCookies(tab: activeTab, targetDomain: targetDomain, allDomains: allDomains, connection: connection, origin: origin)
                return true
            }

            if action == "get" {
                await executeGetCookies(tab: activeTab, targetDomain: targetDomain, allDomains: allDomains, connection: connection, origin: origin)
                return true
            }

            let cookieStore = activeTab.webView.configuration.websiteDataStore.httpCookieStore
            let host = (targetDomain.isEmpty ? "localhost" : targetDomain)

            var cookiesToSet: [[String: Any]] = []
            if let list = json["cookies"] as? [[String: Any]] {
                cookiesToSet = list
            } else if json["name"] != nil && json["value"] != nil {
                cookiesToSet = [json]
            }

            if cookiesToSet.isEmpty {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"No cookie definition provided to set (expected 'name' and 'value' or 'cookies' array)\",\"code\":\"INVALID_COOKIE\",\"success\":false}", origin: origin)
                return true
            }

            var setCount = 0
            for c in cookiesToSet {
                guard let name = c["name"] as? String, let value = c["value"] as? String else { continue }
                let domain = c["domain"] as? String ?? host
                let path = c["path"] as? String ?? "/"
                var props: [HTTPCookiePropertyKey: Any] = [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: path
                ]
                if let sec = (c["isSecure"] as? Bool) ?? (c["secure"] as? Bool), sec {
                    props[.secure] = "TRUE"
                }
                if let httpOnly = (c["isHTTPOnly"] as? Bool) ?? (c["httpOnly"] as? Bool) ?? (c["isHttpOnly"] as? Bool), httpOnly {
                    props[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
                }
                if let exp = (c["expires"] as? Double) ?? (c["expiry"] as? Double) {
                    props[.expires] = Date(timeIntervalSince1970: exp)
                }
                if let cookie = HTTPCookie(properties: props) {
                    await cookieStore.setCookie(cookie)
                    setCount += 1
                }
            }
            sendJSON(connection: connection, object: ["success": true, "setCount": setCount], origin: origin)
            return true

        case ("DELETE", "/cookies"):
            let json = bodyData.flatMap { !$0.isEmpty ? (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] : nil }
            let tid = (json?["tabId"] as? String) ?? queryItem("tabId")
            guard let activeTab = requireTab(id: tid, connection: connection, origin: origin) else { return true }
            var allDomains = queryBool("allDomains")
            var targetDomain = queryItem("domain")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let json = json {
                if let bAll = json["allDomains"] as? Bool {
                    allDomains = allDomains || bAll
                }
                if let d = json["domain"] as? String, !d.isEmpty {
                    targetDomain = d.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            await executeClearCookies(tab: activeTab, targetDomain: targetDomain, allDomains: allDomains, connection: connection, origin: origin)
            return true

        case ("GET", "/downloads"):
            let limit = Int(queryItem("limit") ?? "20") ?? 20
            let list = DownloadManager.shared.listDownloads(limit: limit)
            sendJSON(connection: connection, object: [
                "success": true,
                "downloads": list,
                "count": list.count,
                "downloadsDirectory": DownloadManager.shared.downloadsDirectory.path
            ], origin: origin)
            return true

        case ("GET", "/downloads/last"):
            if let last = DownloadManager.shared.lastDownloadInfo() {
                sendJSON(connection: connection, object: [
                    "success": true,
                    "download": last
                ], origin: origin)
            } else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"No downloads found\",\"code\":\"NO_DOWNLOADS\",\"success\":false}", origin: origin)
            }
            return true

        case ("POST", "/downloads/wait"), ("GET", "/downloads/wait"):
            var timeoutMs = 15000
            var sinceDate: Date? = nil
            let iso = ISO8601DateFormatter()
            if method == "POST", let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let t = json["timeoutMs"] as? Int { timeoutMs = t }
                if let s = json["since"] as? String {
                    sinceDate = iso.date(from: s)
                } else if let sNum = json["since"] as? Double {
                    sinceDate = Date(timeIntervalSince1970: sNum > 1_000_000_000_000 ? sNum / 1000.0 : sNum)
                }
            } else {
                if let tStr = queryItem("timeoutMs"), let t = Int(tStr) { timeoutMs = t }
                if let sStr = queryItem("since") {
                    sinceDate = iso.date(from: sStr) ?? Double(sStr).map { Date(timeIntervalSince1970: $0 > 1_000_000_000_000 ? $0 / 1000.0 : $0) }
                }
            }
            let res = await DownloadManager.shared.waitForDownload(timeoutMs: timeoutMs, since: sinceDate)
            sendJSON(connection: connection, object: res, origin: origin)
            return true

        case ("DELETE", "/downloads"):
            var target: String? = queryItem("filename") ?? queryItem("path")
            if target == nil, let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                target = json["filename"] as? String ?? json["path"] as? String
            }
            guard let targetFile = target, !targetFile.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing 'filename' or 'path' in DELETE /downloads\",\"code\":\"MISSING_FILENAME\",\"success\":false}", origin: origin)
                return true
            }
            let deleted = await MainActor.run { DownloadManager.shared.deleteDownload(filenameOrPath: targetFile) }
            sendJSON(connection: connection, object: ["success": deleted, "filename": targetFile], origin: origin)
            return true

        case ("GET", "/events"):
            registerEventStream(connection: connection, origin: origin)
            return true

        case ("GET", "/console"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin, errorMessage: "Tab not found") else { return true }
            let clear = queryBool("clear")
            let levelFilter = queryItem("level")?.lowercased()
            let filtered = activeTab.consoleEntries.filter { entry in
                if let lvl = levelFilter, !lvl.isEmpty && lvl != "all" {
                    return entry.level.rawValue.lowercased() == lvl
                }
                return true
            }
            let entries = filtered.map { entry in
                [
                    "id": entry.id.uuidString,
                    "level": entry.level.rawValue,
                    "message": entry.message,
                    "timestamp": entry.timestamp.timeIntervalSince1970 * 1000.0
                ] as [String: Any]
            }
            if clear {
                activeTab.consoleEntries.removeAll()
            }
            sendJSON(connection: connection, object: [
                "success": true,
                "tabId": activeTab.id.uuidString,
                "count": entries.count,
                "entries": entries
            ], origin: origin)
            return true

        case ("POST", "/console/clear"), ("DELETE", "/console"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.consoleEntries.removeAll()
            sendJSON(connection: connection, object: ["success": true, "cleared": true], origin: origin)
            return true

        case ("GET", "/network"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin, errorMessage: "Tab not found") else { return true }
            let clear = queryBool("clear")
            let filter = queryItem("statusFilter") ?? "all"
            let filtered = activeTab.networkEntries.filter { entry in
                if filter == "errors" { return entry.isError }
                if filter == "success" { return !entry.isError }
                if let code = Int(filter) { return entry.status == code }
                return true
            }
            let entries = filtered.map { entry in
                [
                    "id": entry.id.uuidString,
                    "method": entry.method,
                    "url": entry.url,
                    "status": entry.status,
                    "durationMs": entry.durationMs,
                    "type": entry.type,
                    "isError": entry.isError,
                    "error": (entry.error as Any?) ?? NSNull(),
                    "timestamp": entry.timestamp.timeIntervalSince1970 * 1000.0
                ] as [String: Any]
            }
            if clear {
                activeTab.networkEntries.removeAll()
            }
            sendJSON(connection: connection, object: [
                "success": true,
                "tabId": activeTab.id.uuidString,
                "count": entries.count,
                "entries": entries
            ], origin: origin)
            return true

        case ("POST", "/network/clear"), ("DELETE", "/network"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.networkEntries.removeAll()
            sendJSON(connection: connection, object: ["success": true, "cleared": true], origin: origin)
            return true

        case ("POST", "/network/mock"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            guard let bodyData = bodyData,
                  let mockObj = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                  let mockUrl = mockObj["url"] as? String, !mockUrl.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing required 'url' in /network/mock\",\"code\":\"MISSING_URL\",\"success\":false}", origin: origin)
                return true
            }
            let serialized = String(data: bodyData, encoding: .utf8) ?? "{}"
            let js = "window.__nomad_mock_routes = (window.__nomad_mock_routes || []).concat([\(serialized)]);"
            activeTab.webView.evaluateJavaScript(js) { _, _ in }
            sendJSON(connection: connection, object: ["success": true, "mockedUrl": mockUrl], origin: origin)
            return true

        case ("GET", "/network/mock"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.webView.evaluateJavaScript("JSON.stringify(window.__nomad_mock_routes || [])") { res, _ in
                let jsonStr = (res as? String) ?? "[]"
                let data = Data(jsonStr.utf8)
                let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
                self.sendJSON(connection: connection, object: ["success": true, "mocks": array], origin: origin)
            }
            return true

        case ("DELETE", "/network/mock"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.webView.evaluateJavaScript("window.__nomad_mock_routes = [];") { _, _ in }
            sendJSON(connection: connection, object: ["success": true, "cleared": true], origin: origin)
            return true

        case ("POST", "/network/block"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            guard let bodyData = bodyData,
                  let blockObj = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid JSON body in /network/block\",\"code\":\"INVALID_PAYLOAD\",\"success\":false}", origin: origin)
                return true
            }
            let blockUrl = (blockObj["url"] as? String) ?? (blockObj["pattern"] as? String) ?? ""
            if blockUrl.isEmpty && blockObj["urls"] == nil {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing 'url' or 'pattern' in /network/block\",\"code\":\"MISSING_URL\",\"success\":false}", origin: origin)
                return true
            }
            var rules: [[String: Any]] = []
            if !blockUrl.isEmpty {
                rules.append(["url": blockUrl, "block": true])
            }
            if let urls = blockObj["urls"] as? [String] {
                for u in urls where !u.isEmpty {
                    rules.append(["url": u, "block": true])
                }
            }
            let rulesJson = (try? JSONSerialization.data(withJSONObject: rules)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let js = "window.__nomad_mock_routes = (window.__nomad_mock_routes || []).concat(\(rulesJson));"
            activeTab.webView.evaluateJavaScript(js) { _, _ in }
            sendJSON(connection: connection, object: ["success": true, "blocked": true, "count": rules.count, "url": blockUrl], origin: origin)
            return true

        case ("GET", "/network/block"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.webView.evaluateJavaScript("JSON.stringify((window.__nomad_mock_routes || []).filter(m => m && m.block))") { res, _ in
                let jsonStr = (res as? String) ?? "[]"
                let data = Data(jsonStr.utf8)
                let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
                self.sendJSON(connection: connection, object: ["success": true, "blockedRules": array, "count": array.count], origin: origin)
            }
            return true

        case ("DELETE", "/network/block"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.webView.evaluateJavaScript("window.__nomad_mock_routes = (window.__nomad_mock_routes || []).filter(m => !m || !m.block);") { _, _ in }
            sendJSON(connection: connection, object: ["success": true, "cleared": true], origin: origin)
            return true

        case ("GET", "/cache/routes"):
            let domain = queryItem("domain")
            let intent = queryItem("intent")
            let routes: [CachedRoute]
            if let d = domain, !d.isEmpty {
                routes = NomadRouteCache.shared.lookup(domain: d, intent: intent)
            } else {
                routes = NomadRouteCache.shared.allRoutes()
            }
            let routeList: [[String: Any]] = routes.map { r in
                [
                    "id": r.id.uuidString,
                    "domain": r.domain,
                    "intent": r.intent,
                    "selector": r.selector,
                    "action": r.action,
                    "successCount": r.successCount,
                    "lastUsed": r.lastUsed.timeIntervalSince1970 * 1000.0
                ]
            }
            sendJSON(connection: connection, object: ["success": true, "routes": routeList, "count": routeList.count], origin: origin)
            return true

        case ("POST", "/cache/routes"):
            guard let bodyData = bodyData,
                  let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                  let domain = json["domain"] as? String, !domain.isEmpty,
                  let intent = json["intent"] as? String, !intent.isEmpty,
                  let selector = json["selector"] as? String, !selector.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing domain, intent, or selector in /cache/routes\",\"code\":\"INVALID_PAYLOAD\",\"success\":false}", origin: origin)
                return true
            }
            let action = json["action"] as? String ?? "click"
            NomadRouteCache.shared.recordSuccess(domain: domain, intent: intent, selector: selector, action: action)
            sendJSON(connection: connection, object: ["success": true, "cached": true, "domain": domain, "intent": intent], origin: origin)
            return true

        case ("DELETE", "/cache/routes"):
            NomadRouteCache.shared.clearRoutes()
            sendJSON(connection: connection, object: ["success": true, "cleared": true], origin: origin)
            return true

        case ("POST", "/trace"), ("POST", "/trajectory"):
            var eventType = "agent"
            var message = ""
            var tabId = queryItem("tabId")
            var metadata: [String: String] = [:]

            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let t = (json["type"] as? String) ?? (json["eventType"] as? String) {
                    eventType = t
                }
                if let m = (json["message"] as? String) ?? (json["text"] as? String) ?? (json["action"] as? String) {
                    message = m
                }
                if let tid = json["tabId"] as? String {
                    tabId = tid
                }
                if let meta = json["metadata"] as? [String: Any] {
                    for (k, v) in meta {
                        metadata[k] = "\(v)"
                    }
                }
            } else if let msgParam = queryItem("message") {
                message = msgParam
                if let tParam = queryItem("type") { eventType = tParam }
            }

            NomadRouteCache.shared.record(eventType: eventType, message: message, tabId: tabId, metadata: metadata)
            sendJSON(connection: connection, object: ["success": true, "recorded": true, "type": eventType, "message": message], origin: origin)
            return true

        case ("GET", "/trace"), ("GET", "/trajectory"):
            let tabId = queryItem("tabId")
            let entries = NomadRouteCache.shared.exportTrajectory(tabId: tabId)
            sendJSON(connection: connection, object: [
                "success": true,
                "tabId": (tabId as Any?) ?? NSNull(),
                "entriesCount": entries.count,
                "trajectory": entries
            ], origin: origin)
            return true

        case ("DELETE", "/trace"), ("DELETE", "/trajectory"):
            NomadRouteCache.shared.clearTrajectory()
            sendJSON(connection: connection, object: ["success": true, "cleared": true], origin: origin)
            return true

        default:
            return false
        }
    }
}

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
                var resp = last
                resp["success"] = true
                resp["download"] = last
                sendJSON(connection: connection, object: resp, origin: origin)
            } else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"No downloads found\",\"code\":\"NO_DOWNLOADS\",\"success\":false}", origin: origin)
            }
            return true

        case ("POST", "/downloads/wait"), ("GET", "/downloads/wait"):
            var timeoutMs = 15000
            var sinceDate: Date? = nil
            var targetFilename: String? = queryItem("filename")
            let parseSince: (Any?) -> Date? = { val in
                guard let val = val else { return nil }
                if let s = val as? String {
                    return ISO8601DateFormatter().date(from: s) ?? Double(s).map { Date(timeIntervalSince1970: $0 > 1_000_000_000_000 ? $0 / 1000.0 : $0) }
                }
                if let d = val as? Double {
                    return Date(timeIntervalSince1970: d > 1_000_000_000_000 ? d / 1000.0 : d)
                }
                return nil
            }
            if method == "POST", let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let t = json["timeoutMs"] as? Int { timeoutMs = t }
                if let f = json["filename"] as? String { targetFilename = f }
                sinceDate = parseSince(json["since"])
            } else {
                if let tStr = queryItem("timeoutMs"), let t = Int(tStr) { timeoutMs = t }
                sinceDate = parseSince(queryItem("since"))
            }
            let res = await DownloadManager.shared.waitForDownload(timeoutMs: timeoutMs, since: sinceDate, filename: targetFilename)
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

        case ("GET", "/storage"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            let shouldRedact = queryItem("redact") != "false" && queryItem("raw") != "true"
            let targetType = (queryItem("type") ?? "all").lowercased()

            let script = """
            (() => {
                var ls = {};
                var ss = {};
                try {
                    for (var i = 0; i < localStorage.length; i++) {
                        var k = localStorage.key(i);
                        if (k !== null) ls[k] = localStorage.getItem(k);
                    }
                } catch(e) {}
                try {
                    for (var j = 0; j < sessionStorage.length; j++) {
                        var sk = sessionStorage.key(j);
                        if (sk !== null) ss[sk] = sessionStorage.getItem(sk);
                    }
                } catch(e) {}
                return {
                    origin: window.location.origin || '',
                    localStorage: ls,
                    sessionStorage: ss
                };
            })()
            """
            let storeData = (try? await activeTab.webView.evaluateJavaScript(script)) as? [String: Any] ?? [:]
            var ls = storeData["localStorage"] as? [String: String] ?? [:]
            var ss = storeData["sessionStorage"] as? [String: String] ?? [:]
            let originStr = (storeData["origin"] as? String) ?? (activeTab.url?.host ?? "")

            if shouldRedact {
                func redactDict(_ dict: [String: String]) -> [String: String] {
                    var out: [String: String] = [:]
                    for (k, v) in dict {
                        let lk = k.lowercased()
                        let isSens = lk.contains("token") || lk.contains("jwt") || lk.contains("auth") || lk.contains("secret") || lk.contains("key") || lk.contains("password") || lk.contains("pass") || lk.contains("credential") || lk.contains("session") || v.hasPrefix("eyJ")
                        out[k] = isSens ? "[REDACTED]" : v
                    }
                    return out
                }
                ls = redactDict(ls)
                ss = redactDict(ss)
            }

            var resp: [String: Any] = [
                "success": true,
                "origin": originStr,
                "tabId": activeTab.id.uuidString
            ]
            if targetType == "all" || targetType == "local" { resp["localStorage"] = ls }
            if targetType == "all" || targetType == "session" { resp["sessionStorage"] = ss }

            if targetType == "all" || targetType == "cookies" {
                let host = activeTab.url?.host ?? ""
                let allCookies = await activeTab.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let matched = allCookies.filter { c in
                    host.isEmpty || c.domain.hasSuffix(host) || host.hasSuffix(c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                }.map { c -> [String: Any] in
                    var d: [String: Any] = [
                        "name": c.name,
                        "value": shouldRedact && (c.name.lowercased().contains("token") || c.name.lowercased().contains("auth") || c.name.lowercased().contains("session") || c.name.lowercased().contains("jwt") || c.value.hasPrefix("eyJ")) ? "[REDACTED]" : c.value,
                        "domain": c.domain,
                        "path": c.path,
                        "isSecure": c.isSecure,
                        "isHTTPOnly": c.isHTTPOnly
                    ]
                    if let exp = c.expiresDate { d["expires"] = exp.timeIntervalSince1970 }
                    return d
                }
                resp["cookies"] = matched
            }

            sendJSON(connection: connection, object: resp, origin: origin)
            return true

        case ("POST", "/storage"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            guard let bodyData = bodyData,
                  let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid JSON body in /storage\",\"code\":\"INVALID_PAYLOAD\",\"success\":false}", origin: origin)
                return true
            }

            var updated: [String] = []
            if let key = json["key"] as? String, !key.isEmpty {
                let val = (json["value"] as? String) ?? (json["val"] as? String) ?? ""
                let target = ((json["type"] as? String) ?? (json["target"] as? String) ?? "localStorage").lowercased()
                let isSession = (target == "sessionstorage" || target == "session")
                let storeName = isSession ? "sessionStorage" : "localStorage"
                let escapedKey = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let escapedVal = val.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let script = "\(storeName).setItem(\"\(escapedKey)\", \"\(escapedVal)\")"
                _ = try? await activeTab.webView.evaluateJavaScript(script)
                if !updated.contains(storeName) { updated.append(storeName) }
            }

            if let lsUpdates = json["localStorage"] as? [String: Any],
               let lsData = try? JSONSerialization.data(withJSONObject: lsUpdates),
               let lsJSON = String(data: lsData, encoding: .utf8) {
                let script = """
                (() => {
                    var u = \(lsJSON);
                    for (var k in u) {
                        if (Object.prototype.hasOwnProperty.call(u, k)) {
                            localStorage.setItem(k, String(u[k]));
                        }
                    }
                })()
                """
                _ = try? await activeTab.webView.evaluateJavaScript(script)
                updated.append("localStorage")
            }

            if let ssUpdates = json["sessionStorage"] as? [String: Any],
               let ssData = try? JSONSerialization.data(withJSONObject: ssUpdates),
               let ssJSON = String(data: ssData, encoding: .utf8) {
                let script = """
                (() => {
                    var u = \(ssJSON);
                    for (var k in u) {
                        if (Object.prototype.hasOwnProperty.call(u, k)) {
                            sessionStorage.setItem(k, String(u[k]));
                        }
                    }
                })()
                """
                _ = try? await activeTab.webView.evaluateJavaScript(script)
                updated.append("sessionStorage")
            }

            if let cookieList = json["cookies"] as? [[String: Any]] {
                let cookieStore = activeTab.webView.configuration.websiteDataStore.httpCookieStore
                let curHost = activeTab.url?.host ?? "localhost"
                for cDict in cookieList {
                    guard let name = cDict["name"] as? String, !name.isEmpty,
                          let val = (cDict["value"] as? String) ?? (cDict["val"] as? String) else { continue }
                    var props: [HTTPCookiePropertyKey: Any] = [
                        .name: name,
                        .value: val,
                        .domain: (cDict["domain"] as? String) ?? curHost,
                        .path: (cDict["path"] as? String) ?? "/"
                    ]
                    if let sec = cDict["isSecure"] as? Bool { props[.secure] = sec ? "TRUE" : "FALSE" }
                    if let exp = cDict["expires"] as? Double { props[.expires] = Date(timeIntervalSince1970: exp) }
                    if let cookie = HTTPCookie(properties: props) {
                        await cookieStore.setCookie(cookie)
                    }
                }
                updated.append("cookies")
            }

            sendJSON(connection: connection, object: ["success": true, "updated": updated], origin: origin)
            return true

        case ("DELETE", "/storage"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var targetType = "all"
            if let t = queryItem("type") { targetType = t.lowercased() }
            let bodyJSON = bodyData.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            if let t = bodyJSON?["type"] as? String {
                targetType = t.lowercased()
            }
            if let k = (queryItem("key") ?? (bodyJSON?["key"] as? String)), !k.isEmpty {
                let esc = k.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let script = """
                (() => {
                    var t = '\(targetType)';
                    if (t === 'all' || t === 'local' || t === 'localstorage') { try { localStorage.removeItem("\(esc)"); } catch(e) {} }
                    if (t === 'all' || t === 'session' || t === 'sessionstorage') { try { sessionStorage.removeItem("\(esc)"); } catch(e) {} }
                })()
                """
                _ = try? await activeTab.webView.evaluateJavaScript(script)
                sendJSON(connection: connection, object: ["success": true, "removed": k], origin: origin)
                return true
            }

            let script = """
            (() => {
                var t = '\(targetType)';
                if (t === 'all' || t === 'local') { try { localStorage.clear(); } catch(e) {} }
                if (t === 'all' || t === 'session') { try { sessionStorage.clear(); } catch(e) {} }
            })()
            """
            _ = try? await activeTab.webView.evaluateJavaScript(script)

            if targetType == "all" || targetType == "cookies" {
                let host = activeTab.url?.host ?? ""
                let cookieStore = activeTab.webView.configuration.websiteDataStore.httpCookieStore
                let allCookies = await cookieStore.allCookies()
                for c in allCookies {
                    if host.isEmpty || c.domain.hasSuffix(host) || host.hasSuffix(c.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                        await cookieStore.deleteCookie(c)
                    }
                }
            }

            sendJSON(connection: connection, object: ["success": true, "cleared": targetType], origin: origin)
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

        case ("POST", "/route"), ("POST", "/network/route"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            guard let bodyData = bodyData,
                  let routeObj = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid JSON body in /route\",\"code\":\"INVALID_PAYLOAD\",\"success\":false}", origin: origin)
                return true
            }
            let pattern = (routeObj["pattern"] as? String) ?? (routeObj["url"] as? String) ?? ""
            guard !pattern.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing required 'pattern' or 'url' in /route\",\"code\":\"MISSING_PATTERN\",\"success\":false}", origin: origin)
                return true
            }
            let action = ((routeObj["action"] as? String) ?? (routeObj["type"] as? String) ?? "").lowercased()
            let isBlock = (action == "abort" || action == "block") || (routeObj["block"] as? Bool ?? false)
            if isBlock {
                if !activeTab.blockedURLPatterns.contains(pattern) {
                    activeTab.blockedURLPatterns.append(pattern)
                }
                activeTab.mockRoutes.removeAll(where: { ($0["url"] as? String) == pattern })
                activeTab.mockRoutes.append(["url": pattern, "block": true])
                activeTab.syncMockRoutes()
                sendJSON(connection: connection, object: ["success": true, "routed": true, "action": "block", "pattern": pattern], origin: origin)
                return true
            } else {
                var mockObj = routeObj
                mockObj["url"] = pattern
                let method = (mockObj["method"] as? String)?.uppercased()
                activeTab.mockRoutes.removeAll(where: {
                    ($0["url"] as? String) == pattern &&
                    (($0["method"] as? String)?.uppercased() == method)
                })
                activeTab.mockRoutes.append(mockObj)
                activeTab.syncMockRoutes()
                sendJSON(connection: connection, object: ["success": true, "routed": true, "action": "mock", "pattern": pattern], origin: origin)
                return true
            }

        case ("GET", "/route"), ("GET", "/route/list"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            sendJSON(connection: connection, object: [
                "success": true,
                "routes": activeTab.mockRoutes,
                "blockedPatterns": activeTab.blockedURLPatterns
            ], origin: origin)
            return true

        case ("DELETE", "/route"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.blockedURLPatterns.removeAll()
            activeTab.mockRoutes.removeAll()
            activeTab.syncMockRoutes()
            sendJSON(connection: connection, object: ["success": true, "cleared": true], origin: origin)
            return true

        case ("POST", "/network/mock"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            guard let bodyData = bodyData,
                  var mockObj = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid JSON body in /network/mock\",\"code\":\"INVALID_PAYLOAD\",\"success\":false}", origin: origin)
                return true
            }
            let mockUrl = (mockObj["url"] as? String) ?? (mockObj["pattern"] as? String) ?? ""
            guard !mockUrl.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing required 'url' in /network/mock\",\"code\":\"MISSING_URL\",\"success\":false}", origin: origin)
                return true
            }
            mockObj["url"] = mockUrl
            let method = (mockObj["method"] as? String)?.uppercased()
            activeTab.mockRoutes.removeAll(where: {
                ($0["url"] as? String) == mockUrl &&
                (($0["method"] as? String)?.uppercased() == method) &&
                !($0["block"] as? Bool ?? false)
            })
            activeTab.mockRoutes.append(mockObj)
            activeTab.syncMockRoutes()
            sendJSON(connection: connection, object: ["success": true, "mockedUrl": mockUrl], origin: origin)
            return true

        case ("GET", "/network/mock"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            let mocks = activeTab.mockRoutes.filter { !($0["block"] as? Bool ?? false) }
            sendJSON(connection: connection, object: ["success": true, "mocks": mocks], origin: origin)
            return true

        case ("DELETE", "/network/mock"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.mockRoutes.removeAll(where: { !($0["block"] as? Bool ?? false) })
            activeTab.syncMockRoutes()
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
            for r in rules {
                if let u = r["url"] as? String {
                    if !activeTab.blockedURLPatterns.contains(u) {
                        activeTab.blockedURLPatterns.append(u)
                    }
                    activeTab.mockRoutes.removeAll(where: {
                        ($0["url"] as? String) == u && ($0["block"] as? Bool ?? false)
                    })
                    activeTab.mockRoutes.append(r)
                }
            }
            activeTab.syncMockRoutes()
            sendJSON(connection: connection, object: ["success": true, "blocked": true, "count": activeTab.blockedURLPatterns.count, "url": blockUrl, "patterns": activeTab.blockedURLPatterns], origin: origin)
            return true

        case ("GET", "/network/block"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            let rules = activeTab.blockedURLPatterns.map { ["url": $0, "block": true] }
            sendJSON(connection: connection, object: ["success": true, "blockedRules": rules, "count": rules.count], origin: origin)
            return true

        case ("DELETE", "/network/block"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            activeTab.blockedURLPatterns.removeAll()
            activeTab.mockRoutes.removeAll(where: { ($0["block"] as? Bool ?? false) })
            activeTab.syncMockRoutes()
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

//
//  AgentNavigationRoutes.swift
//  nomad
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import WebKit

extension NomadAgentServer {
    func handleNavAction(_ action: String, tab: Tab, connection: NWConnection, origin: String?) {
        switch action {
        case "back":
            if !tab.canGoBack {
                sendJSON(connection: connection, object: ["success": false, "action": "back", "code": "CANNOT_GO_BACK", "error": "Cannot go back: navigation history is empty"], origin: origin)
            } else {
                store?.goBack()
                sendJSON(connection: connection, object: ["success": true, "action": "back"], origin: origin)
            }
        case "forward":
            if !tab.canGoForward {
                sendJSON(connection: connection, object: ["success": false, "action": "forward", "code": "CANNOT_GO_FORWARD", "error": "Cannot go forward: navigation history is empty"], origin: origin)
            } else {
                store?.goForward()
                sendJSON(connection: connection, object: ["success": true, "action": "forward"], origin: origin)
            }
        case "reload":
            store?.reload()
            sendJSON(connection: connection, object: ["success": true, "action": "reload"], origin: origin)
        default:
            break
        }
    }

    func handleNavigationRoute(method: String, cleanPath: String, bodyData: Data?, queryItem: (String) -> String?, connection: NWConnection, origin: String?) async -> Bool {
        switch (method, cleanPath) {
        case ("POST", "/navigate"):
            guard let bodyData = bodyData, !bodyData.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing body in /navigate\",\"code\":\"MISSING_BODY\",\"success\":false}", origin: origin)
                return true
            }
            guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed JSON in request body\",\"code\":\"MALFORMED_JSON\",\"success\":false}", origin: origin)
                return true
            }
            let tid = (json["tabId"] as? String) ?? queryItem("tabId")
            guard let activeTab = requireTab(id: tid, connection: connection, origin: origin) else { return true }
            let action = (json["action"] as? String)?.lowercased()
            if let action = action, ["back", "forward", "reload"].contains(action) {
                handleNavAction(action, tab: activeTab, connection: connection, origin: origin)
            } else {
                guard let urlStr = json["url"] as? String, let url = URL(string: urlStr), let scheme = url.scheme?.lowercased() else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing or invalid url in body\",\"code\":\"INVALID_URL\",\"success\":false}", origin: origin)
                    return true
                }
                if scheme == "javascript" {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"javascript: URLs are not permitted in navigate. Use /evaluate instead.\",\"code\":\"INVALID_URL_SCHEME\",\"success\":false}", origin: origin)
                    return true
                }
                let allowLocal = (json["allowLocalFiles"] as? Bool) ?? false
                if scheme == "file" {
                    if !allowLocal {
                        sendResponse(connection: connection, status: "403 Forbidden", body: "{\"error\":\"file:// URLs are disabled by default. Pass allowLocalFiles: true to navigate local files.\",\"code\":\"FILE_URLS_DISABLED\",\"success\":false}", origin: origin)
                        return true
                    }
                    let filePath = url.path
                    if !FileManager.default.fileExists(atPath: filePath) {
                        sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"File not found at path '\(filePath)'\",\"code\":\"FILE_NOT_FOUND\",\"success\":false}", origin: origin)
                        return true
                    }
                    let rawLower = filePath.lowercased()
                    let canonicalLower = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().standardized.path.lowercased()
                    let isSensitive = [rawLower, canonicalLower].contains { p in
                        p.contains("/.ssh") || p.contains("/.nomad") || p.contains("/library/keychains") || p.contains("/etc/master.passwd") || p.contains("/etc/sudoers")
                    }
                    if isSensitive {
                        sendResponse(connection: connection, status: "403 Forbidden", body: "{\"error\":\"Access to sensitive directory or credential file is blocked by Nomad security policy.\",\"code\":\"ACCESS_DENIED\",\"success\":false}", origin: origin)
                        return true
                    }
                }
                let mySeq = activeTab.navigationSeq + 1
                activeTab.load(url: url)
                // Poll briefly (up to 350ms) to ensure provisional navigation starts or early DNS/host error is reported
                var navError: String? = nil
                var superseded = false
                let navStart = Date()
                while Date().timeIntervalSince(navStart) < 0.35 {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    if activeTab.navigationSeq != mySeq {
                        superseded = true
                        break
                    }
                    if let err = activeTab.lastNavigationError {
                        navError = err
                        break
                    }
                }
                if superseded {
                    NomadRouteCache.shared.record(eventType: "navigationCancelled", message: "Navigation superseded for \(url.absoluteString)", tabId: activeTab.id.uuidString)
                    sendJSON(connection: connection, object: ["success": false, "cancelled": true, "code": "NAVIGATION_SUPERSEDED", "reason": "superseded", "navigatedTo": url.absoluteString], origin: origin)
                } else if let navError = navError {
                    NomadRouteCache.shared.record(eventType: "navigationError", message: "Navigation failed for \(url.absoluteString): \(navError)", tabId: activeTab.id.uuidString)
                    sendJSON(connection: connection, object: ["success": false, "error": navError, "code": "NAVIGATION_FAILED", "navigatedTo": url.absoluteString], origin: origin)
                } else {
                    NomadRouteCache.shared.record(eventType: "navigation", message: "Navigated to \(url.absoluteString)", tabId: activeTab.id.uuidString)
                    sendJSON(connection: connection, object: ["success": true, "navigatedTo": url.absoluteString], origin: origin)
                }
            }
            return true

        case ("POST", "/navigate/back"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            handleNavAction("back", tab: activeTab, connection: connection, origin: origin)
            return true

        case ("POST", "/navigate/forward"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            handleNavAction("forward", tab: activeTab, connection: connection, origin: origin)
            return true

        case ("POST", "/navigate/reload"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            handleNavAction("reload", tab: activeTab, connection: connection, origin: origin)
            return true

        case ("POST", "/wait"):
            var mode = "stability"
            var quietMs = 250
            var timeoutMs = 5000
            var durationMs = 1000
            var selector = ""
            var urlPattern = ""
            var idleMs = 500
            var tid: String? = nil

            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                tid = json["tabId"] as? String
                if let m = json["mode"] as? String { mode = m.lowercased() }
                if let q = json["quietMs"] as? Int { quietMs = q }
                if let t = json["timeoutMs"] as? Int { timeoutMs = t }
                if let d = json["durationMs"] as? Int { durationMs = d }
                if let s = json["selector"] as? String { selector = s }
                if let u = json["urlPattern"] as? String { urlPattern = u }
                if let u = json["url"] as? String, urlPattern.isEmpty { urlPattern = u }
                if let i = json["idleMs"] as? Int { idleMs = i }
            }

            guard let activeTab = requireTab(id: tid, connection: connection, origin: origin) else { return true }

            // Auto-infer selector mode if selector string is present
            if !selector.isEmpty && (mode == "stability" || mode.isEmpty) {
                mode = "selector"
            }

            switch mode {
            case "stability", "stable", "domstable", "idle", "quiescence":
                do {
                    let result = try await activeTab.waitForStability(quietMs: quietMs, timeoutMs: timeoutMs)
                    sendJSON(connection: connection, object: result, origin: origin)
                } catch {
                    sendResponse(connection: connection, status: "500 Internal Server Error", body: "{\"error\":\"\(error.localizedDescription)\",\"code\":\"WAIT_ERROR\",\"success\":false}", origin: origin)
                }

            case "selector":
                guard !selector.isEmpty else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing selector string\",\"code\":\"MISSING_SELECTOR\",\"success\":false}", origin: origin)
                    return true
                }
                let startTime = Date()
                let maxDuration = Double(timeoutMs) / 1000.0

                let escapedSelector: String
                if let data = try? JSONEncoder().encode(selector), let str = String(data: data, encoding: .utf8) {
                    escapedSelector = str
                } else {
                    escapedSelector = "\"\(selector)\""
                }

                let checkScript = """
                (() => {
                    var sel = \(escapedSelector);
                    function match(node, s) {
                        if (!node) return false;
                        try {
                            if (node.querySelector(s) || node.querySelector('[data-nomad-id="' + s + '"]')) return true;
                        } catch(e) {}
                        return false;
                    }
                    function deepSearch(root) {
                        if (!root) return false;
                        if (match(root, sel)) return true;
                        try {
                            var all = root.querySelectorAll('*');
                            for (var i = 0; i < all.length; i++) {
                                var el = all[i];
                                if (el.shadowRoot) {
                                    if (deepSearch(el.shadowRoot)) return true;
                                }
                                if (el.tagName === 'IFRAME') {
                                    try {
                                        var fDoc = el.contentDocument || (el.contentWindow ? el.contentWindow.document : null);
                                        if (fDoc && deepSearch(fDoc)) return true;
                                    } catch(e) {}
                                }
                            }
                        } catch(e) {}
                        return false;
                    }
                    if (window.__nomad && window.__nomad.findInTree) {
                        try {
                            if (window.__nomad.findInTree(document, sel)) return true;
                        } catch(e) {}
                    }
                    return deepSearch(document);
                })()
                """

                var found = false
                while Date().timeIntervalSince(startTime) < maxDuration {
                    if !activeTab.isLoading {
                        let res = (try? await activeTab.webView.evaluateJavaScript(checkScript)) as? Bool ?? false
                        if res {
                            found = true
                            break
                        }
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }

                if found {
                    sendJSON(connection: connection, object: ["success": true, "selector": selector, "message": "Element appeared"], origin: origin)
                } else {
                    sendJSON(connection: connection, object: ["success": false, "reason": "timeout", "message": "Timeout waiting for selector '\(selector)'"], origin: origin)
                }

            case "networkidle", "network_idle":
                let startTime = Date()
                var lastActivity = Date()
                var prevCount = activeTab.networkEntries.count
                while Date().timeIntervalSince(startTime) < (Double(timeoutMs) / 1000.0) {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    let currentCount = activeTab.networkEntries.count
                    if currentCount != prevCount {
                        prevCount = currentCount
                        lastActivity = Date()
                    } else if Date().timeIntervalSince(lastActivity) >= (Double(idleMs) / 1000.0) && !activeTab.isLoading {
                        sendJSON(connection: connection, object: ["success": true, "message": "Network idle for \(idleMs)ms", "requests": currentCount], origin: origin)
                        return true
                    }
                }
                sendJSON(connection: connection, object: ["success": false, "reason": "timeout", "message": "Exceeded max wait of \(timeoutMs)ms waiting for network idle"], origin: origin)

            case "navigation", "url":
                let expectedPattern = !urlPattern.isEmpty ? urlPattern : selector
                let regex = !expectedPattern.isEmpty ? try? NSRegularExpression(pattern: expectedPattern, options: .caseInsensitive) : nil
                let initialUrl = activeTab.url?.absoluteString ?? ""
                var didStartNavigating = activeTab.isLoading
                let startTime = Date()

                while Date().timeIntervalSince(startTime) < (Double(timeoutMs) / 1000.0) {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    let curUrl = activeTab.url?.absoluteString ?? ""
                    let decodedUrl = curUrl.removingPercentEncoding ?? curUrl
                    if activeTab.isLoading {
                        didStartNavigating = true
                    }
                    if !expectedPattern.isEmpty {
                        let matchesSubstring = curUrl.contains(expectedPattern) || decodedUrl.contains(expectedPattern)
                        let matchesRegex: Bool
                        if let regex = regex {
                            let rangeCur = NSRange(curUrl.startIndex..., in: curUrl)
                            let rangeDecoded = NSRange(decodedUrl.startIndex..., in: decodedUrl)
                            matchesRegex = regex.firstMatch(in: curUrl, options: [], range: rangeCur) != nil ||
                                           regex.firstMatch(in: decodedUrl, options: [], range: rangeDecoded) != nil
                        } else {
                            matchesRegex = false
                        }
                        if (matchesSubstring || matchesRegex) && !activeTab.isLoading {
                            sendJSON(connection: connection, object: ["success": true, "message": "Navigated to \(curUrl)", "url": curUrl], origin: origin)
                            return true
                        }
                    } else {
                        let urlChanged = (!initialUrl.isEmpty && curUrl != initialUrl)
                        let finishedAfterStart = activeTab.lastNavigationFinishTime.map { $0 >= startTime } ?? false
                        if (didStartNavigating || urlChanged || finishedAfterStart) && !activeTab.isLoading {
                            sendJSON(connection: connection, object: ["success": true, "message": "Navigation finished", "url": curUrl], origin: origin)
                            return true
                        }
                    }
                }
                let timeoutMsg = !expectedPattern.isEmpty ? "Exceeded max wait of \(timeoutMs)ms waiting for navigation to \(expectedPattern)" : "Exceeded max wait of \(timeoutMs)ms waiting for navigation (no navigation observed)"
                sendJSON(connection: connection, object: ["success": false, "reason": "timeout", "message": timeoutMsg], origin: origin)

            case "timeout", "sleep", "delay":
                try? await Task.sleep(nanoseconds: UInt64(durationMs) * 1_000_000)
                sendJSON(connection: connection, object: ["success": true, "waitedMs": durationMs], origin: origin)

            default:
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Unknown wait mode: \(mode)\",\"code\":\"INVALID_WAIT_MODE\",\"success\":false}", origin: origin)
            }
            return true

        default:
            return false
        }
    }
}

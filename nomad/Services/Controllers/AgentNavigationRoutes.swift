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
                    if NomadAgentServer.isSensitivePath(filePath) {
                        sendResponse(connection: connection, status: "403 Forbidden", body: "{\"error\":\"Access to sensitive directory or credential file is blocked by Nomad security policy.\",\"code\":\"ACCESS_DENIED\",\"success\":false}", origin: origin)
                        return true
                    }
                }
                let mySeq = activeTab.navigationSeq + 1
                activeTab.load(url: url)
                // Await navigation resolution (commitment or provisional failure) up to 5.0 seconds
                var navError: String? = nil
                var superseded = false
                let navStart = Date()
                while Date().timeIntervalSince(navStart) < 5.0 {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    if activeTab.navigationSeq != mySeq {
                        superseded = true
                        break
                    }
                    if activeTab.lastFailedNavigationSeq == mySeq, let err = activeTab.lastNavigationError {
                        navError = err
                        break
                    }
                    if activeTab.committedNavigationSeq >= mySeq {
                        // Navigation successfully committed or finished
                        break
                    }
                }
                if superseded {
                    NomadRouteCache.shared.record(eventType: "navigationCancelled", message: "Navigation superseded for \(url.absoluteString)", tabId: activeTab.id.uuidString)
                    sendJSON(connection: connection, status: "409 Conflict", object: ["success": false, "cancelled": true, "code": "NAVIGATION_SUPERSEDED", "reason": "superseded", "navigatedTo": url.absoluteString], origin: origin)
                } else if let navError = navError {
                    NomadRouteCache.shared.record(eventType: "navigationError", message: "Navigation failed for \(url.absoluteString): \(navError)", tabId: activeTab.id.uuidString)
                    sendJSON(connection: connection, status: "502 Bad Gateway", object: ["success": false, "error": navError, "code": "NAVIGATION_FAILED", "navigatedTo": url.absoluteString], origin: origin)
                } else {
                    var resolvedTitle = activeTab.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if resolvedTitle.isEmpty && activeTab.title != "New Tab" && !activeTab.title.isEmpty {
                        resolvedTitle = activeTab.title
                    }
                    if resolvedTitle.isEmpty || resolvedTitle == "New Tab" {
                        if let docTitle = (try? await activeTab.webView.evaluateJavaScript("document.title")) as? String,
                           !docTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            resolvedTitle = docTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            activeTab.title = resolvedTitle
                        } else {
                            resolvedTitle = url.host ?? activeTab.title
                        }
                    }
                    NomadRouteCache.shared.record(eventType: "navigation", message: "Navigated to \(url.absoluteString)", tabId: activeTab.id.uuidString)
                    sendJSON(connection: connection, status: "200 OK", object: ["success": true, "navigatedTo": url.absoluteString, "title": resolvedTitle], origin: origin)
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
            var mode = "auto"
            var quietMs = 250
            var timeoutMs = 5000
            var durationMs = 1000
            var selector = ""
            var urlPattern = ""
            var textPattern = queryItem("text") ?? ""
            var stateExpected = queryItem("state")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            var idleMs = 500
            var tid: String? = nil

            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                tid = json["tabId"] as? String
                if let m = json["mode"] as? String { mode = m.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if let q = json["quietMs"] as? Int { quietMs = q }
                if let t = json["timeoutMs"] as? Int { timeoutMs = t }
                if let d = json["durationMs"] as? Int { durationMs = d }
                if let s = json["selector"] as? String { selector = s }
                if let u = json["urlPattern"] as? String { urlPattern = u }
                if let u = json["url"] as? String, urlPattern.isEmpty { urlPattern = u }
                if let tp = json["text"] as? String { textPattern = tp }
                if let st = json["state"] as? String { stateExpected = st.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if let i = json["idleMs"] as? Int { idleMs = i }
            }
            if !textPattern.isEmpty && (mode == "auto" || mode == "default") { mode = "text" }
            if !stateExpected.isEmpty && (mode == "auto" || mode == "default") { mode = "state" }
            if mode.isEmpty { mode = "auto" }

            guard let activeTab = requireTab(id: tid, connection: connection, origin: origin) else { return true }

            switch mode {
            case "auto", "default":
                let startTime = Date()
                let maxTimeoutSec = Double(timeoutMs) / 1000.0

                // 1. Navigation check: if active page is navigating, wait for it to settle
                if activeTab.isLoading {
                    await activeTab.waitForNavigationSettled(timeout: max(0.5, maxTimeoutSec - Date().timeIntervalSince(startTime)))
                }

                // Ensure document readyState is not 'loading'
                let readyDeadline = Date().addingTimeInterval(min(2.0, max(0.2, maxTimeoutSec - Date().timeIntervalSince(startTime))))
                while Date() < readyDeadline {
                    let readyState = (try? await activeTab.webView.evaluateJavaScript("document.readyState")) as? String
                    if readyState != "loading" { break }
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }

                // 2. Target readiness check (if selector or elementId is passed)
                var targetAppeared = false
                if !selector.isEmpty {
                    let escapedSelector: String
                    if let data = try? JSONEncoder().encode(selector), let str = String(data: data, encoding: .utf8) {
                        escapedSelector = str
                    } else {
                        escapedSelector = "\"\(selector)\""
                    }
                    let checkScript = """
                    (() => {
                        var sel = \(escapedSelector);
                        if (window.__nomad && window.__nomad.findInTree) {
                            try { if (window.__nomad.findInTree(document, sel)) return true; } catch(e) {}
                        }
                        try { if (document.querySelector(sel) || document.querySelector('[data-nomad-id="' + sel + '"]')) return true; } catch(e) {}
                        return false;
                    })()
                    """
                    let selectorDeadline = Date().addingTimeInterval(max(0.1, maxTimeoutSec - Date().timeIntervalSince(startTime)))
                    while Date() < selectorDeadline {
                        let found = (try? await activeTab.webView.evaluateJavaScript(checkScript)) as? Bool ?? false
                        if found {
                            targetAppeared = true
                            break
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }

                // 3. Network inflight check: wait for inflight network requests to settle (200ms quiet window, capped at 2.5s)
                let netCap = min(2.5, max(0.2, maxTimeoutSec - Date().timeIntervalSince(startTime)))
                let netDeadline = Date().addingTimeInterval(netCap)
                var netQuietStart = Date()
                while Date() < netDeadline {
                    let inflightCount = (try? await activeTab.webView.evaluateJavaScript("window.__nomad_inflight_count || 0")) as? Int ?? 0
                    if inflightCount > 0 {
                        netQuietStart = Date()
                        try? await Task.sleep(nanoseconds: 60_000_000)
                    } else {
                        if Date().timeIntervalSince(netQuietStart) >= 0.2 {
                            break
                        }
                        try? await Task.sleep(nanoseconds: 40_000_000)
                    }
                }

                // 4. DOM stability check: await DOM mutation quiet period
                let remainingSec = max(0.1, maxTimeoutSec - Date().timeIntervalSince(startTime))
                let remainingMs = Int(remainingSec * 1000.0)
                do {
                    let stabilityResult = try await activeTab.waitForStability(quietMs: min(quietMs, 200), timeoutMs: remainingMs)
                    var response: [String: Any] = [
                        "success": true,
                        "mode": "auto",
                        "message": "Page settled (navigation, network, and DOM stable)"
                    ]
                    if !selector.isEmpty {
                        response["selector"] = selector
                        response["targetAppeared"] = targetAppeared
                    }
                    if let mut = stabilityResult["mutations"] as? Int {
                        response["mutations"] = mut
                    }
                    sendJSON(connection: connection, object: response, origin: origin)
                } catch {
                    sendJSON(connection: connection, object: [
                        "success": true,
                        "mode": "auto",
                        "message": "Auto-wait completed with fallback stability: \(error.localizedDescription)"
                    ], origin: origin)
                }

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

            case "text":
                guard !textPattern.isEmpty else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing 'text' parameter for wait text mode\",\"code\":\"MISSING_TEXT\",\"success\":false}", origin: origin)
                    return true
                }
                let startTime = Date()
                let maxDuration = Double(timeoutMs) / 1000.0
                let escapedText: String = (try? String(data: JSONEncoder().encode(textPattern), encoding: .utf8)) ?? "\"\(textPattern)\""
                let escapedSel: String = selector.isEmpty ? "null" : ((try? String(data: JSONEncoder().encode(selector), encoding: .utf8)) ?? "\"\(selector)\"")

                let checkTextScript = """
                (() => {
                    var targetText = \(escapedText).toLowerCase();
                    var sel = \(escapedSel);
                    var root = document;
                    if (sel) {
                        if (window.__nomad && window.__nomad.findInTree) {
                            try { root = window.__nomad.findInTree(document, sel) || document.querySelector(sel); } catch(e) {}
                        } else {
                            try { root = document.querySelector(sel); } catch(e) {}
                        }
                    }
                    if (!root) return false;
                    var content = (root.innerText || root.textContent || '').toLowerCase();
                    return content.indexOf(targetText) !== -1;
                })()
                """

                var matched = false
                while Date().timeIntervalSince(startTime) < maxDuration {
                    if !activeTab.isLoading {
                        let res = (try? await activeTab.webView.evaluateJavaScript(checkTextScript)) as? Bool ?? false
                        if res {
                            matched = true
                            break
                        }
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }

                if matched {
                    sendJSON(connection: connection, object: ["success": true, "text": textPattern, "message": "Text appeared in page"], origin: origin)
                } else {
                    sendJSON(connection: connection, object: ["success": false, "reason": "timeout", "message": "Timeout waiting for text '\(textPattern)'"], origin: origin)
                }

            case "state":
                guard !selector.isEmpty else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing 'selector' parameter for wait state mode\",\"code\":\"MISSING_SELECTOR\",\"success\":false}", origin: origin)
                    return true
                }
                let startTime = Date()
                let maxDuration = Double(timeoutMs) / 1000.0
                let escapedSel: String = (try? String(data: JSONEncoder().encode(selector), encoding: .utf8)) ?? "\"\(selector)\""
                let escapedState: String = (try? String(data: JSONEncoder().encode(stateExpected), encoding: .utf8)) ?? "\"\(stateExpected)\""

                let checkStateScript = """
                (() => {
                    var sel = \(escapedSel);
                    var expected = \(escapedState).toLowerCase();
                    var el = null;
                    if (window.__nomad && window.__nomad.findInTree) {
                        try { el = window.__nomad.findInTree(document, sel) || document.querySelector(sel); } catch(e) {}
                    } else {
                        try { el = document.querySelector(sel); } catch(e) {}
                    }
                    if (!el) return expected === 'hidden' || expected === 'detached';
                    var style = window.getComputedStyle(el);
                    var isVisible = (style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0' && (el.offsetWidth > 0 || el.offsetHeight > 0));
                    switch(expected) {
                        case 'visible': return isVisible;
                        case 'hidden': return !isVisible;
                        case 'enabled': return !el.disabled && !el.hasAttribute('disabled');
                        case 'disabled': return Boolean(el.disabled || el.hasAttribute('disabled'));
                        case 'checked': return Boolean(el.checked || el.getAttribute('aria-checked') === 'true');
                        case 'unchecked': return !el.checked && el.getAttribute('aria-checked') !== 'true';
                        case 'focused': return document.activeElement === el;
                        default:
                            if (el.getAttribute(expected) !== null) return true;
                            if (String(el.value || '').toLowerCase() === expected) return true;
                            return false;
                    }
                })()
                """

                var matched = false
                while Date().timeIntervalSince(startTime) < maxDuration {
                    if !activeTab.isLoading {
                        let res = (try? await activeTab.webView.evaluateJavaScript(checkStateScript)) as? Bool ?? false
                        if res {
                            matched = true
                            break
                        }
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }

                if matched {
                    sendJSON(connection: connection, object: ["success": true, "selector": selector, "state": stateExpected, "message": "Element reached state '\(stateExpected)'"], origin: origin)
                } else {
                    sendJSON(connection: connection, object: ["success": false, "reason": "timeout", "message": "Timeout waiting for element '\(selector)' to reach state '\(stateExpected)'"], origin: origin)
                }

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

//
//  AgentPerceptionRoutes.swift
//  nomad
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import AppKit
import WebKit

extension NomadAgentServer {
    func handlePerceptionRoute(method: String, cleanPath: String, bodyData: Data?, queryItem: (String) -> String?, connection: NWConnection, origin: String?) async -> Bool {
        func queryBool(_ name: String, default defaultValue: Bool = false) -> Bool {
            guard let val = queryItem(name) else { return defaultValue }
            return val == "true" || val == "1"
        }

        switch (method, cleanPath) {
        case ("GET", "/snapshot"), ("GET", "/tree"), ("POST", "/snapshot"), ("POST", "/tree"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var limit = queryItem("limit").flatMap(Int.init) ?? 100
            var offset = queryItem("offset").flatMap(Int.init) ?? 0
            var viewportOnly = queryBool("viewportOnly")
            var includeText = (queryItem("includeText") != "false" && queryItem("includeText") != "0")
            var mode = queryItem("mode")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var roleFilter = queryItem("role")?.trimmingCharacters(in: .whitespacesAndNewlines)
            var textFilter = queryItem("text")?.trimmingCharacters(in: .whitespacesAndNewlines)
            var target = queryItem("target")?.trimmingCharacters(in: .whitespacesAndNewlines)
            var depth = queryItem("depth").flatMap(Int.init)
            var track = queryBool("track")
            var isUnrestricted = queryBool("unrestricted") || queryBool("force")
            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let l = json["limit"] as? Int { limit = l }
                if let o = json["offset"] as? Int { offset = o }
                if let v = json["viewportOnly"] as? Bool { viewportOnly = v }
                if let it = json["includeText"] as? Bool { includeText = it }
                if let m = json["mode"] as? String { mode = m.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if let r = json["role"] as? String { roleFilter = r.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let t = json["text"] as? String { textFilter = t.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let tgt = json["target"] as? String { target = tgt.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let d = json["depth"] as? Int { depth = d }
                if let trk = json["track"] as? Bool { track = trk }
                if let u = json["unrestricted"] as? Bool { isUnrestricted = u }
                if let f = json["force"] as? Bool { isUnrestricted = isUnrestricted || f }
            }
            if let m = mode, !m.isEmpty {
                guard ["text", "summary", "json", "full"].contains(m) else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Invalid snapshot mode '\(m)'. Expected 'text' or 'json'\",\"code\":\"INVALID_MODE\",\"success\":false}", origin: origin)
                    return true
                }
            }

            var snapshotWarning: String? = nil
            var isClamped = false
            var notice: String? = nil
            if (mode == "json" || mode == "full") && !isUnrestricted && limit > 250 {
                let originalLimit = limit
                limit = 250
                isClamped = true
                snapshotWarning = "JSON mode limit was clamped from \(originalLimit) to 250 elements to prevent excessive token consumption (~110 tokens/element). Pass 'unrestricted=true' to bypass, or use default mode='text' (~20 tokens/element) for ~100x lower cost."
                notice = "Output clamped to 250 elements to prevent context blowup (~110 tokens/element). Pass 'unrestricted=true' to fetch all, use limit/offset pagination, or switch to default mode: 'text' (~20 tokens/element) to ingest the full page in ~1,200 tokens."
            }

            do {
                let snapshot = try await activeTab.getSemanticTree(
                    limit: limit,
                    offset: offset,
                    viewportOnly: viewportOnly,
                    includeText: includeText,
                    role: (roleFilter?.isEmpty == false) ? roleFilter : nil,
                    text: (textFilter?.isEmpty == false) ? textFilter : nil,
                    target: (target?.isEmpty == false) ? target : nil,
                    depth: depth,
                    track: track
                )
                if mode == "json" || mode == "full" {
                    var fullSnapshot = snapshot
                    fullSnapshot.isClamped = isClamped
                    fullSnapshot.unclampedTotal = snapshot.filteredTotal ?? snapshot.totalElements ?? snapshot.elements.count
                    if isClamped {
                        fullSnapshot.notice = notice
                    }
                    // Compute accurate full token estimate including the elements array
                    let rawData = try JSONEncoder().encode(snapshot)
                    let fullTokens = max(1, Int(ceil(Double(rawData.count) / 4.0)))
                    fullSnapshot.tokenEstimate = fullTokens
                    if let w = snapshotWarning {
                        fullSnapshot.warning = w
                    } else if fullTokens > 20_000 {
                        fullSnapshot.warning = "High token count (\(fullTokens) tokens). Consider using text mode (summary) or adding filters (e.g., viewportOnly=true, role=a, text=...) for ~100x token savings."
                    }
                    let data = try JSONEncoder().encode(fullSnapshot)
                    sendRaw(connection: connection, contentType: "application/json; charset=utf-8", data: data, origin: origin)
                } else {
                    // Default perception mode (mode == nil, "text", or "summary"): compact semantic markdown
                    let textTokens = max(1, Int(ceil(Double(snapshot.summary.utf8.count) / 4.0)))
                    var resp: [String: Any] = [
                        "success": true,
                        "title": snapshot.title,
                        "url": snapshot.url,
                        "summary": snapshot.summary,
                        "tokenEstimate": textTokens
                    ]
                    if let te = snapshot.totalElements { resp["totalElements"] = te }
                    if let ft = snapshot.filteredTotal { resp["filteredTotal"] = ft }
                    if let ut = snapshot.unfilteredTotal { resp["unfilteredTotal"] = ut }
                    if let tgt = snapshot.target { resp["target"] = tgt }
                    if let trk = snapshot.tracked { resp["tracked"] = trk }
                    if let w = snapshot.warning ?? snapshotWarning { resp["warning"] = w }
                    sendJSON(connection: connection, object: resp, origin: origin)
                }
            } catch {
                sendJSON(connection: connection, object: ["success": false, "error": error.localizedDescription, "code": "SNAPSHOT_ERROR"], origin: origin)
            }
            return true

        case ("GET", "/find"), ("POST", "/find"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var roleQ = queryItem("role")?.trimmingCharacters(in: .whitespacesAndNewlines)
            var textQ = queryItem("text")?.trimmingCharacters(in: .whitespacesAndNewlines)
            var selQ = queryItem("selector")?.trimmingCharacters(in: .whitespacesAndNewlines)
            var vpOnly = queryBool("viewportOnly") || queryBool("viewport")

            if method == "POST", let bodyData = bodyData, !bodyData.isEmpty,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let r = json["role"] as? String { roleQ = r.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let t = json["text"] as? String { textQ = t.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let s = json["selector"] as? String { selQ = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let v = json["viewportOnly"] as? Bool { vpOnly = v }
            }

            let escapedRole: String = roleQ.map { (try? String(data: JSONEncoder().encode($0), encoding: .utf8)) ?? "null" } ?? "null"
            let escapedText: String = textQ.map { (try? String(data: JSONEncoder().encode($0), encoding: .utf8)) ?? "null" } ?? "null"
            let escapedSel: String = selQ.map { (try? String(data: JSONEncoder().encode($0), encoding: .utf8)) ?? "null" } ?? "null"

            await activeTab.ensureNomadScriptInjected()
            let findScript = """
            (() => {
                if (!window.__nomad) return null;
                var snap = window.__nomad.getSemanticTree();
                var elements = (snap && snap.elements) ? snap.elements : [];
                var role = \(escapedRole);
                var text = \(escapedText);
                var selector = \(escapedSel);
                var vpOnly = \(vpOnly ? "true" : "false");

                for (var i = 0; i < elements.length; i++) {
                    var el = elements[i];
                    if (vpOnly && !el.inViewport) continue;
                    if (role) {
                        var elRole = (el.role || '').toLowerCase();
                        var targetRole = role.toLowerCase();
                        if (elRole !== targetRole) {
                            if (!(targetRole === 'textbox' && elRole === 'searchbox')) continue;
                        }
                    }
                    if (text) {
                        var combined = ((el.text || '') + ' ' + (el.value || '')).toLowerCase();
                        if (combined.indexOf(text.toLowerCase()) === -1) continue;
                    }
                    if (selector) {
                        try {
                            var domEl = window.__nomad.elements && window.__nomad.elements[el.id];
                            if (!domEl || !domEl.matches(selector)) continue;
                        } catch(e) { continue; }
                    }
                    return {
                        success: true,
                        ref: el.id,
                        role: el.role,
                        tag: el.tag,
                        text: el.text || el.value || '',
                        inViewport: el.inViewport,
                        bounds: el.bounds
                    };
                }
                return { success: false, code: "ELEMENT_NOT_FOUND", message: "No element found matching query" };
            })()
            """

            if let result = try? await activeTab.webView.evaluateJavaScript(findScript) as? [String: Any],
               let success = result["success"] as? Bool, success {
                sendJSON(connection: connection, object: result, origin: origin)
            } else {
                sendResponse(connection: connection, status: "404 Not Found", body: "{\"success\":false,\"code\":\"ELEMENT_NOT_FOUND\",\"message\":\"No element found matching query\"}", origin: origin)
            }
            return true

        case ("GET", "/dialog"), ("POST", "/dialog"):
            var targetTabId = queryItem("tabId")
            var bodyJson: [String: Any]? = nil
            if method == "POST", let bodyData = bodyData, !bodyData.isEmpty {
                guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed JSON in dialog body\",\"code\":\"MALFORMED_JSON\",\"success\":false}", origin: origin)
                    return true
                }
                bodyJson = json
                if let t = json["tabId"] as? String { targetTabId = t }
            }

            guard let activeTab = requireTab(id: targetTabId, connection: connection, origin: origin) else { return true }

            let rawPolicy = (bodyJson?["policy"] as? String) ?? queryItem("policy")
            let rawAction = (bodyJson?["action"] as? String) ?? queryItem("action")
            let rawResponse = (bodyJson?["response"] as? String) ?? (bodyJson?["promptResponse"] as? String) ?? queryItem("response") ?? queryItem("promptResponse")

            // 1. Validate 'policy' if provided
            if let rawPolicy = rawPolicy {
                let cleanPolicy = rawPolicy.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard ["accept", "dismiss", "wait"].contains(cleanPolicy) else {
                    sendResponse(
                        connection: connection,
                        status: "400 Bad Request",
                        body: "{\"error\":\"Invalid dialog policy '\(rawPolicy)'. Expected 'accept', 'dismiss', or 'wait'\",\"code\":\"INVALID_POLICY\",\"success\":false}",
                        origin: origin
                    )
                    return true
                }
                activeTab.dialogPolicy = cleanPolicy
            }

            // 2. Validate 'action' if provided
            var actionToResolve: String? = nil
            if let rawAction = rawAction {
                let cleanAction = rawAction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard ["accept", "dismiss"].contains(cleanAction) else {
                    sendResponse(
                        connection: connection,
                        status: "400 Bad Request",
                        body: "{\"error\":\"Invalid dialog action '\(rawAction)'. Expected 'accept' or 'dismiss'\",\"code\":\"INVALID_ACTION\",\"success\":false}",
                        origin: origin
                    )
                    return true
                }
                actionToResolve = cleanAction
                if rawPolicy == nil {
                    activeTab.dialogPolicy = cleanAction
                }
            }

            // 3. Update prompt response text if provided
            if let response = rawResponse {
                activeTab.dialogPromptResponse = response
            }

            // 4. If a dialog is waiting and an action or non-wait policy was specified, resolve it!
            let effectiveAction = actionToResolve ?? (activeTab.dialogPolicy == "wait" ? nil : activeTab.dialogPolicy)
            if let resolveAct = effectiveAction, activeTab.pendingDialog != nil {
                activeTab.resolvePendingDialog(action: resolveAct, responseText: activeTab.dialogPromptResponse)
            }

            var respObj: [String: Any] = [
                "success": true,
                "policy": activeTab.dialogPolicy,
                "response": activeTab.dialogPromptResponse,
                "lastDialog": (activeTab.lastDialog as Any?) ?? NSNull(),
                "hasPendingDialog": activeTab.pendingDialog != nil
            ]
            if let pending = activeTab.pendingDialog {
                var pObj: [String: Any] = [
                    "type": pending.type.rawValue,
                    "message": pending.message
                ]
                if let def = pending.defaultText { pObj["defaultText"] = def }
                respObj["pendingDialog"] = pObj
            }
            sendJSON(connection: connection, object: respObj, origin: origin)
            return true

        case ("GET", "/screenshot"), ("POST", "/screenshot"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var isLabeled = queryBool("labeled")
            var elementId: String? = queryItem("elementId") ?? queryItem("ref")
            var clipRect: CGRect? = nil
            if let clipStr = queryItem("clip") {
                let parts = clipStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 4, parts[2] > 0, parts[3] > 0, !parts[0].isNaN, !parts[1].isNaN, !parts[2].isNaN, !parts[3].isNaN else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Invalid clip parameter. Expected 4 positive numbers x,y,width,height\",\"code\":\"INVALID_CLIP\",\"success\":false}", origin: origin)
                    return true
                }
                clipRect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }
            if let bodyData = bodyData, !bodyData.isEmpty {
                guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed JSON in screenshot body\",\"code\":\"MALFORMED_JSON\",\"success\":false}", origin: origin)
                    return true
                }
                if let labeledBool = json["labeled"] as? Bool { isLabeled = labeledBool }
                if let elId = json["elementId"] as? String { elementId = elId }
                if let clipRaw = json["clip"] {
                    if let clipDict = clipRaw as? [String: Any],
                       let x = (clipDict["x"] as? NSNumber)?.doubleValue,
                       let y = (clipDict["y"] as? NSNumber)?.doubleValue,
                       let w = (clipDict["width"] as? NSNumber)?.doubleValue,
                       let h = (clipDict["height"] as? NSNumber)?.doubleValue,
                       w > 0, h > 0, !x.isNaN, !y.isNaN, !w.isNaN, !h.isNaN {
                        clipRect = CGRect(x: x, y: y, width: w, height: h)
                    } else if let clipStr = clipRaw as? String {
                        let parts = clipStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                        guard parts.count == 4, parts[2] > 0, parts[3] > 0, !parts[0].isNaN, !parts[1].isNaN, !parts[2].isNaN, !parts[3].isNaN else {
                            sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Invalid clip string in body. Expected x,y,width,height with positive dimensions\",\"code\":\"INVALID_CLIP\",\"success\":false}", origin: origin)
                            return true
                        }
                        clipRect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
                    } else {
                        sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Invalid clip object. Expected {x, y, width > 0, height > 0}\",\"code\":\"INVALID_CLIP\",\"success\":false}", origin: origin)
                        return true
                    }
                }
            }
            do {
                let image = try await activeTab.captureScreenshot(labeled: isLabeled, elementId: elementId, clip: clipRect)
                if let png = image.pngData {
                    sendRaw(connection: connection, contentType: "image/png", data: png, origin: origin)
                } else {
                    sendResponse(connection: connection, status: "500 Internal Server Error", body: "{\"error\":\"Failed to encode PNG data\",\"code\":\"PNG_ENCODE_FAILED\",\"success\":false}", origin: origin)
                }
            } catch {
                let errMsg = error.localizedDescription
                let code = errMsg.contains("not found") ? "ELEMENT_NOT_FOUND" : "SCREENSHOT_ERROR"
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"\(errMsg)\",\"code\":\"\(code)\",\"success\":false}", origin: origin)
            }
            return true

        default:
            return false
        }
    }
}

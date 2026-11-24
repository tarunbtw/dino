//
//  AgentPerceptionRoutes.swift
//  dino
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import AppKit
import WebKit
import PDFKit

extension DinoAgentServer {
    func handlePerceptionRoute(method: String, cleanPath: String, bodyData: Data?, queryItem: (String) -> String?, connection: NWConnection, origin: String?) async -> Bool {
        func queryBool(_ name: String, default defaultValue: Bool = false) -> Bool {
            Self.queryBool(name, from: queryItem, default: defaultValue)
        }

        switch (method, cleanPath) {
        case ("GET", "/snapshot"), ("GET", "/tree"), ("POST", "/snapshot"), ("POST", "/tree"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var userLimit: Int? = queryItem("limit").flatMap(Int.init)
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
            var includeSummary = queryBool("summary") || queryBool("includeSummary")
            if let bodyData = bodyData,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let l = json["limit"] as? Int { userLimit = l }
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
                if let s = json["includeSummary"] as? Bool ?? json["summary"] as? Bool { includeSummary = s }
            }
            if let m = mode, !m.isEmpty {
                guard ["text", "summary", "json", "full"].contains(m) else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Invalid snapshot mode '\(m)'. Expected 'text' or 'json'\",\"code\":\"INVALID_MODE\",\"success\":false}", origin: origin)
                    return true
                }
            }

            let isJsonMode = (mode == "json" || mode == "full")

            let currentURL = activeTab.webView.url ?? activeTab.url
            if let url = currentURL, url.pathExtension.lowercased() == "pdf" {
                if let pdfDoc = PDFDocument(url: url) {
                    let pageCount = pdfDoc.pageCount
                    var pageStrings: [String] = []
                    let maxPages = min(pageCount, 30)
                    for i in 0..<maxPages {
                        if let page = pdfDoc.page(at: i), let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            pageStrings.append("### Page \(i + 1) of \(pageCount)\n\(text)")
                        }
                    }
                    if pageStrings.isEmpty {
                        pageStrings.append("[PDF Document with \(pageCount) page(s) has no extractable text layer or is scanned image]")
                    }
                    let title = (pdfDoc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? url.lastPathComponent
                    let body = """
                    [Document: \(title) | Format: PDF | Pages: \(pageCount)]

                    \(pageStrings.joined(separator: "\n\n"))
                    """
                    let fullSummary = "<!-- BEGIN UNTRUSTED WEB CONTENT (origin: \(url.absoluteString)) -->\n\(body)\n<!-- END UNTRUSTED WEB CONTENT -->"
                    let tokenEst = max(10, fullSummary.count / 4)

                    if isJsonMode {
                        sendJSON(connection: connection, object: [
                            "title": title,
                            "url": url.absoluteString,
                            "format": "pdf",
                            "pages": pageCount,
                            "elements": [],
                            "summary": fullSummary,
                            "tokenEstimate": tokenEst
                        ], origin: origin)
                    } else {
                        sendResponse(connection: connection, status: "200 OK", body: fullSummary, origin: origin)
                    }
                    return true
                }
            }

            var limit: Int
            var snapshotWarning: String? = nil
            var isClamped = false
            var notice: String? = nil

            if let specified = userLimit {
                if isJsonMode && !isUnrestricted && specified > 250 {
                    limit = 250
                    isClamped = true
                    snapshotWarning = "JSON mode limit was clamped from \(specified) to 250 elements to prevent excessive token consumption (~110 tokens/element). Pass 'unrestricted=true' to bypass, or use default mode='text' (~20 tokens/element) for ~100x lower cost."
                    notice = "Output clamped to 250 elements to prevent context blowup (~110 tokens/element). Pass 'unrestricted=true' to fetch all, use limit/offset pagination, or switch to default mode: 'text' (~20 tokens/element) to ingest the full page in ~1,200 tokens."
                } else {
                    limit = specified
                }
            } else {
                if isUnrestricted {
                    limit = -1
                } else if isJsonMode {
                    limit = 250
                } else {
                    limit = 100
                }
            }

            let includeCoords = (queryItem("coords") == "true") || (queryItem("includeCoords") == "true") || (queryItem("box") == "true")

            do {
                let snapshot = try await activeTab.getSemanticTree(
                    limit: limit,
                    offset: offset,
                    viewportOnly: viewportOnly,
                    includeText: includeText,
                    includeCoords: includeCoords,
                    role: (roleFilter?.isEmpty == false) ? roleFilter : nil,
                    text: (textFilter?.isEmpty == false) ? textFilter : nil,
                    target: (target?.isEmpty == false) ? target : nil,
                    depth: depth,
                    track: track
                )
                if isJsonMode {
                    var fullSnapshot = snapshot
                    let totalAvailable = snapshot.filteredTotal ?? snapshot.totalElements ?? snapshot.elements.count
                    if !isUnrestricted && totalAvailable > snapshot.elements.count {
                        isClamped = true
                        if notice == nil {
                            notice = "Output clamped to \(snapshot.elements.count) elements to prevent context blowup (~110 tokens/element). Pass 'unrestricted=true' to fetch all, use limit/offset pagination, or switch to default mode: 'text' (~20 tokens/element) to ingest the full page in ~1,200 tokens."
                        }
                    }
                    fullSnapshot.isClamped = isClamped
                    fullSnapshot.unclampedTotal = totalAvailable
                    if isClamped {
                        fullSnapshot.notice = notice
                    }
                    if !includeSummary {
                        fullSnapshot.summary = nil
                    }
                    // Compute accurate full token estimate including the elements array
                    let rawData = try JSONEncoder().encode(fullSnapshot)
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
                    let summaryText = snapshot.summary ?? ""
                    let textTokens = max(1, Int(ceil(Double(summaryText.utf8.count) / 4.0)))
                    var resp: [String: Any] = [
                        "success": true,
                        "title": snapshot.title,
                        "url": snapshot.url,
                        "summary": summaryText,
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

            await activeTab.ensureDinoScriptInjected()
            let findScript = """
            (() => {
                if (!window.__dino) return null;
                var role = \(escapedRole);
                var text = \(escapedText);
                var selector = \(escapedSel);
                var vpOnly = \(vpOnly ? "true" : "false");
                var snap = window.__dino.getSemanticTree({
                    limit: -1,
                    role: role,
                    text: text,
                    viewportOnly: vpOnly
                });
                var elements = (snap && snap.elements) ? snap.elements : [];

                var bestCandidate = null;
                var bestScore = -999999;

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
                            var domEl = window.__dino.elements && window.__dino.elements[el.id];
                            if (!domEl || !domEl.matches(selector)) continue;
                        } catch(e) { continue; }
                    }

                    // Heuristic relevance scoring:
                    var score = 0;
                    var t = (el.tag || '').toLowerCase();
                    var r = (el.role || '').toLowerCase();
                    var isActionable = (t === 'a' || t === 'button' || t === 'input' || t === 'textarea' || t === 'select' || r === 'button' || r === 'link' || r === 'checkbox' || r === 'radio' || r === 'tab' || r === 'menuitem');
                    if (isActionable) score += 100;
                    if (t === 'td' || t === 'th' || t === 'tr' || t === 'table') score -= 50;

                    if (text) {
                        var rawT = ((el.text || '') + ' ' + (el.value || '')).trim().toLowerCase();
                        var qT = text.trim().toLowerCase();
                        if (rawT === qT) {
                            score += 200; // Exact match bonus
                        } else if (rawT.indexOf(qT) === 0) {
                            score += 50;  // Prefix match bonus
                        }
                        // Penalize overly long text containers (e.g. td containing 500 chars)
                        score -= Math.min(60, Math.floor(rawT.length / 10));
                    }

                    if (score > bestScore) {
                        bestScore = score;
                        bestCandidate = el;
                    }
                }

                if (bestCandidate) {
                    return {
                        success: true,
                        ref: bestCandidate.id,
                        role: bestCandidate.role,
                        tag: bestCandidate.tag,
                        text: bestCandidate.text || bestCandidate.value || '',
                        inViewport: bestCandidate.inViewport,
                        bounds: bestCandidate.bounds
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

        case ("GET", "/find/semantic"), ("POST", "/find/semantic"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var query = queryItem("query")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? queryItem("q")?.trimmingCharacters(in: .whitespacesAndNewlines)
            var role = queryItem("role")?.trimmingCharacters(in: .whitespacesAndNewlines)
            var vpOnly = queryBool("viewportOnly") || queryBool("viewport")

            if method == "POST", let bodyData = bodyData, !bodyData.isEmpty,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let q = json["query"] as? String ?? json["q"] as? String { query = q.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let r = json["role"] as? String { role = r.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let v = json["viewportOnly"] as? Bool { vpOnly = v }
            }

            guard let cleanQuery = query, !cleanQuery.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing required 'query' parameter\",\"code\":\"MISSING_QUERY\",\"success\":false}", origin: origin)
                return true
            }

            do {
                let result = try await activeTab.findSemantic(query: cleanQuery, role: role, viewportOnly: vpOnly)
                let success = result["success"] as? Bool ?? false
                if success {
                    sendJSON(connection: connection, object: result, origin: origin)
                } else {
                    let code = (result["code"] as? String) ?? "SEMANTIC_MATCH_NOT_FOUND"
                    let msg = (result["message"] as? String) ?? "No element found matching semantic query"
                    sendResponse(connection: connection, status: "404 Not Found", body: "{\"success\":false,\"code\":\"\(code)\",\"message\":\"\(msg)\"}", origin: origin)
                }
            } catch {
                sendResponse(connection: connection, status: "500 Internal Server Error", body: "{\"error\":\"\(error.localizedDescription)\",\"code\":\"SEMANTIC_FIND_ERROR\",\"success\":false}", origin: origin)
            }
            return true

        case ("GET", "/diff"), ("POST", "/diff"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var vpOnly = queryBool("viewportOnly") || queryBool("viewport")
            var mode = queryItem("mode")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if method == "POST", let bodyData = bodyData, !bodyData.isEmpty,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let v = json["viewportOnly"] as? Bool { vpOnly = v }
                if let m = json["mode"] as? String { mode = m.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            }

            do {
                let diffDict = try await activeTab.getDiff(viewportOnly: vpOnly)
                if mode == "json" || mode == "full" {
                    sendJSON(connection: connection, object: diffDict, origin: origin)
                } else {
                    let summaryText = (diffDict["summary"] as? String) ?? ""
                    let tokens = (diffDict["tokenEstimate"] as? Int) ?? max(1, Int(ceil(Double(summaryText.utf8.count) / 4.0)))
                    let resp: [String: Any] = [
                        "success": true,
                        "title": diffDict["title"] ?? "",
                        "url": diffDict["url"] ?? "",
                        "summary": summaryText,
                        "tokenEstimate": tokens,
                        "hasBaseline": diffDict["hasBaseline"] ?? false,
                        "totalMutations": diffDict["totalMutations"] ?? 0,
                        "addedCount": diffDict["addedCount"] ?? 0,
                        "removedCount": diffDict["removedCount"] ?? 0,
                        "changedCount": diffDict["changedCount"] ?? 0
                    ]
                    sendJSON(connection: connection, object: resp, origin: origin)
                }
            } catch {
                sendJSON(connection: connection, object: ["success": false, "error": error.localizedDescription, "code": "DIFF_ERROR"], origin: origin)
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
            }

            // 3. Update prompt response text if provided
            if let response = rawResponse {
                activeTab.dialogPromptResponse = response
            }

            // 4. If a dialog is waiting and an action or non-wait policy was specified, resolve it!
            let effectiveAction = actionToResolve ?? (activeTab.dialogPolicy == "wait" ? nil : activeTab.dialogPolicy)
            if let resolveAct = effectiveAction, activeTab.pendingDialog != nil {
                activeTab.resolvePendingDialog(action: resolveAct, responseText: activeTab.dialogPromptResponse)
                // If the previous policy was "wait", one waiting dialog has been addressed; restore safe default "dismiss" unless caller explicitly supplied policy
                if rawPolicy == nil && activeTab.dialogPolicy == "wait" {
                    activeTab.dialogPolicy = "dismiss"
                }
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
            var isSomCrop = queryBool("somCrop") || queryBool("container") || queryBool("cropContainer")
            var isFullPage = queryBool("fullPage") || queryBool("fullpage")
            var elementId: String? = queryItem("elementId") ?? queryItem("ref")
            var clipRect: CGRect? = nil
            var scaleFactor: CGFloat? = nil
            if let scaleStr = queryItem("scale"), let sVal = Double(scaleStr), sVal > 0 {
                scaleFactor = CGFloat(sVal)
            }
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
                if let somBool = json["somCrop"] as? Bool ?? json["container"] as? Bool ?? json["cropContainer"] as? Bool { isSomCrop = somBool }
                if let fp = json["fullPage"] as? Bool ?? json["fullpage"] as? Bool { isFullPage = fp }
                if let elId = json["elementId"] as? String { elementId = elId }
                if let sNum = json["scale"] as? NSNumber, sNum.doubleValue > 0 {
                    scaleFactor = CGFloat(sNum.doubleValue)
                } else if let sStr = json["scale"] as? String, let sVal = Double(sStr), sVal > 0 {
                    scaleFactor = CGFloat(sVal)
                }
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
                let image = try await activeTab.captureScreenshot(labeled: isLabeled, elementId: elementId, clip: clipRect, somCrop: isSomCrop, fullPage: isFullPage)
                if let png = image.pngData(scale: scaleFactor) {
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

        case ("GET", "/pdf"), ("POST", "/pdf"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            let pdfConfig = WKPDFConfiguration()
            if let clipStr = queryItem("clip") {
                let parts = clipStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count == 4 && parts[2] > 0 && parts[3] > 0 && !parts[0].isNaN && !parts[1].isNaN && !parts[2].isNaN && !parts[3].isNaN {
                    pdfConfig.rect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
                }
            }
            if let bodyData = bodyData, !bodyData.isEmpty,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let clipDict = json["clip"] as? [String: Any],
                   let x = (clipDict["x"] as? NSNumber)?.doubleValue,
                   let y = (clipDict["y"] as? NSNumber)?.doubleValue,
                   let w = (clipDict["width"] as? NSNumber)?.doubleValue,
                   let h = (clipDict["height"] as? NSNumber)?.doubleValue,
                   w > 0, h > 0 {
                    pdfConfig.rect = CGRect(x: x, y: y, width: w, height: h)
                }
            }
            do {
                let pdfData = try await activeTab.generatePDF(configuration: pdfConfig)
                sendRaw(connection: connection, contentType: "application/pdf", data: pdfData, origin: origin)
            } catch {
                sendResponse(connection: connection, status: "500 Internal Server Error", body: "{\"error\":\"\(error.localizedDescription)\",\"code\":\"PDF_EXPORT_FAILED\",\"success\":false}", origin: origin)
            }
            return true

        case ("GET", "/extract"), ("POST", "/extract"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            var selector: String? = queryItem("selector") ?? queryItem("target") ?? queryItem("s")
            var mode: String = queryItem("mode") ?? queryItem("m") ?? "auto"

            if let bodyData = bodyData, !bodyData.isEmpty,
               let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let s = json["selector"] as? String ?? json["target"] as? String { selector = s }
                if let m = json["mode"] as? String { mode = m }
            }

            let selArg = selector ?? ""
            let script = "return window.__dino && window.__dino.extract ? window.__dino.extract(selector || null, mode) : null;"
            let res = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
                activeTab.webView.callAsyncJavaScript(script, arguments: ["selector": selArg, "mode": mode], in: nil, in: .page) { result in
                    continuation.resume(with: result)
                }
            }

            if let dict = res as? [String: Any], let success = dict["success"] as? Bool, success {
                sendJSON(connection: connection, object: dict, origin: origin)
            } else if let dict = res as? [String: Any] {
                let msg = (dict["message"] as? String) ?? "Failed to extract structured data from page"
                let code = (dict["code"] as? String) ?? "EXTRACT_FAILED"
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"\(msg)\",\"code\":\"\(code)\",\"success\":false}", origin: origin)
            } else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Extraction produced no data or core script not ready\",\"code\":\"NO_DATA\",\"success\":false}", origin: origin)
            }
            return true

        case ("GET", "/view"), ("HEAD", "/view"):
            let html = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Dino Live Observability View</title>
              <style>
                body { margin: 0; padding: 0; background: #0c0d12; color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; overflow: hidden; }
                .badge { position: fixed; top: 18px; left: 24px; display: flex; align-items: center; gap: 8px; z-index: 100; font-size: 13px; font-weight: 600; color: #e5e7eb; background: rgba(18, 20, 28, 0.85); padding: 7px 16px; border-radius: 9999px; backdrop-filter: blur(12px); border: 1px solid rgba(255,255,255,0.12); box-shadow: 0 4px 12px rgba(0,0,0,0.4); }
                .pulse { width: 9px; height: 9px; border-radius: 50%; background: #10b981; box-shadow: 0 0 10px #10b981; animation: livePulse 2s infinite ease-in-out; }
                @keyframes livePulse { 0%, 100% { transform: scale(1); opacity: 1; } 50% { transform: scale(1.3); opacity: 0.6; } }
                .screen { max-width: 95vw; max-height: 88vh; border-radius: 12px; overflow: hidden; box-shadow: 0 20px 50px rgba(0,0,0,0.85); border: 1px solid rgba(255,255,255,0.15); background: #000; display: flex; align-items: center; justify-content: center; }
                img { display: block; max-width: 100%; max-height: 88vh; object-fit: contain; }
              </style>
            </head>
            <body>
              <div class="badge"><div class="pulse"></div> Dino Live Observability (15 FPS)</div>
              <div class="screen">
                <img src="/stream" alt="Live View Stream" />
              </div>
            </body>
            </html>
            """
            sendRaw(connection: connection, contentType: "text/html; charset=utf-8", data: Data(html.utf8), origin: origin)
            return true

        case ("GET", "/stream"), ("HEAD", "/stream"):
            guard let activeTab = requireTab(id: queryItem("tabId"), connection: connection, origin: origin) else { return true }
            let initialHeaders = """
            HTTP/1.1 200 OK\r
            Content-Type: multipart/x-mixed-replace; boundary=--frame\r
            Cache-Control: no-cache, no-store, must-revalidate\r
            Connection: close\r
            Access-Control-Allow-Origin: *\r\n\r\n
            """
            if method == "HEAD" {
                connection.send(content: Data(initialHeaders.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return true
            }
            connection.send(content: Data(initialHeaders.utf8), completion: .contentProcessed { [weak activeTab] err in
                guard err == nil, let tab = activeTab else {
                    connection.cancel()
                    return
                }
                Task { @MainActor in
                    while connection.state == .ready {
                        let config = WKSnapshotConfiguration()
                        let viewWidth = tab.webView.frame.width > 0 ? tab.webView.frame.width : 1280
                        config.snapshotWidth = NSNumber(value: Double(viewWidth))
                        if let img = try? await withCheckedThrowingContinuation({ (c: CheckedContinuation<NSImage, Error>) in
                            tab.webView.takeSnapshot(with: config) { i, e in
                                if let e = e { c.resume(throwing: e) }
                                else if let i = i { c.resume(returning: i) }
                                else { c.resume(throwing: NSError(domain: "Dino", code: -1)) }
                            }
                        }),
                           let tiff = img.tiffRepresentation,
                           let rep = NSBitmapImageRep(data: tiff),
                           let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                            var frameHeader = "--frame\r\n"
                            frameHeader += "Content-Type: image/jpeg\r\n"
                            frameHeader += "Content-Length: \(jpeg.count)\r\n\r\n"
                            var frameData = Data(frameHeader.utf8)
                            frameData.append(jpeg)
                            frameData.append(Data("\r\n".utf8))
                            connection.send(content: frameData, completion: .contentProcessed { sendErr in
                                if sendErr != nil {
                                    connection.cancel()
                                }
                            })
                        }
                        try? await Task.sleep(nanoseconds: 66_000_000)
                    }
                }
            })
            return true

        default:
            return false
        }
    }
}

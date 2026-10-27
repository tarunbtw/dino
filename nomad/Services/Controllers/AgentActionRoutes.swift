//
//  AgentActionRoutes.swift
//  nomad
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import WebKit

extension NomadAgentServer {
    func handleActionRoute(method: String, cleanPath: String, bodyData: Data?, connection: NWConnection, origin: String?) async -> Bool {
        switch (method, cleanPath) {
        case ("POST", "/action"):
            guard let bodyData = bodyData, !bodyData.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing action body\",\"code\":\"MISSING_BODY\",\"success\":false}", origin: origin)
                return true
            }
            let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            if json == nil {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed JSON in action body\",\"code\":\"MALFORMED_JSON\",\"success\":false}", origin: origin)
                return true
            }
            let tid = json?["tabId"] as? String
            guard let activeTab = requireTab(id: tid, connection: connection, origin: origin) else { return true }
            do {
                let action = try JSONDecoder().decode(NomadAction.self, from: bodyData)
                let result = try await activeTab.performAction(action)
                let resData = try JSONEncoder().encode(result)
                sendRaw(connection: connection, contentType: "application/json; charset=utf-8", data: resData, origin: origin)
            } catch let decodingError as DecodingError {
                let msg: String
                switch decodingError {
                case .dataCorrupted(let ctx):
                    msg = ctx.debugDescription
                case .keyNotFound(let key, _):
                    msg = "Missing required key '\(key.stringValue)'"
                case .typeMismatch(_, let ctx):
                    msg = ctx.debugDescription
                case .valueNotFound(_, let ctx):
                    msg = ctx.debugDescription
                @unknown default:
                    msg = decodingError.localizedDescription
                }
                let code = msg.contains("dialog policy") ? "INVALID_POLICY" : "INVALID_ACTION_PAYLOAD"
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"\(msg)\",\"code\":\"\(code)\",\"success\":false}", origin: origin)
            } catch {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"\(error.localizedDescription)\",\"code\":\"ACTION_ERROR\",\"success\":false}", origin: origin)
            }
            return true

        case ("POST", "/upload"):
            guard let bodyData = bodyData, !bodyData.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing upload body\",\"code\":\"MISSING_BODY\",\"success\":false}", origin: origin)
                return true
            }
            guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed JSON in upload body\",\"code\":\"MALFORMED_JSON\",\"success\":false}", origin: origin)
                return true
            }
            let targetId = (json["elementId"] as? String) ?? (json["target"] as? String) ?? (json["selector"] as? String)
            guard let targetId = targetId, !targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing required 'elementId' or 'target' in upload body\",\"code\":\"MISSING_TARGET\",\"success\":false}", origin: origin)
                return true
            }
            var paths: [String] = []
            if let arr = json["paths"] as? [String] {
                paths = arr
            } else if let arr = json["files"] as? [String] {
                paths = arr
            } else if let single = json["path"] as? String {
                paths = [single]
            } else if let single = json["file"] as? String {
                paths = [single]
            }
            guard !paths.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing required 'paths' or 'files' array in upload body\",\"code\":\"MISSING_PATHS\",\"success\":false}", origin: origin)
                return true
            }
            let tid = json["tabId"] as? String
            guard let activeTab = requireTab(id: tid, connection: connection, origin: origin) else { return true }
            do {
                let action = NomadAction(action: "upload", target: targetId, paths: paths)
                let result = try await activeTab.performAction(action)
                let resData = try JSONEncoder().encode(result)
                sendRaw(connection: connection, contentType: "application/json; charset=utf-8", data: resData, origin: origin)
            } catch {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"\(error.localizedDescription)\",\"code\":\"UPLOAD_ERROR\",\"success\":false}", origin: origin)
            }
            return true

        case ("POST", "/evaluate"):
            guard let bodyData = bodyData, !bodyData.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing body in /evaluate\",\"code\":\"MISSING_BODY\",\"success\":false}", origin: origin)
                return true
            }
            guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed JSON in evaluate body\",\"code\":\"MALFORMED_JSON\",\"success\":false}", origin: origin)
                return true
            }
            guard let script = (json["script"] as? String) ?? (json["expression"] as? String) else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing script or expression string in body\",\"code\":\"MISSING_SCRIPT\",\"success\":false}", origin: origin)
                return true
            }
            let tid = json["tabId"] as? String
            guard let activeTab = requireTab(id: tid, connection: connection, origin: origin) else { return true }
            if activeTab.webView.isLoading {
                let start = Date()
                while activeTab.webView.isLoading && Date().timeIntervalSince(start) < 0.4 {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
                if activeTab.webView.isLoading {
                    sendJSON(connection: connection, object: [
                        "success": false,
                        "error": "Cannot evaluate script: active page is currently navigating. Wait for navigation to complete before evaluating scripts.",
                        "code": "NAVIGATION_BUSY"
                    ], origin: origin)
                    return true
                }
            }
            let worldParam = (json["world"] as? String)?.lowercased() ?? "isolated"
            let contentWorld: WKContentWorld = (worldParam == "page") ? .page : .defaultClient

            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            let wrappedScript = """
            return await (async (code) => {
                try {
                    const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
                    let fn;
                    // 1. If it parses as a direct expression, return it
                    try {
                        fn = new AsyncFunction("return (" + code + ");");
                        const val = await fn.call(window);
                        return { __nomad_ok: true, value: val };
                    } catch (_) {}

                    // 2. If it contains an explicit return statement, execute as function body
                    if (code.includes("return ") || code.includes("return;")) {
                        fn = new AsyncFunction(code);
                        const val = await fn.call(window);
                        return { __nomad_ok: true, value: val };
                    }

                    // 3. Multi-statement code without explicit return:
                    // Try evaluating with eval to capture completion value of last expression
                    try {
                        const val = await window.eval(code);
                        return { __nomad_ok: true, value: val };
                    } catch (evalErr) {
                        // 4. If window.eval fails (e.g. top-level await or strict CSP), try wrapping last statement in return
                        let lastLineRetried = false;
                        let val;
                        let lines = code.trim().split("\\n");
                        if (lines.length > 0) {
                            let last = lines[lines.length - 1].trim();
                            if (last && !last.startsWith("return ") && !last.startsWith("const ") && !last.startsWith("let ") && !last.startsWith("var ") && !last.startsWith("if ") && !last.startsWith("for ") && !last.startsWith("while ") && !last.startsWith("class ") && !last.startsWith("function ")) {
                                let expr = last.endsWith(";") ? last.slice(0, -1) : last;
                                let modified = lines.slice(0, -1).concat(["return (" + expr + ");"]);
                                try {
                                    let fnTry = new AsyncFunction(modified.join("\\n"));
                                    val = await fnTry.call(window);
                                    lastLineRetried = true;
                                } catch (_) {}
                            }
                        }
                        if (!lastLineRetried) {
                            fn = new AsyncFunction(code);
                            val = await fn.call(window);
                        }
                        return { __nomad_ok: true, value: val };
                    }
                } catch (err) {
                    return {
                        __nomad_ok: false,
                        error: (err && err.message) ? err.message : String(err),
                        stack: (err && err.stack) ? err.stack : null,
                        name: (err && err.name) ? err.name : 'Error'
                    };
                }
            })(code);
            """
            enum EvalRaceResult {
                case evaluated(Any?)
                case dialogAppeared(Tab.PendingDialog)
            }

            do {
                let raceResult: EvalRaceResult = try await withCheckedThrowingContinuation { continuation in
                    var resumed = false
                    let lock = NSLock()

                    activeTab.onDialogAppeared = { pending in
                        lock.lock()
                        defer { lock.unlock() }
                        if !resumed {
                            resumed = true
                            activeTab.onDialogAppeared = nil
                            continuation.resume(returning: .dialogAppeared(pending))
                        }
                    }

                    activeTab.webView.callAsyncJavaScript(wrappedScript, arguments: ["code": trimmed], in: nil, in: contentWorld) { result in
                        lock.lock()
                        defer { lock.unlock() }
                        if !resumed {
                            resumed = true
                            activeTab.onDialogAppeared = nil
                            switch result {
                            case .success(let val):
                                continuation.resume(returning: .evaluated(val))
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }

                let evalResult: Any?
                switch raceResult {
                case .dialogAppeared(let pending):
                    var pDict: [String: Any] = [
                        "type": pending.type.rawValue,
                        "message": pending.message
                    ]
                    if let def = pending.defaultText { pDict["defaultText"] = def }
                    let resp: [String: Any] = [
                        "success": true,
                        "code": "PENDING_DIALOG",
                        "hasPendingDialog": true,
                        "lastDialog": (activeTab.lastDialog as Any?) ?? NSNull(),
                        "pendingDialog": pDict
                    ]
                    sendJSON(connection: connection, object: resp, origin: origin)
                    return true

                case .evaluated(let val):
                    evalResult = val
                }

                if let dict = evalResult as? [String: Any], dict["__nomad_ok"] as? Bool == false {
                    let errMsg = dict["error"] as? String ?? "JavaScript evaluation failed"
                    let errStack = dict["stack"] as? String
                    let rawName = dict["name"] as? String ?? "Error"

                    let isCSP = rawName == "EvalError" || errMsg.contains("Content Security Policy") || errMsg.contains("CSP") || errMsg.contains("Refused to evaluate")
                    let isSyntax = rawName == "SyntaxError" || errMsg.contains("SyntaxError") || errMsg.contains("Unexpected token")
                    let isType = rawName == "TypeError"
                    let isRef = rawName == "ReferenceError"

                    let errCode: String
                    if isCSP {
                        errCode = "EVAL_CSP"
                    } else if isSyntax {
                        errCode = "SYNTAX_ERROR"
                    } else if isType {
                        errCode = "TYPE_ERROR"
                    } else if isRef {
                        errCode = "REFERENCE_ERROR"
                    } else {
                        errCode = "EVAL_ERROR"
                    }

                    var resp: [String: Any] = [
                        "success": false,
                        "error": errMsg,
                        "code": errCode,
                        "name": rawName
                    ]
                    if let stack = errStack { resp["stack"] = stack }
                    sendJSON(connection: connection, object: resp, origin: origin)
                    return true
                }

                var rawValue: Any? = evalResult
                if let dict = evalResult as? [String: Any], dict["__nomad_ok"] as? Bool == true {
                    rawValue = dict["value"]
                }

                var responseObj: [String: Any] = ["success": true]
                if let val = rawValue {
                    if let strVal = val as? String {
                        if strVal.count > 50_000 {
                            responseObj["result"] = String(strVal.prefix(50_000)) + "\n... [truncated by Nomad: result exceeded 50,000 chars]"
                        } else {
                            responseObj["result"] = strVal
                        }
                    } else if JSONSerialization.isValidJSONObject([val]) || val is NSNumber || val is [Any] || val is [String: Any] {
                        responseObj["result"] = val
                    } else {
                        let repr = "\(val)"
                        if repr.count > 50_000 {
                            responseObj["result"] = String(repr.prefix(50_000)) + "\n... [truncated by Nomad: result exceeded 50,000 chars]"
                        } else {
                            responseObj["result"] = repr
                        }
                    }
                } else {
                    responseObj["result"] = NSNull()
                }
                sendJSON(connection: connection, object: responseObj, origin: origin)
            } catch {
                let nsErr = error as NSError
                var errMsg = nsErr.localizedDescription
                if let jsMsg = nsErr.userInfo["WKJavaScriptExceptionMessage"] as? String, !jsMsg.isEmpty {
                    errMsg = jsMsg
                }
                let isCSP = nsErr.domain == "WKErrorDomain" && (errMsg.contains("Content Security Policy") || errMsg.contains("CSP") || errMsg.contains("Refused to evaluate"))
                let isSyntax = errMsg.contains("SyntaxError") || errMsg.contains("Unexpected token")
                let errCode = isCSP ? "EVAL_CSP" : (isSyntax ? "SYNTAX_ERROR" : "EVAL_ERROR")
                sendJSON(connection: connection, object: [
                    "success": false,
                    "error": errMsg,
                    "code": errCode
                ], origin: origin)
            }
            return true

        default:
            return false
        }
    }
}

//
//  AgentActionRoutes.swift
//  dino
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import WebKit

extension DinoAgentServer {
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
                let action = try JSONDecoder().decode(DinoAction.self, from: bodyData)
                let result = try await activeTab.performAction(action)
                let resData = try JSONEncoder().encode(result)
                let status: String
                if result.success {
                    var recordedAction = action
                    if (recordedAction.selector == nil || recordedAction.selector?.isEmpty == true),
                       let sel = result.selector, !sel.isEmpty {
                        recordedAction.selector = sel
                    }
                    AgentPlaybookManager.shared.record(action: recordedAction)
                    status = "200 OK"
                } else {
                    switch result.code {
                    case "STALE_REF", "SELECTOR_NOT_FOUND", "ELEMENT_NOT_FOUND":
                        status = "404 Not Found"
                    case "PENDING_DIALOG":
                        status = "409 Conflict"
                    default:
                        status = "400 Bad Request"
                    }
                }
                sendRaw(connection: connection, status: status, contentType: "application/json; charset=utf-8", data: resData, origin: origin)
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
                let action = DinoAction(action: "upload", target: targetId, paths: paths)
                let result = try await activeTab.performAction(action)
                if result.success {
                    var recordedAction = action
                    if (recordedAction.selector == nil || recordedAction.selector?.isEmpty == true),
                       let sel = result.selector, !sel.isEmpty {
                        recordedAction.selector = sel
                    }
                    AgentPlaybookManager.shared.record(action: recordedAction)
                }
                let resData = try JSONEncoder().encode(result)
                let status: String = result.success ? "200 OK" : ((result.code == "STALE_REF" || result.code == "SELECTOR_NOT_FOUND" || result.code == "ELEMENT_NOT_FOUND") ? "404 Not Found" : "400 Bad Request")
                sendRaw(connection: connection, status: status, contentType: "application/json; charset=utf-8", data: resData, origin: origin)
            } catch {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"\(error.localizedDescription)\",\"code\":\"UPLOAD_ERROR\",\"success\":false}", origin: origin)
            }
            return true

        case ("POST", "/evaluate"), ("POST", "/eval"):
            guard let bodyData = bodyData, !bodyData.isEmpty else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing body in /evaluate\",\"code\":\"MISSING_BODY\",\"success\":false}", origin: origin)
                return true
            }
            guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed JSON in evaluate body\",\"code\":\"MALFORMED_JSON\",\"success\":false}", origin: origin)
                return true
            }
            guard let script = (json["script"] as? String) ?? (json["expression"] as? String) ?? (json["code"] as? String) else {
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
            let scriptToRun: String
            let hasExplicitReturn = trimmed.contains("return ") || trimmed.contains("return\n") || trimmed.contains("return;")
            if hasExplicitReturn {
                scriptToRun = trimmed
            } else if !trimmed.contains(";") && !trimmed.contains("\n") {
                scriptToRun = "return (\(trimmed));"
            } else {
                let parts: [String]
                if trimmed.contains("\n") {
                    parts = trimmed.split(separator: "\n").map(String.init)
                } else {
                    parts = trimmed.split(separator: ";").map(String.init)
                }
                if let last = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !last.isEmpty,
                   !last.hasPrefix("const ") && !last.hasPrefix("let ") && !last.hasPrefix("var ") && !last.hasPrefix("if ") && !last.hasPrefix("for ") && !last.hasPrefix("while ") && !last.hasPrefix("function ") && !last.hasPrefix("class ") {
                    let cleanLast = last.hasSuffix(";") ? String(last.dropLast()) : last
                    let separator = trimmed.contains("\n") ? "\n" : "; "
                    let prefix = parts.dropLast().joined(separator: separator)
                    scriptToRun = prefix.isEmpty ? "return (\(cleanLast));" : "\(prefix)\(separator)return (\(cleanLast));"
                } else {
                    scriptToRun = trimmed
                }
            }

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

                    activeTab.webView.callAsyncJavaScript(scriptToRun, arguments: [:], in: nil, in: contentWorld) { result in
                        lock.lock()
                        defer { lock.unlock() }
                        if !resumed {
                            switch result {
                            case .success(let val):
                                resumed = true
                                activeTab.onDialogAppeared = nil
                                continuation.resume(returning: .evaluated(val))
                            case .failure(let error):
                                let nsErr = error as NSError
                                let isSyntax = (nsErr.userInfo["WKJavaScriptExceptionMessage"] as? String ?? "").contains("SyntaxError")
                                if isSyntax && scriptToRun != trimmed {
                                    activeTab.webView.callAsyncJavaScript(trimmed, arguments: [:], in: nil, in: contentWorld) { retryResult in
                                        lock.lock()
                                        defer { lock.unlock() }
                                        resumed = true
                                        activeTab.onDialogAppeared = nil
                                        switch retryResult {
                                        case .success(let rVal):
                                            continuation.resume(returning: .evaluated(rVal))
                                        case .failure(let rErr):
                                            continuation.resume(throwing: rErr)
                                        }
                                    }
                                    return
                                }
                                resumed = true
                                activeTab.onDialogAppeared = nil
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

                var responseObj: [String: Any] = ["success": true]
                if let val = evalResult {
                    if val is NSNull {
                        responseObj["result"] = NSNull()
                        responseObj["isNull"] = true
                    } else if let strVal = val as? String {
                        if strVal.count > 50_000 {
                            responseObj["result"] = String(strVal.prefix(50_000)) + "\n... [truncated by Dino: result exceeded 50,000 chars]"
                        } else {
                            responseObj["result"] = strVal
                        }
                    } else if JSONSerialization.isValidJSONObject([val]) || val is NSNumber || val is [Any] || val is [String: Any] {
                        responseObj["result"] = val
                    } else {
                        let repr = "\(val)"
                        if repr.count > 50_000 {
                            responseObj["result"] = String(repr.prefix(50_000)) + "\n... [truncated by Dino: result exceeded 50,000 chars]"
                        } else {
                            responseObj["result"] = repr
                        }
                    }
                } else {
                    responseObj["result"] = "undefined"
                    responseObj["isUndefined"] = true
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

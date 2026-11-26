//
//  DinoAgentServer+Routing.swift
//  dino
//

import Foundation
import Network
import WebKit

extension DinoAgentServer {

    @MainActor
    func routeRequest(method: String, path: String, queryString: String, headers: [String: String], bodyData: Data?, connection: NWConnection) async {
        let origin = headers["origin"]

        // Validate Origin header against DNS rebinding & cross-site exfiltration attacks
        if !Self.isAllowedOrigin(origin) {
            print("[dino] Blocked cross-origin request from untrusted origin: \(origin ?? "unknown")")
            sendResponse(connection: connection, status: "403 Forbidden", body: "{\"error\":\"Forbidden: cross-origin requests from untrusted web origins are blocked by Dino security policy.\",\"code\":\"FORBIDDEN\",\"success\":false}", origin: nil)
            return
        }

        // Handle CORS Preflight (only reached if origin is valid)
        if method == "OPTIONS" {
            sendResponse(connection: connection, status: "204 No Content", body: "", origin: origin)
            return
        }

        // Parse query params once into a fast lookup table
        let queryParams: [String: String] = {
            guard !queryString.isEmpty,
                  let items = URLComponents(string: "?" + queryString)?.queryItems else { return [:] }
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        }()

        func queryItem(_ name: String) -> String? {
            queryParams[name]
        }

        func queryBool(_ name: String, default defaultValue: Bool = false) -> Bool {
            guard let val = queryParams[name] else { return defaultValue }
            return val == "true" || val == "1"
        }

        let cleanPath = (path.count > 1 && path.hasSuffix("/")) ? String(path.dropLast()) : path

        // Handle WebSocket Upgrade (CDP /devtools/page/*, /devtools/browser/*, or /cdp)
        if headers["upgrade"]?.lowercased() == "websocket" {
            handleCDPWebSocketUpgrade(path: cleanPath, headers: headers, connection: connection)
            return
        }

        // Handle CDP HTTP Discovery Endpoints (/json/version, /json/list, /json/new, etc.)
        if cleanPath.hasPrefix("/json") || cleanPath == "/devtools/version" {
            if handleCDPDiscoveryRoute(method: method, cleanPath: cleanPath, queryString: queryString, bodyData: bodyData, queryItem: queryItem, connection: connection, origin: origin) {
                return
            }
        }

        // Token Auth check (bypassed if DINO_DISABLE_AUTH=1 in environment)
        let authDisabled = ProcessInfo.processInfo.environment["DINO_DISABLE_AUTH"] == "1"
        var isAuthenticated = authDisabled
        if !isAuthenticated {
            let authHeader = headers["authorization"] ?? ""
            var providedToken: String? = nil
            if authHeader.lowercased().starts(with: "bearer ") {
                providedToken = String(authHeader.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if let customHeader = headers["x-dino-token"] {
                providedToken = customHeader.trimmingCharacters(in: .whitespaces)
            } else if let urlToken = queryItem("token") {
                providedToken = urlToken.trimmingCharacters(in: .whitespaces)
            }

            if let tok = providedToken, Self.constantTimeEquals(tok, self.token) {
                isAuthenticated = true
            }
        }

        // Unauthenticated access is strictly limited to health check probe and local live stream viewer
        let isPublicHealthCheck = ((method == "GET" || method == "HEAD") && (path == "/" || path == "/status" || cleanPath == "/" || cleanPath == "/status" || cleanPath == "/health" || cleanPath == "/version" || cleanPath == "/capabilities" || cleanPath == "/daemon" || cleanPath == "/headless" || cleanPath == "/socket" || cleanPath == "/view" || cleanPath == "/stream")) || ((method == "POST" || method == "DELETE") && (cleanPath == "/socket" || cleanPath == "/daemon"))
        if !isAuthenticated {
            if isPublicHealthCheck {
                if cleanPath == "/view" || cleanPath == "/stream" {
                    // Allow local loopback live view and streaming to proceed to perception router
                } else if !((method == "POST" || method == "DELETE") && (cleanPath == "/socket" || cleanPath == "/daemon")) {
                    let publicStatusObj: [String: Any] = [
                        "success": true,
                        "dino": "active",
                        "status": "healthy",
                        "version": Updater.currentVersion,
                        "build": Updater.currentBuild,
                        "authRequired": true
                    ]
                    sendJSON(connection: connection, object: publicStatusObj, origin: origin)
                    return
                }
            } else {
                let authErrorObj: [String: Any] = [
                    "error": "Unauthorized: valid Bearer token required in 'Authorization: Bearer <token>' or 'X-Dino-Token: <token>' header.",
                    "code": "UNAUTHORIZED",
                    "success": false,
                    "tokenPath": "~/.dino/agent-token",
                    "hint": "Read token from ~/.dino/agent-token, run 'dino token --header' via CLI, or set DINO_DISABLE_AUTH=1 in your environment for local development."
                ]
                sendJSON(connection: connection, status: "401 Unauthorized", object: authErrorObj, origin: origin)
                return
            }
        }

        // Dedicated version endpoint
        if method == "GET" && cleanPath == "/version" {
            sendJSON(connection: connection, object: [
                "success": true,
                "dino": "active",
                "version": Updater.currentVersion,
                "build": Updater.currentBuild,
                "isDevelopmentBuild": Updater.isDevelopmentBuild
            ], origin: origin)
            return
        }

        // Dedicated health probe endpoint (also aliases GET /socket)
        if method == "GET" && (cleanPath == "/health" || cleanPath == "/socket") {
            let socketPath = DinoUnixSocketBridge.defaultSocketPath
            let socketExists = FileManager.default.fileExists(atPath: socketPath)
            sendJSON(connection: connection, object: [
                "success": true,
                "status": "healthy",
                "dino": "active",
                "version": Updater.currentVersion,
                "build": Updater.currentBuild,
                "port": self.port,
                "unixSocket": [
                    "path": socketPath,
                    "active": DinoUnixSocketBridge.shared.isListening,
                    "exists": socketExists,
                    "error": (DinoUnixSocketBridge.shared.lastError as Any?) ?? NSNull()
                ]
            ], origin: origin)
            return
        }

        // Dynamic socket binding, rebinding, or unbinding (DELETE /socket or POST /socket)
        if (cleanPath == "/socket" || cleanPath == "/daemon") && (method == "POST" || method == "DELETE") {
            var isUnbind = (method == "DELETE")
            var requestedPath: String? = nil

            if method == "POST" {
                var jsonDict: [String: Any]? = nil
                if let bodyData = bodyData,
                   let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    jsonDict = parsed
                }

                if let json = jsonDict {
                    if json.isEmpty {
                        isUnbind = true
                    } else if let action = json["action"] as? String, action == "stop" || action == "clear" || action == "unbind" {
                        isUnbind = true
                    } else if let enabled = json["enabled"] as? Bool, !enabled {
                        isUnbind = true
                    } else if let active = json["active"] as? Bool, !active {
                        isUnbind = true
                    } else {
                        requestedPath = (json["socketPath"] as? String) ?? (json["path"] as? String)
                    }
                } else if bodyData == nil || bodyData?.isEmpty == true {
                    if queryItem("socketPath") == nil && queryItem("path") == nil {
                        isUnbind = true
                    } else {
                        requestedPath = queryItem("socketPath") ?? queryItem("path")
                    }
                } else {
                    requestedPath = queryItem("socketPath") ?? queryItem("path")
                }
            }

            if isUnbind {
                // When unbinding a custom socket (e.g. ./dino.sock), clean it up and restore the default socket (~/.dino/dino.sock)
                let customPath = DinoUnixSocketBridge.configuredSocketPath
                DinoUnixSocketBridge.shared.unbind { _ in
                    DinoUnixSocketBridge.shared.rebind(newPath: nil) { active, error in
                        let defaultPath = DinoUnixSocketBridge.defaultSocketPath
                        let exists = FileManager.default.fileExists(atPath: defaultPath)
                        self.sendJSON(connection: connection, object: [
                            "success": true,
                            "active": active,
                            "unbound": true,
                            "previousPath": (customPath as Any?) ?? NSNull(),
                            "socketPath": defaultPath,
                            "path": defaultPath,
                            "exists": exists,
                            "error": (error as Any?) ?? NSNull()
                        ], origin: origin)
                    }
                }
                return
            }

            DinoUnixSocketBridge.shared.rebind(newPath: requestedPath) { active, error in
                let currentPath = DinoUnixSocketBridge.defaultSocketPath
                let exists = FileManager.default.fileExists(atPath: currentPath)
                self.sendJSON(connection: connection, object: [
                    "success": active,
                    "active": active,
                    "socketPath": currentPath,
                    "path": currentPath,
                    "exists": exists,
                    "error": (error as Any?) ?? NSNull()
                ], origin: origin)
            }
            return
        }

        // Health check probes ("GET /" or "GET /status") can respond immediately even before BrowserStore finishes attaching
        if method == "GET" && (cleanPath == "/" || cleanPath == "/status") {
            let socketPath = DinoUnixSocketBridge.defaultSocketPath
            let socketExists = FileManager.default.fileExists(atPath: socketPath)
            let unixSocketInfo: [String: Any] = [
                "path": socketPath,
                "active": DinoUnixSocketBridge.shared.isListening,
                "exists": socketExists,
                "error": (DinoUnixSocketBridge.shared.lastError as Any?) ?? NSNull()
            ]
            let capabilities: [String: Any] = [
                "transports": ["http", "unix_socket", "sse_events"],
                "socketPath": socketPath,
                "unixSocket": unixSocketInfo,
                "waitModes": ["stability", "selector", "timeout", "networkidle", "navigation", "url"],
                "actions": ["click", "hover", "type", "clear", "press", "selectOption", "scroll", "drag", "highlight", "upload", "native_click", "native_type", "native_press", "native_drag", "native_hover"],
                "upload": ["files", "paths"],
                "downloads": ["list", "last", "wait"],
                "hardwareInput": ["isTrusted", "cgEvent", "appKit"],
                "frames": ["crossOrigin", "piercing", "subframes"],
                "screenshot": ["full", "labeled", "clip", "elementId"],
                "evaluateWorlds": ["page", "isolated"],
                "snapshotModes": ["text", "json"],
                "cookies": ["get", "set", "clear"],
                "console": ["log", "warn", "error"],
                "network": ["fetch", "xhr", "status", "timing"],
                "networkInterception": ["mock", "block"],
                "tabVirtualization": ["hot", "warm", "cold"],
                "agenticRuntime": ["route_cache", "trajectory_trace", "headless_daemon", "socket_rebind", "playbooks", "hitl_guardrails"],
                "updater": ["status", "check", "version", "build"],
                "dialogPolicies": ["accept", "dismiss", "wait"]
            ]
            let liveTitle = (self.store?.activeTab?.webView.title?.isEmpty == false ? self.store?.activeTab?.webView.title : self.store?.activeTab?.title) ?? ""
            let liveURL = (self.store?.activeTab?.webView.url?.absoluteString ?? self.store?.activeTab?.url?.absoluteString) ?? ""
            let isVerbose = (queryItem("verbose") == "true" || queryItem("verbose") == "1")
            let wantsCapabilities = isVerbose || (queryItem("capabilities") == "true" || queryItem("capabilities") == "1")
            var statusObj: [String: Any] = [
                "success": true,
                "dino": "active",
                "status": "healthy",
                "version": Updater.currentVersion,
                "build": Updater.currentBuild,
                "mode": DinoHeadlessManager.isHeadless ? "headless_daemon" : "gui",
                "isHeadless": DinoHeadlessManager.isHeadless,
                "port": self.port,
                "tabCount": self.store?.tabs.count ?? 0,
                "tabsCount": self.store?.tabs.count ?? 0,
                "activeTabId": self.store?.activeTabId?.uuidString ?? "",
                "activeURL": liveURL,
                "activeTitle": liveTitle,
                "hasPendingDialog": self.store?.activeTab?.pendingDialog != nil,
                "unixSocket": unixSocketInfo
            ]
            if wantsCapabilities {
                statusObj["capabilities"] = capabilities
            }
            if isVerbose {
                statusObj["lastDialog"] = (self.store?.activeTab?.lastDialog as Any?) ?? NSNull()
            }
            sendJSON(connection: connection, object: statusObj, origin: origin)
            return
        }

        if method == "GET" && cleanPath == "/capabilities" {
            let socketPath = DinoUnixSocketBridge.defaultSocketPath
            let socketExists = FileManager.default.fileExists(atPath: socketPath)
            let unixSocketInfo: [String: Any] = [
                "path": socketPath,
                "active": DinoUnixSocketBridge.shared.isListening,
                "exists": socketExists,
                "error": (DinoUnixSocketBridge.shared.lastError as Any?) ?? NSNull()
            ]
            let capabilities: [String: Any] = [
                "transports": ["http", "unix_socket", "sse_events"],
                "socketPath": socketPath,
                "unixSocket": unixSocketInfo,
                "waitModes": ["auto", "selector", "text", "state", "networkidle", "stability", "timeout", "navigation", "url"],
                "actions": ["click", "hover", "type", "clear", "press", "selectOption", "scroll", "drag", "highlight", "upload", "native_click", "native_type", "native_press", "native_drag", "native_hover"],
                "upload": ["files", "paths"],
                "downloads": ["list", "last", "wait"],
                "hardwareInput": ["isTrusted", "cgEvent", "appKit"],
                "frames": ["crossOrigin", "piercing", "subframes"],
                "screenshot": ["full", "labeled", "clip", "elementId"],
                "evaluateWorlds": ["page", "isolated"],
                "snapshotModes": ["text", "json"],
                "cookies": ["get", "set", "clear"],
                "console": ["log", "warn", "error"],
                "network": ["fetch", "xhr", "status", "timing"],
                "networkInterception": ["mock", "block"],
                "tabVirtualization": ["hot", "warm", "cold"],
                "agenticRuntime": ["route_cache", "trajectory_trace", "headless_daemon", "socket_rebind", "playbooks", "hitl_guardrails"],
                "updater": ["status", "check", "version", "build"],
                "dialogPolicies": ["accept", "dismiss", "wait"],
                "extensions": ["list", "toggle", "enable", "disable"]
            ]
            sendJSON(connection: connection, object: [
                "success": true,
                "version": Updater.currentVersion,
                "capabilities": capabilities
            ], origin: origin)
            return
        }

        if cleanPath == "/policy" || cleanPath == "/allowlist" {
            if method == "GET" {
                sendJSON(connection: connection, object: [
                    "success": true,
                    "mode": self.policyMode,
                    "allowedDomains": self.allowedDomains,
                    "pendingApprovalsCount": self.pendingApprovals.count
                ], origin: origin)
                return
            } else if method == "POST" {
                if let bodyData = bodyData,
                   let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                    if let m = json["mode"] as? String {
                        let cleanM = m.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if ["permissive", "strict", "ask"].contains(cleanM) {
                            self.policyMode = cleanM
                        }
                    }
                    if let domains = (json["allowedDomains"] as? [String]) ??
                                      (json["allowlist"] as? [String]) ??
                                      (json["domains"] as? [String]) {
                        self.allowedDomains = domains.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                    } else if let addDomain = (json["addDomain"] as? String) ?? (json["domain"] as? String) {
                        let d = addDomain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !d.isEmpty && !self.allowedDomains.contains(d) {
                            self.allowedDomains.append(d)
                        }
                    }
                }
                self.recordSecurityAudit(type: "policy_update", message: "Policy mode '\(self.policyMode)', allowedDomains: \(self.allowedDomains)")
                sendJSON(connection: connection, object: [
                    "success": true,
                    "mode": self.policyMode,
                    "allowedDomains": self.allowedDomains
                ], origin: origin)
                return
            } else if method == "DELETE" {
                self.allowedDomains.removeAll()
                self.policyMode = "permissive"
                self.recordSecurityAudit(type: "policy_reset", message: "Policy reset to permissive")
                sendJSON(connection: connection, object: [
                    "success": true,
                    "cleared": true,
                    "mode": self.policyMode
                ], origin: origin)
                return
            }
        }

        if cleanPath == "/permissions" && method == "GET" {
            sendJSON(connection: connection, object: [
                "success": true,
                "policyMode": self.policyMode,
                "allowedDomains": self.allowedDomains,
                "permissions": [
                    "network": true,
                    "nativeInput": true,
                    "fileUpload": true,
                    "downloads": true,
                    "storage": true,
                    "extensions": true
                ]
            ], origin: origin)
            return
        }

        if cleanPath == "/approval" {
            if method == "GET" {
                let list = self.pendingApprovals.map { [
                    "id": $0.id,
                    "type": $0.type,
                    "target": $0.target,
                    "timestamp": $0.timestamp
                ] }
                sendJSON(connection: connection, object: [
                    "success": true,
                    "pending": list,
                    "count": list.count
                ], origin: origin)
                return
            } else if method == "POST" {
                guard let bodyData = bodyData,
                      let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                      let id = json["id"] as? String else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing 'id' in approval decision\",\"code\":\"MISSING_ID\",\"success\":false}", origin: origin)
                    return
                }
                let decision = (json["decision"] as? String)?.lowercased() ?? "deny"
                self.pendingApprovals.removeAll { $0.id == id }
                self.recordSecurityAudit(type: "approval_decision", message: "Approval '\(id)' -> \(decision)")
                sendJSON(connection: connection, object: [
                    "success": true,
                    "id": id,
                    "decision": decision
                ], origin: origin)
                return
            }
        }

        if cleanPath == "/audit" {
            if method == "GET" {
                let list = self.securityAuditLog.map { [
                    "timestamp": $0.timestamp,
                    "type": $0.type,
                    "message": $0.message,
                    "origin": ($0.origin as Any?) ?? NSNull(),
                    "isBlocked": $0.isBlocked
                ] }
                sendJSON(connection: connection, object: [
                    "success": true,
                    "entries": list,
                    "count": list.count
                ], origin: origin)
                return
            } else if method == "DELETE" {
                self.securityAuditLog.removeAll()
                sendJSON(connection: connection, object: ["success": true, "cleared": true], origin: origin)
                return
            }
        }

        if method == "GET" && (cleanPath == "/daemon" || cleanPath == "/headless") {
            let socketPath = DinoUnixSocketBridge.defaultSocketPath
            let socketExists = FileManager.default.fileExists(atPath: socketPath)
            sendJSON(connection: connection, object: [
                "success": true,
                "mode": DinoHeadlessManager.isHeadless ? "headless_daemon" : "gui",
                "isHeadless": DinoHeadlessManager.isHeadless,
                "viewport": ["width": 1280, "height": 800],
                "cliFlags": ["--headless", "DINO_HEADLESS=1"],
                "socketPath": socketPath,
                "unixSocket": [
                    "path": socketPath,
                    "active": DinoUnixSocketBridge.shared.isListening,
                    "exists": socketExists,
                    "error": (DinoUnixSocketBridge.shared.lastError as Any?) ?? NSNull()
                ]
            ], origin: origin)
            return
        }

        if method == "GET" && cleanPath == "/updater" {
            let u = Updater.shared
            let lastCheckVal: Any = u.lastChecked != nil ? (u.lastChecked!.timeIntervalSince1970 * 1000.0) : NSNull()
            sendJSON(connection: connection, object: [
                "success": true,
                "version": Updater.currentVersion,
                "build": Updater.currentBuild,
                "statusMessage": u.statusMessage,
                "checking": u.checking,
                "lastChecked": lastCheckVal,
                "feedURL": Updater.feedURL.absoluteString,
                "autoInstall": u.autoInstall,
                "isDevelopmentBuild": Updater.isDevelopmentBuild
            ], origin: origin)
            return
        }

        if method == "POST" && (cleanPath == "/updater/check" || cleanPath == "/updater") {
            Updater.shared.checkByHand(showAlerts: false)
            sendJSON(connection: connection, object: [
                "success": true,
                "checking": true,
                "version": Updater.currentVersion,
                "build": Updater.currentBuild
            ], origin: origin)
            return
        }

        guard self.store != nil else {
            sendResponse(connection: connection, status: "503 Service Unavailable", body: "{\"error\":\"BrowserStore not connected\",\"code\":\"SERVICE_UNAVAILABLE\",\"success\":false}", origin: origin)
            return
        }

        if await handleTabsRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, queryItem: queryItem, connection: connection, origin: origin) {
            return
        }
        if await handleNavigationRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, queryItem: queryItem, connection: connection, origin: origin) {
            return
        }
        if await handlePerceptionRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, queryItem: queryItem, connection: connection, origin: origin) {
            return
        }
        if await handleActionRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, connection: connection, origin: origin) {
            return
        }
        if await handlePlaybookRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, queryItem: queryItem, connection: connection, origin: origin) {
            return
        }
        if await handleTelemetryRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, queryItem: queryItem, connection: connection, origin: origin) {
            return
        }

        sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Endpoint not found: \(method) \(path)\",\"code\":\"NOT_FOUND\",\"success\":false}", origin: origin)
    }
}

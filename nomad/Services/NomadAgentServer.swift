//
//  NomadAgentServer.swift
//  nomad
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import AppKit
import Combine
import WebKit
import CryptoKit

/// Embedded lightweight local API server for Nomad using Apple's native Network.framework.
/// Binds strictly to 127.0.0.1:9222 with zero third-party dependencies, 0% idle CPU, and automatic socket cleanup.
@MainActor
final class NomadAgentServer: ObservableObject {
    static let shared = NomadAgentServer()

    static var defaultPort: UInt16 {
        if let envStr = ProcessInfo.processInfo.environment["NOMAD_AGENT_PORT"],
           let p = UInt16(envStr) {
            return p
        }
        return 9222
    }

    /// Constant-time string comparison to prevent timing attacks on bearer token authentication.
    nonisolated private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let digestA = SHA256.hash(data: Data(a.utf8))
        let digestB = SHA256.hash(data: Data(b.utf8))
        return digestA == digestB
    }

    /// Validates request Origin header to prevent DNS rebinding and cross-site exfiltration attacks.
    nonisolated static func isAllowedOrigin(_ origin: String?) -> Bool {
        guard let origin = origin, !origin.isEmpty else {
            // Local CLI, curl, Node.js, Python, or MCP servers emit no Origin header
            return true
        }
        let lower = origin.lowercased()
        if lower.hasPrefix("chrome-extension://") || lower.hasPrefix("nomad://") { return true }
        guard let url = URL(string: origin),
              let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }

    /// Checks if a file path points to sensitive OS or user credentials (SSH keys, Nomad tokens, Keychains, system passwd).
    nonisolated static func isSensitivePath(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        let rawLower = expanded.lowercased()
        let canonicalLower = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardized.path.lowercased()
        let sensitiveTokens = ["/.ssh", "/.nomad", "/library/keychains", "/etc/master.passwd", "/etc/sudoers"]
        return [rawLower, canonicalLower].contains { p in
            sensitiveTokens.contains { p.contains($0) }
        }
    }

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var port: UInt16 = NomadAgentServer.defaultPort
    @Published private(set) var requestCount: Int = 0

    /// Secure local authentication token loaded from ~/.nomad/agent-token or NOMAD_TOKEN environment variable.
    let token: String = NomadAgentServer.loadOrCreateAgentToken()

    weak var store: BrowserStore?

    private var listener: NWListener?
    nonisolated private let serverQueue = DispatchQueue(label: "nomad.agent.server", qos: .userInitiated)
    nonisolated private let eventBroadcaster = EventStreamBroadcaster()

    /// Process activity assertion to ensure macOS App Nap and timer coalescing are disabled during agent server operations
    private var activityToken: NSObjectProtocol? = {
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "Nomad Agent Server Automation"
        )
    }()

    // MARK: - Security Model, Policy, Allowlist & Audit
    struct SecurityAuditEntry: Codable {
        let timestamp: Double
        let type: String
        let message: String
        let origin: String?
        let isBlocked: Bool
    }

    struct PendingApprovalItem: Codable {
        let id: String
        let type: String
        let target: String
        let timestamp: Double
    }

    @Published var policyMode: String = "permissive" // "permissive", "strict", "ask"
    @Published var allowedDomains: [String] = []
    @Published var securityAuditLog: [SecurityAuditEntry] = []
    @Published var pendingApprovals: [PendingApprovalItem] = []

    func recordSecurityAudit(type: String, message: String, origin: String? = nil, isBlocked: Bool = false) {
        let entry = SecurityAuditEntry(
            timestamp: Date().timeIntervalSince1970 * 1000.0,
            type: type,
            message: message,
            origin: origin,
            isBlocked: isBlocked
        )
        securityAuditLog.append(entry)
        if securityAuditLog.count > 1000 {
            securityAuditLog.removeFirst(100)
        }
    }

    func isDomainAllowed(_ domain: String) -> Bool {
        guard !allowedDomains.isEmpty else { return true }
        let lDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for allowed in allowedDomains {
            let lAllowed = allowed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if lAllowed == lDomain { return true }
            if lAllowed.hasPrefix("*.") {
                let suffix = String(lAllowed.dropFirst(2))
                if lDomain == suffix || lDomain.hasSuffix("." + suffix) {
                    return true
                }
            }
        }
        return false
    }

    private init() {}

    /// Loads an existing agent token from ~/.nomad/agent-token or generates a new cryptographically secure token.
    static func loadOrCreateAgentToken() -> String {
        if let envToken = ProcessInfo.processInfo.environment["NOMAD_TOKEN"], !envToken.isEmpty {
            return envToken.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let nomadDir = homeDir.appendingPathComponent(".nomad", isDirectory: true)
        let tokenFile = nomadDir.appendingPathComponent("agent-token")

        if let existing = try? String(contentsOf: tokenFile, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        try? fileManager.createDirectory(at: nomadDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        try? token.write(to: tokenFile, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        return token
    }

    private var isStarting: Bool = false

    /// Starts the local agent server (default: NOMAD_AGENT_PORT or 9222).
    @MainActor
    func start(port: UInt16? = nil, store: BrowserStore? = nil) {
        if let store = store {
            self.store = store
        }
        guard !isRunning, !isStarting, listener == nil else { return }
        isStarting = true
        self.port = port ?? Self.defaultPort

        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = false
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback

            guard let endpointPort = NWEndpoint.Port(rawValue: self.port) else {
                print("[nomad] Invalid agent port: \(self.port)")
                isStarting = false
                return
            }

            let newListener = try NWListener(using: params, on: endpointPort)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self.isStarting = false
                        self.isRunning = true
                        NomadUnixSocketBridge.shared.start(port: self.port, token: self.token)
                        print("[nomad] Agent server listening on http://127.0.0.1:\(self.port)")
                    case .failed(let error):
                        print("[nomad] Agent server error: \(error)")
                        self.isStarting = false
                        self.stop()
                    case .cancelled:
                        self.isStarting = false
                        self.isRunning = false
                        print("[nomad] Agent server stopped")
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.handleIncomingConnection(connection)
            }

            self.listener = newListener
            newListener.start(queue: serverQueue)
        } catch {
            isStarting = false
            print("[nomad] Listener error: \(error)")
        }
    }

    /// Stops the server and cleanly releases all sockets and connections.
    func stop() {
        isStarting = false
        isRunning = false
        NomadUnixSocketBridge.shared.stop()
        eventBroadcaster.closeAll()

        listener?.cancel()
        listener = nil
    }

    // MARK: - HTTP Request Handling (Runs on serverQueue)

    nonisolated private func handleIncomingConnection(_ connection: NWConnection) {
        // Enforce loopback check on incoming peer endpoint to prevent interface leakage
        if case .hostPort(let host, _) = connection.endpoint {
            let hostStr = "\(host)"
            if hostStr != "127.0.0.1" && hostStr != "::1" && hostStr != "localhost" {
                print("[nomad] Rejecting non-loopback connection from: \(hostStr)")
                connection.cancel()
                return
            }
        }

        connection.start(queue: serverQueue)
        self.receiveRequest(connection: connection, accumulatedData: Data())
    }

    nonisolated private func receiveRequest(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1048576) { [weak self] data, _, _, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            guard let data = data, !data.isEmpty else {
                if !accumulatedData.isEmpty {
                    self.processRequest(data: accumulatedData, connection: connection)
                } else {
                    connection.cancel()
                }
                return
            }

            var current = accumulatedData
            current.append(data)

            // Check if headers boundary \r\n\r\n is present
            if let headerEndRange = current.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = current.subdata(in: 0..<headerEndRange.lowerBound)
                let bodyCount = current.count - headerEndRange.upperBound

                // Parse Content-Length if present
                var expectedContentLength = 0
                if let headerStr = String(data: headerData, encoding: .utf8) {
                    for line in headerStr.components(separatedBy: "\r\n") {
                        let lower = line.lowercased()
                        if lower.hasPrefix("content-length:") {
                            let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                            expectedContentLength = Int(valStr) ?? 0
                            break
                        }
                    }
                }

                if bodyCount < expectedContentLength {
                    // Body is incomplete, continue receiving more chunks from this connection
                    self.receiveRequest(connection: connection, accumulatedData: current)
                    return
                }

                // Complete HTTP request received!
                self.processRequest(data: current, connection: connection)
            } else {
                // Headers still incomplete, continue receiving
                self.receiveRequest(connection: connection, accumulatedData: current)
            }
        }
    }

    nonisolated private func processRequest(data: Data, connection: NWConnection) {
        // Extract headers and body
        guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed HTTP request\",\"code\":\"MALFORMED_REQUEST\",\"success\":false}")
            return
        }

        let headerData = data.subdata(in: 0..<headerEndRange.lowerBound)
        let bodyData = headerEndRange.upperBound < data.count ? data.subdata(in: headerEndRange.upperBound..<data.count) : nil

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Invalid UTF-8 in headers\",\"code\":\"INVALID_HEADERS\",\"success\":false}")
            return
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Empty request\",\"code\":\"EMPTY_REQUEST\",\"success\":false}")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Malformed HTTP request line\",\"code\":\"MALFORMED_REQUEST_LINE\",\"success\":false}")
            return
        }

        let method = parts[0].uppercased()
        let fullPath = parts[1]
        let path = fullPath.components(separatedBy: "?").first ?? fullPath
        let queryString = fullPath.contains("?") ? String(fullPath.split(separator: "?", maxSplits: 1).last ?? "") : ""

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        Task { @MainActor in
            self.requestCount += 1
            await self.routeRequest(method: method, path: path, queryString: queryString, headers: headers, bodyData: bodyData, connection: connection)
        }
    }

    @MainActor
    private func routeRequest(method: String, path: String, queryString: String, headers: [String: String], bodyData: Data?, connection: NWConnection) async {
        let origin = headers["origin"]

        // Validate Origin header against DNS rebinding & cross-site exfiltration attacks
        if !Self.isAllowedOrigin(origin) {
            print("[nomad] Blocked cross-origin request from untrusted origin: \(origin ?? "unknown")")
            sendResponse(connection: connection, status: "403 Forbidden", body: "{\"error\":\"Forbidden: cross-origin requests from untrusted web origins are blocked by Nomad security policy.\",\"code\":\"FORBIDDEN\",\"success\":false}", origin: nil)
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

        // Token Auth check (bypassed if NOMAD_DISABLE_AUTH=1 in environment)
        let authDisabled = ProcessInfo.processInfo.environment["NOMAD_DISABLE_AUTH"] == "1"
        var isAuthenticated = authDisabled
        if !isAuthenticated {
            let authHeader = headers["authorization"] ?? ""
            var providedToken: String? = nil
            if authHeader.lowercased().starts(with: "bearer ") {
                providedToken = String(authHeader.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if let customHeader = headers["x-nomad-token"] {
                providedToken = customHeader.trimmingCharacters(in: .whitespaces)
            }

            if let tok = providedToken, Self.constantTimeEquals(tok, self.token) {
                isAuthenticated = true
            }
        }

        // Unauthenticated access is strictly limited to minimal health check probe without sensitive page data
        let isPublicHealthCheck = (method == "GET" && (path == "/" || path == "/status" || cleanPath == "/" || cleanPath == "/status" || cleanPath == "/health" || cleanPath == "/version" || cleanPath == "/capabilities" || cleanPath == "/daemon" || cleanPath == "/headless" || cleanPath == "/socket")) || ((method == "POST" || method == "DELETE") && (cleanPath == "/socket" || cleanPath == "/daemon"))
        if !isAuthenticated {
            if isPublicHealthCheck {
                // If it's a socket modification request, process it below
                if !((method == "POST" || method == "DELETE") && (cleanPath == "/socket" || cleanPath == "/daemon")) {
                    let publicStatusObj: [String: Any] = [
                        "success": true,
                        "nomad": "active",
                        "status": "healthy",
                        "version": Updater.currentVersion,
                        "build": Updater.currentBuild,
                        "authRequired": true
                    ]
                    sendJSON(connection: connection, object: publicStatusObj, origin: origin)
                    return
                }
            } else {
                sendResponse(connection: connection, status: "401 Unauthorized", body: "{\"error\":\"Unauthorized: valid Bearer token required in Authorization header or ~/.nomad/agent-token\",\"code\":\"UNAUTHORIZED\",\"success\":false}", origin: origin)
                return
            }
        }

        // Dedicated version endpoint
        if method == "GET" && cleanPath == "/version" {
            sendJSON(connection: connection, object: [
                "success": true,
                "nomad": "active",
                "version": Updater.currentVersion,
                "build": Updater.currentBuild,
                "isDevelopmentBuild": Updater.isDevelopmentBuild
            ], origin: origin)
            return
        }

        // Dedicated health probe endpoint (also aliases GET /socket)
        if method == "GET" && (cleanPath == "/health" || cleanPath == "/socket") {
            let socketPath = NomadUnixSocketBridge.defaultSocketPath
            let socketExists = FileManager.default.fileExists(atPath: socketPath)
            sendJSON(connection: connection, object: [
                "success": true,
                "status": "healthy",
                "nomad": "active",
                "version": Updater.currentVersion,
                "build": Updater.currentBuild,
                "port": self.port,
                "unixSocket": [
                    "path": socketPath,
                    "active": NomadUnixSocketBridge.shared.isListening,
                    "exists": socketExists,
                    "error": (NomadUnixSocketBridge.shared.lastError as Any?) ?? NSNull()
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
                // When unbinding a custom socket (e.g. ./nomad.sock), clean it up and restore the default socket (~/.nomad/nomad.sock)
                let customPath = NomadUnixSocketBridge.configuredSocketPath
                NomadUnixSocketBridge.shared.unbind { _ in
                    NomadUnixSocketBridge.shared.rebind(newPath: nil) { active, error in
                        let defaultPath = NomadUnixSocketBridge.defaultSocketPath
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

            NomadUnixSocketBridge.shared.rebind(newPath: requestedPath) { active, error in
                let currentPath = NomadUnixSocketBridge.defaultSocketPath
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
            let socketPath = NomadUnixSocketBridge.defaultSocketPath
            let socketExists = FileManager.default.fileExists(atPath: socketPath)
            let unixSocketInfo: [String: Any] = [
                "path": socketPath,
                "active": NomadUnixSocketBridge.shared.isListening,
                "exists": socketExists,
                "error": (NomadUnixSocketBridge.shared.lastError as Any?) ?? NSNull()
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
                "agenticRuntime": ["route_cache", "trajectory_trace", "headless_daemon", "socket_rebind"],
                "updater": ["status", "check", "version", "build"],
                "dialogPolicies": ["accept", "dismiss", "wait"]
            ]
            let liveTitle = (self.store?.activeTab?.webView.title?.isEmpty == false ? self.store?.activeTab?.webView.title : self.store?.activeTab?.title) ?? ""
            let liveURL = (self.store?.activeTab?.webView.url?.absoluteString ?? self.store?.activeTab?.url?.absoluteString) ?? ""
            let isVerbose = (queryItem("verbose") == "true" || queryItem("verbose") == "1")
            var statusObj: [String: Any] = [
                "success": true,
                "nomad": "active",
                "status": "healthy",
                "version": Updater.currentVersion,
                "build": Updater.currentBuild,
                "mode": NomadHeadlessManager.isHeadless ? "headless_daemon" : "gui",
                "isHeadless": NomadHeadlessManager.isHeadless,
                "port": self.port,
                "tabCount": self.store?.tabs.count ?? 0,
                "tabsCount": self.store?.tabs.count ?? 0,
                "activeTabId": self.store?.activeTabId?.uuidString ?? "",
                "activeURL": liveURL,
                "activeTitle": liveTitle,
                "hasPendingDialog": self.store?.activeTab?.pendingDialog != nil,
                "unixSocket": unixSocketInfo,
                "capabilities": capabilities
            ]
            if isVerbose {
                statusObj["lastDialog"] = (self.store?.activeTab?.lastDialog as Any?) ?? NSNull()
            }
            sendJSON(connection: connection, object: statusObj, origin: origin)
            return
        }

        if method == "GET" && cleanPath == "/capabilities" {
            let socketPath = NomadUnixSocketBridge.defaultSocketPath
            let socketExists = FileManager.default.fileExists(atPath: socketPath)
            let unixSocketInfo: [String: Any] = [
                "path": socketPath,
                "active": NomadUnixSocketBridge.shared.isListening,
                "exists": socketExists,
                "error": (NomadUnixSocketBridge.shared.lastError as Any?) ?? NSNull()
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
                "agenticRuntime": ["route_cache", "trajectory_trace", "headless_daemon", "socket_rebind"],
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
                    if let domains = json["allowedDomains"] as? [String] {
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
            let socketPath = NomadUnixSocketBridge.defaultSocketPath
            let socketExists = FileManager.default.fileExists(atPath: socketPath)
            sendJSON(connection: connection, object: [
                "success": true,
                "mode": NomadHeadlessManager.isHeadless ? "headless_daemon" : "gui",
                "isHeadless": NomadHeadlessManager.isHeadless,
                "viewport": ["width": 1280, "height": 800],
                "cliFlags": ["--headless", "NOMAD_HEADLESS=1"],
                "socketPath": socketPath,
                "unixSocket": [
                    "path": socketPath,
                    "active": NomadUnixSocketBridge.shared.isListening,
                    "exists": socketExists,
                    "error": (NomadUnixSocketBridge.shared.lastError as Any?) ?? NSNull()
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

        if handleTabsRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, queryItem: queryItem, connection: connection, origin: origin) {
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
        if await handleTelemetryRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, queryItem: queryItem, connection: connection, origin: origin) {
            return
        }

        sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"Endpoint not found: \(method) \(path)\",\"code\":\"NOT_FOUND\",\"success\":false}", origin: origin)
    }

    func resolveTab(id: String?) -> Tab? {
        let tab: Tab?
        if let id = id, !id.isEmpty {
            if let uuid = UUID(uuidString: id) {
                tab = store?.tabs.first(where: { $0.id == uuid })
            } else if let idx = Int(id), let tabs = store?.tabs, !tabs.isEmpty {
                // Support 1-based (CLI) and 0-based (REST) index targeting
                if idx >= 1 && idx <= tabs.count {
                    tab = tabs[idx - 1]
                } else if idx >= 0 && idx < tabs.count {
                    tab = tabs[idx]
                } else {
                    tab = nil
                }
            } else if let tabs = store?.tabs {
                tab = tabs.first(where: { $0.id.uuidString.lowercased().hasPrefix(id.lowercased()) })
            } else {
                tab = nil
            }
        } else {
            tab = store?.activeTab
        }
        if let t = tab, t.tier == .cold {
            t.hydrateToHot()
        }
        return tab
    }

    func requireTab(id: String? = nil, connection: NWConnection, origin: String?, errorMessage: String? = nil) -> Tab? {
        guard let tab = resolveTab(id: id) else {
            let msg: String
            let code: String
            if let errorMessage = errorMessage {
                msg = errorMessage
                code = "TAB_NOT_FOUND"
            } else if let id = id, !id.isEmpty {
                msg = "Tab not found with id '\(id)'"
                code = "TAB_NOT_FOUND"
            } else {
                msg = "No active tab"
                code = "NO_ACTIVE_TAB"
            }
            sendResponse(connection: connection, status: "404 Not Found", body: "{\"error\":\"\(msg)\",\"code\":\"\(code)\",\"success\":false}", origin: origin)
            return nil
        }
        return tab
    }

    // MARK: - HTTP Network Response Serialization

    nonisolated func sendJSON(connection: NWConnection, status: String = "200 OK", object: Any, origin: String? = nil) {
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) {
            sendRaw(connection: connection, status: status, contentType: "application/json; charset=utf-8", data: data, origin: origin)
        } else {
            sendResponse(connection: connection, status: "500 Internal Server Error", body: "{\"error\":\"JSON encoding error\",\"code\":\"INTERNAL_ERROR\",\"success\":false}", origin: origin)
        }
    }

    nonisolated func sendResponse(connection: NWConnection, status: String, body: String, origin: String? = nil) {
        let bodyData = Data(body.utf8)
        sendRaw(connection: connection, status: status, contentType: "application/json; charset=utf-8", data: bodyData, origin: origin)
    }

    nonisolated func sendRaw(connection: NWConnection, status: String = "200 OK", contentType: String, data: Data, origin: String? = nil) {
        var corsHeaders = ""
        if let origin = origin, !origin.isEmpty, Self.isAllowedOrigin(origin) {
            corsHeaders = """
            Access-Control-Allow-Origin: \(origin)\r
            Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r
            Access-Control-Allow-Headers: Authorization, Content-Type, X-Nomad-Token\r\n
            """
        }
        let headers = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        \(corsHeaders)Connection: close\r
        \r\n
        """
        var responseData = Data(headers.utf8)
        responseData.append(data)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Server-Sent Events (SSE) Real-Time Telemetry & Event Streaming

    nonisolated func registerEventStream(connection: NWConnection, origin: String?) {
        eventBroadcaster.register(connection: connection, origin: origin)
    }

    nonisolated func broadcastEvent(name: String, payload: [String: Any]) {
        eventBroadcaster.broadcast(name: name, payload: payload)
    }
}

/// Thread-safe registry and broadcaster for connected Server-Sent Events (SSE) clients.
nonisolated final class EventStreamBroadcaster: @unchecked Sendable {
    private var eventConnections = [ObjectIdentifier: NWConnection]()
    private let eventLock = NSLock()

    func register(connection: NWConnection, origin: String?) {
        var corsHeaders = ""
        if let origin = origin, !origin.isEmpty, NomadAgentServer.isAllowedOrigin(origin) {
            corsHeaders = """
            Access-Control-Allow-Origin: \(origin)\r
            Access-Control-Allow-Methods: GET, OPTIONS\r
            Access-Control-Allow-Headers: Authorization, Content-Type, X-Nomad-Token\r\n
            """
        }
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream; charset=utf-8\r
        Cache-Control: no-cache, no-transform\r
        Connection: keep-alive\r
        \(corsHeaders)\r
        : nomad event stream connected\r\n\r\n
        """
        let headerData = Data(headers.utf8)
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            guard let self = self, error == nil else {
                connection.cancel()
                return
            }
            self.add(connection)
        })
    }

    private func add(_ connection: NWConnection) {
        eventLock.lock()
        let id = ObjectIdentifier(connection)
        eventConnections[id] = connection
        eventLock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .cancelled, .failed:
                self.eventLock.lock()
                self.eventConnections.removeValue(forKey: id)
                self.eventLock.unlock()
            default:
                break
            }
        }
    }

    func broadcast(name: String, payload: [String: Any]) {
        var eventObj = payload
        if eventObj["timestamp"] == nil {
            eventObj["timestamp"] = Date().timeIntervalSince1970 * 1000.0
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: eventObj),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        let sseMessage = "event: \(name)\ndata: \(jsonString)\n\n"
        let sseData = Data(sseMessage.utf8)

        eventLock.lock()
        let connections = Array(eventConnections.values)
        eventLock.unlock()

        for conn in connections {
            conn.send(content: sseData, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.eventLock.lock()
                    self?.eventConnections.removeValue(forKey: ObjectIdentifier(conn))
                    self?.eventLock.unlock()
                    conn.cancel()
                }
            })
        }
    }

    func closeAll() {
        eventLock.lock()
        for conn in eventConnections.values {
            conn.cancel()
        }
        eventConnections.removeAll()
        eventLock.unlock()
    }
}

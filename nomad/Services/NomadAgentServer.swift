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
    nonisolated private static func isAllowedOrigin(_ origin: String?) -> Bool {
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

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var port: UInt16 = NomadAgentServer.defaultPort
    @Published private(set) var requestCount: Int = 0

    /// Secure local authentication token loaded from ~/.nomad/agent-token or NOMAD_TOKEN environment variable.
    let token: String = NomadAgentServer.loadOrCreateAgentToken()

    weak var store: BrowserStore?

    private var listener: NWListener?
    nonisolated private let serverQueue = DispatchQueue(label: "nomad.agent.server", qos: .userInitiated)

    /// Process activity assertion to ensure macOS App Nap and timer coalescing are disabled during agent server operations
    private var activityToken: NSObjectProtocol? = {
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "Nomad Agent Server Automation"
        )
    }()

    private init() {}

    /// Loads an existing agent token from ~/.nomad/agent-token or generates a new cryptographically secure token.
    private static func loadOrCreateAgentToken() -> String {
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

    /// Starts the local agent server (default: NOMAD_AGENT_PORT or 9222).
    @MainActor
    func start(port: UInt16? = nil, store: BrowserStore? = nil) {
        if let store = store {
            self.store = store
        }
        guard !isRunning else { return }
        self.port = port ?? Self.defaultPort

        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = false
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback

            guard let endpointPort = NWEndpoint.Port(rawValue: self.port) else {
                print("⚠️ [NomadAgentServer] Invalid port: \(self.port)")
                return
            }

            let newListener = try NWListener(using: params, on: endpointPort)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self.isRunning = true
                        print("🟢 [NomadAgentServer] Listening on http://127.0.0.1:\(self.port) (Bearer auth enabled)")
                    case .failed(let error):
                        print("🔴 [NomadAgentServer] Failed with error: \(error)")
                        self.stop()
                    case .cancelled:
                        self.isRunning = false
                        print("⚪️ [NomadAgentServer] Stopped.")
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
            print("⚠️ [NomadAgentServer] Could not initialize NWListener: \(error)")
        }
    }

    /// Stops the server and cleanly releases all sockets and connections.
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - HTTP Request Handling (Runs on serverQueue)

    nonisolated private func handleIncomingConnection(_ connection: NWConnection) {
        // Enforce loopback check on incoming peer endpoint to prevent interface leakage
        if case .hostPort(let host, _) = connection.endpoint {
            let hostStr = "\(host)"
            if hostStr != "127.0.0.1" && hostStr != "::1" && hostStr != "localhost" {
                print("🛡️ [NomadAgentServer] Rejecting non-loopback connection from: \(hostStr)")
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
            if let error = error {
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
            print("🛡️ [NomadAgentServer] Blocked cross-origin request from untrusted origin: \(origin ?? "unknown")")
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
        let isPublicHealthCheck = (method == "GET" && (path == "/" || path == "/status" || cleanPath == "/" || cleanPath == "/status"))
        if !isAuthenticated {
            if isPublicHealthCheck {
                let publicStatusObj: [String: Any] = [
                    "nomad": "active",
                    "version": "1.0",
                    "port": self.port,
                    "authRequired": true
                ]
                sendJSON(connection: connection, object: publicStatusObj, origin: origin)
                return
            } else {
                sendResponse(connection: connection, status: "401 Unauthorized", body: "{\"error\":\"Unauthorized: valid Bearer token required in Authorization header or ~/.nomad/agent-token\",\"code\":\"UNAUTHORIZED\",\"success\":false}", origin: origin)
                return
            }
        }

        // Health check probes ("GET /" or "GET /status") can respond immediately even before BrowserStore finishes attaching
        if method == "GET" && (cleanPath == "/" || cleanPath == "/status") {
            let capabilities: [String: Any] = [
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
                "dialogPolicies": ["accept", "dismiss", "wait"]
            ]
            let liveTitle = (self.store?.activeTab?.webView.title?.isEmpty == false ? self.store?.activeTab?.webView.title : self.store?.activeTab?.title) ?? ""
            let liveURL = (self.store?.activeTab?.webView.url?.absoluteString ?? self.store?.activeTab?.url?.absoluteString) ?? ""
            let statusObj: [String: Any] = [
                "nomad": "active",
                "version": "1.0",
                "port": self.port,
                "tabsCount": self.store?.tabs.count ?? 0,
                "tabCount": self.store?.tabs.count ?? 0,
                "activeTabId": self.store?.activeTabId?.uuidString ?? "",
                "activeURL": liveURL,
                "activeTitle": liveTitle,
                "lastDialog": (self.store?.activeTab?.lastDialog as Any?) ?? NSNull(),
                "hasPendingDialog": self.store?.activeTab?.pendingDialog != nil,
                "capabilities": capabilities
            ]
            sendJSON(connection: connection, object: statusObj, origin: origin)
            return
        }

        guard let store = self.store else {
            sendResponse(connection: connection, status: "503 Service Unavailable", body: "{\"error\":\"BrowserStore not connected\",\"code\":\"SERVICE_UNAVAILABLE\",\"success\":false}", origin: origin)
            return
        }

        if handleTabsRoute(method: method, cleanPath: cleanPath, bodyData: bodyData, connection: connection, origin: origin) {
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
        if let id = id, !id.isEmpty {
            guard let uuid = UUID(uuidString: id) else { return nil }
            return store?.tabs.first(where: { $0.id == uuid })
        }
        return store?.activeTab
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
}

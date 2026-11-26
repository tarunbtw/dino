//
//  DinoAgentServer.swift
//  dino
//
//  Created by tarun on 12/10/26.
//

import Foundation
import Network
import AppKit
import Combine
import WebKit
import CryptoKit

/// Embedded lightweight local API server for Dino using Apple's native Network.framework.
/// Binds strictly to 127.0.0.1:9222 with zero third-party dependencies, 0% idle CPU, and automatic socket cleanup.
@MainActor
final class DinoAgentServer: ObservableObject {
    static let shared = DinoAgentServer()

    static var defaultPort: UInt16 {
        if let envStr = ProcessInfo.processInfo.environment["DINO_AGENT_PORT"] ?? ProcessInfo.processInfo.environment["DINO_AGENT_PORT"],
           let p = UInt16(envStr) {
            return p
        }
        return 9222
    }

    /// Tests whether a local loopback TCP port is available for binding.
    nonisolated static func isPortAvailable(_ port: UInt16) -> Bool {
        // 1. Attempt TCP connect. If connection succeeds, another listener is actively bound.
        let connFd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        if connFd >= 0 {
            defer { Darwin.close(connFd) }
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

            let connRes = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    Darwin.connect(connFd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if connRes == 0 {
                return false
            }
        }

        // 2. Attempt bind strictly without SO_REUSEADDR/SO_REUSEPORT
        let bindFd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard bindFd >= 0 else { return false }
        defer { Darwin.close(bindFd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.bind(bindFd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindRes == 0
    }

    /// Scans loopback ports starting from `start` to allocate a collision-free endpoint for headless workers.
    nonisolated static func findAvailablePort(startingAt start: UInt16 = 9222, maxAttempts: UInt16 = 100) -> UInt16 {
        for p in start..<(start + maxAttempts) {
            if isPortAvailable(p) {
                return p
            }
        }
        return start
    }

    /// Constant-time string comparison to prevent timing attacks on bearer token authentication.
    nonisolated static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
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
        if lower.hasPrefix("chrome-extension://") || lower.hasPrefix("dino://") { return true }
        guard let url = URL(string: origin),
              let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }

    /// Checks if a file path points to sensitive OS or user credentials (SSH keys, Dino tokens, Keychains, system passwd, cloud secrets).
    nonisolated static func isSensitivePath(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        let rawLower = expanded.lowercased()
        let canonicalURL = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardized
        let canonicalLower = canonicalURL.path.lowercased()
        let pathsToCheck = [rawLower, canonicalLower]

        // 1. Block sensitive OS system directories
        let blockedSystemPrefixes = [
            "/etc", "/private/etc",
            "/var/root", "/private/var/root",
            "/system", "/usr", "/bin", "/sbin"
        ]
        for p in pathsToCheck {
            for prefix in blockedSystemPrefixes {
                if p == prefix || p.hasPrefix(prefix + "/") {
                    return true
                }
            }
        }

        // 2. Block sensitive user credential and dotfile directories
        let sensitiveDirTokens = [
            "/.ssh", "/.dino", "/.aws", "/.azure", "/.config/gcloud",
            "/.gnupg", "/.kube", "/library/keychains", "/keychains"
        ]
        for p in pathsToCheck {
            if sensitiveDirTokens.contains(where: { p.contains($0) }) {
                return true
            }
        }

        // 3. Block sensitive filenames and credential dotfiles anywhere
        let sensitiveFileNames: Set<String> = [
            "passwd", "shadow", "master.passwd", "sudoers",
            "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa",
            "known_hosts", "authorized_keys",
            ".env", ".gitconfig", ".netrc", ".dockercfg"
        ]
        let lastComponent = canonicalURL.lastPathComponent.lowercased()
        if sensitiveFileNames.contains(lastComponent) || lastComponent.hasPrefix(".env.") || lastComponent.hasSuffix(".passwd") {
            return true
        }

        return false
    }

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var port: UInt16 = DinoAgentServer.defaultPort
    @Published var requestCount: Int = 0

    /// Secure local authentication token loaded from ~/.dino/agent-token or DINO_TOKEN environment variable.
    let token: String = DinoAgentServer.loadOrCreateAgentToken()

    weak var store: BrowserStore?

    private var listener: NWListener?
    nonisolated let serverQueue = DispatchQueue(label: "dino.agent.server", qos: .userInitiated)
    nonisolated private let eventBroadcaster = EventStreamBroadcaster()

    /// Process activity assertion to ensure macOS App Nap and timer coalescing are disabled during agent server operations
    private var activityToken: NSObjectProtocol? = {
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "Dino Agent Server Automation"
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
        if policyMode == "permissive" { return true }
        guard !allowedDomains.isEmpty else { return false }
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

    /// Loads an existing agent token from ~/.dino/agent-token or generates a new cryptographically secure token.
    static func loadOrCreateAgentToken() -> String {
        if let envToken = ProcessInfo.processInfo.environment["DINO_TOKEN"], !envToken.isEmpty {
            return envToken.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let dinoDir = homeDir.appendingPathComponent(".dino", isDirectory: true)
        let tokenFile = dinoDir.appendingPathComponent("agent-token")

        if let existing = try? String(contentsOf: tokenFile, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        try? fileManager.createDirectory(at: dinoDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        try? token.write(to: tokenFile, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        return token
    }

    private var isStarting: Bool = false

    /// Starts the local agent server (default: DINO_AGENT_PORT or 9222).
    @MainActor
    func start(port: UInt16? = nil, store: BrowserStore? = nil) {
        if let store = store {
            self.store = store
        }
        guard !isRunning, !isStarting, listener == nil else { return }
        isStarting = true

        let targetPort: UInt16
        if let explicit = port {
            targetPort = explicit
        } else if DinoHeadlessManager.isHeadless {
            if Self.isPortAvailable(Self.defaultPort) {
                targetPort = Self.defaultPort
            } else {
                targetPort = Self.findAvailablePort(startingAt: 9223)
            }
        } else {
            if Self.isPortAvailable(Self.defaultPort) {
                targetPort = Self.defaultPort
            } else {
                targetPort = Self.findAvailablePort(startingAt: 9223)
            }
        }
        self.port = targetPort

        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = false
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback

            guard let endpointPort = NWEndpoint.Port(rawValue: self.port) else {
                print("[dino] Invalid agent port: \(self.port)")
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
                        if DinoHeadlessManager.isHeadless {
                            let pid = getpid()
                            let workerSocket = DinoCLIManager.workerSocketPath(for: pid)
                            DinoUnixSocketBridge.shared.start(port: self.port, token: self.token, socketPath: workerSocket)
                            if DinoCLIManager.getRunningGUIPID() == nil {
                                let defaultSock = "\(DinoCLIManager.dinoDirectory)/dino.sock"
                                if defaultSock != workerSocket {
                                    unlink(defaultSock)
                                    symlink(workerSocket, defaultSock)
                                }
                            }
                            DinoCLIManager.recordWorker(
                                pid: pid,
                                port: self.port,
                                socketPath: workerSocket,
                                profile: DinoHeadlessManager.shared.profile.rawValue
                            )
                            print("[dino] Headless agent server listening on http://127.0.0.1:\(self.port) (Socket: \(workerSocket))")
                        } else {
                            DinoUnixSocketBridge.shared.start(port: self.port, token: self.token)
                            print("[dino] Agent server listening on http://127.0.0.1:\(self.port)")
                        }
                    case .failed(let error):
                        print("[dino] Agent server error: \(error)")
                        self.isStarting = false
                        self.stop()
                    case .cancelled:
                        self.isStarting = false
                        self.isRunning = false
                        print("[dino] Agent server stopped")
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
            print("[dino] Listener error: \(error)")
        }
    }

    /// Stops the server and cleanly releases all sockets and connections.
    func stop() {
        isStarting = false
        isRunning = false
        DinoUnixSocketBridge.shared.stop()
        eventBroadcaster.closeAll()

        listener?.cancel()
        listener = nil
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

    nonisolated static func queryBool(_ name: String, from queryItem: (String) -> String?, default defaultValue: Bool = false) -> Bool {
        guard let val = queryItem(name) else { return defaultValue }
        return val == "true" || val == "1"
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
        if let origin = origin, !origin.isEmpty, DinoAgentServer.isAllowedOrigin(origin) {
            corsHeaders = """
            Access-Control-Allow-Origin: \(origin)\r
            Access-Control-Allow-Methods: GET, OPTIONS\r
            Access-Control-Allow-Headers: Authorization, Content-Type, X-Dino-Token\r\n
            """
        }
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream; charset=utf-8\r
        Cache-Control: no-cache, no-transform\r
        Connection: keep-alive\r
        \(corsHeaders)\r
        : dino event stream connected\r\n\r\n
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

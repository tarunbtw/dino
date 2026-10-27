//
//  NomadUnixSocketBridge.swift
//  nomad
//
//  Created by tarun on 27/10/26.
//

import Foundation
import Darwin

/// High-performance local IPC bridge listening on a POSIX Unix Domain Socket (`~/.nomad/nomad.sock`).
/// Provides sub-millisecond local communication for developer CLI tools and SDKs (npm/pip)
/// with strict 0600 file permissions and automatic bearer token injection for same-user processes.
final class NomadUnixSocketBridge: @unchecked Sendable {
    static let shared = NomadUnixSocketBridge()

    private var serverFd: Int32 = -1
    private var isRunning: Bool = false
    private let stateLock = NSLock()
    private let queue = DispatchQueue(label: "nomad.ipc.unixsocket", qos: .userInitiated)
    private var source: DispatchSourceRead?
    private var targetPort: UInt16 = 9222
    private var authToken: String = ""

    private(set) var lastError: String? = nil
    static var configuredSocketPath: String? = nil

    /// Returns true if the AF_UNIX domain socket is currently bound and listening.
    var isListening: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning && serverFd >= 0
    }

    static var defaultSocketPath: String {
        if let custom = configuredSocketPath, !custom.isEmpty {
            return resolvePath(custom)
        }
        if let envPath = ProcessInfo.processInfo.environment["NOMAD_SOCKET_PATH"], !envPath.isEmpty {
            return resolvePath(envPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.nomad/nomad.sock"
    }

    static func resolvePath(_ raw: String) -> String {
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return expanded
        }
        let cwd = FileManager.default.currentDirectoryPath
        return (cwd as NSString).appendingPathComponent(expanded)
    }

    private init() {}

    func start(port: UInt16, token: String) {
        queue.async { [weak self] in
            self?.startSync(port: port, token: token)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopSync()
        }
    }

    /// Unbinds and closes the unix domain socket, unlinking the socket file from disk.
    func unbind(completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else {
                completion?(false)
                return
            }
            let oldPath = Self.defaultSocketPath
            self.stopSync()
            unlink(oldPath)
            Self.configuredSocketPath = nil
            completion?(true)
        }
    }

    /// Rebinds the unix domain socket to a new path (or restarts on existing path) dynamically at runtime.
    func rebind(newPath: String? = nil, completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        if let newPath = newPath, !newPath.isEmpty {
            Self.configuredSocketPath = newPath
        }
        queue.async { [weak self] in
            guard let self = self else {
                completion?(false, "bridge deallocated")
                return
            }
            self.stopSync()
            let p = self.targetPort
            let tok = self.authToken
            self.startSync(port: p, token: tok)
            let active = self.isListening
            let err = self.lastError
            completion?(active, err)
        }
    }

    private func startSync(port: UInt16, token: String) {
        stateLock.lock()
        guard !isRunning else {
            stateLock.unlock()
            return
        }
        self.targetPort = port
        self.authToken = token
        stateLock.unlock()

        let socketPath = Self.defaultSocketPath
        let parentDir = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        // Clean up any stale socket file
        unlink(socketPath)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            let err = errno
            let errStr = String(cString: strerror(err))
            print("⚠️ [NomadUnixSocketBridge] Failed to create AF_UNIX socket: \(err) (\(errStr))")
            stateLock.lock()
            lastError = "socket failed: \(err) (\(errStr))"
            stateLock.unlock()
            return
        }

        // Set non-blocking
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        socketPath.withCString { cstr in
            _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                memset(raw, 0, maxPathLen + 1)
                strncpy(raw, cstr, maxPathLen)
            }
        }
        let pathLen = min(socketPath.utf8.count, maxPathLen)
        let sunOffset = 2
        let sunLen = UInt8(sunOffset + pathLen)
        addr.sun_len = sunLen

        var bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.bind(fd, saPtr, socklen_t(sunLen))
            }
        }
        if bindRes != 0 {
            bindRes = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    Darwin.bind(fd, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }

        guard bindRes == 0 else {
            let err = errno
            let errStr = String(cString: strerror(err))
            print("⚠️ [NomadUnixSocketBridge] Failed to bind to \(socketPath): \(err) (\(errStr))")
            stateLock.lock()
            lastError = "bind failed: \(err) (\(errStr))"
            stateLock.unlock()
            Darwin.close(fd)
            return
        }

        // Enforce 0600 permissions so only the current user can access the socket
        chmod(socketPath, 0o600)

        guard Darwin.listen(fd, 64) == 0 else {
            let err = errno
            let errStr = String(cString: strerror(err))
            print("⚠️ [NomadUnixSocketBridge] Failed to listen on socket: \(err) (\(errStr))")
            stateLock.lock()
            lastError = "listen failed: \(err) (\(errStr))"
            stateLock.unlock()
            Darwin.close(fd)
            unlink(socketPath)
            return
        }

        stateLock.lock()
        self.serverFd = fd
        self.isRunning = true
        self.lastError = nil
        stateLock.unlock()

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.acceptIncomingConnections()
        }
        readSource.setCancelHandler {
            Darwin.close(fd)
            unlink(socketPath)
        }
        self.source = readSource
        readSource.resume()

        print("🟢 [NomadUnixSocketBridge] IPC Socket ready at: \(socketPath) (Permissions: 0600)")
    }

    private func stopSync() {
        stateLock.lock()
        guard isRunning else {
            stateLock.unlock()
            return
        }
        isRunning = false
        serverFd = -1
        stateLock.unlock()

        source?.cancel()
        source = nil
        unlink(Self.defaultSocketPath)
        print("⚪️ [NomadUnixSocketBridge] IPC Socket closed.")
    }

    private func acceptIncomingConnections() {
        while isRunning {
            var clientAddr = sockaddr_storage()
            var clientLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    Darwin.accept(serverFd, saPtr, &clientLen)
                }
            }
            if clientFd < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                break
            }

            // Dispatch handling of this connection
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientFd: clientFd)
            }
        }
    }

    private func handleClient(clientFd: Int32) {
        defer { Darwin.close(clientFd) }

        // Read request from client
        var buffer = [UInt8](repeating: 0, count: 65536)
        var requestData = Data()

        while true {
            let n = Darwin.read(clientFd, &buffer, buffer.count)
            if n > 0 {
                requestData.append(buffer, count: n)
                // If headers boundary \r\n\r\n is reached, determine if Content-Length requires more data
                if let headerEndRange = requestData.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = requestData.subdata(in: 0..<headerEndRange.lowerBound)
                    let bodyCount = requestData.count - headerEndRange.upperBound
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
                    if bodyCount >= expectedContentLength {
                        break
                    }
                }
            } else if n == 0 {
                break
            } else {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(1000)
                    continue
                }
                break
            }
        }

        guard !requestData.isEmpty else { return }

        // If client connected via Unix socket without Authorization, inject bearer token
        var finalRequest = requestData
        if let headerString = String(data: requestData, encoding: .utf8),
           !headerString.lowercased().contains("authorization:") {
            if let firstLineEnd = requestData.range(of: Data("\r\n".utf8)) {
                let firstLine = requestData.subdata(in: 0..<firstLineEnd.upperBound)
                let rest = requestData.subdata(in: firstLineEnd.upperBound..<requestData.count)
                let authHeader = "Authorization: Bearer \(authToken)\r\n"
                var modified = Data()
                modified.append(firstLine)
                modified.append(Data(authHeader.utf8))
                modified.append(rest)
                finalRequest = modified
            }
        }

        // Connect to local NomadAgentServer at 127.0.0.1:targetPort
        let tcpFd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard tcpFd >= 0 else { return }
        defer { Darwin.close(tcpFd) }

        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port = targetPort.bigEndian
        sin.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connRes = withUnsafePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(tcpFd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard connRes == 0 else { return }

        // Send modified request to TCP server
        finalRequest.withUnsafeBytes { ptr in
            _ = Darwin.write(tcpFd, ptr.baseAddress, finalRequest.count)
        }

        // Read response from TCP server and stream back to clientFd
        var respBuf = [UInt8](repeating: 0, count: 65536)
        while true {
            let bytesRead = Darwin.read(tcpFd, &respBuf, respBuf.count)
            if bytesRead > 0 {
                var bytesWritten = 0
                while bytesWritten < bytesRead {
                    let w = respBuf.withUnsafeBufferPointer { p in
                        Darwin.write(clientFd, p.baseAddress! + bytesWritten, bytesRead - bytesWritten)
                    }
                    if w <= 0 { break }
                    bytesWritten += w
                }
            } else {
                break
            }
        }
    }
}

//
//  DinoCLIClient.swift
//  dino
//

import Foundation
import Darwin

extension DinoCLIClient {
    // MARK: - IPC Transport (Unix Socket with Loopback HTTP Fallback)

    static func request(
        method: String,
        path: String,
        body: Data? = nil,
        timeoutSeconds: Int = 15,
        socketPath: String? = nil,
        port: UInt16? = nil
    ) -> HTTPResponse {
        let sock = socketPath ?? DinoUnixSocketBridge.defaultSocketPath
        if let resp = sendUnixSocketRequest(method: method, path: path, body: body, socketPath: sock, timeoutSeconds: timeoutSeconds) {
            return resp
        }

        let p = port ?? DinoAgentServer.defaultPort
        if let resp = sendHTTPRequest(method: method, path: path, body: body, port: p, timeoutSeconds: timeoutSeconds) {
            return resp
        }

        // Auto-spawn an isolated headless worker in RAM if Dino is not running
        if DinoCLIManager.getRunningWorkers().isEmpty && DinoCLIManager.getRunningGUIPID() == nil {
            if let desc = DinoCLIManager.spawnWorker(profile: "agent", noReap: true) {
                if let resp = sendUnixSocketRequest(method: method, path: path, body: body, socketPath: desc.socketPath, timeoutSeconds: timeoutSeconds) {
                    return resp
                }
                if let resp = sendHTTPRequest(method: method, path: path, body: body, port: desc.port, timeoutSeconds: timeoutSeconds) {
                    return resp
                }
            }
        }

        emitError("dino: Dino is not running. Start it with 'dino start' or launch the Dino app.")
        exit(1)
    }

    static func sendUnixSocketRequest(
        method: String,
        path: String,
        body: Data?,
        socketPath: String,
        timeoutSeconds: Int
    ) -> HTTPResponse? {
        let resolved = DinoUnixSocketBridge.resolvePath(socketPath)
        guard FileManager.default.fileExists(atPath: resolved) else { return nil }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var sockBufSize: Int32 = 1024 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &sockBufSize, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sockBufSize, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path) - 1

        resolved.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                memset(raw, 0, maxPathLen + 1)
                strncpy(raw, cstr, maxPathLen)
            }
        }
        let pathLen = min(resolved.utf8.count, maxPathLen)
        let sunLen = UInt8(2 + pathLen)
        addr.sun_len = sunLen
        let sockLen = socklen_t(sunLen)

        let connRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(fd, saPtr, sockLen)
            }
        }
        guard connRes == 0 else { return nil }

        let bodyData = body ?? Data()
        let token = DinoAgentServer.loadOrCreateAgentToken()
        var reqHeader = "\(method) \(path) HTTP/1.1\r\n"
        reqHeader += "Host: localhost\r\n"
        reqHeader += "Authorization: Bearer \(token)\r\n"
        reqHeader += "Content-Type: application/json\r\n"
        reqHeader += "Content-Length: \(bodyData.count)\r\n"
        reqHeader += "Connection: close\r\n\r\n"

        var reqData = Data(reqHeader.utf8)
        reqData.append(bodyData)

        let writeOk = reqData.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            var written = 0
            while written < reqData.count {
                let w = Darwin.write(fd, base + written, reqData.count - written)
                if w > 0 {
                    written += w
                } else if w < 0 {
                    if errno == EINTR { continue }
                    return false
                } else {
                    return false
                }
            }
            return true
        }
        guard writeOk else { return nil }

        var respData = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        var expectedTotalBytes: Int? = nil

        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n > 0 {
                respData.append(buf, count: n)
                if expectedTotalBytes == nil, let headerEndRange = respData.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = respData.subdata(in: 0..<headerEndRange.lowerBound)
                    if let headerStr = String(data: headerData, encoding: .utf8) {
                        for line in headerStr.components(separatedBy: "\r\n") {
                            let lower = line.lowercased()
                            if lower.hasPrefix("content-length:") {
                                let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                                if let len = Int(valStr) {
                                    expectedTotalBytes = headerEndRange.upperBound + len
                                }
                                break
                            }
                        }
                    }
                }
                if let exp = expectedTotalBytes, respData.count >= exp {
                    break
                }
            } else if n == 0 {
                break
            } else {
                if errno == EINTR { continue }
                break
            }
        }

        guard !respData.isEmpty else { return nil }
        return parseHTTPResponse(data: respData)
    }

    static func sendHTTPRequest(
        method: String,
        path: String,
        body: Data?,
        port: UInt16,
        timeoutSeconds: Int
    ) -> HTTPResponse? {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeoutSeconds)
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let token = DinoAgentServer.loadOrCreateAgentToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let semaphore = DispatchSemaphore(value: 0)
        var parsedResp: HTTPResponse? = nil

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                return
            }
            var headers: [String: String] = [:]
            for (k, v) in httpResponse.allHeaderFields {
                if let ks = k as? String, let vs = v as? String {
                    headers[ks.lowercased()] = vs
                }
            }
            parsedResp = HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds + 2))
        return parsedResp
    }

    static func parseHTTPResponse(data: Data) -> HTTPResponse? {
        guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let headerData = data.subdata(in: 0..<headerEndRange.lowerBound)
        let bodyData = data.subdata(in: headerEndRange.upperBound..<data.count)

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return nil }
        let statusParts = statusLine.components(separatedBy: " ")
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        return HTTPResponse(statusCode: statusCode, headers: headers, body: bodyData)
    }

    // MARK: - Tab ID Resolver

    /// Resolves a tab identifier or 1-based index to a target UUID string.
    static func resolveTabId(_ raw: String?, port: UInt16?, socketPath: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // If it's already a full UUID string, use directly
        if UUID(uuidString: raw) != nil {
            return raw
        }

        // Check if it's an integer index (1-based) or prefix
        let resp = request(method: "GET", path: "/tabs", socketPath: socketPath, port: port)
        guard let json = resp.jsonObject, let tabs = json["tabs"] as? [[String: Any]] else {
            return raw
        }

        if let idx = Int(raw), idx >= 1, idx <= tabs.count {
            return tabs[idx - 1]["id"] as? String ?? raw
        }

        if let matching = tabs.first(where: { ($0["id"] as? String)?.lowercased().hasPrefix(raw.lowercased()) == true }) {
            return matching["id"] as? String ?? raw
        }

        return raw
    }

}

//
//  DinoAgentServer+HTTP.swift
//  dino
//

import Foundation
import Network

extension DinoAgentServer {

    // MARK: - HTTP Request Handling (Runs on serverQueue)

    nonisolated func handleIncomingConnection(_ connection: NWConnection) {
        DispatchQueue.main.async {
            DinoHeadlessManager.shared.recordActivity()
        }
        // Enforce loopback check on incoming peer endpoint to prevent interface leakage
        if case .hostPort(let host, _) = connection.endpoint {
            let hostStr = "\(host)"
            if hostStr != "127.0.0.1" && hostStr != "::1" && hostStr != "localhost" {
                print("[dino] Rejecting non-loopback connection from: \(hostStr)")
                connection.cancel()
                return
            }
        }

        connection.start(queue: serverQueue)
        self.receiveRequest(connection: connection, accumulatedData: Data())
    }

    nonisolated func receiveRequest(connection: NWConnection, accumulatedData: Data) {
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

    nonisolated func processRequest(data: Data, connection: NWConnection) {
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
            Access-Control-Allow-Headers: Authorization, Content-Type, X-Dino-Token\r\n
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

//
//  AgentCDPRoutes.swift
//  dino
//
//  Created by tarun on 04/11/26.
//

import Foundation
import Network
import AppKit
import WebKit
import CryptoKit

// MARK: - Helpers for CDP Target Formatting

@MainActor
func cdpTargetInfo(for tab: Tab?, serverPort: UInt16) -> [String: Any] {
    guard let tab = tab else {
        return [
            "targetId": UUID().uuidString,
            "type": "page",
            "title": "Dino",
            "url": "about:blank",
            "attached": false,
            "canAccessOpener": false,
            "browserContextId": "default"
        ]
    }
    let tabId = tab.id.uuidString
    let title = (tab.webView.title?.isEmpty == false ? tab.webView.title : tab.title) ?? ""
    let urlStr = (tab.webView.url?.absoluteString ?? tab.url?.absoluteString) ?? "about:blank"
    return [
        "targetId": tabId,
        "type": "page",
        "title": title,
        "url": urlStr,
        "attached": false,
        "canAccessOpener": false,
        "browserContextId": "default"
    ]
}

@MainActor
func cdpTargetJSON(for tab: Tab, serverPort: UInt16) -> [String: Any] {
    let tabId = tab.id.uuidString
    let title = (tab.webView.title?.isEmpty == false ? tab.webView.title : tab.title) ?? ""
    let urlStr = (tab.webView.url?.absoluteString ?? tab.url?.absoluteString) ?? "about:blank"
    let wsUrl = "ws://127.0.0.1:\(serverPort)/devtools/page/\(tabId)"
    let devtoolsFrontendUrl = "/devtools/inspector.html?ws=127.0.0.1:\(serverPort)/devtools/page/\(tabId)"
    return [
        "description": "",
        "devtoolsFrontendUrl": devtoolsFrontendUrl,
        "id": tabId,
        "title": title,
        "type": "page",
        "url": urlStr,
        "webSocketDebuggerUrl": wsUrl
    ]
}

func cdpRemoteObject(from value: Any?) -> [String: Any] {
    guard let value = value else {
        return ["type": "undefined"]
    }
    if let b = value as? Bool {
        return ["type": "boolean", "value": b]
    }
    if let n = value as? NSNumber {
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return ["type": "boolean", "value": n.boolValue]
        }
        return ["type": "number", "value": n]
    }
    if let s = value as? String {
        return ["type": "string", "value": s]
    }
    if let dict = value as? [String: Any] {
        return ["type": "object", "value": dict]
    }
    if let arr = value as? [Any] {
        return ["type": "object", "value": arr]
    }
    return ["type": "object", "description": "\(value)"]
}

// MARK: - CDP Session Manager

@MainActor
final class DinoCDPSessionManager {
    static let shared = DinoCDPSessionManager()

    private var sessions: [ObjectIdentifier: DinoCDPWebSocketSession] = [:]

    private init() {}

    func startSession(connection: NWConnection, path: String, server: DinoAgentServer) {
        let session = DinoCDPWebSocketSession(connection: connection, path: path, server: server)
        sessions[ObjectIdentifier(session)] = session
        session.start()
    }

    func unregister(session: DinoCDPWebSocketSession) {
        sessions.removeValue(forKey: ObjectIdentifier(session))
    }

    func notifyTargetCreated(tab: Tab, serverPort: UInt16) {
        let info = cdpTargetInfo(for: tab, serverPort: serverPort)
        for session in sessions.values where session.discoveryEnabled {
            session.sendEvent(method: "Target.targetCreated", params: ["targetInfo": info])
        }
    }

    func notifyTargetDestroyed(tabId: String) {
        for session in sessions.values where session.discoveryEnabled {
            session.sendEvent(method: "Target.targetDestroyed", params: ["targetId": tabId])
        }
    }
}

// MARK: - RFC 6455 WebSocket CDP Protocol Session

@MainActor
final class DinoCDPWebSocketSession {
    let connection: NWConnection
    let pageTabId: UUID?
    weak var server: DinoAgentServer?

    var discoveryEnabled: Bool = false
    var sessionMap: [String: UUID] = [:]
    private var buffer = Data()
    private var isClosed = false

    init(connection: NWConnection, path: String, server: DinoAgentServer) {
        self.connection = connection
        self.server = server

        if path.contains("/devtools/page/") {
            let idPart = path.components(separatedBy: "/devtools/page/").last?.components(separatedBy: "/").first ?? ""
            self.pageTabId = UUID(uuidString: idPart)
        } else {
            self.pageTabId = nil
        }
    }

    func start() {
        receiveLoop()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        DinoCDPSessionManager.shared.unregister(session: self)
        connection.cancel()
    }

    private func receiveLoop() {
        guard !isClosed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1048576) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isClosed else { return }
                if error != nil {
                    self.close()
                    return
                }
                if let data = data, !data.isEmpty {
                    self.buffer.append(data)
                    self.processBuffer()
                }
                if isComplete {
                    self.close()
                } else {
                    self.receiveLoop()
                }
            }
        }
    }

    private func processBuffer() {
        while buffer.count >= 2 {
            let b0 = buffer[buffer.startIndex]
            let b1 = buffer[buffer.startIndex + 1]

            let fin = (b0 & 0x80) != 0
            let opcode = b0 & 0x0F
            let isMasked = (b1 & 0x80) != 0
            var payloadLen = UInt64(b1 & 0x7F)

            var headerSize = 2
            if payloadLen == 126 {
                headerSize = 4
                if buffer.count < headerSize { return }
                let high = UInt64(buffer[buffer.startIndex + 2])
                let low = UInt64(buffer[buffer.startIndex + 3])
                payloadLen = (high << 8) | low
            } else if payloadLen == 127 {
                headerSize = 10
                if buffer.count < headerSize { return }
                var len: UInt64 = 0
                for i in 0..<8 {
                    len = (len << 8) | UInt64(buffer[buffer.startIndex + 2 + i])
                }
                payloadLen = len
            }

            var maskKey: [UInt8] = []
            if isMasked {
                if buffer.count < headerSize + 4 { return }
                maskKey = [
                    buffer[buffer.startIndex + headerSize],
                    buffer[buffer.startIndex + headerSize + 1],
                    buffer[buffer.startIndex + headerSize + 2],
                    buffer[buffer.startIndex + headerSize + 3]
                ]
                headerSize += 4
            }

            let totalFrameSize = headerSize + Int(payloadLen)
            if buffer.count < totalFrameSize {
                return
            }

            let payloadStart = buffer.startIndex + headerSize
            let payloadEnd = payloadStart + Int(payloadLen)
            var payloadData = buffer.subdata(in: payloadStart..<payloadEnd)

            buffer.removeSubrange(buffer.startIndex..<payloadEnd)

            if isMasked && !maskKey.isEmpty {
                var unmasked = payloadData
                for i in 0..<unmasked.count {
                    unmasked[unmasked.startIndex + i] ^= maskKey[i % 4]
                }
                payloadData = unmasked
            }

            handleFrame(opcode: opcode, fin: fin, payload: payloadData)
        }
    }

    private func handleFrame(opcode: UInt8, fin: Bool, payload: Data) {
        switch opcode {
        case 0x1: // Text frame
            if let text = String(data: payload, encoding: .utf8) {
                handleMessage(text)
            }
        case 0x8: // Close frame
            sendCloseFrame()
            close()
        case 0x9: // Ping frame
            sendPongFrame(payload: payload)
        case 0xA: // Pong frame
            break
        default:
            break
        }
    }

    private func sendCloseFrame() {
        let frame = Data([0x88, 0x00])
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func sendPongFrame(payload: Data) {
        var frame = Data()
        frame.append(0x8A)
        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len <= 0xFFFF {
            frame.append(126)
            var be16 = UInt16(len).bigEndian
            withUnsafeBytes(of: &be16) { frame.append(contentsOf: $0) }
        } else {
            frame.append(127)
            var be64 = UInt64(len).bigEndian
            withUnsafeBytes(of: &be64) { frame.append(contentsOf: $0) }
        }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    func sendText(_ text: String) {
        guard !isClosed else { return }
        let payload = Data(text.utf8)
        var frame = Data()
        frame.append(0x81) // FIN + text opcode

        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len <= 0xFFFF {
            frame.append(126)
            var be16 = UInt16(len).bigEndian
            withUnsafeBytes(of: &be16) { frame.append(contentsOf: $0) }
        } else {
            frame.append(127)
            var be64 = UInt64(len).bigEndian
            withUnsafeBytes(of: &be64) { frame.append(contentsOf: $0) }
        }

        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            if error != nil {
                Task { @MainActor [weak self] in
                    self?.close()
                }
            }
        })
    }

    func sendResult(id: Any?, result: Any, sessionId: String? = nil) {
        guard let id = id else { return }
        var response: [String: Any] = [
            "id": id,
            "result": result
        ]
        if let sess = sessionId {
            response["sessionId"] = sess
        }
        if let data = try? JSONSerialization.data(withJSONObject: response),
           let str = String(data: data, encoding: .utf8) {
            sendText(str)
        }
    }

    func sendError(id: Any?, code: Int, message: String, sessionId: String? = nil) {
        guard let id = id else { return }
        var response: [String: Any] = [
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if let sess = sessionId {
            response["sessionId"] = sess
        }
        if let data = try? JSONSerialization.data(withJSONObject: response),
           let str = String(data: data, encoding: .utf8) {
            sendText(str)
        }
    }

    func sendEvent(method: String, params: [String: Any], sessionId: String? = nil) {
        var event: [String: Any] = [
            "method": method,
            "params": params
        ]
        if let sess = sessionId {
            event["sessionId"] = sess
        }
        if let data = try? JSONSerialization.data(withJSONObject: event),
           let str = String(data: data, encoding: .utf8) {
            sendText(str)
        }
    }

    private func resolveTargetTab(sessionId: String?) -> Tab? {
        if let sessId = sessionId, let tabId = sessionMap[sessId] {
            return server?.store?.tabs.first(where: { $0.id == tabId })
        }
        if let pageId = self.pageTabId {
            return server?.store?.tabs.first(where: { $0.id == pageId })
        }
        return server?.store?.activeTab
    }

    private func handleMessage(_ text: String) {
        DinoHeadlessManager.shared.recordActivity()
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }

        let id = json["id"]
        let method = json["method"] as? String ?? ""
        let params = (json["params"] as? [String: Any]) ?? [:]
        let sessionId = json["sessionId"] as? String

        Task { @MainActor in
            await self.dispatchCDP(id: id, method: method, params: params, sessionId: sessionId)
        }
    }

    private func dispatchCDP(id: Any?, method: String, params: [String: Any], sessionId: String?) async {
        let store = server?.store
        let serverPort = server?.port ?? 9222

        switch method {
        // MARK: - Browser Domain
        case "Browser.getVersion":
            sendResult(id: id, result: [
                "protocolVersion": "1.3",
                "product": "Dino/\(Updater.currentVersion)",
                "revision": "\(Updater.currentBuild)",
                "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15 Dino/\(Updater.currentVersion)",
                "jsVersion": "1.0.0"
            ], sessionId: sessionId)

        case "Browser.close":
            sendResult(id: id, result: [:], sessionId: sessionId)
            if DinoHeadlessManager.isHeadless {
                exit(0)
            }

        // MARK: - Target Domain
        case "Target.setDiscoverTargets":
            self.discoveryEnabled = (params["discover"] as? Bool) ?? true
            sendResult(id: id, result: [:], sessionId: sessionId)
            if self.discoveryEnabled, let store = store {
                for tab in store.tabs {
                    let info = cdpTargetInfo(for: tab, serverPort: serverPort)
                    sendEvent(method: "Target.targetCreated", params: ["targetInfo": info])
                }
            }

        case "Target.getTargets":
            let infos = (store?.tabs ?? []).map { cdpTargetInfo(for: $0, serverPort: serverPort) }
            sendResult(id: id, result: ["targetInfos": infos], sessionId: sessionId)

        case "Target.attachToTarget":
            let targetIdStr = params["targetId"] as? String ?? ""
            let tab = store?.tabs.first(where: { $0.id.uuidString == targetIdStr }) ?? store?.activeTab
            let sessId = UUID().uuidString
            if let tab = tab {
                sessionMap[sessId] = tab.id
            }
            sendResult(id: id, result: ["sessionId": sessId], sessionId: sessionId)
            if let tab = tab {
                let info = cdpTargetInfo(for: tab, serverPort: serverPort)
                sendEvent(method: "Target.attachedToTarget", params: [
                    "sessionId": sessId,
                    "targetInfo": info,
                    "waitingForDebugger": false
                ])
            }

        case "Target.detachFromTarget":
            if let sessId = params["sessionId"] as? String {
                sessionMap.removeValue(forKey: sessId)
                sendEvent(method: "Target.detachedFromTarget", params: ["sessionId": sessId])
            }
            sendResult(id: id, result: [:], sessionId: sessionId)

        case "Target.createTarget":
            let urlStr = params["url"] as? String
            let url = urlStr.flatMap { URL(string: $0) }
            if let store = store {
                let tab = store.newTab(url: url)
                DinoCDPSessionManager.shared.notifyTargetCreated(tab: tab, serverPort: serverPort)
                sendResult(id: id, result: ["targetId": tab.id.uuidString], sessionId: sessionId)
            } else {
                sendResult(id: id, result: ["targetId": UUID().uuidString], sessionId: sessionId)
            }

        case "Target.closeTarget":
            let targetIdStr = params["targetId"] as? String
            if let uuid = targetIdStr.flatMap({ UUID(uuidString: $0) }) {
                store?.closeTab(id: uuid)
                DinoCDPSessionManager.shared.notifyTargetDestroyed(tabId: uuid.uuidString)
            }
            sendResult(id: id, result: ["success": true], sessionId: sessionId)

        case "Target.activateTarget":
            let targetIdStr = params["targetId"] as? String
            if let uuid = targetIdStr.flatMap({ UUID(uuidString: $0) }) {
                store?.selectTab(id: uuid)
            }
            sendResult(id: id, result: [:], sessionId: sessionId)

        case "Target.setAutoAttach":
            sendResult(id: id, result: [:], sessionId: sessionId)

        // MARK: - Page Domain
        case "Page.navigate":
            guard let tab = resolveTargetTab(sessionId: sessionId) else {
                sendError(id: id, code: -32000, message: "Target tab not found", sessionId: sessionId)
                return
            }
            let urlStr = params["url"] as? String ?? ""
            let url = URL(string: urlStr) ?? URL(string: "https://" + urlStr)
            if let u = url {
                tab.load(url: u)
            }
            let frameId = tab.id.uuidString
            let loaderId = UUID().uuidString
            sendResult(id: id, result: ["frameId": frameId, "loaderId": loaderId], sessionId: sessionId)
            sendEvent(method: "Page.frameNavigated", params: [
                "frame": [
                    "id": frameId,
                    "loaderId": loaderId,
                    "url": urlStr,
                    "securityOrigin": url?.host ?? "",
                    "mimeType": "text/html"
                ]
            ], sessionId: sessionId)
            sendEvent(method: "Page.loadEventFired", params: ["timestamp": Date().timeIntervalSince1970], sessionId: sessionId)

        case "Page.reload":
            let tab = resolveTargetTab(sessionId: sessionId)
            tab?.webView.reload()
            sendResult(id: id, result: [:], sessionId: sessionId)

        case "Page.getFrameTree":
            let tab = resolveTargetTab(sessionId: sessionId)
            let frameId = tab?.id.uuidString ?? UUID().uuidString
            let frameObj: [String: Any] = [
                "id": frameId,
                "loaderId": frameId,
                "url": tab?.url?.absoluteString ?? "",
                "securityOrigin": tab?.url?.host ?? "",
                "mimeType": "text/html"
            ]
            sendResult(id: id, result: ["frameTree": ["frame": frameObj, "childFrames": []]], sessionId: sessionId)

        case "Page.captureScreenshot":
            guard let tab = resolveTargetTab(sessionId: sessionId) else {
                sendError(id: id, code: -32000, message: "Target tab not found", sessionId: sessionId)
                return
            }
            do {
                let img = try await tab.webView.takeSnapshot(configuration: nil)
                if let png = img.pngData {
                    sendResult(id: id, result: ["data": png.base64EncodedString()], sessionId: sessionId)
                } else {
                    sendError(id: id, code: -32000, message: "Screenshot encoding failed", sessionId: sessionId)
                }
            } catch {
                sendError(id: id, code: -32000, message: error.localizedDescription, sessionId: sessionId)
            }

        case "Page.bringToFront":
            if let tab = resolveTargetTab(sessionId: sessionId) {
                store?.selectTab(id: tab.id)
            }
            sendResult(id: id, result: [:], sessionId: sessionId)

        case "Page.close":
            if let tab = resolveTargetTab(sessionId: sessionId) {
                let idStr = tab.id.uuidString
                store?.closeTab(id: tab.id)
                DinoCDPSessionManager.shared.notifyTargetDestroyed(tabId: idStr)
            }
            sendResult(id: id, result: [:], sessionId: sessionId)

        // MARK: - Runtime Domain
        case "Runtime.evaluate":
            guard let tab = resolveTargetTab(sessionId: sessionId) else {
                sendError(id: id, code: -32000, message: "Target tab not found", sessionId: sessionId)
                return
            }
            let expr = params["expression"] as? String ?? ""
            do {
                let res = try await tab.webView.evaluateJavaScript(expr)
                let ro = cdpRemoteObject(from: res)
                sendResult(id: id, result: ["result": ro], sessionId: sessionId)
            } catch {
                sendResult(id: id, result: [
                    "result": ["type": "undefined"],
                    "exceptionDetails": [
                        "text": error.localizedDescription,
                        "lineNumber": 1,
                        "columnNumber": 1
                    ]
                ], sessionId: sessionId)
            }

        case "Runtime.callFunctionOn":
            guard let tab = resolveTargetTab(sessionId: sessionId) else {
                sendError(id: id, code: -32000, message: "Target tab not found", sessionId: sessionId)
                return
            }
            let decl = params["functionDeclaration"] as? String ?? ""
            let expr = "(\(decl))()"
            do {
                let res = try await tab.webView.evaluateJavaScript(expr)
                let ro = cdpRemoteObject(from: res)
                sendResult(id: id, result: ["result": ro], sessionId: sessionId)
            } catch {
                sendResult(id: id, result: [
                    "result": ["type": "undefined"],
                    "exceptionDetails": ["text": error.localizedDescription]
                ], sessionId: sessionId)
            }

        // MARK: - DOM Domain
        case "DOM.getDocument":
            let rootNode: [String: Any] = [
                "nodeId": 1,
                "backendNodeId": 1,
                "nodeType": 9,
                "nodeName": "#document",
                "localName": "",
                "nodeValue": "",
                "childNodeCount": 1,
                "children": [
                    [
                        "nodeId": 2,
                        "backendNodeId": 2,
                        "nodeType": 1,
                        "nodeName": "HTML",
                        "localName": "html",
                        "nodeValue": "",
                        "childNodeCount": 2,
                        "children": [
                            ["nodeId": 3, "backendNodeId": 3, "nodeType": 1, "nodeName": "HEAD", "localName": "head", "nodeValue": "", "childNodeCount": 0],
                            ["nodeId": 4, "backendNodeId": 4, "nodeType": 1, "nodeName": "BODY", "localName": "body", "nodeValue": "", "childNodeCount": 0]
                        ]
                    ]
                ]
            ]
            sendResult(id: id, result: ["root": rootNode], sessionId: sessionId)

        // MARK: - Input Domain
        case "Input.dispatchMouseEvent":
            guard let tab = resolveTargetTab(sessionId: sessionId) else {
                sendError(id: id, code: -32000, message: "Target tab not found", sessionId: sessionId)
                return
            }
            let type = params["type"] as? String ?? "mousePressed"
            let x = (params["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (params["y"] as? NSNumber)?.doubleValue ?? 0
            let button = params["button"] as? String ?? "left"
            let clickCount = (params["clickCount"] as? Int) ?? 1

            if type == "mousePressed" || clickCount > 0 {
                var act = DinoAction()
                act.action = button == "right" ? "right_click" : (clickCount == 2 ? "dblclick" : "click")
                act.x = CGFloat(x)
                act.y = CGFloat(y)
                act.native = true
                _ = try? await tab.performAction(act)
            } else if type == "mouseMoved" {
                var act = DinoAction()
                act.action = "hover"
                act.x = CGFloat(x)
                act.y = CGFloat(y)
                act.native = true
                _ = try? await tab.performAction(act)
            }
            sendResult(id: id, result: [:], sessionId: sessionId)

        case "Input.dispatchKeyEvent":
            guard let tab = resolveTargetTab(sessionId: sessionId) else {
                sendError(id: id, code: -32000, message: "Target tab not found", sessionId: sessionId)
                return
            }
            let text = params["text"] as? String
            let key = params["key"] as? String
            if let t = text, !t.isEmpty {
                var act = DinoAction()
                act.action = "type"
                act.text = t
                act.native = true
                _ = try? await tab.performAction(act)
            } else if let k = key, !k.isEmpty {
                var act = DinoAction()
                act.action = "press"
                act.key = k
                act.native = true
                _ = try? await tab.performAction(act)
            }
            sendResult(id: id, result: [:], sessionId: sessionId)

        case "Input.insertText":
            guard let tab = resolveTargetTab(sessionId: sessionId) else {
                sendError(id: id, code: -32000, message: "Target tab not found", sessionId: sessionId)
                return
            }
            let text = params["text"] as? String ?? ""
            let act = DinoAction(action: "type", text: text, native: true)
            _ = try? await tab.performAction(act)
            sendResult(id: id, result: [:], sessionId: sessionId)

        // MARK: - Enablers, Configurations & Resilient Fallback
        default:
            // Standard CDP notifications, enables, and metric overrides return empty result to keep clients functioning smoothly
            sendResult(id: id, result: [:], sessionId: sessionId)
        }
    }
}

// MARK: - DinoAgentServer CDP Discovery & Upgrade Extensions

extension DinoAgentServer {
    func handleCDPWebSocketUpgrade(path: String, headers: [String: String], connection: NWConnection) {
        guard let key = headers["sec-websocket-key"]?.trimmingCharacters(in: .whitespaces), !key.isEmpty else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "{\"error\":\"Missing Sec-WebSocket-Key\",\"code\":\"MISSING_KEY\",\"success\":false}")
            return
        }

        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        let acceptKey = Data(digest).base64EncodedString()

        let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(acceptKey)\r\n\r\n"
        let responseData = Data(response.utf8)

        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            guard let self = self, error == nil else {
                connection.cancel()
                return
            }
            Task { @MainActor in
                DinoCDPSessionManager.shared.startSession(
                    connection: connection,
                    path: path,
                    server: self
                )
            }
        })
    }

    func handleCDPDiscoveryRoute(method: String, cleanPath: String, queryString: String, bodyData: Data?, queryItem: (String) -> String?, connection: NWConnection, origin: String?) -> Bool {
        guard let store = self.store else { return false }

        switch (method, cleanPath) {
        case ("GET", "/json/version"), ("GET", "/devtools/version"):
            let browserId = "00000000-0000-0000-0000-000000000000"
            let wsUrl = "ws://127.0.0.1:\(self.port)/devtools/browser/\(browserId)"
            let versionObj: [String: Any] = [
                "Browser": "Dino/\(Updater.currentVersion)",
                "Protocol-Version": "1.3",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15 Dino/\(Updater.currentVersion)",
                "V8-Version": "1.0.0",
                "WebKit-Version": "605.1.15",
                "webSocketDebuggerUrl": wsUrl
            ]
            sendJSON(connection: connection, object: versionObj, origin: origin)
            return true

        case ("GET", "/json"), ("GET", "/json/list"):
            let targets = store.tabs.map { tab -> [String: Any] in
                cdpTargetJSON(for: tab, serverPort: self.port)
            }
            sendJSON(connection: connection, object: targets, origin: origin)
            return true

        case ("GET", "/json/protocol"):
            let protocolObj: [String: Any] = [
                "domains": [
                    ["domain": "Target", "version": "1.3"],
                    ["domain": "Browser", "version": "1.3"],
                    ["domain": "Page", "version": "1.3"],
                    ["domain": "Runtime", "version": "1.3"],
                    ["domain": "DOM", "version": "1.3"],
                    ["domain": "Input", "version": "1.3"],
                    ["domain": "Network", "version": "1.3"],
                    ["domain": "CSS", "version": "1.3"],
                    ["domain": "Log", "version": "1.3"],
                    ["domain": "Emulation", "version": "1.3"]
                ]
            ]
            sendJSON(connection: connection, object: protocolObj, origin: origin)
            return true

        case ("GET", "/json/new"), ("PUT", "/json/new"):
            var targetURL: URL? = nil
            if let qURL = queryItem("url"), let parsed = URL(string: qURL) {
                targetURL = parsed
            } else if !queryString.isEmpty, let parsed = URL(string: queryString) {
                targetURL = parsed
            } else if let bodyData = bodyData,
                      let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                      let urlStr = json["url"] as? String,
                      let parsed = URL(string: urlStr) {
                targetURL = parsed
            }
            let newTab = store.newTab(url: targetURL)
            DinoCDPSessionManager.shared.notifyTargetCreated(tab: newTab, serverPort: self.port)
            let targetObj = cdpTargetJSON(for: newTab, serverPort: self.port)
            sendJSON(connection: connection, object: targetObj, origin: origin)
            return true

        case ("GET", _) where cleanPath.hasPrefix("/json/activate/"):
            let tabIdStr = String(cleanPath.dropFirst("/json/activate/".count))
            if let tab = self.resolveTab(id: tabIdStr) {
                store.selectTab(id: tab.id)
                sendResponse(connection: connection, status: "200 OK", body: "Target activated", origin: origin)
            } else {
                sendResponse(connection: connection, status: "404 Not Found", body: "No such target", origin: origin)
            }
            return true

        case ("GET", _) where cleanPath.hasPrefix("/json/close/"):
            let tabIdStr = String(cleanPath.dropFirst("/json/close/".count))
            if let tab = self.resolveTab(id: tabIdStr) {
                let idStr = tab.id.uuidString
                store.closeTab(id: tab.id)
                DinoCDPSessionManager.shared.notifyTargetDestroyed(tabId: idStr)
                sendResponse(connection: connection, status: "200 OK", body: "Target is closing", origin: origin)
            } else {
                sendResponse(connection: connection, status: "404 Not Found", body: "No such target", origin: origin)
            }
            return true

        default:
            return false
        }
    }
}

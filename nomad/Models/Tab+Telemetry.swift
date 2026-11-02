//
//  Tab+Telemetry.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import WebKit

// MARK: - Script Message Handler & Bridge
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

extension Tab: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in
            self?.handleScriptMessage(name: message.name, body: message.body)
        }
    }

    func handleScriptMessage(name: String, body: Any) {
        if name == "nomadConsole", let dict = body as? [String: Any] {
            let lvlStr = dict["level"] as? String ?? "log"
            let msg = dict["message"] as? String ?? ""
            let level: ConsoleEntry.Level
            switch lvlStr {
            case "error": level = .error
            case "warn": level = .warn
            case "info": level = .info
            default: level = .log
            }
            appendConsoleEntry(level: level, message: msg)
            NomadAgentServer.shared.broadcastEvent(name: "console", payload: [
                "tabId": self.id.uuidString,
                "level": level.rawValue,
                "message": msg
            ])
        } else if name == "nomadInspect", let dict = body as? [String: Any] {
            if dict["cancel"] as? Bool == true {
                self.isInspectorActive = false
                return
            }
            let selector = dict["selector"] as? String ?? ""
            let tag = dict["tag"] as? String ?? ""
            let idAttr = dict["idAttr"] as? String ?? ""
            let classes = dict["classes"] as? String ?? ""
            let text = dict["text"] as? String ?? ""
            let width = dict["width"] as? Int ?? 0
            let height = dict["height"] as? Int ?? 0
            let agentId = dict["agentId"] as? String
            self.inspectedElementInfo = InspectedElementInfo(
                selector: selector,
                tag: tag,
                idAttr: idAttr,
                classes: classes,
                text: text,
                width: width,
                height: height,
                agentId: agentId
            )
            self.isInspectorActive = false
        } else if name == "nomadNetwork", let dict = body as? [String: Any] {
            let method = dict["method"] as? String ?? "GET"
            let url = dict["url"] as? String ?? ""
            let status = dict["status"] as? Int ?? 200
            let duration = dict["duration"] as? Int ?? 0
            let type = dict["type"] as? String ?? "fetch"
            let error = dict["error"] as? String
            let entry = NetworkEntry(method: method, url: url, status: status, durationMs: duration, type: type, error: error)
            if self.networkEntries.count > 400 {
                self.networkEntries.removeFirst(50)
            }
            self.networkEntries.append(entry)
            var netPayload: [String: Any] = [
                "tabId": self.id.uuidString,
                "method": method,
                "url": url,
                "status": status,
                "durationMs": duration,
                "type": type
            ]
            if let err = error { netPayload["error"] = err }
            NomadAgentServer.shared.broadcastEvent(name: "network", payload: netPayload)
        } else if name == "nomadZapper", let dict = body as? [String: Any] {
            if dict["cancel"] as? Bool == true {
                self.isZapperActive = false
                return
            }
            guard let currentHost = self.url?.host?.lowercased(), !currentHost.isEmpty else { return }
            if let sel = dict["selector"] as? String {
                ZapperStore.shared.addSelector(sel, for: currentHost)
            }
        } else if name == "nomadFrameBridge", let dict = body as? [String: Any] {
            if let els = dict["elements"] as? [[String: Any]], !els.isEmpty {
                let fid = (dict["frameId"] as? String) ?? "f1"
                let urlStr = (dict["url"] as? String) ?? ""
                let titleStr = (dict["title"] as? String) ?? ""
                if let data = try? JSONSerialization.data(withJSONObject: els),
                   let elsJSON = String(data: data, encoding: .utf8) {
                    let updateScript = """
                    if (!window.__nomad_frames) window.__nomad_frames = {};
                    window.__nomad_frames['\(fid)'] = {
                        frameId: '\(fid)',
                        url: '\(urlStr)',
                        title: '\(titleStr)',
                        elements: \(elsJSON),
                        updatedAt: Date.now()
                    };
                    """
                    self.webView.evaluateJavaScript(updateScript, completionHandler: nil)
                }
            }
        } else if name == "nomadLinkHover", let dict = body as? [String: Any] {
            self.hoveredLink = dict["url"] as? String
        } else if name == "nomadAutofill", let dict = body as? [String: Any] {
            let action = dict["action"] as? String ?? ""
            if action == "save",
               let host = dict["host"] as? String,
               let user = dict["user"] as? String,
               let secret = dict["secret"] as? String {
                KeychainVault.shared.save(host: host, user: user, secret: secret)
            }
        }
    }

}

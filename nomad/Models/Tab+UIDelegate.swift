//
//  Tab+UIDelegate.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import AppKit
import WebKit

// MARK: - WKUIDelegate
extension Tab: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.modifierFlags.contains(.shift),
           let targetURL = navigationAction.request.url,
           ["http", "https"].contains(targetURL.scheme?.lowercased() ?? "") {
            self.onRequestPeek?(targetURL)
            return nil
        }
        if let onOpenTabWithWebView = self.onOpenTabWithWebView {
            return onOpenTabWithWebView(configuration, navigationAction)
        }
        if let targetURL = navigationAction.request.url {
            if let onOpenURLInNewTab = self.onOpenURLInNewTab {
                onOpenURLInNewTab(targetURL)
            } else {
                self.load(url: targetURL)
            }
        }
        return nil
    }

    // MARK: - Non-blocking JavaScript Alert / Confirm / Prompt handling
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        appendConsoleEntry(level: .info, message: "[Dialog Alert] \(message)")
        NomadAgentServer.shared.broadcastEvent(name: "dialog", payload: [
            "tabId": self.id.uuidString,
            "type": "alert",
            "message": message,
            "policy": dialogPolicy
        ])
        if dialogPolicy.lowercased() == "wait" {
            self.lastDialog = "[Alert: \(message)] -> waiting"
            let pending = PendingDialog(type: .alert, message: message, defaultText: nil, timestamp: Date(), resolve: { [weak self] _ in
                self?.lastDialog = message
                completionHandler()
            })
            self.pendingDialog = pending
            scheduleDialogTimeout(for: message)
            self.onDialogAppeared?(pending)
        } else {
            self.lastDialog = message
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        appendConsoleEntry(level: .info, message: "[Dialog Confirm] \(message)")
        NomadAgentServer.shared.broadcastEvent(name: "dialog", payload: [
            "tabId": self.id.uuidString,
            "type": "confirm",
            "message": message,
            "policy": dialogPolicy
        ])
        if dialogPolicy.lowercased() == "wait" {
            self.lastDialog = "[Confirm: \(message)] -> waiting"
            let pending = PendingDialog(type: .confirm, message: message, defaultText: nil, timestamp: Date(), resolve: { [weak self] result in
                let shouldAccept = (result as? Bool) ?? false
                self?.lastDialog = "[Confirm: \(message)] -> \(shouldAccept ? "accepted" : "dismissed")"
                self?.appendConsoleEntry(level: .info, message: "[Dialog Confirm] \(message) -> \(shouldAccept ? "Accepted" : "Dismissed")")
                completionHandler(shouldAccept)
            })
            self.pendingDialog = pending
            scheduleDialogTimeout(for: message)
            self.onDialogAppeared?(pending)
        } else {
            let shouldAccept = (dialogPolicy.lowercased() == "accept")
            self.lastDialog = "[Confirm: \(message)] -> \(shouldAccept ? "accepted" : "dismissed")"
            appendConsoleEntry(level: .info, message: "[Dialog Confirm] \(message) -> \(shouldAccept ? "Accepted" : "Dismissed")")
            completionHandler(shouldAccept)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        appendConsoleEntry(level: .info, message: "[Dialog Prompt] \(prompt)")
        NomadAgentServer.shared.broadcastEvent(name: "dialog", payload: [
            "tabId": self.id.uuidString,
            "type": "prompt",
            "message": prompt,
            "defaultText": defaultText as Any,
            "policy": dialogPolicy
        ])
        if dialogPolicy.lowercased() == "wait" {
            self.lastDialog = "[Prompt: \(prompt)] -> waiting"
            let pending = PendingDialog(type: .prompt, message: prompt, defaultText: defaultText, timestamp: Date(), resolve: { [weak self] result in
                if let respStr = result as? String {
                    self?.lastDialog = "[Prompt: \(prompt)] -> \"\(respStr)\""
                    self?.appendConsoleEntry(level: .info, message: "[Dialog Prompt] \(prompt) -> \"\(respStr)\"")
                    completionHandler(respStr)
                } else {
                    self?.lastDialog = "[Prompt: \(prompt)] -> dismissed"
                    self?.appendConsoleEntry(level: .info, message: "[Dialog Prompt] \(prompt) -> Dismissed")
                    completionHandler(nil)
                }
            })
            self.pendingDialog = pending
            scheduleDialogTimeout(for: prompt)
            self.onDialogAppeared?(pending)
        } else if dialogPolicy.lowercased() == "accept" {
            let resp = dialogPromptResponse.isEmpty ? (defaultText ?? "") : dialogPromptResponse
            self.lastDialog = "[Prompt: \(prompt)] -> \"\(resp)\""
            appendConsoleEntry(level: .info, message: "[Dialog Prompt] \(prompt) -> \"\(resp)\"")
            completionHandler(resp)
        } else {
            self.lastDialog = "[Prompt: \(prompt)] -> dismissed"
            appendConsoleEntry(level: .info, message: "[Dialog Prompt] \(prompt) -> Dismissed")
            completionHandler(nil)
        }
    }

    private func scheduleDialogTimeout(for message: String) {
        dialogTimeoutTask?.cancel()
        dialogTimeoutTask = Task { @MainActor [weak self] in
            // 20s auto-dismiss safety guard for unhandled dialogs
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self = self, let pending = self.pendingDialog else { return }
            self.appendConsoleEntry(level: .warn, message: "[Dialog Timeout] Unhandled \(pending.type.rawValue) dialog auto-dismissed after 20s.")
            self.pendingDialog = nil
            pending.resolve(nil)
        }
    }

    @discardableResult
    func resolvePendingDialog(action: String, responseText: String? = nil) -> Bool {
        guard let pending = self.pendingDialog else { return false }
        self.pendingDialog = nil
        self.dialogTimeoutTask?.cancel()
        self.dialogTimeoutTask = nil

        let act = action.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch pending.type {
        case .confirm:
            let shouldAccept = (act == "accept")
            pending.resolve(shouldAccept)
        case .alert:
            pending.resolve(())
        case .prompt:
            if act == "dismiss" {
                pending.resolve(nil)
            } else {
                let resp = responseText ?? self.dialogPromptResponse
                let finalResp = resp.isEmpty ? (pending.defaultText ?? "") : resp
                pending.resolve(finalResp)
            }
        }
        return true
    }

    // MARK: - Programmatic & Interactive File Uploads
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        if let staged = self.stagedUploadURLs, !staged.isEmpty {
            self.clearStagedUpload()
            let urlsToUpload = parameters.allowsMultipleSelection ? staged : [staged[0]]
            appendConsoleEntry(level: .info, message: "[Upload] Programmatically injected \(urlsToUpload.count) file(s): \(urlsToUpload.map { $0.lastPathComponent }.joined(separator: ", "))")
            completionHandler(urlsToUpload)
            return
        }

        if NomadHeadlessManager.isHeadless {
            appendConsoleEntry(level: .warn, message: "[Upload] File upload dialog requested without staged files in headless mode. Use 'nomad upload <file>' before clicking upload.")
            completionHandler(nil)
            return
        }

        // Native macOS NSOpenPanel modal sheet fallback for human browsing
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            let response = panel.runModal()
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
}


//
//  TabAutomationDriver.swift
//  dino
//
//  Created for Dino Browser.
//  Encapsulates automation perception, synthetic AppKit/CoreGraphics event generation,
//  in-memory screenshot capture, and action dispatch for an individual Tab.
//

import AppKit
import WebKit
import PDFKit

/// Dedicated automation driver executing DOM perception, synthetic OS events,
/// screenshot capture, and action dispatch for a specific Tab.
@MainActor
final class TabAutomationDriver {
    unowned let tab: Tab
    var webView: WKWebView { tab.webView }

    init(tab: Tab) {
        self.tab = tab
    }

    // MARK: - Isolated Content World Execution Helpers (Ponytail: immune to in-page tampering and bot detection)

    @discardableResult
    func callAsyncIsolated(_ script: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let val): continuation.resume(returning: val)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }
    }

    @discardableResult
    func tryCallAsyncIsolated(_ script: String, arguments: [String: Any] = [:]) async -> Any? {
        try? await callAsyncIsolated(script, arguments: arguments)
    }

    @discardableResult
    func evalIsolated(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let val): continuation.resume(returning: val)
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
        }
    }

    @discardableResult
    func tryEvalIsolated(_ script: String) async -> Any? {
        try? await evalIsolated(script)
    }

    func evalIsolatedString(_ script: String) async throws -> String {
        let val = try await evalIsolated(script)
        return (val as? String) ?? ""
    }

    // MARK: - Script Injection & Settling

    /// Injects DinoDOMScript only if window.__dino is not already initialized in the isolated world.
    func ensureDinoScriptInjected() async {
        let isLoaded = ((try? await evalIsolated("Boolean(window.__dino)")) as? Bool) ?? false
        if !isLoaded {
            _ = try? await evalIsolated(DinoDOMScript.core)
        }
    }

    /// Evaluates in-page anti-bot challenge and 2FA status for Human-in-the-Loop guardrails.
    func checkHitlStatus() async -> (detected: Bool, type: String?, resolved: Bool) {
        await ensureDinoScriptInjected()
        let script = "JSON.stringify(window.__dino && window.__dino.detectChallenge ? window.__dino.detectChallenge() : { detected: false, resolved: true })"
        if let jsonStr = try? await evalIsolatedString(script),
           let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detected = dict["detected"] as? Bool {
            let type = dict["type"] as? String
            let resolved = dict["resolved"] as? Bool ?? true
            return (detected, type, resolved)
        }
        return (false, nil, true)
    }

    /// Checks and synchronizes HITL state on the tab (triggering the in-app banner if active).
    @discardableResult
    func updateHitlState() async -> Bool {
        let (detected, type, resolved) = await checkHitlStatus()
        if detected && !resolved {
            tab.isHitlActive = true
            tab.hitlChallengeType = type
            return true
        } else if resolved && tab.isHitlActive {
            tab.isHitlActive = false
            tab.hitlChallengeType = nil
            return false
        }
        return tab.isHitlActive
    }

    /// Waits for in-flight web view navigation to settle up to a given timeout.
    @discardableResult
    func waitForNavigationSettled(timeout: TimeInterval = 4.0, pollIntervalMs: UInt64 = 25) async -> Bool {
        guard webView.isLoading else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while webView.isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: pollIntervalMs * 1_000_000)
        }
        return !webView.isLoading
    }

    // MARK: - Perception

    /// Extracts a dense, token-efficient semantic tree and element index from the active page.
    func getSemanticTree(
        limit: Int = 100,
        offset: Int = 0,
        viewportOnly: Bool = false,
        includeText: Bool = true,
        includeCoords: Bool = false,
        role: String? = nil,
        text: String? = nil,
        target: String? = nil,
        depth: Int? = nil,
        track: Bool = false
    ) async throws -> DinoSnapshot {
        _ = await waitForNavigationSettled(timeout: 1.5)
        await ensureDinoScriptInjected()

        // Ensure DOM readiness: wait briefly if document or document.body is still loading
        let readyScript = "Boolean(document && document.body && document.readyState !== 'loading')"
        let isReady = (try? await evalIsolated(readyScript)) as? Bool ?? false
        if !isReady {
            let start = Date()
            while Date().timeIntervalSince(start) < 0.6 {
                try? await Task.sleep(nanoseconds: 30_000_000)
                let readyNow = (try? await evalIsolated(readyScript)) as? Bool ?? false
                if readyNow { break }
            }
            await ensureDinoScriptInjected()
        }

        // Actively synchronize sub-frames before taking semantic snapshot
        let syncScript = """
        if (window.__dino && window.__dino.syncSubframes) {
            return await window.__dino.syncSubframes(250);
        }
        return { count: 0 };
        """
        await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(syncScript, arguments: [:], in: nil, in: .defaultClient) { _ in
                continuation.resume()
            }
        }

        var opts: [String: Any] = ["limit": limit, "offset": offset, "viewportOnly": viewportOnly, "includeText": includeText]
        if includeCoords { opts["coords"] = true }
        if let r = role, !r.isEmpty { opts["role"] = r }
        if let txt = text, !txt.isEmpty { opts["text"] = txt }
        if let tgt = target, !tgt.isEmpty { opts["target"] = tgt }
        if let d = depth { opts["depth"] = d }
        if track { opts["track"] = true }
        let optsData = (try? JSONSerialization.data(withJSONObject: opts)) ?? Data()
        let optsJSON = String(data: optsData, encoding: .utf8) ?? "{}"
        let jsonString = (try? await evalIsolatedString("JSON.stringify(window.__dino.getSemanticTree(\(optsJSON)))")) ?? "{}"
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "DinoAgent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse snapshot JSON"])
        }
        var snapshot = try JSONDecoder().decode(DinoSnapshot.self, from: data)

        // Self-healing retry: if snapshot returned 0 elements immediately following a navigation,
        // retry once after 80ms to catch DOM construction if HTML parsing just completed.
        if snapshot.elements.isEmpty && (tab.url?.absoluteString != "about:blank") && role == nil && text == nil {
            try? await Task.sleep(nanoseconds: 80_000_000)
            await ensureDinoScriptInjected()
            if let retryJSON = try? await evalIsolatedString("JSON.stringify(window.__dino.getSemanticTree(\(optsJSON)))"),
               let retryData = retryJSON.data(using: .utf8),
               let retrySnapshot = try? JSONDecoder().decode(DinoSnapshot.self, from: retryData),
               !retrySnapshot.elements.isEmpty {
                snapshot = retrySnapshot
            }
        }

        return snapshot
    }

    /// Computes compact DOM mutation diff between sequential actions (<80 tokens).
    func getDiff(viewportOnly: Bool = false) async throws -> [String: Any] {
        _ = await waitForNavigationSettled(timeout: 1.0)
        await ensureDinoScriptInjected()

        let opts: [String: Any] = ["viewportOnly": viewportOnly]
        let optsData = (try? JSONSerialization.data(withJSONObject: opts)) ?? Data()
        let optsJSON = String(data: optsData, encoding: .utf8) ?? "{}"
        let script = "JSON.stringify(window.__dino.getDiff(\(optsJSON)))"
        let jsonString = (try? await evalIsolatedString(script)) ?? "{}"
        guard let data = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "DinoAgent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compute DOM diff"])
        }
        return dict
    }

    /// Fast, intent-driven semantic natural language element finder with heuristic scoring.
    func findSemantic(query: String, role: String? = nil, viewportOnly: Bool = false) async throws -> [String: Any] {
        await ensureDinoScriptInjected()

        var opts: [String: Any] = ["viewportOnly": viewportOnly]
        if let r = role, !r.isEmpty { opts["role"] = r }
        let optsData = (try? JSONSerialization.data(withJSONObject: opts)) ?? Data()
        let optsJSON = String(data: optsData, encoding: .utf8) ?? "{}"
        let queryData = (try? JSONSerialization.data(withJSONObject: [query])) ?? Data("[\"\"]".utf8)
        let queryArray = String(data: queryData, encoding: .utf8) ?? "[\"\"]"

        let script = "JSON.stringify(window.__dino.findSemantic((\(queryArray))[0], \(optsJSON)))"
        let jsonString = (try? await evalIsolatedString(script)) ?? "{}"
        guard let data = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "DinoAgent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to perform semantic element find"])
        }
        return dict
    }

    // MARK: - Action Dispatch

    /// Dispatches a browser action (click, hover, type, clear, scroll, keypress, select, highlight) on the active page.
    /// Actions on the same tab are serialized through `tab.actionQueue` to prevent focus/input collisions.
    func performAction(_ action: DinoAction) async throws -> DinoActionResult {
        await tab.actionQueue.acquire()
        do {
            let result = try await executeAction(action)
            await tab.actionQueue.release()
            return result
        } catch {
            await tab.actionQueue.release()
            throw error
        }
    }

    private func executeAction(_ action: DinoAction) async throws -> DinoActionResult {
        tab.lastActionTime = Date()
        if let dp = action.dialogPolicy {
            tab.dialogPolicy = dp
        }
        if let dr = action.dialogResponse {
            tab.dialogPromptResponse = dr
        }
        _ = await waitForNavigationSettled(timeout: 2.5)
        if webView.isLoading {
            return DinoActionResult(success: false, message: "Cannot execute action '\(action.action)': active page is currently navigating. Wait for navigation to complete before dispatching actions.", elementId: action.target, lastDialog: tab.lastDialog, hasPendingDialog: tab.pendingDialog != nil)
        }

        // If a pending dialog is already awaiting response, do not dispatch further actions
        if let pending = tab.pendingDialog {
            return DinoActionResult(
                success: false,
                message: "A JavaScript dialog [\(pending.type.rawValue): \"\(pending.message)\"] is currently waiting for resolution. Resolve it via /dialog before dispatching actions.",
                elementId: action.target,
                code: "PENDING_DIALOG",
                lastDialog: tab.lastDialog,
                hasPendingDialog: true
            )
        }

        // Ensure Dino core perception & action scripts are always injected before any action runs
        await ensureDinoScriptInjected()

        // Minimal Human-in-the-Loop check: pause automation if an unsolved security challenge or 2FA gate is active
        if await updateHitlState() {
            return DinoActionResult(
                success: false,
                message: "A security check [\(tab.hitlChallengeType ?? "Security Verification")] is active on this page. Complete the challenge in the browser to resume.",
                elementId: action.target,
                code: "HITL_REQUIRED",
                lastDialog: tab.lastDialog,
                hasPendingDialog: false
            )
        }

        // Native AppKit & CoreGraphics hardware input dispatch (isTrusted: true)
        let isNative = (action.native == true) || action.action.lowercased().hasPrefix("native_")
        if isNative {
            var nativeRes = try await performNativeAction(action)
            nativeRes.lastDialog = tab.lastDialog
            if tab.pendingDialog != nil {
                nativeRes.hasPendingDialog = true
            }
            return nativeRes
        }

        // Programmatic file upload staging & validation
        if action.action.lowercased() == "upload" {
            let paths = action.resolvedPaths
            guard !paths.isEmpty else {
                return DinoActionResult(success: false, message: "Missing required 'paths' or 'files' for upload action", elementId: action.target, code: "MISSING_PATHS", lastDialog: tab.lastDialog, hasPendingDialog: tab.pendingDialog != nil)
            }
            var validatedURLs: [URL] = []
            for path in paths {
                let expanded = (path as NSString).expandingTildeInPath
                if DinoAgentServer.isSensitivePath(expanded) {
                    return DinoActionResult(success: false, message: "Access to sensitive file or directory is blocked by Dino security policy: \(path)", elementId: action.target, code: "ACCESS_DENIED", lastDialog: tab.lastDialog, hasPendingDialog: tab.pendingDialog != nil)
                }
                guard FileManager.default.fileExists(atPath: expanded) else {
                    return DinoActionResult(success: false, message: "File not found at path: \(path)", elementId: action.target, code: "FILE_NOT_FOUND", lastDialog: tab.lastDialog, hasPendingDialog: tab.pendingDialog != nil)
                }
                guard FileManager.default.isReadableFile(atPath: expanded) else {
                    return DinoActionResult(success: false, message: "File is not readable at path: \(path)", elementId: action.target, code: "FILE_NOT_READABLE", lastDialog: tab.lastDialog, hasPendingDialog: tab.pendingDialog != nil)
                }
                validatedURLs.append(URL(fileURLWithPath: expanded))
            }
            tab.stageUpload(urls: validatedURLs)
        }

        await ensureDinoScriptInjected()
        let actionData = try JSONEncoder().encode(action)
        guard let actionJSON = String(data: actionData, encoding: .utf8) else {
            throw NSError(domain: "DinoAgent", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode action JSON"])
        }

        return await withCheckedContinuation { continuation in
            var resumed = false
            let lock = NSLock()

            let safeResume: (DinoActionResult) -> Void = { res in
                lock.lock()
                defer { lock.unlock() }
                if !resumed {
                    resumed = true
                    self.tab.onDialogAppeared = nil
                    continuation.resume(returning: res)
                }
            }

            // If dialogPolicy is "wait" and a dialog appears while executing the action,
            // immediately unblock the HTTP client so it can inspect and respond via /dialog!
            tab.onDialogAppeared = { [weak self] pending in
                guard let self = self else { return }
                let dialogResult = DinoActionResult(
                    success: true,
                    message: "Action triggered a JavaScript dialog: [\(pending.type.rawValue)] \"\(pending.message)\". Awaiting response via /dialog.",
                    elementId: action.target,
                    code: "PENDING_DIALOG",
                    lastDialog: self.tab.lastDialog,
                    hasPendingDialog: true
                )
                safeResume(dialogResult)
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    let resultString = (try? await self.evalIsolatedString("JSON.stringify(window.__dino.performAction(\(actionJSON)))")) ?? "{}"
                    guard let resultData = resultString.data(using: .utf8) else {
                        safeResume(DinoActionResult(success: false, message: "Failed to parse action result JSON", elementId: action.target, code: "ACTION_PARSE_ERROR", lastDialog: self.tab.lastDialog, hasPendingDialog: self.tab.pendingDialog != nil))
                        return
                    }
                    var res = try JSONDecoder().decode(DinoActionResult.self, from: resultData)
                    if action.action.lowercased() == "upload" {
                        if res.success {
                            res.files = action.resolvedPaths
                            res.count = action.resolvedPaths.count
                            res.message = "Successfully uploaded \(res.count ?? 1) file(s) to \(action.target ?? "element")"
                        } else {
                            self.tab.clearStagedUpload()
                        }
                    }
                    if res.success {
                        if action.action.lowercased() == "hover" {
                            if let coords = res.centerCoordinates, let cx = coords["x"], let cy = coords["y"] {
                                let pt = CGPoint(x: cx, y: cy)
                                let winPoint = self.webView.convert(pt, to: nil)
                                if let moveEvent = NSEvent.mouseEvent(
                                    with: .mouseMoved,
                                    location: winPoint,
                                    modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: self.webView.window?.windowNumber ?? 0,
                                    context: nil,
                                    eventNumber: 0,
                                    clickCount: 0,
                                    pressure: 0.0
                                ) {
                                    let sel = NSSelectorFromString("_simulateMouseMove:")
                                    if self.webView.responds(to: sel) {
                                        self.webView.perform(sel, with: moveEvent)
                                    }
                                }
                            }
                        }
                        if res.obscured == true || res.isObscured == true {
                            let tag = (res.interceptedBy ?? res.occludedBy).map { "<\($0)>" } ?? "overlay"
                            DinoRouteCache.shared.record(eventType: "action", message: "Action '\(action.action)' on \(action.target ?? "element") was obscured (intercepted by \(tag))", tabId: self.tab.id.uuidString)
                        } else {
                            DinoRouteCache.shared.record(eventType: "action", message: "Action '\(action.action)' succeeded on \(action.target ?? "element")", tabId: self.tab.id.uuidString)
                        }
                    } else {
                        if (res.code == "STALE_REF" || res.code == "ELEMENT_NOT_FOUND" || res.code == "SELECTOR_NOT_FOUND"),
                           let fallbackSelector = action.selector, !fallbackSelector.isEmpty, fallbackSelector != action.target {
                            var fallbackAction = action
                            fallbackAction.target = fallbackSelector
                            fallbackAction.selector = nil
                            if let fallbackRes = try? await self.executeAction(fallbackAction), fallbackRes.success {
                                safeResume(fallbackRes)
                                return
                            }
                        }
                        DinoRouteCache.shared.record(eventType: "actionError", message: "Action '\(action.action)' failed on \(action.target ?? "element"): \(res.message)", tabId: self.tab.id.uuidString)
                    }
                    res.lastDialog = self.tab.lastDialog
                    if self.tab.pendingDialog != nil {
                        res.hasPendingDialog = true
                    }
                    safeResume(res)
                } catch let decodeErr as DecodingError {
                    if action.action.lowercased() == "upload" { self.tab.clearStagedUpload() }
                    safeResume(DinoActionResult(success: false, message: "Failed to decode action result: \(decodeErr.localizedDescription)", elementId: action.target, code: "ACTION_DECODE_ERROR", lastDialog: self.tab.lastDialog, hasPendingDialog: self.tab.pendingDialog != nil))
                } catch {
                    if action.action.lowercased() == "upload" { self.tab.clearStagedUpload() }
                    safeResume(DinoActionResult(
                        success: false,
                        message: "JavaScript evaluation failed: \(error.localizedDescription)",
                        elementId: action.target,
                        code: "ACTION_EVALUATION_ERROR",
                        error: error.localizedDescription,
                        lastDialog: self.tab.lastDialog,
                        hasPendingDialog: self.tab.pendingDialog != nil
                    ))
                }
            }
        }
    }

    /// Waits for DOM mutation quiescence (stability) on the active page.
    func waitForStability(quietMs: Int = 250, timeoutMs: Int = 5000) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        // 1. Wait for webView provisional or active navigation to complete
        await waitForNavigationSettled(timeout: max(0.0, deadline.timeIntervalSinceNow), pollIntervalMs: 50)

        // 2. Wait for HTML document to finish parsing
        while Date() < deadline {
            let readyState = (try? await webView.evaluateJavaScript("document.readyState")) as? String
            if readyState != "loading" {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let remainingSeconds = deadline.timeIntervalSinceNow
        if remainingSeconds <= 0.05 && timeoutMs > 50 {
            return ["success": false, "reason": "timeout", "message": "Exceeded max wait of \(timeoutMs)ms (page still loading)"]
        }
        let remainingTimeoutMs = max(50, Int(remainingSeconds * 1000.0))

        await ensureDinoScriptInjected()
        let script = """
        return await (async () => {
            if (!window.__dino || !window.__dino.waitForStability) {
                return { success: false, reason: "not_ready", message: "Dino agent perception script not initialized" };
            }
            return await window.__dino.waitForStability(quietMs, timeoutMs);
        })();
        """
        return try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.webView.callAsyncJavaScript(script, arguments: ["quietMs": quietMs, "timeoutMs": remainingTimeoutMs], in: nil, in: .defaultClient) { result in
                        switch result {
                        case .success(let val):
                            if let dict = val as? [String: Any] {
                                continuation.resume(returning: dict)
                            } else {
                                continuation.resume(returning: ["success": true, "message": "DOM stabilized"])
                            }
                        case .failure(let error):
                            let nsErr = error as NSError
                            if nsErr.domain == "WKErrorDomain" && nsErr.code == 4 { // WKErrorJavaScriptExceptionOccurred during page navigation
                                continuation.resume(returning: ["success": false, "reason": "navigation_occurred", "message": "Document navigated during wait for stability"])
                            } else {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
            group.addTask {
                let sleepTime = max(0.1, remainingSeconds + 0.3)
                try await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
                return ["success": false, "reason": "timeout", "message": "Exceeded max wait of \(timeoutMs)ms"]
            }
            let firstResult = try await group.next()!
            group.cancelAll()
            return firstResult
        }
    }

}

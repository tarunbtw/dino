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

    // MARK: - Native Hardware Input (AppKit & CoreGraphics isTrusted: true)

    /// Synthesizes native AppKit and CoreGraphics input events delivering true OS-level user gestures (isTrusted: true).
    func performNativeAction(_ action: DinoAction) async throws -> DinoActionResult {
        if let dp = action.dialogPolicy {
            tab.dialogPolicy = dp
        }
        if let dr = action.dialogResponse {
            tab.dialogPromptResponse = dr
        }
        await ensureDinoScriptInjected()

        // 1. Resolve target coordinates and element properties in web view viewport space
        var targetPoint: CGPoint? = nil
        var isTargetEditable = false
        var targetTagName = ""
        let hasTarget = action.target.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false

        if let target = action.target, hasTarget {
            if let rect = (try? await callAsyncIsolated(
                "return window.__dino.getElementViewportRect(target);",
                arguments: ["target": target]
            )) as? [String: Any],
               let x = (rect["left"] as? NSNumber)?.doubleValue,
               let y = (rect["top"] as? NSNumber)?.doubleValue,
               let w = (rect["width"] as? NSNumber)?.doubleValue,
               let h = (rect["height"] as? NSNumber)?.doubleValue,
               (w > 0 || h > 0) {
                if let ax = action.x, let ay = action.y {
                    targetPoint = CGPoint(x: x + ax, y: y + ay)
                } else {
                    targetPoint = CGPoint(x: x + w / 2.0, y: y + h / 2.0)
                }
                isTargetEditable = rect["isEditable"] as? Bool ?? false
                targetTagName = (rect["tagName"] as? String ?? "").lowercased()
            } else {
                let hasSignature = ((try? await callAsyncIsolated(
                    "return Boolean(window.__dino && window.__dino.elementSignatures && window.__dino.elementSignatures[target]);",
                    arguments: ["target": target]
                )) as? Bool) ?? false
                let isRef = (target.range(of: "^(f[0-9]+:)?[e][0-9]+$", options: .regularExpression) != nil)
                let isExplicitSelector = (action.selector != nil)
                let code: String
                let message: String
                if hasSignature {
                    code = "ELEMENT_UNMOUNTED"
                    message = "Target element '\(target)' was unmounted or scrolled offscreen (virtual list). Use 'dino scroll to \(target)' or 'dino snap -v' to refresh viewport."
                } else if isRef {
                    code = "STALE_REF"
                    message = "Target element '\(target)' not found. Please re-snapshot."
                } else if isExplicitSelector {
                    code = "SELECTOR_NOT_FOUND"
                    message = "Target element matching selector '\(target)' not found in DOM."
                } else {
                    code = "ELEMENT_NOT_FOUND"
                    message = "Target element '\(target)' not found or has zero geometry in viewport."
                }
                return DinoActionResult(
                    success: false,
                    message: message,
                    elementId: target,
                    code: code
                )
            }
        } else if let ax = action.x, let ay = action.y {
            targetPoint = CGPoint(x: ax, y: ay)
        }

        let rawType = action.action.lowercased().replacingOccurrences(of: "native_", with: "")

        // 2. Ensure webView is first responder in its window without stealing OS workspace focus
        if let win = webView.window, win.firstResponder != webView {
            win.makeFirstResponder(webView)
        }

        let windowNumber = webView.window?.windowNumber ?? 0

        switch rawType {
        case "click":
            guard let pt = targetPoint else {
                return DinoActionResult(success: false, message: "Missing target element or (x, y) coordinates for native click", elementId: action.target, code: "MISSING_TARGET")
            }
            let winPoint = webView.convert(pt, to: nil)

            // Organic preceding mouseMoved event for Cloudflare Turnstile & anti-bot event validation
            let moveEvent = NSEvent.mouseEvent(
                with: .mouseMoved,
                location: winPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0.0
            )
            if let move = moveEvent { webView.mouseMoved(with: move) }
            await tryEvalIsolated("window.__dino && window.__dino.updateVirtualCursor && window.__dino.updateVirtualCursor(\(pt.x), \(pt.y));")
            try? await Task.sleep(nanoseconds: 12_000_000)

            let downEvent = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: winPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1.0
            )
            let upEvent = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: winPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + 0.03,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0.0
            )

            // ponytail: Single-dispatch native AppKit mouse events in window coordinates.
            // Avoids duplicate event firings and multi-monitor CoreGraphics coordinate distortion.
            if let down = downEvent { webView.mouseDown(with: down) }
            try? await Task.sleep(nanoseconds: 35_000_000)
            if let up = upEvent { webView.mouseUp(with: up) }
            await tryEvalIsolated("if (window.__dino && window.__dino.pulseVirtualCursor) window.__dino.pulseVirtualCursor(\(pt.x), \(pt.y)); else if (window.__dino && window.__dino.updateVirtualCursor) window.__dino.updateVirtualCursor(\(pt.x), \(pt.y));")
            try? await Task.sleep(nanoseconds: 30_000_000)

            return DinoActionResult(
                success: true,
                message: "Native click dispatched at (\(Int(pt.x)), \(Int(pt.y))) with isTrusted: true",
                elementId: action.target,
                centerCoordinates: ["x": pt.x, "y": pt.y],
                code: "SUCCESS",
                native: true,
                isTrusted: true,
                lastDialog: tab.lastDialog,
                hasPendingDialog: tab.pendingDialog != nil
            )

        case "dblclick", "double_click", "doubleclick", "native_dblclick", "native_double_click":
            guard let pt = targetPoint else {
                return DinoActionResult(success: false, message: "Missing target element or (x, y) coordinates for native double click", elementId: action.target, code: "MISSING_TARGET")
            }
            let winPoint = webView.convert(pt, to: nil)

            // Click 1
            if let down1 = NSEvent.mouseEvent(with: .leftMouseDown, location: winPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
                webView.mouseDown(with: down1)
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
            if let up1 = NSEvent.mouseEvent(with: .leftMouseUp, location: winPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0) {
                webView.mouseUp(with: up1)
            }
            try? await Task.sleep(nanoseconds: 25_000_000)

            // Click 2 (with clickCount = 2)
            if let down2 = NSEvent.mouseEvent(with: .leftMouseDown, location: winPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1.0) {
                webView.mouseDown(with: down2)
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
            if let up2 = NSEvent.mouseEvent(with: .leftMouseUp, location: winPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 0.0) {
                webView.mouseUp(with: up2)
            }
            await tryEvalIsolated("if (window.__dino && window.__dino.pulseVirtualCursor) window.__dino.pulseVirtualCursor(\(pt.x), \(pt.y)); else if (window.__dino && window.__dino.updateVirtualCursor) window.__dino.updateVirtualCursor(\(pt.x), \(pt.y));")
            try? await Task.sleep(nanoseconds: 30_000_000)

            return DinoActionResult(
                success: true,
                message: "Native double click dispatched at (\(Int(pt.x)), \(Int(pt.y))) with isTrusted: true",
                elementId: action.target,
                centerCoordinates: ["x": pt.x, "y": pt.y],
                code: "SUCCESS",
                native: true,
                isTrusted: true,
                lastDialog: tab.lastDialog,
                hasPendingDialog: tab.pendingDialog != nil
            )

        case "right_click", "rightclick", "context_menu", "contextmenu":
            guard let pt = targetPoint else {
                return DinoActionResult(success: false, message: "Missing target element or (x, y) coordinates for native right click", elementId: action.target, code: "MISSING_TARGET")
            }
            let winPoint = webView.convert(pt, to: nil)

            // Preceding mouseMoved
            let moveEvent = NSEvent.mouseEvent(
                with: .mouseMoved,
                location: winPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0.0
            )
            if let move = moveEvent { webView.mouseMoved(with: move) }
            await tryEvalIsolated("window.__dino && window.__dino.updateVirtualCursor && window.__dino.updateVirtualCursor(\(pt.x), \(pt.y));")
            try? await Task.sleep(nanoseconds: 12_000_000)

            let downEvent = NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: winPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1.0
            )
            let upEvent = NSEvent.mouseEvent(
                with: .rightMouseUp,
                location: winPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + 0.03,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0.0
            )

            if let down = downEvent { webView.rightMouseDown(with: down) }
            try? await Task.sleep(nanoseconds: 35_000_000)
            if let up = upEvent { webView.rightMouseUp(with: up) }
            await tryEvalIsolated("if (window.__dino && window.__dino.pulseVirtualCursor) window.__dino.pulseVirtualCursor(\(pt.x), \(pt.y)); else if (window.__dino && window.__dino.updateVirtualCursor) window.__dino.updateVirtualCursor(\(pt.x), \(pt.y));")
            try? await Task.sleep(nanoseconds: 30_000_000)

            return DinoActionResult(
                success: true,
                message: "Native context menu (right click) dispatched at (\(Int(pt.x)), \(Int(pt.y))) with isTrusted: true",
                elementId: action.target,
                centerCoordinates: ["x": pt.x, "y": pt.y],
                code: "SUCCESS",
                native: true,
                isTrusted: true,
                lastDialog: tab.lastDialog,
                hasPendingDialog: tab.pendingDialog != nil
            )

        case "hover":
            guard let pt = targetPoint else {
                return DinoActionResult(success: false, message: "Missing target element or (x, y) coordinates for hover", elementId: action.target, code: "MISSING_TARGET", lastDialog: tab.lastDialog, hasPendingDialog: tab.pendingDialog != nil)
            }
            let winPoint = webView.convert(pt, to: nil)
            let screenPoint = webView.window?.convertPoint(toScreen: winPoint) ?? winPoint

            if let win = webView.window {
                win.acceptsMouseMovedEvents = true
            }

            // In-app virtual cursor: dispatch AppKit NSEvent directly to WKWebView and NSWindow without warping the user's OS mouse
            if let moveEvent = NSEvent.mouseEvent(
                with: .mouseMoved,
                location: winPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0.0
            ) {
                let targetView = webView.window?.contentView?.hitTest(winPoint) ?? webView
                targetView.mouseMoved(with: moveEvent)
                webView.window?.sendEvent(moveEvent)
                let sel = NSSelectorFromString("_simulateMouseMove:")
                if webView.responds(to: sel) {
                    webView.perform(sel, with: moveEvent)
                }
            }

            // Also dispatch synthetic pointer & mouse events and apply :hover CSS state emulation
            let escapedTarget = (action.target ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let jsDispatch = """
            (function() {
                try {
                    var el = null;
                    if ("\(escapedTarget)") {
                        el = (window.__dino && window.__dino.elements && window.__dino.elements["\(escapedTarget)"]) || (window.__dino && window.__dino.findInTree && window.__dino.findInTree(document, "\(escapedTarget)")) || document.querySelector("[data-dino-id='\(escapedTarget)']") || document.querySelector("\(escapedTarget)");
                    }
                    if (!el) {
                        el = document.elementFromPoint(\(pt.x), \(pt.y));
                    }
                    if (el) {
                        var elDoc = el.ownerDocument || document;
                        var elWin = elDoc.defaultView || window;
                        var rect = el.getBoundingClientRect();
                        var cx = Math.round(rect.left + rect.width / 2) || \(Int(pt.x));
                        var cy = Math.round(rect.top + rect.height / 2) || \(Int(pt.y));
                        var evOpts = { bubbles: true, cancelable: true, view: elWin, clientX: cx, clientY: cy, screenX: \(Int(screenPoint.x)), screenY: \(Int(screenPoint.y)), pointerId: 1, pointerType: 'mouse', isPrimary: true };
                        var enterOpts = { bubbles: false, cancelable: false, view: elWin, clientX: cx, clientY: cy, screenX: \(Int(screenPoint.x)), screenY: \(Int(screenPoint.y)), pointerId: 1, pointerType: 'mouse', isPrimary: true };
                        el.dispatchEvent(new elWin.PointerEvent('pointerover', evOpts));
                        el.dispatchEvent(new elWin.PointerEvent('pointerenter', enterOpts));
                        el.dispatchEvent(new elWin.PointerEvent('pointermove', evOpts));
                        el.dispatchEvent(new elWin.MouseEvent('mouseover', evOpts));
                        el.dispatchEvent(new elWin.MouseEvent('mouseenter', enterOpts));
                        el.dispatchEvent(new elWin.MouseEvent('mousemove', evOpts));

                        if (window.__dino && window.__dino.emulateHover) {
                            window.__dino.emulateHover(el, cx, cy);
                        } else if (window.__dino && window.__dino.updateVirtualCursor) {
                            window.__dino.updateVirtualCursor(cx, cy);
                        }
                    }
                } catch(e) {}
            })()
            """
            _ = await tryEvalIsolated(jsDispatch)

            try? await Task.sleep(nanoseconds: 30_000_000)

            return DinoActionResult(
                success: true,
                message: "Hover dispatched at (\(Int(pt.x)), \(Int(pt.y))) with isTrusted: true",
                elementId: action.target,
                centerCoordinates: ["x": pt.x, "y": pt.y],
                code: "SUCCESS",
                native: true,
                isTrusted: true,
                lastDialog: tab.lastDialog,
                hasPendingDialog: tab.pendingDialog != nil
            )

        case "drag":
            guard let fromPt = targetPoint else {
                return DinoActionResult(success: false, message: "No target element or coordinates specified for drag action", elementId: action.target, code: "MISSING_TARGET")
            }
            var destPoint: CGPoint? = nil
            if let tx = action.toX, let ty = action.toY {
                destPoint = CGPoint(x: tx, y: ty)
            } else if let toTarget = (action.toTarget ?? action.toElementId ?? action.toSelector)?.trimmingCharacters(in: .whitespacesAndNewlines), !toTarget.isEmpty {
                let escaped = toTarget.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let script = "JSON.stringify(window.__dino.getElementViewportRect(\"\(escaped)\"))"
                if let rectStr = try? await evalIsolatedString(script),
                   let rectData = rectStr.data(using: .utf8),
                   let rect = try? JSONSerialization.jsonObject(with: rectData) as? [String: Any],
                   let x = (rect["left"] as? NSNumber)?.doubleValue,
                   let y = (rect["top"] as? NSNumber)?.doubleValue,
                   let w = (rect["width"] as? NSNumber)?.doubleValue,
                   let h = (rect["height"] as? NSNumber)?.doubleValue,
                   (w > 0 || h > 0) {
                    destPoint = CGPoint(x: x + w / 2.0, y: y + h / 2.0)
                } else {
                    return DinoActionResult(success: false, message: "Cannot execute native drag: destination element '\(toTarget)' not found or has zero geometry in viewport.", elementId: toTarget, code: "DESTINATION_NOT_FOUND")
                }
            }
            guard let toPt = destPoint else {
                return DinoActionResult(success: false, message: "Missing destination coordinates (toX, toY) or destination element (toElementId/toTarget) for native drag", elementId: action.target, code: "MISSING_DESTINATION")
            }
            let fromWin = webView.convert(fromPt, to: nil)
            let toWin = webView.convert(toPt, to: nil)

            // 1. Native mouse down (AppKit window coordinates)
            if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: fromWin, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
                webView.mouseDown(with: down)
            }
            let steps = 5
            for i in 1...steps {
                let factor = CGFloat(i) / CGFloat(steps)
                let intermediate = CGPoint(x: fromPt.x + (toPt.x - fromPt.x) * factor, y: fromPt.y + (toPt.y - fromPt.y) * factor)
                let intermediateWin = webView.convert(intermediate, to: nil)

                if let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: intermediateWin, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
                    webView.mouseDragged(with: drag)
                }
                await tryEvalIsolated("if (window.__dino && window.__dino.updateVirtualCursor) window.__dino.updateVirtualCursor(\(intermediate.x), \(intermediate.y));")
                try? await Task.sleep(nanoseconds: 15_000_000)
            }

            // 2. Dispatch HTML5 Drag & Drop pipeline (dragstart -> dragenter -> dragover -> drop -> dragend)
            _ = await tryCallAsyncIsolated(
                "return window.__dino.dispatchHtml5Drag(fromTarget, fromX, fromY, toX, toY, null, toTarget);",
                arguments: [
                    "fromTarget": action.target ?? "",
                    "fromX": fromPt.x,
                    "fromY": fromPt.y,
                    "toX": toPt.x,
                    "toY": toPt.y,
                    "toTarget": action.toTarget ?? action.toElementId ?? ""
                ]
            )

            // 3. Native mouse up (AppKit)
            if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: toWin, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0) {
                webView.mouseUp(with: up)
            }
            let destDesc = (action.toTarget ?? action.toElementId) != nil ? "'\(action.toTarget ?? action.toElementId!)' (\(Int(toPt.x)), \(Int(toPt.y)))" : "(\(Int(toPt.x)), \(Int(toPt.y)))"
            return DinoActionResult(success: true, message: "Native drag executed from '\(action.target ?? "element")' (\(Int(fromPt.x)), \(Int(fromPt.y))) to \(destDesc) with isTrusted: true", elementId: action.target, code: "SUCCESS", native: true, isTrusted: true)

        case "type":
            guard let text = action.text else {
                return DinoActionResult(success: false, message: "Missing 'text' for native type action", elementId: action.target, code: "MISSING_TEXT")
            }
            guard hasTarget, let target = action.target else {
                return DinoActionResult(
                    success: false,
                    message: "Missing target element for native type action",
                    elementId: action.target,
                    code: "MISSING_TARGET"
                )
            }
            if !isTargetEditable {
                let tag = targetTagName.isEmpty ? "element" : targetTagName
                return DinoActionResult(
                    success: false,
                    message: "Target element <\(tag)> is not editable or an input control",
                    elementId: target,
                    code: "NOT_EDITABLE"
                )
            }

            // Establish DOM focus on the target element and fail loudly if focus cannot be set
            if let focusRes = (try? await callAsyncIsolated(
                "return window.__dino.focusElement(target);",
                arguments: ["target": target]
            )) as? [String: Any] {
                let focused = focusRes["success"] as? Bool ?? false
                if !focused {
                    let msg = focusRes["message"] as? String ?? "Failed to establish focus on target element '\(target)'"
                    return DinoActionResult(
                        success: false,
                        message: msg,
                        elementId: target,
                        code: "FOCUS_FAILED"
                    )
                }
            }

            // Click target with native AppKit events to ensure full window & gesture activation
            if let pt = targetPoint {
                let winPoint = webView.convert(pt, to: nil)
                if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: winPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
                    webView.mouseDown(with: down)
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
                if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: winPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0) {
                    webView.mouseUp(with: up)
                }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }

            // ponytail: Use NSEvent keyDown/keyUp for standard ASCII keys, and NSTextInputClient.insertText for non-ASCII/Unicode/CJK/emoji.
            let shiftedChars: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ~!@#$%^&*()_+{}|:\"<>?")
            for char in text {
                let charStr = String(char)
                let keyCode = Self.keyCodeForCharacter(char)
                let isSupportedAsciiKey = char.isASCII && (keyCode != 0 || char == "a" || char == "A")

                if isSupportedAsciiKey {
                    let isShifted = shiftedChars.contains(char)
                    let flags: NSEvent.ModifierFlags = isShifted ? [.shift] : []
                    let unshiftedStr = isShifted ? charStr.lowercased() : charStr
                    if let downKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: charStr, charactersIgnoringModifiers: unshiftedStr, isARepeat: false, keyCode: keyCode) {
                        webView.keyDown(with: downKey)
                    }
                    try? await Task.sleep(nanoseconds: 12_000_000)
                    if let upKey = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: charStr, charactersIgnoringModifiers: unshiftedStr, isARepeat: false, keyCode: keyCode) {
                        webView.keyUp(with: upKey)
                    }
                } else if let textClient = (webView.window?.firstResponder as? NSTextInputClient) ?? (webView as? NSTextInputClient) {
                    textClient.insertText(charStr, replacementRange: NSRange(location: NSNotFound, length: 0))
                } else {
                    await tryCallAsyncIsolated(
                        "document.execCommand('insertText', false, text);",
                        arguments: ["text": charStr]
                    )
                }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            if action.submit == true {
                if let returnDown = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                    webView.keyDown(with: returnDown)
                }
                if let returnUp = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                    webView.keyUp(with: returnUp)
                }
            }
            return DinoActionResult(success: true, message: "Native typing executed (\(text.count) chars) with isTrusted: true", elementId: action.target, code: "SUCCESS", native: true, isTrusted: true)

        case "press":
            let rawChord = (action.key ?? action.text ?? "Enter").trimmingCharacters(in: .whitespacesAndNewlines)
            let (keyCode, charStr, modFlags) = Self.parseKeyChord(rawChord, explicitModifiers: action.modifiers)

            if hasTarget, let target = action.target {
                let escapedTarget = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let focusScript = """
                (function() {
                    var el = (window.__dino && window.__dino.elements && window.__dino.elements["\(escapedTarget)"]) || (window.__dino && window.__dino.findInTree && window.__dino.findInTree(document, "\(escapedTarget)")) || document.querySelector("[data-dino-id='\(escapedTarget)']") || document.querySelector("\(escapedTarget)");
                    if (el) {
                        try { el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                        try { el.focus(); } catch(e) {}
                    }
                })()
                """
                _ = await tryEvalIsolated(focusScript)
                try? await Task.sleep(nanoseconds: 15_000_000)
            }

            // Direct native editing command triggers for Select All
            if modFlags.contains(.command) && (charStr.lowercased() == "a") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: webView)
            }

            if let keyDn = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modFlags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: charStr, charactersIgnoringModifiers: charStr, isARepeat: false, keyCode: keyCode) {
                webView.keyDown(with: keyDn)
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
            if let keyUp = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: modFlags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: charStr, charactersIgnoringModifiers: charStr, isARepeat: false, keyCode: keyCode) {
                webView.keyUp(with: keyUp)
            }

            if hasTarget, let target = action.target {
                let escapedTarget = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let stepScript = """
                (function() {
                    var el = (window.__dino && window.__dino.elements && window.__dino.elements["\(escapedTarget)"]) || (window.__dino && window.__dino.findInTree && window.__dino.findInTree(document, "\(escapedTarget)")) || document.querySelector("[data-dino-id='\(escapedTarget)']") || document.querySelector("\(escapedTarget)");
                    if (el && el.tagName === 'INPUT' && (el.type === 'range' || el.type === 'number')) {
                        var k = "\(rawChord)".toLowerCase();
                        if (k.indexOf('right') !== -1 || k.indexOf('up') !== -1) {
                            try { el.stepUp(); el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); } catch(e) {}
                        } else if (k.indexOf('left') !== -1 || k.indexOf('down') !== -1) {
                            try { el.stepDown(); el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); } catch(e) {}
                        }
                    }
                })()
                """
                _ = await tryEvalIsolated(stepScript)
            }
            return DinoActionResult(success: true, message: "Native keypress '\(rawChord)' dispatched with isTrusted: true", elementId: action.target, code: "SUCCESS", native: true, isTrusted: true)

        case "scroll", "wheel", "scrollwheel", "native_scroll", "native_wheel":
            var rawDeltaX = action.scrollDeltaX ?? 0
            var rawDeltaY = action.scrollDeltaY ?? 0

            if action.scrollDeltaX == nil && action.scrollDeltaY == nil {
                let amount = action.amount ?? 120
                let dir = (action.direction ?? "down").lowercased()
                switch dir {
                case "up":
                    rawDeltaY = -amount
                case "down":
                    rawDeltaY = amount
                case "left":
                    rawDeltaX = -amount
                case "right":
                    rawDeltaX = amount
                default:
                    rawDeltaY = amount
                }
            }

            let pt = targetPoint ?? CGPoint(x: webView.bounds.midX, y: webView.bounds.midY)
            let winPoint = webView.convert(pt, to: nil)
            let screenPoint = webView.window?.convertPoint(toScreen: winPoint) ?? winPoint
            let primaryScreenH = NSScreen.screens.first?.frame.height ?? webView.window?.screen?.frame.height ?? webView.bounds.height
            let cgPos = CGPoint(x: screenPoint.x, y: primaryScreenH - screenPoint.y)

            // 1. High-fidelity AppKit scroll dispatched directly to webView
            if let cgScroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(-rawDeltaY), wheel2: Int32(-rawDeltaX), wheel3: 0) {
                cgScroll.location = cgPos
                if let nsScroll = NSEvent(cgEvent: cgScroll) {
                    webView.scrollWheel(with: nsScroll)
                }
            }

            // 2. Fallback DOM scroll & in-app virtual cursor tracking in isolated world
            let jsScroll = """
            (function() {
                try {
                    window.scrollBy(\(rawDeltaX), \(rawDeltaY));
                    if (window.__dino && window.__dino.updateVirtualCursor) {
                        window.__dino.updateVirtualCursor(\(pt.x), \(pt.y));
                    }
                } catch(e) {}
            })()
            """
            _ = await tryEvalIsolated(jsScroll)
            try? await Task.sleep(nanoseconds: 20_000_000)

            return DinoActionResult(
                success: true,
                message: "Native scroll dispatched (deltaX: \(Int(rawDeltaX)), deltaY: \(Int(rawDeltaY))) at (\(Int(pt.x)), \(Int(pt.y))) with isTrusted: true",
                elementId: action.target,
                centerCoordinates: ["x": pt.x, "y": pt.y],
                code: "SUCCESS",
                native: true,
                isTrusted: true,
                lastDialog: tab.lastDialog,
                hasPendingDialog: tab.pendingDialog != nil
            )

        default:
            return DinoActionResult(success: false, message: "Native mode not supported for action type '\(action.action)'", elementId: action.target, code: "UNSUPPORTED_NATIVE_ACTION")
        }
    }

    // MARK: - Key Chord Helpers

    private static func keyCodeForCharacter(_ char: Character) -> UInt16 {
        switch char {
        case "a", "A": return 0
        case "s", "S": return 1
        case "d", "D": return 2
        case "f", "F": return 3
        case "h", "H": return 4
        case "g", "G": return 5
        case "z", "Z": return 6
        case "x", "X": return 7
        case "c", "C": return 8
        case "v", "V": return 9
        case "b", "B": return 11
        case "q", "Q": return 12
        case "w", "W": return 13
        case "e", "E": return 14
        case "r", "R": return 15
        case "y", "Y": return 16
        case "t", "T": return 17
        case "1", "!": return 18
        case "2", "@": return 19
        case "3", "#": return 20
        case "4", "$": return 21
        case "6", "^": return 22
        case "5", "%": return 23
        case "=", "+": return 24
        case "9", "(": return 25
        case "7", "&": return 26
        case "-", "_": return 27
        case "8", "*": return 28
        case "0", ")": return 29
        case "o", "O": return 31
        case "u", "U": return 32
        case "i", "I": return 34
        case "p", "P": return 35
        case "l", "L": return 37
        case "j", "J": return 38
        case "k", "K": return 40
        case ";", ":": return 41
        case "\\", "|": return 42
        case ",", "<": return 43
        case "/", "?": return 44
        case "n", "N": return 45
        case "m", "M": return 46
        case ".", ">": return 47
        case " ": return 49
        case "\r", "\n": return 36
        case "\t": return 48
        default: return 0
        }
    }

    private static func parseKeyChord(_ chord: String, explicitModifiers: [String]? = nil) -> (UInt16, String, NSEvent.ModifierFlags) {
        var flags: NSEvent.ModifierFlags = []
        if let explicit = explicitModifiers {
            for mod in explicit {
                let m = mod.lowercased()
                if m.contains("meta") || m.contains("cmd") || m.contains("command") { flags.insert(.command) }
                if m.contains("ctrl") || m.contains("control") { flags.insert(.control) }
                if m.contains("alt") || m.contains("option") { flags.insert(.option) }
                if m.contains("shift") { flags.insert(.shift) }
            }
        }

        let parts = chord.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        let mainKey = parts.last ?? chord
        if parts.count > 1 {
            for modPart in parts.dropLast() {
                let m = modPart.lowercased()
                if m == "meta" || m == "cmd" || m == "command" { flags.insert(.command) }
                else if m == "ctrl" || m == "control" { flags.insert(.control) }
                else if m == "alt" || m == "option" { flags.insert(.option) }
                else if m == "shift" { flags.insert(.shift) }
            }
        }

        let (keyCode, charStr) = keyCodeForKeyName(mainKey)
        return (keyCode, charStr, flags)
    }

    private static func keyCodeForKeyName(_ name: String) -> (UInt16, String) {
        let lower = name.lowercased()
        switch lower {
        case "enter", "return": return (36, "\r")
        case "tab": return (48, "\t")
        case "space": return (49, " ")
        case "backspace", "delete": return (51, "\u{7f}")
        case "escape", "esc": return (53, "\u{1b}")
        case "arrowleft", "left": return (123, "\u{f702}")
        case "arrowright", "right": return (124, "\u{f703}")
        case "arrowdown", "down": return (125, "\u{f701}")
        case "arrowup", "up": return (126, "\u{f700}")
        default:
            if let first = name.first {
                return (keyCodeForCharacter(first), String(first))
            }
            return (36, "\r")
        }
    }

    // MARK: - Screenshot & PDF

    /// Captures a crisp screenshot directly from WebKit's in-memory compositing buffer (GPU RAM).
    func captureScreenshot(labeled: Bool = false, elementId: String? = nil, clip: CGRect? = nil, somCrop: Bool = false, fullPage: Bool = false) async throws -> NSImage {
        await ensureDinoScriptInjected()

        if labeled || (elementId != nil && elementId?.contains("f") == true) {
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
        }

        var targetRect: CGRect? = clip

        if fullPage && targetRect == nil && elementId == nil {
            let dimsScript = """
            (function() {
                var w = Math.max(document.body ? document.body.scrollWidth : 0, document.documentElement ? document.documentElement.scrollWidth : 0, window.innerWidth || 1280);
                var h = Math.max(document.body ? document.body.scrollHeight : 0, document.documentElement ? document.documentElement.scrollHeight : 0, window.innerHeight || 800);
                return { width: w, height: h };
            })()
            """
            if let dims = (try? await evalIsolated(dimsScript)) as? [String: Any],
               let w = (dims["width"] as? NSNumber)?.doubleValue,
               let h = (dims["height"] as? NSNumber)?.doubleValue,
               w > 0 && h > 0 {
                targetRect = CGRect(x: 0, y: 0, width: w, height: h)
            }
        }

        // Set-of-Marks (SoM) Dynamic Container Cropping
        if targetRect == nil && somCrop {
            let safeEl = elementId ?? ""
            let safeElData = (try? JSONSerialization.data(withJSONObject: [safeEl])) ?? Data("[\"\"]".utf8)
            let safeElArray = String(data: safeElData, encoding: .utf8) ?? "[\"\"]"
            let somScript = """
            (function() {
                if (window.__dino && window.__dino.getSomContainerRect) {
                    var r = window.__dino.getSomContainerRect((\(safeElArray))[0]);
                    return r ? JSON.stringify(r) : null;
                }
                return null;
            })()
            """
            if let dictStr = try? await evalIsolatedString(somScript),
               let dictData = dictStr.data(using: .utf8),
               let rectDict = try? JSONSerialization.jsonObject(with: dictData) as? [String: Any],
               let x = (rectDict["x"] as? NSNumber)?.doubleValue,
               let y = (rectDict["y"] as? NSNumber)?.doubleValue,
               let w = (rectDict["width"] as? NSNumber)?.doubleValue,
               let h = (rectDict["height"] as? NSNumber)?.doubleValue,
               w > 0 && h > 0 {
                targetRect = CGRect(x: x, y: y, width: w, height: h)
            }
        }

        if targetRect == nil, let elId = elementId {
            let safeElIdData = (try? JSONSerialization.data(withJSONObject: [elId])) ?? Data("[\"\"]".utf8)
            let safeElIdArray = String(data: safeElIdData, encoding: .utf8) ?? "[\"\"]"
            let rectScript = """
            (function() {
                var targetId = (\(safeElIdArray))[0];
                if (!targetId || typeof targetId !== 'string') return null;

                function resolveRect(tid) {
                    // 1. Direct query via getElementViewportRect (handles frame IDs like 'f1:e2', selectors, and DOM IDs)
                    if (window.__dino && window.__dino.getElementViewportRect) {
                        try {
                            var r = window.__dino.getElementViewportRect(tid);
                            if (r && (r.width > 0 || r.height > 0)) {
                                var rx = r.left !== undefined ? r.left : (r.x !== undefined ? r.x : 0);
                                var ry = r.top !== undefined ? r.top : (r.y !== undefined ? r.y : 0);
                                return { x: rx, y: ry, width: r.width, height: r.height };
                            }
                        } catch(e) {}
                    }

                    // 2. Direct lookup in semantic tree bounds cache
                    var cache = (window.__dino && window.__dino.elementsBounds) || window.__dino_elements_bounds;
                    if (cache && cache[tid]) {
                        var b = cache[tid];
                        if (b && (b.width > 0 || b.height > 0)) {
                            var bx = b.left !== undefined ? b.left : (b.x !== undefined ? b.x : 0);
                            var by = b.top !== undefined ? b.top : (b.y !== undefined ? b.y : 0);
                            return { x: bx, y: by, width: b.width, height: b.height };
                        }
                    }

                    // 3. Fallback: resolve DOM element directly in top document or open shadow tree
                    var el = window.__dino && window.__dino.elements && window.__dino.elements[tid];
                    if (!el && window.__dino && window.__dino.findInTree) {
                        el = window.__dino.findInTree(document, tid);
                    }
                    if (!el) {
                        try { el = document.querySelector('[data-dino-id="' + CSS.escape(tid) + '"]'); } catch(e) {}
                    }
                    if (!el) {
                        try { el = document.getElementById(tid) || document.querySelector('#' + CSS.escape(tid)); } catch(e) {}
                    }
                    if (!el) {
                        try { el = document.querySelector('[name="' + CSS.escape(tid) + '"]') || document.querySelector('[data-testid="' + CSS.escape(tid) + '"]'); } catch(e) {}
                    }
                    if (!el) {
                        try { el = document.querySelector(tid); } catch(e) {}
                    }
                    if (el) {
                        var er = (window.__dino && window.__dino.getElementViewportRect) ? window.__dino.getElementViewportRect(el) : el.getBoundingClientRect();
                        if (er && (er.width > 0 || er.height > 0)) {
                            var erx = er.left !== undefined ? er.left : (er.x !== undefined ? er.x : 0);
                            var ery = er.top !== undefined ? er.top : (er.y !== undefined ? er.y : 0);
                            return { x: erx, y: ery, width: er.width, height: er.height };
                        }
                    }

                    return null;
                }

                var res = resolveRect(targetId);
                if (!res && window.__dino && window.__dino.getSemanticTree) {
                    try {
                        window.__dino.getSemanticTree();
                        res = resolveRect(targetId);
                    } catch(e) {}
                }
                return res;
            })()
            """
            if let dict = (try? await evalIsolated(rectScript)) as? [String: Any],
               let x = (dict["x"] as? NSNumber)?.doubleValue,
               let y = (dict["y"] as? NSNumber)?.doubleValue,
               let w = (dict["width"] as? NSNumber)?.doubleValue,
               let h = (dict["height"] as? NSNumber)?.doubleValue,
               w > 0 && h > 0 {
                targetRect = CGRect(x: x, y: y, width: w, height: h)
            } else {
                await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
                throw NSError(domain: "DinoAgent", code: -5, userInfo: [NSLocalizedDescriptionKey: "Element '\(elId)' not found or has zero dimensions for screenshot crop"])
            }
        }

        // Flush layout and apply sensitive input blurring (plus visual badges if labeled == true)
        let badgeRectArg = targetRect.map { "{ x: \($0.origin.x), y: \($0.origin.y), width: \($0.size.width), height: \($0.size.height) }" } ?? "null"
        let prepScript = """
        (function() {
            try {
                if (window.__dino) {
                    window.__dino.blurSensitiveInputs();
                    if (\(labeled ? "true" : "false")) {
                        window.__dino.getSemanticTree();
                        window.__dino.showBadges(\(badgeRectArg));
                    }
                }
                if (document.body) { void document.body.offsetHeight; }
                return true;
            } catch(e) {
                return false;
            }
        })()
        """
        await tryEvalIsolated(prepScript)

        let config = WKSnapshotConfiguration()
        if let rect = targetRect {
            config.rect = rect
        } else {
            let viewWidth = webView.frame.width > 0 ? webView.frame.width : 1280
            config.snapshotWidth = NSNumber(value: Double(viewWidth))
        }

        do {
            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
                self.webView.takeSnapshot(with: config) { img, err in
                    if let err = err {
                        continuation.resume(throwing: err)
                    } else if let img = img {
                        continuation.resume(returning: img)
                    } else {
                        continuation.resume(throwing: NSError(domain: "DinoAgent", code: -4, userInfo: [NSLocalizedDescriptionKey: "Snapshot returned nil"]))
                    }
                }
            }

            // In displayless sessions (remote SSH, display asleep), WindowServer has no hardware framebuffer,
            // producing a blank/transparent frame. Fall back to WebKit vector PDF layout rendering.
            if self.isBlankImage(image) {
                let pdfConfig = WKPDFConfiguration()
                if let rect = targetRect {
                    pdfConfig.rect = rect
                }
                if let pdfData = try? await self.generatePDF(configuration: pdfConfig),
                   let fallbackImg = self.renderPDFToImage(pdfData: pdfData) {
                    await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
                    return fallbackImg
                }
            }

            await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
            return image
        } catch {
            // If takeSnapshot failed due to display session absence, fall back to createPDF
            let pdfConfig = WKPDFConfiguration()
            if let rect = targetRect {
                pdfConfig.rect = rect
            }
            if let pdfData = try? await self.generatePDF(configuration: pdfConfig),
               let fallbackImg = self.renderPDFToImage(pdfData: pdfData) {
                await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
                return fallbackImg
            }

            await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
            throw error
        }
    }

    func generatePDF(configuration: WKPDFConfiguration? = nil) async throws -> Data {
        let config = configuration ?? WKPDFConfiguration()
        return try await withCheckedThrowingContinuation { continuation in
            self.webView.createPDF(configuration: config) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func renderPDFToImage(pdfData: Data) -> NSImage? {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            return nil
        }

        let pageRect = page.getBoxRect(.mediaBox)
        let width = Int(pageRect.width * 2.0)
        let height = Int(pageRect.height * 2.0)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: 2.0, y: 2.0)
        context.drawPDFPage(page)

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: pageRect.size)
    }

    private func isBlankImage(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return true }
        guard rep.pixelsWide > 0 && rep.pixelsHigh > 0 else { return true }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh

        var sampleColors: [NSColor] = []
        for xi in 1...4 {
            for yi in 1...4 {
                let x = min(w - 1, (w * xi) / 5)
                let y = min(h - 1, (h * yi) / 5)
                if let c = rep.colorAt(x: x, y: y) {
                    sampleColors.append(c)
                }
            }
        }
        guard !sampleColors.isEmpty else { return true }

        // If all pixels are transparent (alpha < 0.05), frame is blank
        if sampleColors.allSatisfy({ $0.alphaComponent < 0.05 }) {
            return true
        }

        // If all pixels are pure solid white (#FFFFFF, typical of WindowServer without display session), frame is blank
        if sampleColors.allSatisfy({ $0.redComponent > 0.99 && $0.greenComponent > 0.99 && $0.blueComponent > 0.99 }) {
            return true
        }

        return false
    }
}

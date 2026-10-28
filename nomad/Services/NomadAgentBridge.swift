//
//  NomadAgentBridge.swift
//  nomad
//
//  Created by tarun on 12/10/26.
//

import AppKit
import WebKit

// MARK: - Agent Data Models

/// Dense, token-efficient snapshot of interactive elements on a web page.
struct NomadSnapshot: Codable {
    let title: String
    let url: String
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    var totalElements: Int?
    var filteredTotal: Int?
    var unfilteredTotal: Int?
    var target: String?
    var tracked: [String: Int]?
    let elements: [NomadElement]
    /// Pre-formatted dense semantic tree for LLM prompt ingestion (~300 tokens).
    let summary: String
    var tokenEstimate: Int?
    var warning: String?
    var isClamped: Bool?
    var unclampedTotal: Int?
    var notice: String?
}

/// A single interactive element discovered on the page.
struct NomadElement: Codable {
    let id: String
    let tag: String
    let role: String?
    let text: String
    let value: String?
    let type: String?
    let bounds: NomadBounds
    var className: String?
    var domId: String?
    var rank: String?
    var isObscured: Bool?
    var inViewport: Bool?
    var hasContextMenu: Bool?
    var disabled: Bool?
    var checked: Bool?
    var selected: Bool?
    var focused: Bool?
    var readOnly: Bool?
    var isInShadowRoot: Bool?
    var src: String?
    var alt: String?
    var href: String?
    var isNew: Bool?
    var depth: Int?
}

/// Bounding rectangle in viewport coordinates.
struct NomadBounds: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Action request issued by an AI agent or DevX tool.
struct NomadAction: Codable {
    var action: String = "click" // "click", "hover", "type", "clear", "press", "selectOption", "scroll", "drag", "highlight", "upload", "right_click", "context_menu", "native_click", ...
    var target: String? // e.g. "e1", "e2", or CSS selector fallback
    var selector: String?
    var elementId: String?
    var toTarget: String? // e.g. "e8" or CSS selector destination for drag
    var toElementId: String?
    var toSelector: String?
    var text: String?
    var key: String? // "Enter", "Escape", "Tab", or chords "Meta+A", "Control+Enter"
    var direction: String? // "up", "down", "left", "right"
    var amount: CGFloat?
    var submit: Bool?
    var blur: Bool?
    var change: Bool?
    var clear: Bool?
    var force: Bool?
    var native: Bool?
    var x: CGFloat?
    var y: CGFloat?
    var toX: CGFloat?
    var toY: CGFloat?
    var scrollDeltaY: CGFloat?
    var scrollDeltaX: CGFloat?
    var optionValue: String?
    var optionText: String?
    var modifiers: [String]?
    var paths: [String]?
    var dialogPolicy: String?
    var dialogResponse: String?

    var resolvedPaths: [String] {
        paths ?? []
    }

    init(action: String = "click", target: String? = nil, selector: String? = nil, elementId: String? = nil, toTarget: String? = nil, toElementId: String? = nil, toSelector: String? = nil, text: String? = nil, key: String? = nil, direction: String? = nil, amount: CGFloat? = nil, submit: Bool? = nil, blur: Bool? = nil, change: Bool? = nil, clear: Bool? = nil, force: Bool? = nil, native: Bool? = nil, x: CGFloat? = nil, y: CGFloat? = nil, toX: CGFloat? = nil, toY: CGFloat? = nil, scrollDeltaY: CGFloat? = nil, scrollDeltaX: CGFloat? = nil, optionValue: String? = nil, optionText: String? = nil, modifiers: [String]? = nil, paths: [String]? = nil, dialogPolicy: String? = nil, dialogResponse: String? = nil) {
        self.action = action
        self.target = target ?? elementId ?? selector
        self.selector = selector
        self.elementId = elementId
        self.toTarget = toTarget ?? toElementId ?? toSelector
        self.toElementId = toElementId
        self.toSelector = toSelector
        self.text = text
        self.key = key
        self.direction = direction
        self.amount = amount
        self.submit = submit
        self.blur = blur
        self.change = change
        self.clear = clear
        self.force = force
        self.native = native
        self.x = x
        self.y = y
        self.toX = toX
        self.toY = toY
        self.scrollDeltaY = scrollDeltaY
        self.scrollDeltaX = scrollDeltaX
        self.optionValue = optionValue
        self.optionText = optionText
        self.modifiers = modifiers
        self.paths = paths
        self.dialogPolicy = dialogPolicy
        self.dialogResponse = dialogResponse
    }

    enum CodingKeys: String, CodingKey {
        case action, type, target, elementId, selector, toTarget, toElementId, toSelector, text, key, direction, amount
        case submit, blur, change, clear, force, native, isNative, hardware, x, y, toX, toY
        case scrollDeltaY, deltaY, scrollDeltaX, deltaX, optionValue, optionText, modifiers
        case paths, path, files, file
        case dialogPolicy, policy, dialogAction, dialogResponse, promptResponse
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawAction = (try c.decodeIfPresent(String.self, forKey: .action) ?? c.decodeIfPresent(String.self, forKey: .type))?.trimmingCharacters(in: .whitespacesAndNewlines), !rawAction.isEmpty else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required 'type' or 'action' field in action object"))
        }
        let validActions: Set<String> = [
            "click", "right_click", "rightclick", "context_menu", "contextmenu",
            "hover", "type", "clear", "press", "selectoption", "scroll", "drag", "highlight", "upload",
            "native_click", "native_right_click", "native_context_menu", "native_hover", "native_type", "native_press", "native_drag"
        ]
        guard validActions.contains(rawAction.lowercased()) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown action type '\(rawAction)'"))
        }
        self.action = rawAction
        self.selector = try c.decodeIfPresent(String.self, forKey: .selector)
        self.elementId = try c.decodeIfPresent(String.self, forKey: .elementId)
        self.target = try c.decodeIfPresent(String.self, forKey: .target) ?? self.elementId ?? self.selector
        self.toSelector = try c.decodeIfPresent(String.self, forKey: .toSelector)
        self.toElementId = try c.decodeIfPresent(String.self, forKey: .toElementId)
        self.toTarget = try c.decodeIfPresent(String.self, forKey: .toTarget) ?? self.toElementId ?? self.toSelector
        self.text = try c.decodeIfPresent(String.self, forKey: .text)
        self.key = try c.decodeIfPresent(String.self, forKey: .key)
        self.submit = try c.decodeIfPresent(Bool.self, forKey: .submit)
        self.blur = try c.decodeIfPresent(Bool.self, forKey: .blur)
        self.change = try c.decodeIfPresent(Bool.self, forKey: .change)
        self.clear = try c.decodeIfPresent(Bool.self, forKey: .clear)
        self.force = try c.decodeIfPresent(Bool.self, forKey: .force)
        let decNative = (try? c.decodeIfPresent(Bool.self, forKey: .native))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: .isNative))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: .hardware))
        self.native = (decNative == true) || rawAction.lowercased().hasPrefix("native_")
        self.x = try c.decodeIfPresent(CGFloat.self, forKey: .x)
        self.y = try c.decodeIfPresent(CGFloat.self, forKey: .y)
        self.toX = try c.decodeIfPresent(CGFloat.self, forKey: .toX)
        self.toY = try c.decodeIfPresent(CGFloat.self, forKey: .toY)
        let dy = try c.decodeIfPresent(CGFloat.self, forKey: .scrollDeltaY) ?? c.decodeIfPresent(CGFloat.self, forKey: .deltaY)
        let dx = try c.decodeIfPresent(CGFloat.self, forKey: .scrollDeltaX) ?? c.decodeIfPresent(CGFloat.self, forKey: .deltaX)
        self.scrollDeltaY = dy
        self.scrollDeltaX = dx
        self.amount = dy != nil ? abs(dy!) : (dx != nil ? abs(dx!) : try c.decodeIfPresent(CGFloat.self, forKey: .amount))
        self.direction = dy != nil ? (dy! >= 0 ? "down" : "up") : (dx != nil ? (dx! >= 0 ? "right" : "left") : try c.decodeIfPresent(String.self, forKey: .direction))
        self.optionValue = try c.decodeIfPresent(String.self, forKey: .optionValue)
        self.optionText = try c.decodeIfPresent(String.self, forKey: .optionText)
        self.modifiers = try c.decodeIfPresent([String].self, forKey: .modifiers)

        if let pathsArray = try? c.decodeIfPresent([String].self, forKey: .paths) ?? c.decodeIfPresent([String].self, forKey: .files) {
            var seen = Set<String>()
            let cleaned = pathsArray.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
            self.paths = cleaned.isEmpty ? nil : cleaned
        } else if let single = (try? c.decodeIfPresent(String.self, forKey: .paths) ?? c.decodeIfPresent(String.self, forKey: .path) ?? c.decodeIfPresent(String.self, forKey: .files) ?? c.decodeIfPresent(String.self, forKey: .file))?.trimmingCharacters(in: .whitespacesAndNewlines), !single.isEmpty {
            self.paths = [single]
        } else {
            self.paths = nil
        }

        if let rawPolicy = (try? c.decodeIfPresent(String.self, forKey: .dialogPolicy)) ?? (try? c.decodeIfPresent(String.self, forKey: .policy)) {
            let cleanPolicy = rawPolicy.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard ["accept", "dismiss", "wait"].contains(cleanPolicy) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid dialog policy '\(rawPolicy)'. Expected 'accept', 'dismiss', or 'wait'"))
            }
            self.dialogPolicy = cleanPolicy
        } else {
            self.dialogPolicy = nil
        }
        self.dialogResponse = (try? c.decodeIfPresent(String.self, forKey: .dialogResponse)) ?? (try? c.decodeIfPresent(String.self, forKey: .promptResponse))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(action, forKey: .action)
        try c.encodeIfPresent(target, forKey: .target)
        try c.encodeIfPresent(selector, forKey: .selector)
        try c.encodeIfPresent(elementId, forKey: .elementId)
        try c.encodeIfPresent(toTarget, forKey: .toTarget)
        try c.encodeIfPresent(toElementId, forKey: .toElementId)
        try c.encodeIfPresent(toSelector, forKey: .toSelector)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(direction, forKey: .direction)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(submit, forKey: .submit)
        try c.encodeIfPresent(blur, forKey: .blur)
        try c.encodeIfPresent(change, forKey: .change)
        try c.encodeIfPresent(clear, forKey: .clear)
        try c.encodeIfPresent(force, forKey: .force)
        try c.encodeIfPresent(native, forKey: .native)
        try c.encodeIfPresent(x, forKey: .x)
        try c.encodeIfPresent(y, forKey: .y)
        try c.encodeIfPresent(toX, forKey: .toX)
        try c.encodeIfPresent(toY, forKey: .toY)
        try c.encodeIfPresent(scrollDeltaY, forKey: .scrollDeltaY)
        try c.encodeIfPresent(scrollDeltaX, forKey: .scrollDeltaX)
        try c.encodeIfPresent(optionValue, forKey: .optionValue)
        try c.encodeIfPresent(optionText, forKey: .optionText)
        try c.encodeIfPresent(modifiers, forKey: .modifiers)
        try c.encodeIfPresent(paths, forKey: .paths)
        try c.encodeIfPresent(dialogPolicy, forKey: .dialogPolicy)
        try c.encodeIfPresent(dialogResponse, forKey: .dialogResponse)
    }
}


/// Execution outcome of an action.
struct NomadActionResult: Codable {
    let success: Bool
    var message: String
    var elementId: String? = nil
    var obscured: Bool? = nil
    var interceptedBy: String? = nil
    var healed: Bool? = nil
    var staleRef: Bool? = nil
    var code: String? = nil
    var stack: String? = nil
    var error: String? = nil
    var files: [String]? = nil
    var count: Int? = nil
    var native: Bool? = nil
    var isTrusted: Bool? = nil
    var lastDialog: String? = nil
    var hasPendingDialog: Bool? = nil

    init(success: Bool, message: String, elementId: String? = nil, obscured: Bool? = nil, interceptedBy: String? = nil, healed: Bool? = nil, staleRef: Bool? = nil, code: String? = nil, stack: String? = nil, error: String? = nil, files: [String]? = nil, count: Int? = nil, native: Bool? = nil, isTrusted: Bool? = nil, lastDialog: String? = nil, hasPendingDialog: Bool? = nil) {
        self.success = success
        self.message = message
        self.elementId = elementId
        self.obscured = obscured
        self.interceptedBy = interceptedBy
        self.healed = healed
        self.staleRef = staleRef
        self.code = code
        self.stack = stack
        self.error = error
        self.files = files
        self.count = count
        self.native = native
        self.isTrusted = isTrusted
        self.lastDialog = lastDialog
        self.hasPendingDialog = hasPendingDialog
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(elementId, forKey: .elementId)
        if obscured == true { try container.encode(true, forKey: .obscured) }
        try container.encodeIfPresent(interceptedBy, forKey: .interceptedBy)
        if healed == true { try container.encode(true, forKey: .healed) }
        if staleRef == true { try container.encode(true, forKey: .staleRef) }
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(stack, forKey: .stack)
        if let err = error, err != message {
            try container.encode(err, forKey: .error)
        }
        try container.encodeIfPresent(files, forKey: .files)
        try container.encodeIfPresent(count, forKey: .count)
        if native == true { try container.encode(true, forKey: .native) }
        if isTrusted == true { try container.encode(true, forKey: .isTrusted) }
        try container.encodeIfPresent(lastDialog, forKey: .lastDialog)
        if hasPendingDialog == true { try container.encode(true, forKey: .hasPendingDialog) }
    }
}

// MARK: - In-Page Perception & Action Engine (JavaScript Core)

enum NomadDOMScript {
    /// Injected JavaScript that parses visible interactive elements (including open Shadow DOM and iframes),
    /// performs occlusion hit-testing, formats a dense LLM-friendly semantic summary (~300 tokens),
    /// and executes reliable native-like actions (React 16+ prototype setters, hover, clear, key chords).
    public static var core: String {
        ScriptLoader.load(named: "nomad-dom-core")
    }
}

// MARK: - Native Tab Agent Extensions

extension Tab {
    /// Injects NomadDOMScript only if window.__nomad is not already initialized.
    @MainActor
    func ensureNomadScriptInjected() async {
        let isLoaded = (try? await webView.evaluateJavaScript("Boolean(window.__nomad)")) as? Bool ?? false
        if !isLoaded {
            _ = try? await webView.evaluateJavaScript(NomadDOMScript.core)
        }
    }

    /// Waits for in-flight web view navigation to settle up to a given timeout.
    @MainActor
    func waitForNavigationSettled(timeout: TimeInterval = 0.5, pollIntervalMs: UInt64 = 30) async {
        guard webView.isLoading else { return }
        let deadline = Date().addingTimeInterval(timeout)
        while webView.isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: pollIntervalMs * 1_000_000)
        }
    }

    /// Extracts a dense, token-efficient semantic tree and element index from the active page.
    @MainActor
    func getSemanticTree(
        limit: Int = 100,
        offset: Int = 0,
        viewportOnly: Bool = false,
        includeText: Bool = true,
        role: String? = nil,
        text: String? = nil,
        target: String? = nil,
        depth: Int? = nil,
        track: Bool = false
    ) async throws -> NomadSnapshot {
        await waitForNavigationSettled(timeout: 0.6)
        await ensureNomadScriptInjected()

        // Ensure DOM readiness: wait briefly if document or document.body is still loading
        let readyScript = "Boolean(document && document.body && document.readyState !== 'loading')"
        let isReady = (try? await webView.evaluateJavaScript(readyScript)) as? Bool ?? false
        if !isReady {
            let start = Date()
            while Date().timeIntervalSince(start) < 0.4 {
                try? await Task.sleep(nanoseconds: 30_000_000)
                let readyNow = (try? await webView.evaluateJavaScript(readyScript)) as? Bool ?? false
                if readyNow { break }
            }
            await ensureNomadScriptInjected()
        }

        // Actively synchronize sub-frames before taking semantic snapshot
        let syncScript = """
        if (window.__nomad && window.__nomad.syncSubframes) {
            return await window.__nomad.syncSubframes(250);
        }
        return { count: 0 };
        """
        await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(syncScript, arguments: [:], in: nil, in: .page) { _ in
                continuation.resume()
            }
        }

        var opts: [String: Any] = ["limit": limit, "offset": offset, "viewportOnly": viewportOnly, "includeText": includeText]
        if let r = role, !r.isEmpty { opts["role"] = r }
        if let txt = text, !txt.isEmpty { opts["text"] = txt }
        if let tgt = target, !tgt.isEmpty { opts["target"] = tgt }
        if let d = depth { opts["depth"] = d }
        if track { opts["track"] = true }
        let optsData = (try? JSONSerialization.data(withJSONObject: opts)) ?? Data()
        let optsJSON = String(data: optsData, encoding: .utf8) ?? "{}"
        let jsonString = try await webView.evaluateJavaScript("JSON.stringify(window.__nomad.getSemanticTree(\(optsJSON)))") as? String ?? "{}"
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "NomadAgent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse snapshot JSON"])
        }
        var snapshot = try JSONDecoder().decode(NomadSnapshot.self, from: data)

        // Self-healing retry: if snapshot returned 0 elements immediately following a navigation,
        // retry once after 60ms to catch DOM construction if HTML parsing just completed.
        if snapshot.elements.isEmpty && (self.url?.absoluteString != "about:blank") && role == nil && text == nil {
            try? await Task.sleep(nanoseconds: 60_000_000)
            await ensureNomadScriptInjected()
            if let retryJSON = try? await webView.evaluateJavaScript("JSON.stringify(window.__nomad.getSemanticTree(\(optsJSON)))") as? String,
               let retryData = retryJSON.data(using: .utf8),
               let retrySnapshot = try? JSONDecoder().decode(NomadSnapshot.self, from: retryData),
               !retrySnapshot.elements.isEmpty {
                snapshot = retrySnapshot
            }
        }

        return snapshot
    }

    /// Dispatches a browser action (click, hover, type, clear, scroll, keypress, select, highlight) on the active page.
    @MainActor
    func performAction(_ action: NomadAction) async throws -> NomadActionResult {
        self.lastActionTime = Date()
        if let dp = action.dialogPolicy {
            self.dialogPolicy = dp
        }
        if let dr = action.dialogResponse {
            self.dialogPromptResponse = dr
        }
        await waitForNavigationSettled(timeout: 0.4)
        if webView.isLoading {
            return NomadActionResult(success: false, message: "Cannot execute action '\(action.action)': active page is currently navigating. Wait for navigation to complete before dispatching actions.", elementId: action.target, lastDialog: self.lastDialog, hasPendingDialog: self.pendingDialog != nil)
        }

        // If a pending dialog is already awaiting response, do not dispatch further actions
        if let pending = self.pendingDialog {
            return NomadActionResult(
                success: false,
                message: "A JavaScript dialog [\(pending.type.rawValue): \"\(pending.message)\"] is currently waiting for resolution. Resolve it via /dialog before dispatching actions.",
                elementId: action.target,
                code: "PENDING_DIALOG",
                lastDialog: self.lastDialog,
                hasPendingDialog: true
            )
        }

        // Native AppKit & CoreGraphics hardware input dispatch (isTrusted: true)
        // Note: 'hover' requires native cursor positioning and mouse moved event to activate CSS :hover pseudo-class
        let isNative = (action.native == true) || action.action.lowercased().hasPrefix("native_") || action.action.lowercased() == "hover"
        if isNative {
            var nativeRes = try await performNativeAction(action)
            nativeRes.lastDialog = self.lastDialog
            if self.pendingDialog != nil {
                nativeRes.hasPendingDialog = true
            }
            return nativeRes
        }

        // Programmatic file upload staging & validation
        if action.action.lowercased() == "upload" {
            let paths = action.resolvedPaths
            guard !paths.isEmpty else {
                return NomadActionResult(success: false, message: "Missing required 'paths' or 'files' for upload action", elementId: action.target, code: "MISSING_PATHS", lastDialog: self.lastDialog, hasPendingDialog: self.pendingDialog != nil)
            }
            var validatedURLs: [URL] = []
            for path in paths {
                let expanded = (path as NSString).expandingTildeInPath
                if NomadAgentServer.isSensitivePath(expanded) {
                    return NomadActionResult(success: false, message: "Access to sensitive file or directory is blocked by Nomad security policy: \(path)", elementId: action.target, code: "ACCESS_DENIED", lastDialog: self.lastDialog, hasPendingDialog: self.pendingDialog != nil)
                }
                guard FileManager.default.fileExists(atPath: expanded) else {
                    return NomadActionResult(success: false, message: "File not found at path: \(path)", elementId: action.target, code: "FILE_NOT_FOUND", lastDialog: self.lastDialog, hasPendingDialog: self.pendingDialog != nil)
                }
                guard FileManager.default.isReadableFile(atPath: expanded) else {
                    return NomadActionResult(success: false, message: "File is not readable at path: \(path)", elementId: action.target, code: "FILE_NOT_READABLE", lastDialog: self.lastDialog, hasPendingDialog: self.pendingDialog != nil)
                }
                validatedURLs.append(URL(fileURLWithPath: expanded))
            }
            self.stageUpload(urls: validatedURLs)
        }

        await ensureNomadScriptInjected()
        let actionData = try JSONEncoder().encode(action)
        guard let actionJSON = String(data: actionData, encoding: .utf8) else {
            throw NSError(domain: "NomadAgent", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode action JSON"])
        }

        return await withCheckedContinuation { continuation in
            var resumed = false
            let lock = NSLock()

            let safeResume: (NomadActionResult) -> Void = { res in
                lock.lock()
                defer { lock.unlock() }
                if !resumed {
                    resumed = true
                    self.onDialogAppeared = nil
                    continuation.resume(returning: res)
                }
            }

            // If dialogPolicy is "wait" and a dialog appears while executing the action,
            // immediately unblock the HTTP client so it can inspect and respond via /dialog!
            self.onDialogAppeared = { [weak self] pending in
                guard let self = self else { return }
                let dialogResult = NomadActionResult(
                    success: true,
                    message: "Action triggered a JavaScript dialog: [\(pending.type.rawValue)] \"\(pending.message)\". Awaiting response via /dialog.",
                    elementId: action.target,
                    code: "PENDING_DIALOG",
                    lastDialog: self.lastDialog,
                    hasPendingDialog: true
                )
                safeResume(dialogResult)
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    let resultString = try await self.webView.evaluateJavaScript("JSON.stringify(window.__nomad.performAction(\(actionJSON)))") as? String ?? "{}"
                    guard let resultData = resultString.data(using: .utf8) else {
                        safeResume(NomadActionResult(success: false, message: "Failed to parse action result JSON", elementId: action.target, code: "ACTION_PARSE_ERROR", lastDialog: self.lastDialog, hasPendingDialog: self.pendingDialog != nil))
                        return
                    }
                    var res = try JSONDecoder().decode(NomadActionResult.self, from: resultData)
                    if action.action.lowercased() == "upload" {
                        if res.success {
                            res.files = action.resolvedPaths
                            res.count = action.resolvedPaths.count
                            res.message = "Successfully uploaded \(res.count ?? 1) file(s) to \(action.target ?? "element")"
                        } else {
                            self.clearStagedUpload()
                        }
                    }
                    if res.success {
                        NomadRouteCache.shared.record(eventType: "action", message: "Action '\(action.action)' succeeded on \(action.target ?? "element")", tabId: self.id.uuidString)
                        if let domain = self.url?.host, let target = action.target, !target.isEmpty {
                            NomadRouteCache.shared.recordSuccess(domain: domain, intent: action.action, selector: target, action: action.action)
                        }
                    } else {
                        NomadRouteCache.shared.record(eventType: "actionError", message: "Action '\(action.action)' failed on \(action.target ?? "element"): \(res.message)", tabId: self.id.uuidString)
                    }
                    res.lastDialog = self.lastDialog
                    if self.pendingDialog != nil {
                        res.hasPendingDialog = true
                    }
                    safeResume(res)
                } catch let decodeErr as DecodingError {
                    if action.action.lowercased() == "upload" { self.clearStagedUpload() }
                    safeResume(NomadActionResult(success: false, message: "Failed to decode action result: \(decodeErr.localizedDescription)", elementId: action.target, code: "ACTION_DECODE_ERROR", lastDialog: self.lastDialog, hasPendingDialog: self.pendingDialog != nil))
                } catch {
                    if action.action.lowercased() == "upload" { self.clearStagedUpload() }
                    safeResume(NomadActionResult(
                        success: false,
                        message: "JavaScript evaluation failed: \(error.localizedDescription)",
                        elementId: action.target,
                        code: "ACTION_EVALUATION_ERROR",
                        error: error.localizedDescription,
                        lastDialog: self.lastDialog,
                        hasPendingDialog: self.pendingDialog != nil
                    ))
                }
            }
        }
    }

    /// Waits for DOM mutation quiescence (stability) on the active page.
    @MainActor
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

        await ensureNomadScriptInjected()
        let script = """
        return await (async () => {
            if (!window.__nomad || !window.__nomad.waitForStability) {
                return { success: false, reason: "not_ready", message: "Nomad agent perception script not initialized" };
            }
            return await window.__nomad.waitForStability(quietMs, timeoutMs);
        })();
        """
        return try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.webView.callAsyncJavaScript(script, arguments: ["quietMs": quietMs, "timeoutMs": remainingTimeoutMs], in: nil, in: .page) { result in
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
    @MainActor
    func performNativeAction(_ action: NomadAction) async throws -> NomadActionResult {
        if let dp = action.dialogPolicy {
            self.dialogPolicy = dp
        }
        if let dr = action.dialogResponse {
            self.dialogPromptResponse = dr
        }
        await ensureNomadScriptInjected()

        // 1. Resolve target coordinates and element properties in web view viewport space
        var targetPoint: CGPoint? = nil
        var isTargetEditable = false
        var targetTagName = ""
        let hasTarget = action.target.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false

        if let target = action.target, hasTarget {
            let escaped = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "JSON.stringify(window.__nomad.getElementViewportRect(\"\(escaped)\"))"
            if let rectStr = try? await webView.evaluateJavaScript(script) as? String,
               let rectData = rectStr.data(using: .utf8),
               let rect = try? JSONSerialization.jsonObject(with: rectData) as? [String: Any],
               let x = (rect["left"] as? NSNumber)?.doubleValue,
               let y = (rect["top"] as? NSNumber)?.doubleValue,
               let w = (rect["width"] as? NSNumber)?.doubleValue,
               let h = (rect["height"] as? NSNumber)?.doubleValue,
               (w > 0 || h > 0) {
                targetPoint = CGPoint(x: x + w / 2.0, y: y + h / 2.0)
                isTargetEditable = rect["isEditable"] as? Bool ?? false
                targetTagName = (rect["tagName"] as? String ?? "").lowercased()
            } else {
                let isRef = (target.range(of: "^(f[0-9]+:)?[e][0-9]+$", options: .regularExpression) != nil)
                let isExplicitSelector = (action.selector != nil)
                let code = isRef ? "STALE_REF" : (isExplicitSelector ? "SELECTOR_NOT_FOUND" : "ELEMENT_NOT_FOUND")
                let message: String
                if isRef {
                    message = "Target element '\(target)' not found. Please re-snapshot."
                } else if isExplicitSelector {
                    message = "Target element matching selector '\(target)' not found in DOM."
                } else {
                    message = "Target element '\(target)' not found or has zero geometry in viewport."
                }
                return NomadActionResult(
                    success: false,
                    message: message,
                    elementId: target,
                    code: code
                )
            }
        }

        if let ax = action.x, let ay = action.y {
            targetPoint = CGPoint(x: ax, y: ay)
        }

        let rawType = action.action.lowercased().replacingOccurrences(of: "native_", with: "")

        // 2. Bring window and web view to front for active hardware input (GUI mode only)
        if !NomadHeadlessManager.isHeadless {
            NSApp.activate(ignoringOtherApps: true)
            if let win = webView.window {
                if !win.isKeyWindow {
                    win.makeKeyAndOrderFront(nil)
                }
                if win.firstResponder != webView {
                    win.makeFirstResponder(webView)
                }
            }
        } else {
            // Headless mode: Never activate application or order window front.
            // Ensure webView is first responder in its own offscreen window hierarchy.
            if let win = webView.window, win.firstResponder != webView {
                win.makeFirstResponder(webView)
            }
        }

        let windowNumber = webView.window?.windowNumber ?? 0

        switch rawType {
        case "click":
            guard let pt = targetPoint else {
                return NomadActionResult(success: false, message: "Missing target element or (x, y) coordinates for native click", elementId: action.target, code: "MISSING_TARGET")
            }
            let winPoint = webView.convert(pt, to: nil)
            let screenPoint = webView.window?.convertPoint(toScreen: winPoint) ?? winPoint
            let primaryScreenH = NSScreen.screens.first?.frame.height ?? 1080
            let cgPos = CGPoint(x: screenPoint.x, y: primaryScreenH - screenPoint.y)

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

            // Low-level CoreGraphics HID injection for hardware queues (GUI mode only)
            if !NomadHeadlessManager.isHeadless {
                if let cgDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cgPos, mouseButton: .left) {
                    cgDown.postToPid(ProcessInfo.processInfo.processIdentifier)
                }
            }
            if let down = downEvent { webView.mouseDown(with: down) }
            try? await Task.sleep(nanoseconds: 35_000_000)

            if !NomadHeadlessManager.isHeadless {
                if let cgUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cgPos, mouseButton: .left) {
                    cgUp.postToPid(ProcessInfo.processInfo.processIdentifier)
                }
            }
            if let up = upEvent { webView.mouseUp(with: up) }
            try? await Task.sleep(nanoseconds: 30_000_000)

            return NomadActionResult(
                success: true,
                message: "Native click dispatched at (\(Int(pt.x)), \(Int(pt.y))) with isTrusted: true",
                elementId: action.target,
                code: "SUCCESS",
                native: true,
                isTrusted: true,
                lastDialog: self.lastDialog,
                hasPendingDialog: self.pendingDialog != nil
            )

        case "right_click", "rightclick", "context_menu", "contextmenu":
            guard let pt = targetPoint else {
                return NomadActionResult(success: false, message: "Missing target element or (x, y) coordinates for native right click", elementId: action.target, code: "MISSING_TARGET")
            }
            let winPoint = webView.convert(pt, to: nil)
            let screenPoint = webView.window?.convertPoint(toScreen: winPoint) ?? winPoint
            let primaryScreenH = NSScreen.screens.first?.frame.height ?? 1080
            let cgPos = CGPoint(x: screenPoint.x, y: primaryScreenH - screenPoint.y)

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

            if !NomadHeadlessManager.isHeadless {
                if let cgDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: cgPos, mouseButton: .right) {
                    cgDown.postToPid(ProcessInfo.processInfo.processIdentifier)
                }
            }
            if let down = downEvent { webView.rightMouseDown(with: down) }
            try? await Task.sleep(nanoseconds: 35_000_000)

            if !NomadHeadlessManager.isHeadless {
                if let cgUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: cgPos, mouseButton: .right) {
                    cgUp.postToPid(ProcessInfo.processInfo.processIdentifier)
                }
            }
            if let up = upEvent { webView.rightMouseUp(with: up) }
            try? await Task.sleep(nanoseconds: 30_000_000)

            return NomadActionResult(
                success: true,
                message: "Native context menu (right click) dispatched at (\(Int(pt.x)), \(Int(pt.y))) with isTrusted: true",
                elementId: action.target,
                code: "SUCCESS",
                native: true,
                isTrusted: true,
                lastDialog: self.lastDialog,
                hasPendingDialog: self.pendingDialog != nil
            )

        case "hover":
            guard let pt = targetPoint else {
                return NomadActionResult(success: false, message: "Missing target element or (x, y) coordinates for hover", elementId: action.target, code: "MISSING_TARGET", lastDialog: self.lastDialog, hasPendingDialog: self.pendingDialog != nil)
            }
            let winPoint = webView.convert(pt, to: nil)
            let screenPoint = webView.window?.convertPoint(toScreen: winPoint) ?? winPoint
            let primaryScreenH = NSScreen.screens.first?.frame.height ?? 1080
            let cgPos = CGPoint(x: screenPoint.x, y: primaryScreenH - screenPoint.y)

            if let win = webView.window {
                win.acceptsMouseMovedEvents = true
            }

            // 1. Move hardware system cursor to target location (GUI mode only)
            if !NomadHeadlessManager.isHeadless {
                CGWarpMouseCursorPosition(cgPos)

                // 2. Post CoreGraphics mouseMoved event to application event stream
                if let cgMove = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPos, mouseButton: .center) {
                    cgMove.postToPid(ProcessInfo.processInfo.processIdentifier)
                }
            }

            // 3. Dispatch AppKit NSEvent directly to WKContentView and NSWindow
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
            }

            // 4. Also dispatch synthetic pointer & mouse events to target or element at point in JS
            let escapedTarget = (action.target ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let jsDispatch = """
            (function() {
                try {
                    var el = null;
                    if ("\(escapedTarget)") {
                        el = (window.__nomad && window.__nomad.elements && window.__nomad.elements["\(escapedTarget)"]) || (window.__nomad && window.__nomad.findInTree && window.__nomad.findInTree(document, "\(escapedTarget)")) || document.querySelector("[data-nomad-id='\(escapedTarget)']") || document.querySelector("\(escapedTarget)");
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
                        var evOpts = { bubbles: true, cancelable: true, view: elWin, clientX: cx, clientY: cy, screenX: \(Int(screenPoint.x)), screenY: \(Int(screenPoint.y)) };
                        var enterOpts = { bubbles: false, cancelable: false, view: elWin, clientX: cx, clientY: cy, screenX: \(Int(screenPoint.x)), screenY: \(Int(screenPoint.y)) };
                        el.dispatchEvent(new elWin.PointerEvent('pointerover', evOpts));
                        el.dispatchEvent(new elWin.PointerEvent('pointerenter', enterOpts));
                        el.dispatchEvent(new elWin.MouseEvent('mouseover', evOpts));
                        el.dispatchEvent(new elWin.MouseEvent('mouseenter', enterOpts));
                        el.dispatchEvent(new elWin.MouseEvent('mousemove', evOpts));
                    }
                } catch(e) {}
            })()
            """
            _ = try? await webView.evaluateJavaScript(jsDispatch)

            try? await Task.sleep(nanoseconds: 30_000_000)

            return NomadActionResult(
                success: true,
                message: "Hover dispatched at (\(Int(pt.x)), \(Int(pt.y))) with isTrusted: true",
                elementId: action.target,
                code: "SUCCESS",
                native: true,
                isTrusted: true,
                lastDialog: self.lastDialog,
                hasPendingDialog: self.pendingDialog != nil
            )

        case "drag":
            guard let fromPt = targetPoint else {
                return NomadActionResult(success: false, message: "No target element or coordinates specified for drag action", elementId: action.target, code: "MISSING_TARGET")
            }
            var destPoint: CGPoint? = nil
            if let tx = action.toX, let ty = action.toY {
                destPoint = CGPoint(x: tx, y: ty)
            } else if let toTarget = (action.toTarget ?? action.toElementId ?? action.toSelector)?.trimmingCharacters(in: .whitespacesAndNewlines), !toTarget.isEmpty {
                let escaped = toTarget.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let script = "JSON.stringify(window.__nomad.getElementViewportRect(\"\(escaped)\"))"
                if let rectStr = try? await webView.evaluateJavaScript(script) as? String,
                   let rectData = rectStr.data(using: .utf8),
                   let rect = try? JSONSerialization.jsonObject(with: rectData) as? [String: Any],
                   let x = (rect["left"] as? NSNumber)?.doubleValue,
                   let y = (rect["top"] as? NSNumber)?.doubleValue,
                   let w = (rect["width"] as? NSNumber)?.doubleValue,
                   let h = (rect["height"] as? NSNumber)?.doubleValue,
                   (w > 0 || h > 0) {
                    destPoint = CGPoint(x: x + w / 2.0, y: y + h / 2.0)
                } else {
                    return NomadActionResult(success: false, message: "Cannot execute native drag: destination element '\(toTarget)' not found or has zero geometry in viewport.", elementId: toTarget, code: "DESTINATION_NOT_FOUND")
                }
            }
            guard let toPt = destPoint else {
                return NomadActionResult(success: false, message: "Missing destination coordinates (toX, toY) or destination element (toElementId/toTarget) for native drag", elementId: action.target, code: "MISSING_DESTINATION")
            }
            let fromWin = webView.convert(fromPt, to: nil)
            let toWin = webView.convert(toPt, to: nil)
            let screenFromPoint = webView.window?.convertPoint(toScreen: fromWin) ?? fromWin
            let screenToPoint = webView.window?.convertPoint(toScreen: toWin) ?? toWin
            let primaryScreenH = NSScreen.screens.first?.frame.height ?? 1080
            let cgFromPos = CGPoint(x: screenFromPoint.x, y: primaryScreenH - screenFromPoint.y)
            let cgToPos = CGPoint(x: screenToPoint.x, y: primaryScreenH - screenToPoint.y)

            // 1. Native mouse down (CoreGraphics & AppKit)
            if !NomadHeadlessManager.isHeadless {
                if let cgDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cgFromPos, mouseButton: .left) {
                    cgDown.postToPid(ProcessInfo.processInfo.processIdentifier)
                }
            }
            if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: fromWin, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
                webView.mouseDown(with: down)
            }
            let steps = 5
            for i in 1...steps {
                let factor = CGFloat(i) / CGFloat(steps)
                let intermediate = CGPoint(x: fromPt.x + (toPt.x - fromPt.x) * factor, y: fromPt.y + (toPt.y - fromPt.y) * factor)
                let intermediateWin = webView.convert(intermediate, to: nil)
                let intermediateScreen = webView.window?.convertPoint(toScreen: intermediateWin) ?? intermediateWin
                let cgIntermediatePos = CGPoint(x: intermediateScreen.x, y: primaryScreenH - intermediateScreen.y)

                if !NomadHeadlessManager.isHeadless {
                    if let cgDrag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: cgIntermediatePos, mouseButton: .left) {
                        cgDrag.postToPid(ProcessInfo.processInfo.processIdentifier)
                    }
                }
                if let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: intermediateWin, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
                    webView.mouseDragged(with: drag)
                }
                try? await Task.sleep(nanoseconds: 15_000_000)
            }

            // 2. Dispatch HTML5 Drag & Drop pipeline (dragstart -> dragenter -> dragover -> drop -> dragend)
            let escapedTarget = (action.target ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedToTarget = (action.toTarget ?? action.toElementId ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let dragScript = "JSON.stringify(window.__nomad.dispatchHtml5Drag(\"\(escapedTarget)\", \(fromPt.x), \(fromPt.y), \(toPt.x), \(toPt.y), null, \"\(escapedToTarget)\"))"
            _ = try? await webView.evaluateJavaScript(dragScript)

            // 3. Native mouse up (CoreGraphics & AppKit)
            if let cgUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cgToPos, mouseButton: .left) {
                cgUp.postToPid(ProcessInfo.processInfo.processIdentifier)
            }
            if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: toWin, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0) {
                webView.mouseUp(with: up)
            }
            let destDesc = (action.toTarget ?? action.toElementId) != nil ? "'\(action.toTarget ?? action.toElementId!)' (\(Int(toPt.x)), \(Int(toPt.y)))" : "(\(Int(toPt.x)), \(Int(toPt.y)))"
            return NomadActionResult(success: true, message: "Native drag executed from '\(action.target ?? "element")' (\(Int(fromPt.x)), \(Int(fromPt.y))) to \(destDesc) with isTrusted: true", elementId: action.target, code: "SUCCESS", native: true, isTrusted: true)

        case "type":
            guard let text = action.text else {
                return NomadActionResult(success: false, message: "Missing 'text' for native type action", elementId: action.target, code: "MISSING_TEXT")
            }
            guard hasTarget, let target = action.target else {
                return NomadActionResult(
                    success: false,
                    message: "Missing target element for native type action",
                    elementId: action.target,
                    code: "MISSING_TARGET"
                )
            }
            if !isTargetEditable {
                let tag = targetTagName.isEmpty ? "element" : targetTagName
                return NomadActionResult(
                    success: false,
                    message: "Target element <\(tag)> is not editable or an input control",
                    elementId: target,
                    code: "NOT_EDITABLE"
                )
            }

            // Establish DOM focus on the target element and fail loudly if focus cannot be set
            let escapedTarget = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let focusScript = "JSON.stringify(window.__nomad.focusElement(\"\(escapedTarget)\"))"
            if let focusStr = try? await webView.evaluateJavaScript(focusScript) as? String,
               let focusData = focusStr.data(using: .utf8),
               let focusRes = try? JSONSerialization.jsonObject(with: focusData) as? [String: Any] {
                let focused = focusRes["success"] as? Bool ?? false
                if !focused {
                    let msg = focusRes["message"] as? String ?? "Failed to establish focus on target element '\(target)'"
                    return NomadActionResult(
                        success: false,
                        message: msg,
                        elementId: target,
                        code: "FOCUS_FAILED"
                    )
                }
            }

            // Click target with native CoreGraphics and AppKit events to ensure full window & gesture activation
            if let pt = targetPoint {
                let winPoint = webView.convert(pt, to: nil)
                let screenPoint = webView.window?.convertPoint(toScreen: winPoint) ?? winPoint
                let primaryScreenH = NSScreen.screens.first?.frame.height ?? 1080
                let cgPos = CGPoint(x: screenPoint.x, y: primaryScreenH - screenPoint.y)

                if !NomadHeadlessManager.isHeadless {
                    if let cgDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cgPos, mouseButton: .left) {
                        cgDown.postToPid(ProcessInfo.processInfo.processIdentifier)
                    }
                }
                if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: winPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
                    webView.mouseDown(with: down)
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
                if !NomadHeadlessManager.isHeadless {
                    if let cgUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cgPos, mouseButton: .left) {
                        cgUp.postToPid(ProcessInfo.processInfo.processIdentifier)
                    }
                }
                if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: winPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0) {
                    webView.mouseUp(with: up)
                }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            for char in text {
                let charStr = String(char)
                let keyCode = Self.keyCodeForCharacter(char)
                if let downKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: charStr, charactersIgnoringModifiers: charStr, isARepeat: false, keyCode: keyCode) {
                    webView.keyDown(with: downKey)
                }
                try? await Task.sleep(nanoseconds: 12_000_000)
                if let upKey = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: charStr, charactersIgnoringModifiers: charStr, isARepeat: false, keyCode: keyCode) {
                    webView.keyUp(with: upKey)
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
            return NomadActionResult(success: true, message: "Native typing executed (\(text.count) chars) with isTrusted: true", elementId: action.target, code: "SUCCESS", native: true, isTrusted: true)

        case "press":
            let rawChord = (action.key ?? action.text ?? "Enter").trimmingCharacters(in: .whitespacesAndNewlines)
            let (keyCode, charStr, modFlags) = Self.parseKeyChord(rawChord, explicitModifiers: action.modifiers)

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
            return NomadActionResult(success: true, message: "Native keypress '\(rawChord)' dispatched with isTrusted: true", elementId: action.target, code: "SUCCESS", native: true, isTrusted: true)

        default:
            return NomadActionResult(success: false, message: "Native mode not supported for action type '\(action.action)'", elementId: action.target, code: "UNSUPPORTED_NATIVE_ACTION")
        }
    }

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

    /// Captures a crisp screenshot directly from WebKit's in-memory compositing buffer (GPU RAM).
    /// If `labeled` is true, temporary visual index badges are overlaid to ground Vision LLMs.
    /// If `elementId` or `clip` is provided, captures only the cropped element/region.
    @MainActor
    func captureScreenshot(labeled: Bool = false, elementId: String? = nil, clip: CGRect? = nil) async throws -> NSImage {
        await ensureNomadScriptInjected()

        if labeled || (elementId != nil && elementId?.contains("f") == true) {
            let syncScript = """
            if (window.__nomad && window.__nomad.syncSubframes) {
                return await window.__nomad.syncSubframes(250);
            }
            return { count: 0 };
            """
            await withCheckedContinuation { continuation in
                webView.callAsyncJavaScript(syncScript, arguments: [:], in: nil, in: .page) { _ in
                    continuation.resume()
                }
            }
        }

        // Flush layout and apply sensitive input blurring (plus visual badges if labeled == true)
        let prepScript = """
        (function() {
            try {
                if (window.__nomad) {
                    window.__nomad.blurSensitiveInputs();
                    if (\(labeled ? "true" : "false")) {
                        window.__nomad.getSemanticTree();
                        window.__nomad.showBadges();
                    }
                }
                if (document.body) { void document.body.offsetHeight; }
                return true;
            } catch(e) {
                return false;
            }
        })()
        """
        _ = try? await webView.evaluateJavaScript(prepScript)

        var targetRect: CGRect? = clip
        if targetRect == nil, let elId = elementId {
            let safeElIdData = (try? JSONSerialization.data(withJSONObject: [elId])) ?? Data("[\"\"]".utf8)
            let safeElIdArray = String(data: safeElIdData, encoding: .utf8) ?? "[\"\"]"
            let rectScript = """
            (function() {
                var targetId = (\(safeElIdArray))[0];
                if (!targetId || typeof targetId !== 'string') return null;

                function resolveRect(tid) {
                    // 1. Direct query via getElementViewportRect (handles frame IDs like 'f1:e2', selectors, and DOM IDs)
                    if (window.__nomad && window.__nomad.getElementViewportRect) {
                        try {
                            var r = window.__nomad.getElementViewportRect(tid);
                            if (r && (r.width > 0 || r.height > 0)) {
                                var rx = r.left !== undefined ? r.left : (r.x !== undefined ? r.x : 0);
                                var ry = r.top !== undefined ? r.top : (r.y !== undefined ? r.y : 0);
                                return { x: rx, y: ry, width: r.width, height: r.height };
                            }
                        } catch(e) {}
                    }

                    // 2. Direct lookup in semantic tree bounds cache
                    var cache = (window.__nomad && window.__nomad.elementsBounds) || window.__nomad_elements_bounds;
                    if (cache && cache[tid]) {
                        var b = cache[tid];
                        if (b && (b.width > 0 || b.height > 0)) {
                            var bx = b.left !== undefined ? b.left : (b.x !== undefined ? b.x : 0);
                            var by = b.top !== undefined ? b.top : (b.y !== undefined ? b.y : 0);
                            return { x: bx, y: by, width: b.width, height: b.height };
                        }
                    }

                    // 3. Fallback: resolve DOM element directly in top document or open shadow tree
                    var el = window.__nomad && window.__nomad.elements && window.__nomad.elements[tid];
                    if (!el && window.__nomad && window.__nomad.findInTree) {
                        el = window.__nomad.findInTree(document, tid);
                    }
                    if (!el) {
                        try { el = document.querySelector('[data-nomad-id="' + CSS.escape(tid) + '"]'); } catch(e) {}
                    }
                    if (!el) {
                        try { el = document.querySelector(tid); } catch(e) {}
                    }
                    if (el) {
                        var er = (window.__nomad && window.__nomad.getElementViewportRect) ? window.__nomad.getElementViewportRect(el) : el.getBoundingClientRect();
                        if (er && (er.width > 0 || er.height > 0)) {
                            var erx = er.left !== undefined ? er.left : (er.x !== undefined ? er.x : 0);
                            var ery = er.top !== undefined ? er.top : (er.y !== undefined ? er.y : 0);
                            return { x: erx, y: ery, width: er.width, height: er.height };
                        }
                    }

                    return null;
                }

                var res = resolveRect(targetId);
                if (!res && window.__nomad && window.__nomad.getSemanticTree) {
                    try {
                        window.__nomad.getSemanticTree();
                        res = resolveRect(targetId);
                    } catch(e) {}
                }
                return res;
            })()
            """
            if let dict = (try? await webView.evaluateJavaScript(rectScript)) as? [String: Any],
               let x = (dict["x"] as? NSNumber)?.doubleValue,
               let y = (dict["y"] as? NSNumber)?.doubleValue,
               let w = (dict["width"] as? NSNumber)?.doubleValue,
               let h = (dict["height"] as? NSNumber)?.doubleValue,
               w > 0 && h > 0 {
                targetRect = CGRect(x: x, y: y, width: w, height: h)
            } else {
                _ = try? await webView.evaluateJavaScript("window.__nomad && window.__nomad.hideBadges && window.__nomad.hideBadges();")
                throw NSError(domain: "NomadAgent", code: -5, userInfo: [NSLocalizedDescriptionKey: "Element '\(elId)' not found or has zero dimensions for screenshot crop"])
            }
        }

        let config = WKSnapshotConfiguration()
        if let rect = targetRect {
            config.rect = rect
        } else {
            let viewWidth = self.webView.frame.width > 0 ? self.webView.frame.width : 1280
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
                        continuation.resume(throwing: NSError(domain: "NomadAgent", code: -4, userInfo: [NSLocalizedDescriptionKey: "Snapshot returned nil"]))
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
                    _ = try? await webView.evaluateJavaScript("window.__nomad && window.__nomad.hideBadges && window.__nomad.hideBadges();")
                    return fallbackImg
                }
            }

            _ = try? await webView.evaluateJavaScript("window.__nomad && window.__nomad.hideBadges && window.__nomad.hideBadges();")
            return image
        } catch {
            // If takeSnapshot failed due to display session absence, fall back to createPDF
            let pdfConfig = WKPDFConfiguration()
            if let rect = targetRect {
                pdfConfig.rect = rect
            }
            if let pdfData = try? await self.generatePDF(configuration: pdfConfig),
               let fallbackImg = self.renderPDFToImage(pdfData: pdfData) {
                _ = try? await webView.evaluateJavaScript("window.__nomad && window.__nomad.hideBadges && window.__nomad.hideBadges();")
                return fallbackImg
            }

            _ = try? await webView.evaluateJavaScript("window.__nomad && window.__nomad.hideBadges && window.__nomad.hideBadges();")
            throw error
        }
    }

    private func generatePDF(configuration: WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.webView.createPDF(configuration: configuration) { result in
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

// MARK: - NSImage Image Helper

extension NSImage {
    /// Encodes NSImage to standard PNG data.
    var pngData: Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

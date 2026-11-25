//
//  DinoAgentBridge.swift
//  dino
//
//  Created by tarun on 12/10/26.
//

import AppKit
import WebKit

// MARK: - Agent Data Models

/// Dense, token-efficient snapshot of interactive elements on a web page.
struct DinoSnapshot: Codable {
    let title: String
    let url: String
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    var totalElements: Int?
    var filteredTotal: Int?
    var unfilteredTotal: Int?
    var target: String?
    var tracked: [String: Int]?
    let elements: [DinoElement]
    /// Pre-formatted dense semantic tree for LLM prompt ingestion (~300 tokens).
    var summary: String?
    var tokenEstimate: Int?
    var warning: String?
    var isClamped: Bool?
    var unclampedTotal: Int?
    var notice: String?
}

/// A single interactive element discovered on the page.
struct DinoElement: Codable {
    let id: String
    let tag: String
    let role: String?
    let text: String
    let value: String?
    let type: String?
    let bounds: DinoBounds
    var box: [Int]?
    var norm: [Int]?
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
struct DinoBounds: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Action request issued by an AI agent or DevX tool.
struct DinoAction: Codable {
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

    /// Returns a copy of this action with template variables (e.g. {{query}}) dynamically interpolated.
    func interpolated(with variables: [String: String]) -> DinoAction {
        guard !variables.isEmpty else { return self }
        var copy = self
        func replaceVars(_ str: String?) -> String? {
            guard let s = str, s.contains("{{") else { return str }
            var result = s
            for (k, v) in variables {
                result = result.replacingOccurrences(of: "{{\(k)}}", with: v)
                result = result.replacingOccurrences(of: "{{ \(k) }}", with: v)
            }
            return result
        }
        copy.text = replaceVars(copy.text)
        copy.target = replaceVars(copy.target)
        copy.selector = replaceVars(copy.selector)
        copy.elementId = replaceVars(copy.elementId)
        copy.toTarget = replaceVars(copy.toTarget)
        copy.optionValue = replaceVars(copy.optionValue)
        copy.optionText = replaceVars(copy.optionText)
        copy.dialogResponse = replaceVars(copy.dialogResponse)
        return copy
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
            "click", "dblclick", "double_click", "doubleclick", "right_click", "rightclick", "context_menu", "contextmenu",
            "hover", "type", "fill", "clear", "press", "selectoption", "scroll", "wheel", "scrollwheel", "drag", "highlight", "upload",
            "native_click", "native_dblclick", "native_double_click", "native_right_click", "native_context_menu", "native_hover", "native_type", "native_press", "native_drag", "native_scroll", "native_wheel"
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
struct DinoActionResult: Codable {
    let success: Bool
    var message: String
    var elementId: String? = nil
    var selector: String? = nil
    var obscured: Bool? = nil
    var isObscured: Bool? = nil
    var interceptedBy: String? = nil
    var occludedBy: String? = nil
    var centerCoordinates: [String: Double]? = nil
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

    init(success: Bool, message: String, elementId: String? = nil, selector: String? = nil, obscured: Bool? = nil, isObscured: Bool? = nil, interceptedBy: String? = nil, occludedBy: String? = nil, centerCoordinates: [String: Double]? = nil, healed: Bool? = nil, staleRef: Bool? = nil, code: String? = nil, stack: String? = nil, error: String? = nil, files: [String]? = nil, count: Int? = nil, native: Bool? = nil, isTrusted: Bool? = nil, lastDialog: String? = nil, hasPendingDialog: Bool? = nil) {
        self.success = success
        self.message = message
        self.elementId = elementId
        self.selector = selector
        self.obscured = obscured ?? isObscured
        self.isObscured = isObscured ?? obscured
        self.interceptedBy = interceptedBy ?? occludedBy
        self.occludedBy = occludedBy ?? interceptedBy
        self.centerCoordinates = centerCoordinates
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

    enum CodingKeys: String, CodingKey {
        case success, message, elementId, selector, obscured, isObscured, interceptedBy, occludedBy, centerCoordinates
        case healed, staleRef, code, stack, error, files, count, native, isTrusted, lastDialog, hasPendingDialog
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(elementId, forKey: .elementId)
        try container.encodeIfPresent(selector, forKey: .selector)
        if obscured == true || isObscured == true {
            try container.encode(true, forKey: .obscured)
            try container.encode(true, forKey: .isObscured)
        }
        if let ib = interceptedBy ?? occludedBy {
            try container.encode(ib, forKey: .interceptedBy)
            try container.encode(ib, forKey: .occludedBy)
        }
        try container.encodeIfPresent(centerCoordinates, forKey: .centerCoordinates)
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

enum DinoDOMScript {
    /// Injected JavaScript that parses visible interactive elements (including open Shadow DOM and iframes),
    /// performs occlusion hit-testing, formats a dense LLM-friendly semantic summary (~300 tokens),
    /// and executes reliable native-like actions (React 16+ prototype setters, hover, clear, key chords).
    public static var core: String {
        let loaded = ScriptLoader.load(named: "dino-dom-core")
        return loaded.isEmpty ? ScriptLoader.load(named: "dino-dom-core") : loaded
    }
}

// MARK: - Tab Automation Bridge (Clean Facade to TabAutomationDriver)

extension Tab {
    /// Injects DinoDOMScript only if window.__dino is not already initialized.
    @MainActor
    func ensureDinoScriptInjected() async {
        await driver.ensureDinoScriptInjected()
    }

    /// Evaluates in-page anti-bot challenge and 2FA status for Human-in-the-Loop guardrails.
    @MainActor
    func checkHitlStatus() async -> (detected: Bool, type: String?, resolved: Bool) {
        await driver.checkHitlStatus()
    }

    /// Checks and synchronizes HITL state on the tab (triggering the in-app banner if active).
    @MainActor
    @discardableResult
    func updateHitlState() async -> Bool {
        await driver.updateHitlState()
    }

    /// Waits for in-flight web view navigation to settle up to a given timeout.
    @MainActor
    func waitForNavigationSettled(timeout: TimeInterval = 0.5, pollIntervalMs: UInt64 = 30) async {
        await driver.waitForNavigationSettled(timeout: timeout, pollIntervalMs: pollIntervalMs)
    }

    /// Extracts a dense, token-efficient semantic tree and element index from the active page.
    @MainActor
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
        try await driver.getSemanticTree(
            limit: limit,
            offset: offset,
            viewportOnly: viewportOnly,
            includeText: includeText,
            includeCoords: includeCoords,
            role: role,
            text: text,
            target: target,
            depth: depth,
            track: track
        )
    }

    /// Computes compact DOM mutation diff between sequential actions (<80 tokens).
    @MainActor
    func getDiff(viewportOnly: Bool = false) async throws -> [String: Any] {
        try await driver.getDiff(viewportOnly: viewportOnly)
    }

    /// Fast, intent-driven semantic natural language element finder with heuristic scoring.
    @MainActor
    func findSemantic(query: String, role: String? = nil, viewportOnly: Bool = false) async throws -> [String: Any] {
        try await driver.findSemantic(query: query, role: role, viewportOnly: viewportOnly)
    }

    /// Dispatches a browser action (click, hover, type, clear, scroll, keypress, select, highlight) on the active page.
    @MainActor
    func performAction(_ action: DinoAction) async throws -> DinoActionResult {
        try await driver.performAction(action)
    }

    /// Waits for DOM mutation quiescence (stability) on the active page.
    @MainActor
    func waitForStability(quietMs: Int = 250, timeoutMs: Int = 5000) async throws -> [String: Any] {
        try await driver.waitForStability(quietMs: quietMs, timeoutMs: timeoutMs)
    }

    /// Synthesizes native AppKit and CoreGraphics input events delivering true OS-level user gestures (isTrusted: true).
    @MainActor
    func performNativeAction(_ action: DinoAction) async throws -> DinoActionResult {
        try await driver.performNativeAction(action)
    }

    /// Captures a crisp screenshot directly from WebKit's in-memory compositing buffer (GPU RAM).
    @MainActor
    func captureScreenshot(labeled: Bool = false, elementId: String? = nil, clip: CGRect? = nil, somCrop: Bool = false, fullPage: Bool = false) async throws -> NSImage {
        try await driver.captureScreenshot(labeled: labeled, elementId: elementId, clip: clip, somCrop: somCrop, fullPage: fullPage)
    }

    /// Renders vector PDF layout of the page.
    @MainActor
    func generatePDF(configuration: WKPDFConfiguration? = nil) async throws -> Data {
        try await driver.generatePDF(configuration: configuration)
    }
}

// MARK: - NSImage Image Helper

extension NSImage {
    /// Encodes NSImage to standard PNG data, optionally scaled by a factor (e.g. 1.0 downsamples from Retina 2x to 1x logical resolution).
    func pngData(scale: CGFloat? = nil) -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }

        let needsDownsample = (scale == 1.0 && bitmapImage.pixelsWide > Int(size.width))
        guard let s = scale, s > 0, (s != 1.0 || needsDownsample) else {
            return bitmapImage.representation(using: .png, properties: [:])
        }

        let targetSize = CGSize(width: max(1, round(size.width * s)), height: max(1, round(size.height * s)))
        guard let scaledRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return bitmapImage.representation(using: .png, properties: [:])
        }

        scaledRep.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaledRep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: CGRect(origin: .zero, size: targetSize), from: CGRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return scaledRep.representation(using: .png, properties: [:])
    }

    /// Encodes NSImage to standard PNG data using native resolution.
    var pngData: Data? {
        pngData(scale: nil)
    }
}

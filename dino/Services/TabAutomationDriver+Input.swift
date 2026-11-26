//
//  TabAutomationDriver.swift
//  dino
//

import AppKit
import WebKit
import PDFKit

@MainActor
extension TabAutomationDriver {
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
                    let hasAnyRefs = ((try? await callAsyncIsolated(
                        "return Boolean(window.__dino && window.__dino.elements && Object.keys(window.__dino.elements).length > 0);"
                    )) as? Bool) ?? true
                    code = "STALE_REF"
                    message = hasAnyRefs
                        ? "Target element '\(target)' not found. Please re-snapshot."
                        : "No element refs indexed on this page yet (target '\(target)'). Run 'dino snap -v' or 'dino goto <url> -s' first, or use a CSS selector."
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

}

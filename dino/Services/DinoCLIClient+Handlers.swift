//
//  DinoCLIClient.swift
//  dino
//

import Foundation
import Darwin

extension DinoCLIClient {
    // MARK: - Subcommand Handlers

    @discardableResult
    static func validateActionResponse(_ resp: HTTPResponse, command: String) -> [String: Any] {
        guard resp.statusCode == 200 else {
            var msg = resp.bodyString
            var code = "ERROR"
            if let json = resp.jsonObject {
                if let err = json["error"] as? String {
                    msg = err
                } else if let m = json["message"] as? String {
                    msg = m
                }
                if let c = json["code"] as? String {
                    code = c
                }
            }
            emitError("dino \(command): [\(code)] \(msg)")
            exit(1)
        }

        guard let json = resp.jsonObject else {
            return [:]
        }

        if let success = json["success"] as? Bool, !success {
            let msg = (json["message"] as? String) ?? (json["error"] as? String) ?? "Action failed"
            let code = (json["code"] as? String) ?? "ACTION_FAILED"
            emitError("dino \(command): [\(code)] \(msg)")
            exit(1)
        }

        return json
    }

    static func handleSnap(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var queryItems: [String] = []

        let isJson = args.boolFlag(["--json", "-j"])
        queryItems.append("mode=\(isJson ? "json" : "text")")

        if args.boolFlag(["--all"]) {
            queryItems.append("viewportOnly=false")
        } else if args.boolFlag(["--viewport", "-v", "--viewportOnly"]) {
            queryItems.append("viewportOnly=true")
        }
        if let target = args.stringOption(["--target", "-t"]) {
            queryItems.append("target=\(target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? target)")
        }
        if let role = args.stringOption(["--role", "-r"]) {
            queryItems.append("role=\(role.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? role)")
        }
        if let text = args.stringOption(["--text"]) {
            queryItems.append("text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)")
        }
        if let depth = args.stringOption(["--depth"]) {
            queryItems.append("depth=\(depth)")
        }
        if let limit = args.stringOption(["--limit"]) {
            queryItems.append("limit=\(limit)")
        } else {
            queryItems.append("limit=50")
        }
        if let offset = args.stringOption(["--offset"]) {
            queryItems.append("offset=\(offset)")
        }
        if args.boolFlag(["--track"]) {
            queryItems.append("track=true")
        }
        if args.boolFlag(["--coords"]) {
            queryItems.append("coords=true")
        }
        if args.boolFlag(["--unrestricted", "--force", "-u"]) {
            queryItems.append("unrestricted=true")
        }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            queryItems.append("tabId=\(tid)")
        }

        let path = "/snapshot?" + queryItems.joined(separator: "&")
        let resp = request(method: "GET", path: path, socketPath: socketPath, port: port)

        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino snap: \(errMsg)")
            exit(1)
        }

        if isJson {
            emitOutput(resp.bodyString)
            exit(0)
        }

        guard let json = resp.jsonObject else {
            emitOutput(resp.bodyString)
            exit(0)
        }

        if let warning = json["warning"] as? String {
            emitError("warning: \(warning)")
        }

        if let summary = json["summary"] as? String {
            let formatted = summary.replacingOccurrences(of: "\\n", with: "\n")
            emitOutput(formatted)
            exit(0)
        } else {
            emitOutput(resp.bodyString)
            exit(0)
        }
    }

    static func handleDiff(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var queryItems: [String] = []

        let isJson = args.boolFlag(["--json", "-j"])
        if isJson {
            queryItems.append("mode=json")
        }

        let vpOnly = args.boolFlag(["--viewport", "-v"])
        if vpOnly {
            queryItems.append("viewportOnly=true")
        }

        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            queryItems.append("tabId=\(tid)")
        }

        let path = queryItems.isEmpty ? "/diff" : "/diff?" + queryItems.joined(separator: "&")
        let resp = request(method: "GET", path: path, socketPath: socketPath, port: port)

        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino diff: \(errMsg)")
            exit(1)
        }

        if isJson {
            emitOutput(resp.bodyString)
            exit(0)
        }

        guard let json = resp.jsonObject else {
            emitOutput(resp.bodyString)
            exit(0)
        }

        if let summary = json["summary"] as? String {
            let formatted = summary.replacingOccurrences(of: "\\n", with: "\n")
            emitOutput(formatted)
            exit(0)
        } else {
            emitOutput(resp.bodyString)
            exit(0)
        }
    }

    static func handleOpen(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard let rawURL = args.positionals.first, !rawURL.isEmpty else {
            emitError("dino open: URL argument is required (e.g. 'dino open https://example.com')")
            exit(1)
        }

        var url = rawURL
        if !url.contains("://") && !url.hasPrefix("about:") && !url.hasPrefix("file:") {
            let parsed = URLParser.parse(rawURL)
            url = parsed.absoluteString
        }

        var bodyObj: [String: Any] = ["url": url]
        if args.boolFlag(["--allow-local-files", "--local", "-l"]) || url.hasPrefix("file://") {
            bodyObj["allowLocalFiles"] = true
        }
        let tabArg = args.stringOption(["--tab"])
        let resolvedTid = tabArg.flatMap { resolveTabId($0, port: port, socketPath: socketPath) }
        if let tid = resolvedTid {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino open: failed to serialize request payload")
            exit(1)
        }

        let resp = request(method: "POST", path: "/navigate", body: bodyData, timeoutSeconds: 30, socketPath: socketPath, port: port)
        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            let code = (resp.jsonObject?["code"] as? String) ?? "NAVIGATION_FAILED"
            emitError("dino open: [\(code)] \(errMsg)")
            exit(1)
        }

        guard let json = resp.jsonObject else {
            emitOutput("Loaded: \(url)")
            exit(0)
        }

        if let success = json["success"] as? Bool, !success {
            let errMsg = (json["error"] as? String) ?? (json["message"] as? String) ?? "Navigation failed"
            let code = (json["code"] as? String) ?? "NAVIGATION_FAILED"
            emitError("dino open: [\(code)] \(errMsg)")
            exit(1)
        }

        // Compound --wait support for open (e.g. dino open https://example.com --wait auto)
        let waitMode = args.stringOption(["--wait", "-w"]) ?? (args.boolFlag(["--wait", "-w"]) ? "auto" : nil)
        if let waitArg = waitMode {
            var waitBody: [String: Any] = ["mode": waitArg]
            if let tid = resolvedTid { waitBody["tabId"] = tid }
            if let wData = try? JSONSerialization.data(withJSONObject: waitBody) {
                let waitResp = request(method: "POST", path: "/wait", body: wData, timeoutSeconds: 15, socketPath: socketPath, port: port)
                _ = validateActionResponse(waitResp, command: "wait")
            }
        }

        let shouldSnap = args.boolFlag(["--snap", "-s"])
        if shouldSnap {
            var snapArgs = args
            if !snapArgs.boolFlag(["--all"]) {
                snapArgs.flags.insert("--viewport")
            }
            handleSnap(args: snapArgs, port: port, socketPath: socketPath)
            return
        }

        let finalURL = (json["navigatedTo"] as? String) ?? (json["url"] as? String) ?? url
        if let title = json["title"] as? String, !title.isEmpty {
            emitOutput("Loaded: \(finalURL) - \"\(title)\"")
        } else {
            emitOutput("Loaded: \(finalURL)")
        }
        exit(0)
    }

    static func handleNavAction(_ action: String, args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var bodyObj: [String: Any] = ["action": action]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino \(action): failed to serialize request payload")
            exit(1)
        }

        let resp = request(method: "POST", path: "/navigate", body: bodyData, timeoutSeconds: 15, socketPath: socketPath, port: port)
        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            let code = (resp.jsonObject?["code"] as? String) ?? "ACTION_FAILED"
            emitError("dino \(action): [\(code)] \(errMsg)")
            exit(1)
        }

        if let json = resp.jsonObject, let success = json["success"] as? Bool, !success {
            let errMsg = (json["error"] as? String) ?? (json["message"] as? String) ?? "Action failed"
            let code = (json["code"] as? String) ?? "ACTION_FAILED"
            emitError("dino \(action): [\(code)] \(errMsg)")
            exit(1)
        }

        // Compound --wait support (e.g. dino back --wait auto or dino reload -w)
        let waitMode = args.stringOption(["--wait", "-w"]) ?? (args.boolFlag(["--wait", "-w"]) ? "auto" : nil)
        if let waitArg = waitMode {
            var waitBody: [String: Any] = ["mode": waitArg]
            if let tid = bodyObj["tabId"] as? String { waitBody["tabId"] = tid }
            if let wData = try? JSONSerialization.data(withJSONObject: waitBody) {
                let waitResp = request(method: "POST", path: "/wait", body: wData, timeoutSeconds: 15, socketPath: socketPath, port: port)
                _ = validateActionResponse(waitResp, command: "wait")
            }
        }

        switch action {
        case "back": emitOutput("Navigated back")
        case "forward": emitOutput("Navigated forward")
        case "reload": emitOutput("Reloaded page")
        default: emitOutput("Action completed: \(action)")
        }
        exit(0)
    }

    static func handleClick(args: ParsedArgs, port: UInt16?, socketPath: String?, isDouble: Bool = false) {
        var posX: Double? = args.stringOption(["--x", "-x"]).flatMap(Double.init)
        var posY: Double? = args.stringOption(["--y", "-y"]).flatMap(Double.init)
        if let coords = args.stringOption(["--coords", "-c"]) {
            let parts = coords.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { posX = parts[0]; posY = parts[1] }
        }
        if let offset = args.stringOption(["--offset", "--offset-coords"]) {
            let parts = offset.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { posX = parts[0]; posY = parts[1] }
        }
        if let ox = args.stringOption(["--offset-x"]).flatMap(Double.init) { posX = ox }
        if let oy = args.stringOption(["--offset-y"]).flatMap(Double.init) { posY = oy }

        let ref = args.positionals.first
        guard (ref != nil && !ref!.isEmpty) || (posX != nil && posY != nil) else {
            emitError("dino click: element reference or coordinates are required (e.g. 'dino click e5' or 'dino click --coords 300,400')")
            exit(1)
        }

        let isRight = args.boolFlag(["--right", "-r", "--context-menu"])
        let isDouble = isDouble || args.boolFlag(["--double", "-d"])
        let isNative = args.boolFlag(["--native"])
        let actionType = isRight ? "right_click" : (isDouble ? "dblclick" : "click")

        var bodyObj: [String: Any] = [
            "action": actionType,
            "type": actionType,
            "native": isNative
        ]
        if let r = ref, !r.isEmpty {
            bodyObj["elementId"] = r
            bodyObj["target"] = r
        }
        if let x = posX { bodyObj["x"] = x }
        if let y = posY { bodyObj["y"] = y }

        let tabArg = args.stringOption(["--tab"])
        let resolvedTid = tabArg.flatMap { resolveTabId($0, port: port, socketPath: socketPath) }
        if let tid = resolvedTid {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino click: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        let json = validateActionResponse(resp, command: "click")

        // Compound --wait support (e.g. dino click e5 --wait auto or dino click e5 --wait)
        let waitMode = args.stringOption(["--wait", "-w"]) ?? (args.boolFlag(["--wait", "-w"]) ? "auto" : nil)
        if let waitArg = waitMode {
            var waitBody: [String: Any] = ["mode": waitArg]
            if let tid = resolvedTid { waitBody["tabId"] = tid }
            if let wData = try? JSONSerialization.data(withJSONObject: waitBody) {
                let waitResp = request(method: "POST", path: "/wait", body: wData, timeoutSeconds: 15, socketPath: socketPath, port: port)
                _ = validateActionResponse(waitResp, command: "wait")
            }
        }

        var desc = isRight ? "Right-clicked" : (isDouble ? "Double-clicked" : "Clicked")
        if let obs = json["obscured"] as? Bool, obs {
            let interceptor = json["interceptedBy"] as? String
            let tag = interceptor != nil ? "<\(interceptor!)>" : "overlay"
            desc += " \(ref ?? "") (warning: obscured, intercepted by \(tag))"
        } else if let r = ref, !r.isEmpty {
            if let x = posX, let y = posY {
                desc += " \(r) offset (\(Int(x)), \(Int(y)))"
            } else {
                desc += " \(r)"
            }
        } else if let x = posX, let y = posY {
            desc += " at (\(Int(x)), \(Int(y)))"
        }
        emitOutput(desc)
        exit(0)
    }

    static func handleType(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard args.positionals.count >= 2 else {
            emitError("dino type: element reference and text are required (e.g. 'dino type e2 \"MacBook Pro\"')")
            exit(1)
        }

        let ref = args.positionals[0]
        let text = args.positionals.dropFirst().joined(separator: " ")
        let isSubmit = args.boolFlag(["--submit", "--press-enter", "--enter", "--return"])
        let isClear = args.boolFlag(["--clear"])
        let isNative = args.boolFlag(["--native"])
        let pressKey = args.stringOption(["--press", "-p"]) ?? (args.boolFlag(["--press", "-p", "--press-enter", "--enter", "--return"]) ? "Enter" : nil)

        var bodyObj: [String: Any] = [
            "type": "type",
            "elementId": ref,
            "text": text,
            "submit": isSubmit || (pressKey?.lowercased() == "enter"),
            "clear": isClear,
            "native": isNative
        ]
        let tabArg = args.stringOption(["--tab"])
        let resolvedTid = tabArg.flatMap { resolveTabId($0, port: port, socketPath: socketPath) }
        if let tid = resolvedTid {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino type: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "type")

        // If extra key chord requested (and not already submitted via Enter)
        if let key = pressKey, key.lowercased() != "enter" {
            var pressObj: [String: Any] = ["type": "press", "key": key, "native": isNative]
            if let tid = resolvedTid { pressObj["tabId"] = tid }
            if let pData = try? JSONSerialization.data(withJSONObject: pressObj) {
                let pressResp = request(method: "POST", path: "/action", body: pData, socketPath: socketPath, port: port)
                _ = validateActionResponse(pressResp, command: "press")
            }
        }

        emitOutput("Typed into \(ref)")
        exit(0)
    }

    static func handlePress(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard let key = args.positionals.first, !key.isEmpty else {
            emitError("dino press: key chord is required (e.g. 'dino press Enter' or 'dino press Meta+A')")
            exit(1)
        }

        let isNative = args.boolFlag(["--native"])
        var bodyObj: [String: Any] = [
            "type": "press",
            "key": key,
            "native": isNative
        ]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino press: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "press")

        emitOutput("Pressed \(key)")
        exit(0)
    }

    static func handleDrag(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard args.positionals.count >= 2 else {
            emitError("dino drag: source and destination element references required (e.g. 'dino drag e3 e8')")
            exit(1)
        }

        let fromRef = args.positionals[0]
        let toRef = args.positionals[1]
        let isNative = args.boolFlag(["--native"])

        var bodyObj: [String: Any] = [
            "type": "drag",
            "elementId": fromRef,
            "toElementId": toRef,
            "native": isNative
        ]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino drag: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "drag")

        emitOutput("Dragged \(fromRef) to \(toRef)")
        exit(0)
    }

    static func handleHover(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var posX: Double? = args.stringOption(["--x", "-x"]).flatMap(Double.init)
        var posY: Double? = args.stringOption(["--y", "-y"]).flatMap(Double.init)
        if let coords = args.stringOption(["--coords", "-c"]) {
            let parts = coords.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { posX = parts[0]; posY = parts[1] }
        }
        if let offset = args.stringOption(["--offset", "--offset-coords"]) {
            let parts = offset.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { posX = parts[0]; posY = parts[1] }
        }
        if let ox = args.stringOption(["--offset-x"]).flatMap(Double.init) { posX = ox }
        if let oy = args.stringOption(["--offset-y"]).flatMap(Double.init) { posY = oy }

        let ref = args.positionals.first
        guard (ref != nil && !ref!.isEmpty) || (posX != nil && posY != nil) else {
            emitError("dino hover: element reference or coordinates required (e.g. 'dino hover e5' or 'dino hover --coords 300,400')")
            exit(1)
        }

        let isNative = args.boolFlag(["--native"])
        var bodyObj: [String: Any] = [
            "action": "hover",
            "type": "hover",
            "native": isNative
        ]
        if let r = ref, !r.isEmpty {
            bodyObj["elementId"] = r
            bodyObj["target"] = r
        }
        if let x = posX { bodyObj["x"] = x }
        if let y = posY { bodyObj["y"] = y }

        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino hover: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "hover")

        if let r = ref, !r.isEmpty {
            if let x = posX, let y = posY {
                emitOutput("Hovered \(r) offset (\(Int(x)), \(Int(y)))")
            } else {
                emitOutput("Hovered \(r)")
            }
        } else if let x = posX, let y = posY {
            emitOutput("Hovered at (\(Int(x)), \(Int(y)))")
        } else {
            emitOutput("Hovered")
        }
        exit(0)
    }

    static func handleSelect(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard args.positionals.count >= 2 else {
            emitError("dino select: element reference and option value required (e.g. 'dino select e4 \"US\"')")
            exit(1)
        }

        let ref = args.positionals[0]
        let val = args.positionals.dropFirst().joined(separator: " ")

        var bodyObj: [String: Any] = [
            "type": "selectOption",
            "elementId": ref,
            "optionValue": val,
            "optionText": val
        ]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino select: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "select")

        emitOutput("Selected \"\(val)\" in \(ref)")
        exit(0)
    }

    static func handleScroll(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var direction = "down"
        var amount: CGFloat = 300
        var targetElement: String? = args.stringOption(["--target", "-t", "--selector", "-s", "--to"])

        if args.positionals.count >= 2 && args.positionals[0].lowercased() == "to" {
            targetElement = args.positionals[1]
        } else if args.positionals.count == 1 {
            let first = args.positionals[0]
            if let num = Double(first) {
                amount = CGFloat(num)
            } else if ["down", "up", "left", "right", "top", "bottom"].contains(first.lowercased()) {
                direction = first.lowercased()
            } else {
                targetElement = first
            }
        } else if args.positionals.count >= 2 {
            direction = args.positionals[0].lowercased()
            if let num = Double(args.positionals[1]) {
                amount = CGFloat(num)
            }
        }

        let isNative = args.boolFlag(["--native", "-n"])

        var bodyObj: [String: Any] = [
            "type": "scroll",
            "direction": direction,
            "amount": amount,
            "native": isNative
        ]
        if let target = targetElement {
            bodyObj["target"] = target
        }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino scroll: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "scroll")

        if let target = targetElement {
            emitOutput("Scrolled \(target) into view")
        } else {
            emitOutput("Scrolled \(direction) \(Int(amount))px\(isNative ? " (native)" : "")")
        }
        exit(0)
    }

    static func handleWait(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var timeoutMs = 5000
        var selector = args.stringOption(["--selector", "-s", "--target", "-t"]) ?? ""
        var urlPattern = args.stringOption(["--url"]) ?? ""
        let textPattern = args.stringOption(["--text"]) ?? ""
        let stateExpected = args.stringOption(["--state"]) ?? ""
        var mode = args.stringOption(["--mode", "-m"]) ?? "auto"

        for pos in args.positionals {
            if let num = Int(pos) {
                timeoutMs = num
            } else if pos.hasPrefix("http://") || pos.hasPrefix("https://") {
                urlPattern = pos
                if mode == "auto" { mode = "navigation" }
            } else if pos.hasPrefix("#") || pos.hasPrefix(".") || pos.hasPrefix("[") || selector.isEmpty {
                selector = pos
                if mode == "auto" && textPattern.isEmpty && stateExpected.isEmpty { mode = "selector" }
            }
        }
        if let tStr = args.stringOption(["--timeout"]) ?? args.stringOption(["--duration"]), let t = Int(tStr) {
            timeoutMs = t
        }
        if !textPattern.isEmpty && (mode == "auto" || mode == "default") { mode = "text" }
        if !stateExpected.isEmpty && (mode == "auto" || mode == "default") { mode = "state" }

        var bodyObj: [String: Any] = [
            "mode": mode,
            "timeoutMs": timeoutMs,
            "selector": selector,
            "urlPattern": urlPattern
        ]
        if !textPattern.isEmpty { bodyObj["text"] = textPattern }
        if !stateExpected.isEmpty { bodyObj["state"] = stateExpected }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino wait: failed to encode wait payload")
            exit(1)
        }

        let sockTimeout = max(10, Int(Double(timeoutMs) / 1000.0) + 5)
        let resp = request(method: "POST", path: "/wait", body: bodyData, timeoutSeconds: sockTimeout, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "wait")

        let desc: String
        if !textPattern.isEmpty { desc = "text '\(textPattern)'" }
        else if !stateExpected.isEmpty { desc = "state '\(stateExpected)' on \(selector)" }
        else { desc = mode }
        emitOutput("Wait completed (\(desc))")
        exit(0)
    }

    static func handleFind(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let query = args.positionals.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let role = args.stringOption(["--role", "-r"])
        let selector = args.stringOption(["--selector", "-s"])
        let textOpt = args.stringOption(["--text"])
        let refOnly = args.boolFlag(["--ref-only"])
        let vpOnly = args.boolFlag(["--viewport", "-v", "--viewportOnly"])

        var bodyObj: [String: Any] = [:]
        if !query.isEmpty && textOpt == nil && selector == nil {
            if query.hasPrefix("#") || query.hasPrefix(".") || query.hasPrefix("[") {
                bodyObj["selector"] = query
            } else {
                bodyObj["text"] = query
            }
        }
        if let r = role { bodyObj["role"] = r }
        if let s = selector { bodyObj["selector"] = s }
        if let t = textOpt { bodyObj["text"] = t }
        if vpOnly { bodyObj["viewportOnly"] = true }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino find: failed to encode find payload")
            exit(1)
        }

        let resp = request(method: "POST", path: "/find", body: bodyData, socketPath: socketPath, port: port)
        if resp.statusCode == 404 {
            emitError("dino find: element not found")
            exit(1)
        }
        guard let json = resp.jsonObject, let success = json["success"] as? Bool, success,
              let ref = json["ref"] as? String else {
            _ = validateActionResponse(resp, command: "find")
            exit(1)
        }

        if refOnly {
            emitOutput(ref)
        } else {
            let roleStr = json["role"] as? String ?? "generic"
            let tagStr = json["tag"] as? String ?? ""
            let textStr = (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = textStr.count > 40 ? String(textStr.prefix(37)) + "..." : textStr
            emitOutput("[\(ref)] role: \(roleStr) tag: <\(tagStr)> text: \"\(snippet)\"")
        }
        exit(0)
    }

    static func handleDialog(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let action = args.positionals.first?.lowercased()
        var bodyObj: [String: Any] = [:]

        if let act = action, ["accept", "dismiss", "wait"].contains(act) {
            bodyObj["policy"] = act
            if act != "wait" { bodyObj["action"] = act }
        }
        if let pol = args.stringOption(["--policy"]) {
            bodyObj["policy"] = pol
        }
        if let resp = args.stringOption(["--response"]) {
            bodyObj["response"] = resp
            bodyObj["promptResponse"] = resp
        }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj)
        let method = bodyObj.isEmpty ? "GET" : "POST"
        let resp = request(method: method, path: "/dialog", body: bodyData, socketPath: socketPath, port: port)
        if resp.statusCode >= 200 && resp.statusCode < 300, let json = resp.jsonObject {
            let policy = json["policy"] as? String ?? "unknown"
            let hasPending = json["hasPendingDialog"] as? Bool ?? false
            let last = json["lastDialog"] as? String ?? "none"
            emitOutput("dialog policy: \(policy)  hasPending: \(hasPending)  lastDialog: \(last)")
            exit(0)
        } else {
            _ = validateActionResponse(resp, command: "dialog")
            exit(1)
        }
    }

    static func handleExtensions(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let sub = args.positionals.first?.lowercased()
        if sub == "enable" || sub == "disable" || sub == "toggle" {
            guard args.positionals.count > 1 else {
                emitError("dino ext \(sub ?? ""): missing extension id")
                exit(1)
            }
            let extId = args.positionals[1]
            var bodyObj: [String: Any] = ["id": extId]
            if sub == "enable" { bodyObj["enabled"] = true }
            if sub == "disable" { bodyObj["enabled"] = false }
            let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let resp = request(method: "POST", path: "/extensions/toggle", body: bodyData, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "ext toggle")
            if let json = resp.jsonObject, let enabled = json["enabled"] as? Bool {
                emitOutput("extension \(extId): \(enabled ? "enabled" : "disabled")")
            } else {
                emitOutput("extension \(extId): toggled")
            }
            exit(0)
        }

        let resp = request(method: "GET", path: "/extensions", body: nil, socketPath: socketPath, port: port)
        if resp.statusCode >= 200 && resp.statusCode < 300,
           let json = resp.jsonObject,
           let exts = json["extensions"] as? [[String: Any]] {
            if exts.isEmpty {
                emitOutput("No extensions installed.")
            } else {
                for ext in exts {
                    let id = ext["id"] as? String ?? ""
                    let name = ext["name"] as? String ?? "Unnamed"
                    let ver = ext["version"] as? String ?? "0.0"
                    let en = (ext["enabled"] as? Bool ?? false) ? "enabled" : "disabled"
                    emitOutput("• \(name) (v\(ver)) [\(en)] id: \(id)")
                }
            }
            exit(0)
        } else {
            _ = validateActionResponse(resp, command: "extensions")
            exit(1)
        }
    }

    static func handleTabs(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let sub = args.positionals.first?.lowercased()

        if sub == "new" {
            var targetURL: String? = nil
            if args.positionals.count > 1 {
                let raw = args.positionals[1]
                if !raw.contains("://") && !raw.hasPrefix("about:") && !raw.hasPrefix("file:") {
                    targetURL = URLParser.parse(raw).absoluteString
                } else {
                    targetURL = raw
                }
            }

            var bodyObj: [String: Any] = [:]
            if let u = targetURL { bodyObj["url"] = u }

            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("dino tab new: serialization failed")
                exit(1)
            }

            let resp = request(method: "POST", path: "/tabs/new", body: bodyData, socketPath: socketPath, port: port)
            guard resp.statusCode == 200, let json = resp.jsonObject else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("dino tab new: \(errMsg)")
                exit(1)
            }

            let tabId = json["tabId"] as? String ?? ""
            let url = json["url"] as? String ?? ""

            // Compound --wait support (e.g. dino tab new https://example.com --wait)
            let waitMode = args.stringOption(["--wait", "-w"]) ?? (args.boolFlag(["--wait", "-w"]) ? "auto" : nil)
            if let waitArg = waitMode {
                var waitBody: [String: Any] = ["mode": waitArg]
                if !tabId.isEmpty { waitBody["tabId"] = tabId }
                if let wData = try? JSONSerialization.data(withJSONObject: waitBody) {
                    let waitResp = request(method: "POST", path: "/wait", body: wData, timeoutSeconds: 15, socketPath: socketPath, port: port)
                    _ = validateActionResponse(waitResp, command: "wait")
                }
            }

            emitOutput("Created tab: \(tabId) (\(url.isEmpty ? "about:blank" : url))")
            exit(0)
        }

        if sub == "switch" {
            guard args.positionals.count > 1 else {
                emitError("dino tab switch: tab ID or index required (e.g. 'dino tab switch 1')")
                exit(1)
            }
            let target = args.positionals[1]
            guard let resolvedId = resolveTabId(target, port: port, socketPath: socketPath) else {
                emitError("dino tab switch: could not resolve tab '\(target)'")
                exit(1)
            }

            let bodyObj = ["id": resolvedId]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("dino tab switch: serialization failed")
                exit(1)
            }

            let resp = request(method: "POST", path: "/tabs/switch", body: bodyData, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("dino tab switch: \(errMsg)")
                exit(1)
            }

            emitOutput("Switched to tab: \(resolvedId)")
            exit(0)
        }

        if sub == "close" {
            var target = args.positionals.count > 1 ? args.positionals[1] : nil
            if target == nil {
                // If not provided, find currently active tab
                let statusResp = request(method: "GET", path: "/status", socketPath: socketPath, port: port)
                target = statusResp.jsonObject?["activeTabId"] as? String
            }
            guard let t = target, let resolvedId = resolveTabId(t, port: port, socketPath: socketPath) else {
                emitError("dino tab close: no active tab to close")
                exit(1)
            }

            let bodyObj = ["id": resolvedId]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("dino tab close: serialization failed")
                exit(1)
            }

            let resp = request(method: "POST", path: "/tabs/close", body: bodyData, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("dino tab close: \(errMsg)")
                exit(1)
            }

            emitOutput("Closed tab: \(resolvedId)")
            exit(0)
        }

        // Default: list all tabs in clean tabular form
        let resp = request(method: "GET", path: "/tabs", socketPath: socketPath, port: port)
        guard resp.statusCode == 200, let json = resp.jsonObject, let tabs = json["tabs"] as? [[String: Any]] else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino tabs: \(errMsg)")
            exit(1)
        }

        if tabs.isEmpty {
            emitOutput("No open tabs")
            exit(0)
        }

        for (idx, tab) in tabs.enumerated() {
            let isActive = (tab["active"] as? Bool) ?? (tab["isActive"] as? Bool) ?? false
            let marker = isActive ? "*" : " "
            let id = tab["id"] as? String ?? ""
            let url = tab["url"] as? String ?? ""
            let title = tab["title"] as? String ?? ""
            let titleSuffix = title.isEmpty ? "" : " - \"\(title)\""
            emitOutput("\(marker) [\(idx + 1)] \(id)  \(url)\(titleSuffix)")
        }
        exit(0)
    }

    static func handleEval(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard !args.positionals.isEmpty else {
            emitError("dino eval: JavaScript expression required (e.g. 'dino eval \"document.title\"')")
            exit(1)
        }

        let expr = args.positionals.joined(separator: " ")
        let world = args.stringOption(["--world"]) ?? "isolated"

        var bodyObj: [String: Any] = [
            "expression": expr,
            "world": world
        ]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino eval: serialization failed")
            exit(1)
        }

        let resp = request(method: "POST", path: "/evaluate", body: bodyData, socketPath: socketPath, port: port)
        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino eval: \(errMsg)")
            exit(1)
        }

        guard let json = resp.jsonObject else {
            emitOutput(resp.bodyString)
            exit(0)
        }

        if let success = json["success"] as? Bool, !success {
            let errMsg = (json["error"] as? String) ?? "Evaluation failed"
            let code = (json["code"] as? String) ?? "EVAL_ERROR"
            emitError("dino eval: [\(code)] \(errMsg)")
            exit(1)
        }
        if let errMsg = json["error"] as? String {
            let code = (json["code"] as? String) ?? "EVAL_ERROR"
            emitError("dino eval: [\(code)] \(errMsg)")
            exit(1)
        }

        if let isUndef = json["isUndefined"] as? Bool, isUndef {
            emitOutput("undefined")
            exit(0)
        }
        if let isNull = json["isNull"] as? Bool, isNull {
            emitOutput("null")
            exit(0)
        }

        if let resultVal = json["result"] {
            if let s = resultVal as? String {
                emitOutput(s)
            } else if let num = resultVal as? NSNumber {
                emitOutput(num.stringValue)
            } else if JSONSerialization.isValidJSONObject(resultVal),
                      let d = try? JSONSerialization.data(withJSONObject: resultVal, options: [.prettyPrinted]),
                      let pretty = String(data: d, encoding: .utf8) {
                emitOutput(pretty)
            } else if resultVal is NSNull {
                emitOutput("null")
            } else {
                emitOutput("\(resultVal)")
            }
        }
        exit(0)
    }

    static func handleShot(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var queryItems: [String] = []

        let isLabeled = args.boolFlag(["--labeled", "-l"])
        if isLabeled {
            queryItems.append("labeled=true")
        }
        let isCrop = args.boolFlag(["--crop", "--som-crop"])
        if isCrop {
            queryItems.append("somCrop=true")
        }
        if let el = args.stringOption(["--element", "-e"]) {
            queryItems.append("elementId=\(el)")
        }
        if let clip = args.stringOption(["--clip", "-c"]) {
            queryItems.append("clip=\(clip)")
        }
        if let scaleVal = args.stringOption(["--scale"]) {
            queryItems.append("scale=\(scaleVal)")
        }
        if args.boolFlag(["--full-page", "--fullpage"]) {
            queryItems.append("fullPage=true")
        }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            queryItems.append("tabId=\(tid)")
        }

        let path = queryItems.isEmpty ? "/screenshot" : "/screenshot?" + queryItems.joined(separator: "&")
        let resp = request(method: "GET", path: path, timeoutSeconds: 30, socketPath: socketPath, port: port)

        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino shot: \(errMsg)")
            exit(1)
        }

        let outTarget = args.positionals.first

        if outTarget == "-" {
            resp.body.withUnsafeBytes { rawBuffer in
                if let base = rawBuffer.baseAddress {
                    var totalWritten = 0
                    while totalWritten < rawBuffer.count {
                        let written = Darwin.write(STDOUT_FILENO, base + totalWritten, rawBuffer.count - totalWritten)
                        if written <= 0 { break }
                        totalWritten += written
                    }
                }
            }
            exit(0)
        }

        let destinationPath: String
        if let custom = outTarget, !custom.isEmpty {
            destinationPath = (custom as NSString).expandingTildeInPath
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let shotDir = "\(home)/.dino/screenshots"
            try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
            let timestamp = Int(Date().timeIntervalSince1970)
            destinationPath = "\(shotDir)/shot-\(timestamp).png"
        }

        let parentDir = (destinationPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        do {
            try resp.body.write(to: URL(fileURLWithPath: destinationPath))
            emitOutput(destinationPath)
            exit(0)
        } catch {
            emitError("dino shot: failed to write image to \(destinationPath): \(error.localizedDescription)")
            exit(1)
        }
    }

    static func handlePdf(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var queryItems: [String] = []

        if let clip = args.stringOption(["--clip", "-c"]) {
            queryItems.append("clip=\(clip)")
        }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            queryItems.append("tabId=\(tid)")
        }

        let path = queryItems.isEmpty ? "/pdf" : "/pdf?" + queryItems.joined(separator: "&")
        let resp = request(method: "GET", path: path, timeoutSeconds: 30, socketPath: socketPath, port: port)

        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino pdf: \(errMsg)")
            exit(1)
        }

        let outTarget = args.positionals.first

        if outTarget == "-" {
            resp.body.withUnsafeBytes { rawBuffer in
                if let base = rawBuffer.baseAddress {
                    var totalWritten = 0
                    while totalWritten < rawBuffer.count {
                        let written = Darwin.write(STDOUT_FILENO, base + totalWritten, rawBuffer.count - totalWritten)
                        if written <= 0 { break }
                        totalWritten += written
                    }
                }
            }
            exit(0)
        }

        let destinationPath: String
        if let custom = outTarget, !custom.isEmpty {
            destinationPath = (custom as NSString).expandingTildeInPath
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let pdfDir = "\(home)/.dino/pdfs"
            try? FileManager.default.createDirectory(atPath: pdfDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            destinationPath = "\(pdfDir)/dino-doc-\(df.string(from: Date())).pdf"
        }

        let url = URL(fileURLWithPath: destinationPath)
        let dir = url.deletingLastPathComponent().path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        do {
            try resp.body.write(to: url, options: .atomic)
            emitOutput(destinationPath)
            exit(0)
        } catch {
            emitError("dino pdf: Failed to write PDF file: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func handleSession(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard let subcmd = args.positionals.first?.lowercased() else {
            emitError("dino session: Missing subcommand. Usage: dino session save [name|path] | dino session restore <name|path>")
            exit(1)
        }

        let isJson = args.boolFlag(["--json", "-j"])
        var tabQuery = ""
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            tabQuery = "?tabId=\(tid)"
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = "\(home)/.dino/sessions"
        try? FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        func resolveSessionPath(_ target: String?) -> String {
            guard let t = target, !t.isEmpty else {
                return "\(sessionsDir)/default.json"
            }
            if t.contains("/") || t.hasSuffix(".json") {
                return (t as NSString).expandingTildeInPath
            }
            return "\(sessionsDir)/\(t).json"
        }

        switch subcmd {
        case "save", "export":
            let targetArg = args.positionals.count > 1 ? args.positionals[1] : nil
            let filePath = resolveSessionPath(targetArg)
            let resp = request(method: "GET", path: "/session/export\(tabQuery)", timeoutSeconds: 30, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("dino session save: \(errMsg)")
                exit(1)
            }
            do {
                let fileURL = URL(fileURLWithPath: filePath)
                let parent = fileURL.deletingLastPathComponent().path
                try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try resp.body.write(to: fileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath)
                if isJson {
                    emitOutput(resp.bodyString)
                } else {
                    let cookiesCount = (resp.jsonObject?["cookies"] as? [Any])?.count ?? 0
                    let originsCount = (resp.jsonObject?["origins"] as? [Any])?.count ?? 0
                    emitOutput("✅ Saved session state (\(cookiesCount) cookies, \(originsCount) origins) to \(filePath)")
                }
                exit(0)
            } catch {
                emitError("dino session save: Failed to write session file: \(error.localizedDescription)")
                exit(1)
            }

        case "restore", "import", "load":
            guard args.positionals.count > 1 else {
                emitError("dino session restore: Missing session name or file path. Usage: dino session restore <name|path>")
                exit(1)
            }
            let filePath = resolveSessionPath(args.positionals[1])
            guard FileManager.default.fileExists(atPath: filePath),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                emitError("dino session restore: Session file not found at \(filePath)")
                exit(1)
            }
            let resp = request(method: "POST", path: "/session/import\(tabQuery)", body: data, timeoutSeconds: 30, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("dino session restore: \(errMsg)")
                exit(1)
            }
            if isJson {
                emitOutput(resp.bodyString)
            } else {
                let cCount = resp.jsonObject?["cookiesImported"] as? Int ?? 0
                let oCount = resp.jsonObject?["originsImported"] as? Int ?? 0
                emitOutput("✅ Restored session state (\(cCount) cookies, \(oCount) origins) from \(filePath)")
            }
            exit(0)

        default:
            emitError("dino session: Unknown subcommand '\(subcmd)'. Usage: dino session save [name|path] | dino session restore <name|path>")
            exit(1)
        }
    }

    static func handleExtract(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var queryItems: [String] = []

        if let mode = args.stringOption(["--mode", "-m"]) {
            queryItems.append("mode=\(mode)")
        }
        if let sel = args.positionals.first, !sel.isEmpty {
            queryItems.append("selector=\(sel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sel)")
        }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            queryItems.append("tabId=\(tid)")
        }

        let path = queryItems.isEmpty ? "/extract" : "/extract?" + queryItems.joined(separator: "&")
        let resp = request(method: "GET", path: path, timeoutSeconds: 30, socketPath: socketPath, port: port)

        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino extract: \(errMsg)")
            exit(1)
        }

        if let json = resp.jsonObject, let data = json["data"] {
            if let prettyData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]),
               let prettyStr = String(data: prettyData, encoding: .utf8) {
                emitOutput(prettyStr)
            } else {
                emitOutput("\(data)")
            }
        } else {
            emitOutput(resp.bodyString)
        }
        exit(0)
    }

    static func handleUpload(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard args.positionals.count >= 2 else {
            emitError("dino upload: element reference and file path(s) required (e.g. 'dino upload e3 document.pdf')")
            exit(1)
        }

        let ref = args.positionals[0]
        let rawPaths = Array(args.positionals.dropFirst())

        var resolvedPaths: [String] = []
        let cwd = FileManager.default.currentDirectoryPath

        for p in rawPaths {
            let expanded = (p as NSString).expandingTildeInPath
            let fullPath = expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
            guard FileManager.default.fileExists(atPath: fullPath) else {
                emitError("dino upload: file not found at path '\(fullPath)'")
                exit(1)
            }
            resolvedPaths.append(fullPath)
        }

        var bodyObj: [String: Any] = [
            "elementId": ref,
            "paths": resolvedPaths
        ]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("dino upload: failed to encode upload payload")
            exit(1)
        }

        let resp = request(method: "POST", path: "/upload", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "upload")

        emitOutput("Uploaded \(resolvedPaths.count) file(s) to \(ref)")
        exit(0)
    }

    static func handleStorage(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let sub = args.positionals.first?.lowercased() ?? "get"
        let tabArg = args.stringOption(["--tab"])
        let resolvedTid = tabArg.flatMap { resolveTabId($0, port: port, socketPath: socketPath) }
        var queryParts: [String] = []
        if let tid = resolvedTid { queryParts.append("tabId=\(tid)") }
        if args.boolFlag(["--raw"]) { queryParts.append("raw=true") }
        if let t = args.stringOption(["--type"]) { queryParts.append("type=\(t)") }
        let qStr = queryParts.isEmpty ? "" : "?" + queryParts.joined(separator: "&")

        switch sub {
        case "get":
            let resp = request(method: "GET", path: "/storage\(qStr)", socketPath: socketPath, port: port)
            let json = validateActionResponse(resp, command: "storage get")
            if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                emitOutput(str)
            }
            exit(0)

        case "clear":
            var bodyObj: [String: Any] = [:]
            if let tid = resolvedTid { bodyObj["tabId"] = tid }
            if let t = args.stringOption(["--type"]) { bodyObj["type"] = t }
            let bData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let resp = request(method: "DELETE", path: "/storage\(qStr)", body: bData, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "storage clear")
            emitOutput("Storage cleared")
            exit(0)

        case "set":
            guard args.positionals.count >= 3 else {
                emitError("dino storage set: requires key and value (e.g. 'dino storage set auth_token abc')")
                exit(1)
            }
            let key = args.positionals[1]
            let val = args.positionals[2]
            let isSession = args.boolFlag(["--session"])
            var bodyObj: [String: Any] = [:]
            if let tid = resolvedTid { bodyObj["tabId"] = tid }
            if isSession {
                bodyObj["sessionStorage"] = [key: val]
            } else {
                bodyObj["localStorage"] = [key: val]
            }
            let bData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let resp = request(method: "POST", path: "/storage", body: bData, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "storage set")
            emitOutput("Set \(isSession ? "sessionStorage" : "localStorage") '\(key)' = '\(val)'")
            exit(0)

        default:
            emitError("Unknown storage subcommand '\(sub)'. Expected 'get', 'set', or 'clear'.")
            exit(1)
        }
    }

    static func handleCookies(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let sub = args.positionals.first?.lowercased() ?? "get"
        let tabArg = args.stringOption(["--tab"])
        let resolvedTid = tabArg.flatMap { resolveTabId($0, port: port, socketPath: socketPath) }
        var queryParts: [String] = []
        if let tid = resolvedTid { queryParts.append("tabId=\(tid)") }
        if let d = args.stringOption(["--domain", "-d"]) { queryParts.append("domain=\(d)") }
        if args.boolFlag(["--all-domains", "--all", "-a"]) { queryParts.append("allDomains=true") }
        let qStr = queryParts.isEmpty ? "" : "?" + queryParts.joined(separator: "&")

        switch sub {
        case "get", "list":
            let resp = request(method: "GET", path: "/cookies\(qStr)", socketPath: socketPath, port: port)
            let json = validateActionResponse(resp, command: "cookies get")
            if args.boolFlag(["--json", "-j"]) {
                if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    emitOutput(str)
                } else {
                    emitOutput(resp.bodyString)
                }
                exit(0)
            }
            guard let cookies = json["cookies"] as? [[String: Any]], !cookies.isEmpty else {
                emitOutput("No cookies found")
                exit(0)
            }
            for c in cookies {
                let name = c["name"] as? String ?? ""
                let val = c["value"] as? String ?? ""
                let domain = c["domain"] as? String ?? ""
                let path = c["path"] as? String ?? "/"
                let secure = (c["isSecure"] as? Bool) == true ? " [secure]" : ""
                let httpOnly = (c["isHTTPOnly"] as? Bool) == true ? " [httpOnly]" : ""
                emitOutput("\(domain)\(path) : \(name)=\(val)\(secure)\(httpOnly)")
            }
            exit(0)

        case "set":
            let nonSubPositionals = args.positionals.dropFirst()
            guard nonSubPositionals.count >= 2 else {
                emitError("dino cookies set: requires name and value (e.g. 'dino cookies set session_id abc123 --domain example.com')")
                exit(1)
            }
            let name = Array(nonSubPositionals)[0]
            let val = Array(nonSubPositionals)[1]
            var cookieObj: [String: Any] = ["name": name, "value": val]
            if let d = args.stringOption(["--domain", "-d"]) { cookieObj["domain"] = d }
            if let p = args.stringOption(["--path"]) { cookieObj["path"] = p }
            if args.boolFlag(["--secure"]) { cookieObj["isSecure"] = true }
            var bodyObj: [String: Any] = ["cookies": [cookieObj]]
            if let tid = resolvedTid { bodyObj["tabId"] = tid }
            let bData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let resp = request(method: "POST", path: "/cookies", body: bData, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "cookies set")
            emitOutput("Set cookie '\(name)'")
            exit(0)

        case "clear", "del", "delete":
            let resp = request(method: "DELETE", path: "/cookies\(qStr)", socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "cookies clear")
            emitOutput("Cookies cleared")
            exit(0)

        default:
            let resp = request(method: "GET", path: "/cookies\(qStr)", socketPath: socketPath, port: port)
            let json = validateActionResponse(resp, command: "cookies")
            if args.boolFlag(["--json", "-j"]) {
                if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    emitOutput(str)
                } else {
                    emitOutput(resp.bodyString)
                }
                exit(0)
            }
            guard let cookies = json["cookies"] as? [[String: Any]], !cookies.isEmpty else {
                emitOutput("No cookies found")
                exit(0)
            }
            for c in cookies {
                let name = c["name"] as? String ?? ""
                let val = c["value"] as? String ?? ""
                let domain = c["domain"] as? String ?? ""
                let path = c["path"] as? String ?? "/"
                let secure = (c["isSecure"] as? Bool) == true ? " [secure]" : ""
                let httpOnly = (c["isHTTPOnly"] as? Bool) == true ? " [httpOnly]" : ""
                emitOutput("\(domain)\(path) : \(name)=\(val)\(secure)\(httpOnly)")
            }
            exit(0)
        }
    }

    static func handleConsole(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var queryParts: [String] = []
        let tabArg = args.stringOption(["--tab"])
        if let tid = tabArg.flatMap({ resolveTabId($0, port: port, socketPath: socketPath) }) {
            queryParts.append("tabId=\(tid)")
        }
        let level = args.stringOption(["--level", "-l"]) ?? args.positionals.first
        if let lvl = level, !lvl.isEmpty {
            queryParts.append("level=\(lvl.lowercased())")
        }
        if args.boolFlag(["--clear", "-c"]) {
            queryParts.append("clear=true")
        }
        let q = queryParts.isEmpty ? "" : "?" + queryParts.joined(separator: "&")
        let resp = request(method: "GET", path: "/console\(q)", socketPath: socketPath, port: port)
        guard resp.statusCode == 200, let json = resp.jsonObject else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino console: \(errMsg)")
            exit(1)
        }
        if args.boolFlag(["--json", "-j"]) {
            emitOutput(resp.bodyString)
            exit(0)
        }
        guard let entries = json["entries"] as? [[String: Any]], !entries.isEmpty else {
            emitOutput("No console entries")
            exit(0)
        }
        for e in entries {
            let lvl = (e["level"] as? String)?.uppercased() ?? "LOG"
            let msg = e["message"] as? String ?? ""
            emitOutput("[\(lvl)] \(msg)")
        }
        exit(0)
    }

    static func handleNetwork(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var queryParts: [String] = []
        let tabArg = args.stringOption(["--tab"])
        if let tid = tabArg.flatMap({ resolveTabId($0, port: port, socketPath: socketPath) }) {
            queryParts.append("tabId=\(tid)")
        }
        let filter = args.stringOption(["--filter", "-f"]) ?? args.positionals.first
        if let f = filter, !f.isEmpty {
            queryParts.append("statusFilter=\(f)")
        }
        if args.boolFlag(["--clear", "-c"]) {
            queryParts.append("clear=true")
        }
        let showBody = args.boolFlag(["--body", "-b"]) || args.stringOption(["--body", "-b"]) != nil
        if showBody || args.boolFlag(["--json", "-j"]) {
            queryParts.append("includeBody=true")
        }
        let q = queryParts.isEmpty ? "" : "?" + queryParts.joined(separator: "&")
        let resp = request(method: "GET", path: "/network\(q)", socketPath: socketPath, port: port)
        guard resp.statusCode == 200, let json = resp.jsonObject else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino network: \(errMsg)")
            exit(1)
        }
        if args.boolFlag(["--json", "-j"]) {
            emitOutput(resp.bodyString)
            exit(0)
        }
        guard let entries = json["entries"] as? [[String: Any]], !entries.isEmpty else {
            emitOutput("No network entries")
            exit(0)
        }
        let bodyFilter = args.stringOption(["--body", "-b"])
        for (idx, e) in entries.enumerated() {
            let method = e["method"] as? String ?? "GET"
            let url = e["url"] as? String ?? ""
            let status = e["status"] as? Int ?? 0
            let duration = e["durationMs"] as? Double ?? 0
            let isError = (e["isError"] as? Bool) ?? (status >= 400 || status == 0)
            let mark = isError ? "❌" : "✓"
            let body = e["body"] as? String
            emitOutput("\(mark) [\(status)] \(method) \(url) (\(String(format: "%.1f", duration))ms)")
            if showBody {
                if let bf = bodyFilter, !bf.isEmpty {
                    if "\(idx)" == bf || url.contains(bf) {
                        if let b = body, !b.isEmpty {
                            emitOutput("  Response Body:\n\(b)\n")
                        } else {
                            emitOutput("  Response Body: (none or binary)")
                        }
                    }
                } else if let b = body, !b.isEmpty {
                    let preview = b.count > 300 ? String(b.prefix(300)) + "... [truncated, use --body <index|url> for full]" : b
                    emitOutput("  Response: \(preview)")
                }
            }
        }
        exit(0)
    }

    static func handleDownloads(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let sub = args.positionals.first?.lowercased()
        if sub == "dir" || sub == "path" {
            let resp = request(method: "GET", path: "/downloads", socketPath: socketPath, port: port)
            if let dir = resp.jsonObject?["downloadsDirectory"] as? String {
                emitOutput(dir)
            } else {
                emitOutput("~/.dino/downloads")
            }
            exit(0)
        }

        if sub == "wait" || args.boolFlag(["--wait", "-w"]) {
            let timeout = args.stringOption(["--timeout", "-t"]).flatMap(Int.init) ?? 15000
            var bodyObj: [String: Any] = ["timeoutMs": timeout]
            if let fn = args.stringOption(["--filename", "-f"]) ?? (args.positionals.count > 1 ? args.positionals[1] : nil) {
                bodyObj["filename"] = fn
            }
            let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let waitTimeoutSecs = max(5, (timeout / 1000) + 5)
            let resp = request(method: "POST", path: "/downloads/wait", body: bodyData, timeoutSeconds: waitTimeoutSecs, socketPath: socketPath, port: port)
            guard resp.statusCode == 200, let json = resp.jsonObject else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("dino downloads: \(errMsg)")
                exit(1)
            }
            if let path = json["path"] as? String {
                emitOutput("Downloaded: \(path)")
            } else {
                emitOutput("Download finished")
            }
            exit(0)
        }

        if sub == "delete" || sub == "remove" || sub == "rm" || args.boolFlag(["--delete", "-d"]) {
            let target = (args.positionals.count > 1 ? args.positionals[1] : nil) ?? args.stringOption(["--delete", "-d"])
            guard let filename = target, !filename.isEmpty else {
                emitError("dino downloads delete: filename required (e.g. 'dino downloads delete file.csv')")
                exit(1)
            }
            let bodyObj = ["filename": filename]
            let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let resp = request(method: "DELETE", path: "/downloads", body: bodyData, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("dino downloads delete: \(errMsg)")
                exit(1)
            }
            emitOutput("Deleted download: \(filename)")
            exit(0)
        }

        if sub == "last" {
            let resp = request(method: "GET", path: "/downloads/last", socketPath: socketPath, port: port)
            guard resp.statusCode == 200, let json = resp.jsonObject else {
                emitOutput("No downloads found")
                exit(0)
            }
            if args.boolFlag(["--json", "-j"]) {
                emitOutput(resp.bodyString)
                exit(0)
            }
            let filename = json["filename"] as? String ?? ""
            let path = json["path"] as? String ?? ""
            let size = json["size"] as? Int ?? 0
            emitOutput("Last download: \(filename) (\(size) bytes) at \(path)")
            exit(0)
        }

        // Default: list downloads
        let resp = request(method: "GET", path: "/downloads", socketPath: socketPath, port: port)
        guard resp.statusCode == 200, let json = resp.jsonObject else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("dino downloads: \(errMsg)")
            exit(1)
        }
        if args.boolFlag(["--json", "-j"]) {
            emitOutput(resp.bodyString)
            exit(0)
        }
        guard let items = json["downloads"] as? [[String: Any]], !items.isEmpty else {
            emitOutput("No downloads found")
            exit(0)
        }
        for item in items {
            let filename = item["filename"] as? String ?? ""
            let size = item["size"] as? Int ?? 0
            let path = item["path"] as? String ?? ""
            emitOutput("- \(filename) (\(size) bytes) -> \(path)")
        }
        exit(0)
    }

    static func handleToken(args: ParsedArgs) {
        let token = DinoAgentServer.loadOrCreateAgentToken()
        if args.boolFlag(["--header", "-H"]) {
            emitOutput("Authorization: Bearer \(token)")
        } else if args.boolFlag(["--json", "-j"]) {
            let obj: [String: Any] = [
                "token": token,
                "header": "Authorization: Bearer \(token)",
                "path": "~/.dino/agent-token"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
               let s = String(data: data, encoding: .utf8) {
                emitOutput(s)
            } else {
                emitOutput("{\"token\":\"\(token)\"}")
            }
        } else {
            emitOutput(token)
        }
        exit(0)
    }

    static func handlePlaybook(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard let sub = args.positionals.first?.lowercased() else {
            emitError("dino playbook: subcommand required (record, stop, run, replay, list, export, delete)")
            exit(1)
        }

        switch sub {
        case "record":
            var name = "playbook"
            if args.positionals.count > 1 {
                name = args.positionals[1]
            } else if let n = args.stringOption(["--name"]) {
                name = n
            }
            var bodyObj: [String: Any] = ["name": name]
            if let tabArg = args.stringOption(["--tab"]),
               let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
                bodyObj["tabId"] = tid
            }
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("dino playbook record: failed to encode request")
                exit(1)
            }
            let resp = request(method: "POST", path: "/playbook/record", body: bodyData, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "playbook record")
            emitOutput("Started recording playbook '\(name)'")
            exit(0)

        case "stop":
            let resp = request(method: "POST", path: "/playbook/stop", socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "playbook stop")
            if let json = resp.jsonObject,
               let name = json["name"] as? String,
               let count = json["actionCount"] as? Int {
                emitOutput("Stopped recording. Saved playbook '\(name)' with \(count) action(s).")
            } else {
                emitOutput("Playbook recording stopped.")
            }
            exit(0)

        case "run", "replay":
            guard args.positionals.count > 1 || args.stringOption(["--name"]) != nil else {
                emitError("dino playbook run: playbook name required (e.g. 'dino playbook run checkout')")
                exit(1)
            }
            let name = args.positionals.count > 1 ? args.positionals[1] : args.stringOption(["--name"])!
            var bodyObj: [String: Any] = ["name": name]

            var variables: [String: String] = [:]
            let varList = (args.multiOptions["--var"] ?? []) + (args.multiOptions["-V"] ?? []) + (args.multiOptions["--param"] ?? [])
            if !varList.isEmpty {
                for item in varList {
                    if let eq = item.firstIndex(of: "=") {
                        let k = String(item[..<eq]).trimmingCharacters(in: .whitespaces)
                        let v = String(item[item.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                        variables[k] = v
                    }
                }
            } else if let single = args.stringOption(["--var", "-V", "--param"]) {
                if let eq = single.firstIndex(of: "=") {
                    let k = String(single[..<eq]).trimmingCharacters(in: .whitespaces)
                    let v = String(single[single.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    variables[k] = v
                }
            }
            if !variables.isEmpty {
                bodyObj["variables"] = variables
            }

            if let tabArg = args.stringOption(["--tab"]),
               let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
                bodyObj["tabId"] = tid
            }
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("dino playbook run: failed to encode request")
                exit(1)
            }
            let resp = request(method: "POST", path: "/playbook/replay", body: bodyData, timeoutSeconds: 60, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "playbook run")
            if let json = resp.jsonObject,
               let total = json["total"] as? Int,
               let executed = json["executed"] as? Int {
                emitOutput("Replayed '\(name)': \(executed)/\(total) step(s) executed successfully (0 tokens).")
            } else {
                emitOutput("Playbook '\(name)' replayed successfully.")
            }
            exit(0)

        case "list":
            let resp = request(method: "GET", path: "/playbook/list", socketPath: socketPath, port: port)
            guard resp.statusCode == 200, let json = resp.jsonObject else {
                emitError("dino playbook list: failed to fetch playbooks")
                exit(1)
            }
            let playbooks = json["playbooks"] as? [String] ?? []
            if playbooks.isEmpty {
                emitOutput("No saved playbooks found in ~/.dino/playbooks/")
            } else {
                emitOutput("Saved Playbooks (\(playbooks.count)):")
                for pb in playbooks {
                    emitOutput("  - \(pb)")
                }
            }
            exit(0)

        case "export":
            guard args.positionals.count > 1 || args.stringOption(["--name"]) != nil else {
                emitError("dino playbook export: playbook name required (e.g. 'dino playbook export checkout')")
                exit(1)
            }
            let name = args.positionals.count > 1 ? args.positionals[1] : args.stringOption(["--name"])!
            let path = "/playbook/export?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
            let resp = request(method: "GET", path: path, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                emitError("dino playbook export: playbook '\(name)' not found")
                exit(1)
            }
            emitOutput(resp.bodyString)
            exit(0)

        case "delete", "rm":
            guard args.positionals.count > 1 || args.stringOption(["--name"]) != nil else {
                emitError("dino playbook delete: playbook name required (e.g. 'dino playbook delete checkout')")
                exit(1)
            }
            let name = args.positionals.count > 1 ? args.positionals[1] : args.stringOption(["--name"])!
            let path = "/playbook?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
            let resp = request(method: "DELETE", path: path, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "playbook delete")
            emitOutput("Deleted playbook '\(name)'")
            exit(0)

        default:
            emitError("dino playbook: unknown subcommand '\(sub)'. Expected record, stop, run, list, export, or delete.")
            exit(1)
        }
    }

    static func handleHitl(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let sub = args.positionals.first?.lowercased() ?? "status"
        switch sub {
        case "status":
            var query = ""
            if let tabArg = args.stringOption(["--tab"]),
               let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
                query = "?tabId=\(tid)"
            }
            let resp = request(method: "GET", path: "/hitl/status\(query)", socketPath: socketPath, port: port)
            guard resp.statusCode == 200, let json = resp.jsonObject else {
                emitError("dino hitl: failed to get HITL status")
                exit(1)
            }
            let isActive = json["isHitlActive"] as? Bool ?? false
            let challengeType = json["challengeType"] as? String ?? "none"
            let resolved = json["resolved"] as? Bool ?? true
            if isActive {
                emitOutput("HITL Guard: Security challenge ACTIVE [\(challengeType)]. Human completion required.")
            } else {
                emitOutput("HITL Guard: Normal (no challenge active, resolved=\(resolved)).")
            }
            exit(0)

        case "resolve":
            var bodyObj: [String: Any] = [:]
            if let tabArg = args.stringOption(["--tab"]),
               let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
                bodyObj["tabId"] = tid
            }
            let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let resp = request(method: "POST", path: "/hitl/resolve", body: bodyData, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "hitl resolve")
            emitOutput("HITL challenge resolved. Automation unblocked.")
            exit(0)

        default:
            emitError("dino hitl: unknown subcommand '\(sub)'. Expected 'status' or 'resolve'.")
            exit(1)
        }
    }

    static func handleRoute(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard let sub = args.positionals.first?.lowercased() else {
            emitError("dino route: subcommand required (block, mock, list, clear)")
            exit(1)
        }

        switch sub {
        case "block", "abort":
            guard args.positionals.count > 1 else {
                emitError("dino route block: pattern required (e.g. 'dino route block *://*.doubleclick.net/**')")
                exit(1)
            }
            let pattern = args.positionals[1]
            var bodyObj: [String: Any] = ["pattern": pattern, "action": "abort"]
            if let tabArg = args.stringOption(["--tab"]),
               let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
                bodyObj["tabId"] = tid
            }
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("dino route block: serialization failed")
                exit(1)
            }
            let resp = request(method: "POST", path: "/route", body: bodyData, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "route block")
            emitOutput("Blocked network pattern: \(pattern)")
            exit(0)

        case "mock":
            guard args.positionals.count > 1 else {
                emitError("dino route mock: pattern required (e.g. 'dino route mock */api/user')")
                exit(1)
            }
            let pattern = args.positionals[1]
            var bodyObj: [String: Any] = [
                "pattern": pattern,
                "action": "mock",
                "status": Int(args.stringOption(["--status"]) ?? "200") ?? 200
            ]
            if let customBody = args.stringOption(["--body"]) {
                if let data = customBody.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    bodyObj["body"] = json
                } else {
                    bodyObj["body"] = customBody
                }
            } else if args.positionals.count > 2 {
                let rest = args.positionals.dropFirst(2).joined(separator: " ")
                if let data = rest.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    bodyObj["body"] = json
                } else {
                    bodyObj["body"] = rest
                }
            }
            if let tabArg = args.stringOption(["--tab"]),
               let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
                bodyObj["tabId"] = tid
            }
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("dino route mock: serialization failed")
                exit(1)
            }
            let resp = request(method: "POST", path: "/route", body: bodyData, socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "route mock")
            emitOutput("Mocked network pattern: \(pattern)")
            exit(0)

        case "list":
            var query = ""
            if let tabArg = args.stringOption(["--tab"]),
               let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
                query = "?tabId=\(tid)"
            }
            let resp = request(method: "GET", path: "/route\(query)", socketPath: socketPath, port: port)
            guard resp.statusCode == 200, let json = resp.jsonObject else {
                emitError("dino route list: failed to fetch routes")
                exit(1)
            }
            var hasRules = false
            if let blocked = json["blockedPatterns"] as? [String], !blocked.isEmpty {
                hasRules = true
                emitOutput("Blocked Patterns (\(blocked.count)):")
                for p in blocked {
                    emitOutput("  - [BLOCK] \(p)")
                }
            }
            if let routes = json["routes"] as? [[String: Any]], !routes.isEmpty {
                hasRules = true
                emitOutput("Active Routes (\(routes.count)):")
                for r in routes {
                    let u = (r["url"] as? String) ?? "*"
                    let isBlock = r["block"] as? Bool ?? false
                    let status = (r["status"] as? Int) ?? 200
                    if isBlock {
                        emitOutput("  - [BLOCK] \(u)")
                    } else {
                        emitOutput("  - [MOCK \(status)] \(u)")
                    }
                }
            }
            if !hasRules {
                emitOutput("No active network routes configured.")
            }
            exit(0)

        case "clear":
            var query = ""
            if let tabArg = args.stringOption(["--tab"]),
               let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
                query = "?tabId=\(tid)"
            }
            let resp = request(method: "DELETE", path: "/route\(query)", socketPath: socketPath, port: port)
            _ = validateActionResponse(resp, command: "route clear")
            emitOutput("All network routes cleared.")
            exit(0)

        default:
            emitError("dino route: unknown subcommand '\(sub)'. Expected block, mock, list, or clear.")
            exit(1)
        }
    }
}

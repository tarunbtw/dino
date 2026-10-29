//
//  NomadCLIClient.swift
//  nomad
//
//  Created by tarun on 28/10/26.
//

import Foundation
import Darwin

/// First-class CLI automation client for driving Nomad from the terminal with maximum token efficiency.
/// Connects via local POSIX Unix domain socket (`~/.nomad/nomad.sock`) with automatic loopback HTTP fallback.
enum NomadCLIClient {

    // MARK: - HTTP Response Model

    struct HTTPResponse {
        let statusCode: Int
        let headers: [String: String]
        let body: Data

        var bodyString: String {
            String(data: body, encoding: .utf8) ?? ""
        }

        var jsonObject: [String: Any]? {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        }
    }

    // MARK: - Standard Unix I/O Helpers

    static func emitError(_ message: String) {
        let text = "\(message)\n"
        if let data = text.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    static func emitOutput(_ message: String) {
        let text = "\(message)\n"
        if let data = text.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }

    // MARK: - Argument Parsing

    struct ParsedArgs {
        var positionals: [String] = []
        var flags: Set<String> = []
        var options: [String: String] = [:]

        func stringOption(_ keys: [String]) -> String? {
            for k in keys {
                if let val = options[k] { return val }
            }
            return nil
        }

        func boolFlag(_ keys: [String]) -> Bool {
            for k in keys {
                if flags.contains(k) { return true }
                if let opt = options[k], opt == "true" || opt == "1" { return true }
            }
            return false
        }
    }

    private static let valueOptionKeys: Set<String> = [
        "--tab", "--target", "-t", "--selector", "-s", "--role", "-r",
        "--text", "--depth", "--mode", "--limit", "--offset", "--clip", "-c",
        "--element", "-e", "--world", "--port", "--socket", "--policy",
        "--press", "-p", "--wait", "-w", "--url", "--to-target", "--to-selector",
        "--to-x", "--to-y", "--output", "-o", "--pixels", "--modifiers", "--value",
        "--state", "--response", "--timeout"
    ]

    private static let allowedCommandOptions: [String: Set<String>] = [
        "snap": ["--json", "-j", "--all", "--viewport", "-v", "--viewportOnly", "--target", "-t", "--role", "-r", "--text", "--depth", "--limit", "--offset", "--track", "--unrestricted", "--force", "-u", "--tab", "--labeled", "-l"],
        "snapshot": ["--json", "-j", "--all", "--viewport", "-v", "--viewportOnly", "--target", "-t", "--role", "-r", "--text", "--depth", "--limit", "--offset", "--track", "--unrestricted", "--force", "-u", "--tab", "--labeled", "-l"],
        "open": ["--allow-local-files", "--local", "-l", "--wait", "-w", "--tab"],
        "nav": ["--allow-local-files", "--local", "-l", "--wait", "-w", "--tab"],
        "navigate": ["--allow-local-files", "--local", "-l", "--wait", "-w", "--tab"],
        "back": ["--wait", "-w", "--tab"],
        "forward": ["--wait", "-w", "--tab"],
        "reload": ["--wait", "-w", "--tab"],
        "click": ["--native", "--right", "-r", "--middle", "--double", "--wait", "-w", "--tab"],
        "dblclick": ["--native", "--wait", "-w", "--tab"],
        "double-click": ["--native", "--wait", "-w", "--tab"],
        "type": ["--press", "-p", "--submit", "--clear", "--native", "--wait", "-w", "--tab"],
        "press": ["--native", "--modifiers", "--wait", "-w", "--tab"],
        "drag": ["--native", "--to-target", "--to-selector", "--to-x", "--to-y", "--wait", "-w", "--tab"],
        "hover": ["--tab"],
        "select": ["--text", "--value", "--wait", "-w", "--tab"],
        "scroll": ["--up", "--down", "--left", "--right", "--top", "--bottom", "--pixels", "--tab"],
        "wait": ["--mode", "-m", "--duration", "--timeout", "--selector", "-s", "--target", "-t", "--url", "--text", "--state", "--tab"],
        "find": ["--role", "-r", "--text", "--selector", "-s", "--viewport", "-v", "--viewportOnly", "--ref-only", "--tab"],
        "dialog": ["--policy", "--response", "--tab"],
        "ext": ["--tab"],
        "extensions": ["--tab"],
        "tab": ["--close", "--new", "--switch", "--wait", "-w", "--incognito"],
        "tabs": ["--close", "--new", "--switch", "--wait", "-w", "--incognito"],
        "eval": ["--world", "--tab"],
        "evaluate": ["--world", "--tab"],
        "shot": ["--clip", "-c", "--element", "-e", "--labeled", "-l", "--output", "-o", "--tab"],
        "screenshot": ["--clip", "-c", "--element", "-e", "--labeled", "-l", "--output", "-o", "--tab"],
        "upload": ["--tab"],
        "storage": ["--tab", "--json", "-j"],
        "console": ["--tab", "--level", "-l", "--clear", "-c", "--json", "-j"],
        "network": ["--tab", "--filter", "-f", "--clear", "-c", "--json", "-j"],
        "downloads": ["--wait", "-w", "--timeout", "-t", "--delete", "-d", "--clear", "--json", "-j"]
    ]

    private static func valueOptionKeys(for command: String) -> Set<String> {
        let cmd = command.lowercased()
        switch cmd {
        case "click", "dblclick", "double-click":
            return ["--tab", "--wait", "-w", "--port", "--socket"]
        case "snap", "snapshot":
            return ["--tab", "--target", "-t", "--role", "-r", "--text", "--depth", "--limit", "--offset", "--port", "--socket"]
        case "find":
            return ["--tab", "--role", "-r", "--text", "--selector", "-s", "--port", "--socket"]
        case "open", "nav", "navigate":
            return ["--tab", "--wait", "-w", "--port", "--socket"]
        case "back", "forward", "reload":
            return ["--tab", "--wait", "-w", "--port", "--socket"]
        case "type":
            return ["--press", "-p", "--tab", "--wait", "-w", "--port", "--socket"]
        case "press":
            return ["--tab", "--modifiers", "--wait", "-w", "--port", "--socket"]
        case "drag":
            return ["--to-target", "--to-selector", "--to-x", "--to-y", "--tab", "--wait", "-w", "--port", "--socket"]
        case "select":
            return ["--text", "--value", "--tab", "--wait", "-w", "--port", "--socket"]
        case "scroll":
            return ["--pixels", "--tab", "--port", "--socket"]
        case "wait":
            return ["--mode", "-m", "--duration", "--timeout", "--selector", "-s", "--target", "-t", "--url", "--text", "--state", "--tab", "--port", "--socket"]
        case "dialog":
            return ["--policy", "--response", "--tab", "--port", "--socket"]
        case "eval", "evaluate":
            return ["--world", "--tab", "--port", "--socket"]
        case "shot", "screenshot":
            return ["--clip", "-c", "--element", "-e", "--output", "-o", "--tab", "--port", "--socket"]
        case "console":
            return ["--tab", "--level", "-l", "--port", "--socket"]
        case "network":
            return ["--tab", "--filter", "-f", "--port", "--socket"]
        case "downloads", "download":
            return ["--timeout", "-t", "--delete", "-d", "--wait", "-w", "--port", "--socket"]
        case "storage":
            return ["--tab", "--port", "--socket"]
        default:
            return valueOptionKeys
        }
    }

    private static func parseArguments(_ args: [String], command: String = "") -> ParsedArgs {
        var parsed = ParsedArgs()
        var i = 0
        let activeValueKeys = valueOptionKeys(for: command)

        while i < args.count {
            let token = args[i]

            if token.hasPrefix("--") || token.hasPrefix("-") {
                if let eqIdx = token.firstIndex(of: "=") {
                    let key = String(token[..<eqIdx])
                    let val = String(token[token.index(after: eqIdx)...])
                    parsed.options[key] = val
                    i += 1
                    continue
                }

                if activeValueKeys.contains(token) {
                    if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                        parsed.options[token] = args[i + 1]
                        i += 2
                        continue
                    }
                }

                parsed.flags.insert(token)
                i += 1
            } else {
                parsed.positionals.append(token)
                i += 1
            }
        }

        return parsed
    }

    // MARK: - IPC Transport (Unix Socket with Loopback HTTP Fallback)

    static func request(
        method: String,
        path: String,
        body: Data? = nil,
        timeoutSeconds: Int = 15,
        socketPath: String? = nil,
        port: UInt16? = nil
    ) -> HTTPResponse {
        let sock = socketPath ?? NomadUnixSocketBridge.defaultSocketPath
        if let resp = sendUnixSocketRequest(method: method, path: path, body: body, socketPath: sock, timeoutSeconds: timeoutSeconds) {
            return resp
        }

        let p = port ?? NomadAgentServer.defaultPort
        if let resp = sendHTTPRequest(method: method, path: path, body: body, port: p, timeoutSeconds: timeoutSeconds) {
            return resp
        }

        emitError("nomad: Nomad is not running. Start it with 'nomad start' or 'nomad headless'")
        exit(1)
    }

    static func sendUnixSocketRequest(
        method: String,
        path: String,
        body: Data?,
        socketPath: String,
        timeoutSeconds: Int
    ) -> HTTPResponse? {
        let resolved = NomadUnixSocketBridge.resolvePath(socketPath)
        guard FileManager.default.fileExists(atPath: resolved) else { return nil }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var sockBufSize: Int32 = 1024 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &sockBufSize, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sockBufSize, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path) - 1

        resolved.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                memset(raw, 0, maxPathLen + 1)
                strncpy(raw, cstr, maxPathLen)
            }
        }
        let pathLen = min(resolved.utf8.count, maxPathLen)
        let sunLen = UInt8(2 + pathLen)
        addr.sun_len = sunLen
        let sockLen = socklen_t(sunLen)

        let connRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(fd, saPtr, sockLen)
            }
        }
        guard connRes == 0 else { return nil }

        let bodyData = body ?? Data()
        var reqHeader = "\(method) \(path) HTTP/1.1\r\n"
        reqHeader += "Host: localhost\r\n"
        reqHeader += "Content-Type: application/json\r\n"
        reqHeader += "Content-Length: \(bodyData.count)\r\n"
        reqHeader += "Connection: close\r\n\r\n"

        var reqData = Data(reqHeader.utf8)
        reqData.append(bodyData)

        let writeOk = reqData.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            var written = 0
            while written < reqData.count {
                let w = Darwin.write(fd, base + written, reqData.count - written)
                if w > 0 {
                    written += w
                } else if w < 0 {
                    if errno == EINTR { continue }
                    return false
                } else {
                    return false
                }
            }
            return true
        }
        guard writeOk else { return nil }

        var respData = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        var expectedTotalBytes: Int? = nil

        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n > 0 {
                respData.append(buf, count: n)
                if expectedTotalBytes == nil, let headerEndRange = respData.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = respData.subdata(in: 0..<headerEndRange.lowerBound)
                    if let headerStr = String(data: headerData, encoding: .utf8) {
                        for line in headerStr.components(separatedBy: "\r\n") {
                            let lower = line.lowercased()
                            if lower.hasPrefix("content-length:") {
                                let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                                if let len = Int(valStr) {
                                    expectedTotalBytes = headerEndRange.upperBound + len
                                }
                                break
                            }
                        }
                    }
                }
                if let exp = expectedTotalBytes, respData.count >= exp {
                    break
                }
            } else if n == 0 {
                break
            } else {
                if errno == EINTR { continue }
                break
            }
        }

        guard !respData.isEmpty else { return nil }
        return parseHTTPResponse(data: respData)
    }

    private static func sendHTTPRequest(
        method: String,
        path: String,
        body: Data?,
        port: UInt16,
        timeoutSeconds: Int
    ) -> HTTPResponse? {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeoutSeconds)
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let token = NomadAgentServer.loadOrCreateAgentToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let semaphore = DispatchSemaphore(value: 0)
        var parsedResp: HTTPResponse? = nil

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse, let data = data else {
                return
            }
            var headers: [String: String] = [:]
            for (k, v) in httpResponse.allHeaderFields {
                if let ks = k as? String, let vs = v as? String {
                    headers[ks.lowercased()] = vs
                }
            }
            parsedResp = HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds + 2))
        return parsedResp
    }

    private static func parseHTTPResponse(data: Data) -> HTTPResponse? {
        guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let headerData = data.subdata(in: 0..<headerEndRange.lowerBound)
        let bodyData = data.subdata(in: headerEndRange.upperBound..<data.count)

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return nil }
        let statusParts = statusLine.components(separatedBy: " ")
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        return HTTPResponse(statusCode: statusCode, headers: headers, body: bodyData)
    }

    // MARK: - Tab ID Resolver

    /// Resolves a tab identifier or 1-based index to a target UUID string.
    private static func resolveTabId(_ raw: String?, port: UInt16?, socketPath: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // If it's already a full UUID string, use directly
        if UUID(uuidString: raw) != nil {
            return raw
        }

        // Check if it's an integer index (1-based) or prefix
        let resp = request(method: "GET", path: "/tabs", socketPath: socketPath, port: port)
        guard let json = resp.jsonObject, let tabs = json["tabs"] as? [[String: Any]] else {
            return raw
        }

        if let idx = Int(raw), idx >= 1, idx <= tabs.count {
            return tabs[idx - 1]["id"] as? String ?? raw
        }

        if let matching = tabs.first(where: { ($0["id"] as? String)?.lowercased().hasPrefix(raw.lowercased()) == true }) {
            return matching["id"] as? String ?? raw
        }

        return raw
    }

    // MARK: - Main Command Dispatcher

    @discardableResult
    static func execute(command: String, rawArgs: [String], port: UInt16?, socketPath: String?) -> Bool {
        let args = parseArguments(rawArgs, command: command)
        let activePort = args.stringOption(["--port"]).flatMap(UInt16.init) ?? port
        let activeSocket = args.stringOption(["--socket"]) ?? socketPath

        if args.boolFlag(["--help", "-h"]) {
            showCommandHelp(command.lowercased())
            exit(0)
        }

        if let allowed = allowedCommandOptions[command.lowercased()] {
            var valid = allowed
            valid.formUnion(["--port", "--socket", "--help", "-h"])
            for f in args.flags {
                if !valid.contains(f) {
                    emitError("nomad \(command): unknown option '\(f)'")
                    exit(1)
                }
            }
            for opt in args.options.keys {
                if !valid.contains(opt) {
                    emitError("nomad \(command): unknown option '\(opt)'")
                    exit(1)
                }
            }
        }

        switch command.lowercased() {
        case "snap", "snapshot":
            handleSnap(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "open", "nav", "navigate":
            handleOpen(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "back":
            handleNavAction("back", args: args, port: activePort, socketPath: activeSocket)
            return true

        case "forward":
            handleNavAction("forward", args: args, port: activePort, socketPath: activeSocket)
            return true

        case "reload":
            handleNavAction("reload", args: args, port: activePort, socketPath: activeSocket)
            return true

        case "click":
            handleClick(args: args, port: activePort, socketPath: activeSocket, isDouble: false)
            return true

        case "dblclick", "double-click":
            handleClick(args: args, port: activePort, socketPath: activeSocket, isDouble: true)
            return true

        case "type":
            handleType(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "press":
            handlePress(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "drag":
            handleDrag(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "hover":
            handleHover(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "select":
            handleSelect(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "scroll":
            handleScroll(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "wait":
            handleWait(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "find":
            handleFind(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "dialog":
            handleDialog(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "tabs", "tab":
            handleTabs(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "eval", "evaluate":
            handleEval(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "shot", "screenshot":
            handleShot(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "upload":
            handleUpload(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "ext", "extensions":
            handleExtensions(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "storage":
            handleStorage(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "console":
            handleConsole(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "network":
            handleNetwork(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "downloads", "download":
            handleDownloads(args: args, port: activePort, socketPath: activeSocket)
            return true

        default:
            return false
        }
    }

    static func showCommandHelp(_ cmd: String) {
        switch cmd {
        case "snap", "snapshot":
            emitOutput("""
            Usage: nomad snap [options]

            Capture an accessibility tree snapshot of the active page.

            Options:
              -v, --viewport           Limit snapshot to currently visible viewport
              --all                    Capture full DOM tree (overrides viewport filter)
              -r, --role <role>        Filter elements by accessibility role (e.g. link, button, textbox)
              --text <query>           Filter elements containing text (case-insensitive substring)
              -t, --target <ref|sel>   Scope snapshot to a subtree rooted at an element ref or selector
              --depth <n>              Limit traversal depth relative to target root
              --limit <n>              Maximum elements to return (default: 50)
              --offset <n>             Starting index offset for element pagination
              --track                  Track element mutations across snapshots (tags [NEW] and returns +/- counts)
              -u, --unrestricted       Bypass 250-element limit in JSON mode
              -j, --json               Output raw JSON AST instead of markdown accessibility text
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "open", "nav", "navigate":
            emitOutput("""
            Usage: nomad open <url> [options]

            Navigate the active or specified tab to a URL.

            Arguments:
              <url>                    Target URL or domain (e.g. https://example.com)

            Options:
              -w, --wait [mode]        Wait after navigation (auto, networkidle, domcontentloaded, load)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "back", "forward", "reload":
            emitOutput("""
            Usage: nomad \(cmd) [options]

            Navigate browser history or reload the tab.

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "click":
            emitOutput("""
            Usage: nomad click <ref|selector> [options]

            Click on an element using its snapshot reference or CSS selector.

            Arguments:
              <ref|selector>           Element reference (e.g. e5, f0:e2) or CSS selector

            Options:
              --right, -r              Trigger context menu / right-click
              --native                 Dispatch native hardware events via macOS CGEvent
              -w, --wait [mode]        Wait after click (auto, networkidle, domcontentloaded, load)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "type":
            emitOutput("""
            Usage: nomad type <ref|selector> <text> [options]

            Type text into an input field or contenteditable element.

            Arguments:
              <ref|selector>           Element reference (e.g. e3) or CSS selector
              <text>                   Text string to type

            Options:
              --submit                 Submit the enclosing form after typing
              -p, --press <key>        Press a key chord after typing (e.g. Enter, Tab, Escape)
              --clear                  Clear existing input before typing
              --native                 Dispatch native hardware events via macOS CGEvent
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "press":
            emitOutput("""
            Usage: nomad press <key> [options]

            Send a keyboard key press or key chord to the active page.

            Arguments:
              <key>                    Key or chord (e.g. Enter, Escape, Tab, Backspace, Meta+A, Control+C)

            Options:
              --native                 Dispatch native hardware events via macOS CGEvent
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "drag":
            emitOutput("""
            Usage: nomad drag <source-ref> <dest-ref> [options]

            Drag an element to a destination element.

            Arguments:
              <source-ref>             Source element reference (e.g. e2)
              <dest-ref>               Destination element reference (e.g. e8)

            Options:
              --native                 Dispatch native hardware events via macOS CGEvent
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "hover":
            emitOutput("""
            Usage: nomad hover <ref|selector> [options]

            Hover the mouse cursor over an element.

            Arguments:
              <ref|selector>           Element reference (e.g. e5) or CSS selector

            Options:
              --native                 Dispatch native hardware events via macOS CGEvent (default: true)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "select":
            emitOutput("""
            Usage: nomad select <ref|selector> <value> [options]

            Select an option in a dropdown element.

            Arguments:
              <ref|selector>           Element reference (e.g. e4) or CSS selector
              <value>                  Option value or visible text to select

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "scroll":
            emitOutput("""
            Usage: nomad scroll [direction] [amount] [options]

            Scroll the page in a given direction.

            Arguments:
              [direction]              Scroll direction: down, up, left, right (default: down)
              [amount]                 Scroll distance in pixels (default: 300)

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "wait":
            emitOutput("""
            Usage: nomad wait [timeoutMs] [options]

            Wait for page settlement, selector, URL pattern, or timeout.

            Arguments:
              [timeoutMs]              Timeout in milliseconds (default: 5000)

            Options:
              --mode <mode>            Wait mode: auto, selector, text, state, networkidle, stability
              -s, --selector <sel>     CSS selector to wait for (when --mode selector)
              --text <query>           Wait for text substring to appear in element or document
              --state <state>          Wait for element state: visible, hidden, enabled, disabled, checked, focused
              --url <pattern>          URL substring to wait for (when --mode url)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "tabs", "tab":
            emitOutput("""
            Usage: nomad tabs [subcommand] [args] [options]

            Inspect and manage browser tabs.

            Subcommands:
              (no args)                List open tabs with IDs, titles, and URLs
              new [url]                Open a new tab (optionally navigating to URL)
              close [id|idx]           Close a tab by index or ID (default: active tab)
              focus <id|idx>           Switch active focus to a tab (alias: switch)
            """)

        case "eval", "evaluate":
            emitOutput("""
            Usage: nomad eval <expression> [options]

            Execute JavaScript expression in page context.

            Arguments:
              <expression>             JavaScript expression to evaluate

            Options:
              --world <isolated|page>  Execution world: isolated (default) or page
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "shot", "screenshot":
            emitOutput("""
            Usage: nomad shot [filepath] [options]

            Capture a PNG screenshot of the page or an element.

            Arguments:
              [filepath]               Output PNG path (prints base64 data URI if omitted, '-' for stdout pipe)

            Options:
              -l, --labeled            Annotate interactive elements with numbered visual badges
              -e, --element <ref|sel>  Capture only a specific element
              -c, --clip <x,y,w,h>     Capture a specific viewport bounding box
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "upload":
            emitOutput("""
            Usage: nomad upload <ref|selector> <filepath...> [options]

            Set files on a file input (<input type="file">) element.

            Arguments:
              <ref|selector>           Element reference or CSS selector
              <filepath...>            One or more file paths to upload

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "find":
            emitOutput("""
            Usage: nomad find [options]

            Fast element lookup returning target ref in minimal tokens (~15 tokens).

            Options:
              -r, --role <role>        Filter by accessibility role (e.g. button, link, textbox)
              --text <query>           Filter by visible text or value substring
              -s, --selector <sel>     Filter by CSS selector
              --ref-only               Print bare element ref only (e.g. 'e1')
              -v, --viewport           Limit search to visible viewport
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "dialog":
            emitOutput("""
            Usage: nomad dialog [action|policy] [options]

            Inspect, accept, dismiss, or configure policy for JavaScript dialogs (alert/confirm/prompt).

            Subcommands / Arguments:
              (no args)                Inspect current dialog policy, pending dialogs, and last dialog
              accept                   Accept currently pending or future dialogs
              dismiss                  Dismiss currently pending or future dialogs
              wait                     Set policy to 'wait' so dialogs remain open until explicitly resolved

            Options:
              --policy <policy>        Set dialog handling policy: accept, dismiss, wait
              --response <text>        Prompt text response string (for window.prompt)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "ext", "extensions":
            emitOutput("""
            Usage: nomad ext [subcommand] [args]

            Inspect and manage installed WebExtensions.

            Subcommands:
              (no args)                List installed extensions and their status
              toggle <id>              Toggle enabled state of an extension
              enable <id>              Enable an installed extension
              disable <id>             Disable an installed extension
            """)

        case "storage":
            emitOutput("""
            Usage: nomad storage [get|set|clear] [args] [options]

            Inspect and manage web storage (localStorage, sessionStorage) and cookies.

            Subcommands:
              get [key]                Get all storage or specific key
              set <key> <val>          Set storage key to value
              clear                    Clear all storage and cookies

            Options:
              --session                Target sessionStorage instead of localStorage
              --json, -j               Output raw JSON
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "console":
            emitOutput("""
            Usage: nomad console [level] [options]

            Inspect JavaScript console logs, warnings, and errors.

            Arguments:
              [level]                  Filter by log level (log, warn, error)

            Options:
              -l, --level <level>      Filter by log level (log, warn, error)
              -c, --clear              Clear console buffer after reading
              -j, --json               Output raw JSON entries
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "network":
            emitOutput("""
            Usage: nomad network [filter] [options]

            Inspect network requests, HTTP statuses, and timings.

            Arguments:
              [filter]                 Filter requests (errors, success, or status code e.g. 404)

            Options:
              -f, --filter <filter>    Filter requests (errors, success, or status code)
              -c, --clear              Clear network log
              -j, --json               Output raw JSON entries
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "downloads", "download":
            emitOutput("""
            Usage: nomad downloads [subcommand] [options]

            Inspect and manage downloaded files.

            Subcommands:
              (no args)                List all completed downloads
              last                     Inspect most recent download
              wait                     Wait for in-progress download to complete
              delete <file>            Delete downloaded file by filename

            Options:
              -w, --wait               Wait for next download to finish
              -t, --timeout <ms>       Wait timeout in milliseconds (default: 10000)
              -d, --delete <file>      Delete downloaded file
              -j, --json               Output raw JSON
            """)

        default:
            emitOutput("No detailed help available for command '\(cmd)'. Run 'nomad help' for all commands.")
        }
    }

    // MARK: - Subcommand Handlers

    @discardableResult
    private static func validateActionResponse(_ resp: HTTPResponse, command: String) -> [String: Any] {
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
            emitError("nomad \(command): [\(code)] \(msg)")
            exit(1)
        }

        guard let json = resp.jsonObject else {
            return [:]
        }

        if let success = json["success"] as? Bool, !success {
            let msg = (json["message"] as? String) ?? (json["error"] as? String) ?? "Action failed"
            let code = (json["code"] as? String) ?? "ACTION_FAILED"
            emitError("nomad \(command): [\(code)] \(msg)")
            exit(1)
        }

        return json
    }

    private static func handleSnap(args: ParsedArgs, port: UInt16?, socketPath: String?) {
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
            emitError("nomad snap: \(errMsg)")
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

    private static func handleOpen(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard let rawURL = args.positionals.first, !rawURL.isEmpty else {
            emitError("nomad open: URL argument is required (e.g. 'nomad open https://example.com')")
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
            emitError("nomad open: failed to serialize request payload")
            exit(1)
        }

        let resp = request(method: "POST", path: "/navigate", body: bodyData, timeoutSeconds: 30, socketPath: socketPath, port: port)
        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            let code = (resp.jsonObject?["code"] as? String) ?? "NAVIGATION_FAILED"
            emitError("nomad open: [\(code)] \(errMsg)")
            exit(1)
        }

        guard let json = resp.jsonObject else {
            emitOutput("Loaded: \(url)")
            exit(0)
        }

        if let success = json["success"] as? Bool, !success {
            let errMsg = (json["error"] as? String) ?? (json["message"] as? String) ?? "Navigation failed"
            let code = (json["code"] as? String) ?? "NAVIGATION_FAILED"
            emitError("nomad open: [\(code)] \(errMsg)")
            exit(1)
        }

        // Compound --wait support for open (e.g. nomad open https://example.com --wait auto)
        let waitMode = args.stringOption(["--wait", "-w"]) ?? (args.boolFlag(["--wait", "-w"]) ? "auto" : nil)
        if let waitArg = waitMode {
            var waitBody: [String: Any] = ["mode": waitArg]
            if let tid = resolvedTid { waitBody["tabId"] = tid }
            if let wData = try? JSONSerialization.data(withJSONObject: waitBody) {
                let waitResp = request(method: "POST", path: "/wait", body: wData, timeoutSeconds: 15, socketPath: socketPath, port: port)
                _ = validateActionResponse(waitResp, command: "wait")
            }
        }

        let finalURL = (json["navigatedTo"] as? String) ?? (json["url"] as? String) ?? url
        if let title = json["title"] as? String, !title.isEmpty {
            emitOutput("Loaded: \(finalURL) - \"\(title)\"")
        } else {
            emitOutput("Loaded: \(finalURL)")
        }
        exit(0)
    }

    private static func handleNavAction(_ action: String, args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var bodyObj: [String: Any] = ["action": action]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("nomad \(action): failed to serialize request payload")
            exit(1)
        }

        let resp = request(method: "POST", path: "/navigate", body: bodyData, timeoutSeconds: 15, socketPath: socketPath, port: port)
        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            let code = (resp.jsonObject?["code"] as? String) ?? "ACTION_FAILED"
            emitError("nomad \(action): [\(code)] \(errMsg)")
            exit(1)
        }

        if let json = resp.jsonObject, let success = json["success"] as? Bool, !success {
            let errMsg = (json["error"] as? String) ?? (json["message"] as? String) ?? "Action failed"
            let code = (json["code"] as? String) ?? "ACTION_FAILED"
            emitError("nomad \(action): [\(code)] \(errMsg)")
            exit(1)
        }

        // Compound --wait support (e.g. nomad back --wait auto or nomad reload -w)
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

    private static func handleClick(args: ParsedArgs, port: UInt16?, socketPath: String?, isDouble: Bool = false) {
        guard let ref = args.positionals.first, !ref.isEmpty else {
            emitError("nomad click: element reference is required (e.g. 'nomad click e5')")
            exit(1)
        }

        let isRight = args.boolFlag(["--right", "-r", "--context-menu"])
        let isDouble = isDouble || args.boolFlag(["--double", "-d"])
        let isNative = args.boolFlag(["--native"])
        let actionType = isRight ? "right_click" : (isDouble ? "dblclick" : "click")

        var bodyObj: [String: Any] = [
            "type": actionType,
            "elementId": ref,
            "native": isNative
        ]
        let tabArg = args.stringOption(["--tab"])
        let resolvedTid = tabArg.flatMap { resolveTabId($0, port: port, socketPath: socketPath) }
        if let tid = resolvedTid {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("nomad click: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        let json = validateActionResponse(resp, command: "click")

        // Compound --wait support (e.g. nomad click e5 --wait auto or nomad click e5 --wait)
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
            desc += " \(ref) (warning: obscured, intercepted by \(tag))"
        } else {
            desc += " \(ref)"
        }
        emitOutput(desc)
        exit(0)
    }

    private static func handleType(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard args.positionals.count >= 2 else {
            emitError("nomad type: element reference and text are required (e.g. 'nomad type e2 \"MacBook Pro\"')")
            exit(1)
        }

        let ref = args.positionals[0]
        let text = args.positionals.dropFirst().joined(separator: " ")
        let isSubmit = args.boolFlag(["--submit"])
        let isClear = args.boolFlag(["--clear"])
        let isNative = args.boolFlag(["--native"])
        let pressKey = args.stringOption(["--press", "-p"]) ?? (args.boolFlag(["--press", "-p"]) ? "Enter" : nil)

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
            emitError("nomad type: failed to encode action")
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

    private static func handlePress(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard let key = args.positionals.first, !key.isEmpty else {
            emitError("nomad press: key chord is required (e.g. 'nomad press Enter' or 'nomad press Meta+A')")
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
            emitError("nomad press: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "press")

        emitOutput("Pressed \(key)")
        exit(0)
    }

    private static func handleDrag(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard args.positionals.count >= 2 else {
            emitError("nomad drag: source and destination element references required (e.g. 'nomad drag e3 e8')")
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
            emitError("nomad drag: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "drag")

        emitOutput("Dragged \(fromRef) to \(toRef)")
        exit(0)
    }

    private static func handleHover(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard let ref = args.positionals.first, !ref.isEmpty else {
            emitError("nomad hover: element reference required (e.g. 'nomad hover e5')")
            exit(1)
        }

        let isNative = args.boolFlag(["--native"])
        var bodyObj: [String: Any] = [
            "type": "hover",
            "elementId": ref,
            "native": isNative
        ]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("nomad hover: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "hover")

        emitOutput("Hovered \(ref)")
        exit(0)
    }

    private static func handleSelect(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard args.positionals.count >= 2 else {
            emitError("nomad select: element reference and option value required (e.g. 'nomad select e4 \"US\"')")
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
            emitError("nomad select: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "select")

        emitOutput("Selected \"\(val)\" in \(ref)")
        exit(0)
    }

    private static func handleScroll(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var direction = "down"
        var amount: CGFloat = 300

        if args.positionals.count == 1 {
            if let num = Double(args.positionals[0]) {
                amount = CGFloat(num)
            } else {
                direction = args.positionals[0].lowercased()
            }
        } else if args.positionals.count >= 2 {
            direction = args.positionals[0].lowercased()
            if let num = Double(args.positionals[1]) {
                amount = CGFloat(num)
            }
        }

        var bodyObj: [String: Any] = [
            "type": "scroll",
            "direction": direction,
            "amount": amount
        ]
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            bodyObj["tabId"] = tid
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            emitError("nomad scroll: failed to encode action")
            exit(1)
        }

        let resp = request(method: "POST", path: "/action", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "scroll")

        emitOutput("Scrolled \(direction) \(Int(amount))px")
        exit(0)
    }

    private static func handleWait(args: ParsedArgs, port: UInt16?, socketPath: String?) {
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
            emitError("nomad wait: failed to encode wait payload")
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

    private static func handleFind(args: ParsedArgs, port: UInt16?, socketPath: String?) {
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
            emitError("nomad find: failed to encode find payload")
            exit(1)
        }

        let resp = request(method: "POST", path: "/find", body: bodyData, socketPath: socketPath, port: port)
        if resp.statusCode == 404 {
            emitError("nomad find: element not found")
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

    private static func handleDialog(args: ParsedArgs, port: UInt16?, socketPath: String?) {
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

    private static func handleExtensions(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let sub = args.positionals.first?.lowercased()
        if sub == "enable" || sub == "disable" || sub == "toggle" {
            guard args.positionals.count > 1 else {
                emitError("nomad ext \(sub ?? ""): missing extension id")
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

    private static func handleTabs(args: ParsedArgs, port: UInt16?, socketPath: String?) {
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
                emitError("nomad tab new: serialization failed")
                exit(1)
            }

            let resp = request(method: "POST", path: "/tabs/new", body: bodyData, socketPath: socketPath, port: port)
            guard resp.statusCode == 200, let json = resp.jsonObject else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("nomad tab new: \(errMsg)")
                exit(1)
            }

            let tabId = json["tabId"] as? String ?? ""
            let url = json["url"] as? String ?? ""

            // Compound --wait support (e.g. nomad tab new https://example.com --wait)
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
                emitError("nomad tab switch: tab ID or index required (e.g. 'nomad tab switch 1')")
                exit(1)
            }
            let target = args.positionals[1]
            guard let resolvedId = resolveTabId(target, port: port, socketPath: socketPath) else {
                emitError("nomad tab switch: could not resolve tab '\(target)'")
                exit(1)
            }

            let bodyObj = ["id": resolvedId]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("nomad tab switch: serialization failed")
                exit(1)
            }

            let resp = request(method: "POST", path: "/tabs/switch", body: bodyData, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("nomad tab switch: \(errMsg)")
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
                emitError("nomad tab close: no active tab to close")
                exit(1)
            }

            let bodyObj = ["id": resolvedId]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj) else {
                emitError("nomad tab close: serialization failed")
                exit(1)
            }

            let resp = request(method: "POST", path: "/tabs/close", body: bodyData, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("nomad tab close: \(errMsg)")
                exit(1)
            }

            emitOutput("Closed tab: \(resolvedId)")
            exit(0)
        }

        // Default: list all tabs in clean tabular form
        let resp = request(method: "GET", path: "/tabs", socketPath: socketPath, port: port)
        guard resp.statusCode == 200, let json = resp.jsonObject, let tabs = json["tabs"] as? [[String: Any]] else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("nomad tabs: \(errMsg)")
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

    private static func handleEval(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard !args.positionals.isEmpty else {
            emitError("nomad eval: JavaScript expression required (e.g. 'nomad eval \"document.title\"')")
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
            emitError("nomad eval: serialization failed")
            exit(1)
        }

        let resp = request(method: "POST", path: "/evaluate", body: bodyData, socketPath: socketPath, port: port)
        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("nomad eval: \(errMsg)")
            exit(1)
        }

        guard let json = resp.jsonObject else {
            emitOutput(resp.bodyString)
            exit(0)
        }

        if let success = json["success"] as? Bool, !success {
            let errMsg = (json["error"] as? String) ?? "Evaluation failed"
            let code = (json["code"] as? String) ?? "EVAL_ERROR"
            emitError("nomad eval: [\(code)] \(errMsg)")
            exit(1)
        }
        if let errMsg = json["error"] as? String {
            let code = (json["code"] as? String) ?? "EVAL_ERROR"
            emitError("nomad eval: [\(code)] \(errMsg)")
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

    private static func handleShot(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        var queryItems: [String] = []

        let isLabeled = args.boolFlag(["--labeled", "-l"])
        if isLabeled {
            queryItems.append("labeled=true")
        }
        if let el = args.stringOption(["--element", "-e"]) {
            queryItems.append("elementId=\(el)")
        }
        if let clip = args.stringOption(["--clip", "-c"]) {
            queryItems.append("clip=\(clip)")
        }
        if let tabArg = args.stringOption(["--tab"]),
           let tid = resolveTabId(tabArg, port: port, socketPath: socketPath) {
            queryItems.append("tabId=\(tid)")
        }

        let path = queryItems.isEmpty ? "/screenshot" : "/screenshot?" + queryItems.joined(separator: "&")
        let resp = request(method: "GET", path: path, timeoutSeconds: 30, socketPath: socketPath, port: port)

        guard resp.statusCode == 200 else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("nomad shot: \(errMsg)")
            exit(1)
        }

        let outTarget = args.positionals.first

        if outTarget == "-" {
            FileHandle.standardOutput.write(resp.body)
            exit(0)
        }

        let destinationPath: String
        if let custom = outTarget, !custom.isEmpty {
            destinationPath = (custom as NSString).expandingTildeInPath
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let shotDir = "\(home)/.nomad/screenshots"
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
            emitError("nomad shot: failed to write image to \(destinationPath): \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func handleUpload(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        guard args.positionals.count >= 2 else {
            emitError("nomad upload: element reference and file path(s) required (e.g. 'nomad upload e3 document.pdf')")
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
                emitError("nomad upload: file not found at path '\(fullPath)'")
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
            emitError("nomad upload: failed to encode upload payload")
            exit(1)
        }

        let resp = request(method: "POST", path: "/upload", body: bodyData, socketPath: socketPath, port: port)
        _ = validateActionResponse(resp, command: "upload")

        emitOutput("Uploaded \(resolvedPaths.count) file(s) to \(ref)")
        exit(0)
    }

    private static func handleStorage(args: ParsedArgs, port: UInt16?, socketPath: String?) {
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
                emitError("nomad storage set: requires key and value (e.g. 'nomad storage set auth_token abc')")
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

    private static func handleConsole(args: ParsedArgs, port: UInt16?, socketPath: String?) {
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
            emitError("nomad console: \(errMsg)")
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

    private static func handleNetwork(args: ParsedArgs, port: UInt16?, socketPath: String?) {
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
        let q = queryParts.isEmpty ? "" : "?" + queryParts.joined(separator: "&")
        let resp = request(method: "GET", path: "/network\(q)", socketPath: socketPath, port: port)
        guard resp.statusCode == 200, let json = resp.jsonObject else {
            let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
            emitError("nomad network: \(errMsg)")
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
        for e in entries {
            let method = e["method"] as? String ?? "GET"
            let url = e["url"] as? String ?? ""
            let status = e["status"] as? Int ?? 0
            let duration = e["durationMs"] as? Double ?? 0
            let isError = (e["isError"] as? Bool) ?? (status >= 400 || status == 0)
            let mark = isError ? "❌" : "✓"
            emitOutput("\(mark) [\(status)] \(method) \(url) (\(String(format: "%.1f", duration))ms)")
        }
        exit(0)
    }

    private static func handleDownloads(args: ParsedArgs, port: UInt16?, socketPath: String?) {
        let sub = args.positionals.first?.lowercased()
        if sub == "wait" || args.boolFlag(["--wait", "-w"]) {
            let timeout = args.stringOption(["--timeout", "-t"]).flatMap(Int.init) ?? 10000
            let bodyObj = ["timeout": timeout]
            let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let waitTimeoutSecs = max(5, (timeout / 1000) + 5)
            let resp = request(method: "POST", path: "/downloads/wait", body: bodyData, timeoutSeconds: waitTimeoutSecs, socketPath: socketPath, port: port)
            guard resp.statusCode == 200, let json = resp.jsonObject else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("nomad downloads: \(errMsg)")
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
                emitError("nomad downloads delete: filename required (e.g. 'nomad downloads delete file.csv')")
                exit(1)
            }
            let bodyObj = ["filename": filename]
            let bodyData = try? JSONSerialization.data(withJSONObject: bodyObj)
            let resp = request(method: "DELETE", path: "/downloads", body: bodyData, socketPath: socketPath, port: port)
            guard resp.statusCode == 200 else {
                let errMsg = (resp.jsonObject?["error"] as? String) ?? resp.bodyString
                emitError("nomad downloads delete: \(errMsg)")
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
            emitError("nomad downloads: \(errMsg)")
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
}

//
//  DinoCLIClient.swift
//  dino
//
//  Created by tarun on 28/10/26.
//

import Foundation
import Darwin

/// First-class CLI automation client for driving Dino from the terminal with maximum token efficiency.
/// Connects via local POSIX Unix domain socket (`~/.dino/dino.sock`) with automatic loopback HTTP fallback.
enum DinoCLIClient {

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
        var multiOptions: [String: [String]] = [:]

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

    static let valueOptionKeys: Set<String> = [
        "--tab", "--target", "-t", "--selector", "-s", "--role", "-r",
        "--text", "--depth", "--mode", "--limit", "--offset", "--clip", "-c",
        "--element", "-e", "--world", "--port", "--socket", "--policy",
        "--press", "-p", "--wait", "-w", "--url", "--to-target", "--to-selector",
        "--to-x", "--to-y", "--output", "-o", "--pixels", "--modifiers", "--value",
        "--state", "--response", "--timeout", "--name", "--coords", "--offset",
        "--offset-x", "--offset-y", "-x", "-y"
    ]

    static let allowedCommandOptions: [String: Set<String>] = [
        "snap": ["--json", "-j", "--all", "--viewport", "-v", "--viewportOnly", "--target", "-t", "--role", "-r", "--text", "--depth", "--limit", "--offset", "--track", "--unrestricted", "--force", "-u", "--tab", "--labeled", "-l", "--coords"],
        "snapshot": ["--json", "-j", "--all", "--viewport", "-v", "--viewportOnly", "--target", "-t", "--role", "-r", "--text", "--depth", "--limit", "--offset", "--track", "--unrestricted", "--force", "-u", "--tab", "--labeled", "-l", "--coords"],
        "diff": ["--json", "-j", "--viewport", "-v", "--tab"],
        "open": ["--allow-local-files", "--local", "-l", "--wait", "-w", "--tab", "--snap", "-s", "--all", "-v", "--viewport"],
        "nav": ["--allow-local-files", "--local", "-l", "--wait", "-w", "--tab", "--snap", "-s", "--all", "-v", "--viewport"],
        "navigate": ["--allow-local-files", "--local", "-l", "--wait", "-w", "--tab", "--snap", "-s", "--all", "-v", "--viewport"],
        "goto": ["--allow-local-files", "--local", "-l", "--wait", "-w", "--tab", "--snap", "-s", "--all", "-v", "--viewport"],
        "back": ["--wait", "-w", "--tab"],
        "forward": ["--wait", "-w", "--tab"],
        "reload": ["--wait", "-w", "--tab"],
        "click": ["--native", "--right", "-r", "--middle", "--double", "--wait", "-w", "--tab", "--coords", "-c", "--offset", "--offset-x", "--offset-y", "-x", "-y", "--context-menu"],
        "dblclick": ["--native", "--wait", "-w", "--tab", "--coords", "-c", "--offset", "--offset-x", "--offset-y", "-x", "-y"],
        "double-click": ["--native", "--wait", "-w", "--tab", "--coords", "-c", "--offset", "--offset-x", "--offset-y", "-x", "-y"],
        "type": ["--press", "-p", "--press-enter", "--enter", "--return", "--submit", "--clear", "--native", "--wait", "-w", "--tab"],
        "press": ["--native", "--modifiers", "--wait", "-w", "--tab"],
        "drag": ["--native", "--to-target", "--to-selector", "--to-x", "--to-y", "--wait", "-w", "--tab", "--coords", "-c"],
        "hover": ["--tab", "--native", "--coords", "-c", "--offset", "--offset-x", "--offset-y", "-x", "-y"],
        "select": ["--text", "--value", "--wait", "-w", "--tab"],
        "scroll": ["--up", "--down", "--left", "--right", "--top", "--bottom", "--pixels", "--tab", "--native", "-n", "--target", "-t", "--selector", "-s", "--to"],
        "wait": ["--mode", "-m", "--duration", "--timeout", "--selector", "-s", "--target", "-t", "--url", "--text", "--state", "--tab"],
        "find": ["--role", "-r", "--text", "--selector", "-s", "--viewport", "-v", "--viewportOnly", "--ref-only", "--tab"],
        "dialog": ["--policy", "--response", "--tab"],
        "ext": ["--tab"],
        "extensions": ["--tab"],
        "tab": ["--close", "--new", "--switch", "--wait", "-w", "--incognito"],
        "tabs": ["--close", "--new", "--switch", "--wait", "-w", "--incognito"],
        "eval": ["--world", "--tab"],
        "evaluate": ["--world", "--tab"],
        "shot": ["--clip", "-c", "--element", "-e", "--labeled", "-l", "--output", "-o", "--tab", "--crop", "--som-crop", "--scale", "--full-page", "--fullpage"],
        "screenshot": ["--clip", "-c", "--element", "-e", "--labeled", "-l", "--output", "-o", "--tab", "--crop", "--som-crop", "--scale", "--full-page", "--fullpage"],
        "pdf": ["--clip", "-c", "--output", "-o", "--tab", "--json", "-j"],
        "session": ["--tab", "--json", "-j"],
        "extract": ["--mode", "-m", "--tab", "--json", "-j"],
        "upload": ["--tab"],
        "storage": ["--tab", "--json", "-j", "--raw"],
        "console": ["--tab", "--level", "-l", "--clear", "-c", "--json", "-j"],
        "network": ["--tab", "--filter", "-f", "--body", "-b", "--clear", "-c", "--json", "-j"],
        "cookies": ["--domain", "-d", "--path", "--secure", "--all-domains", "--all", "-a", "--tab", "--json", "-j"],
        "cookie": ["--domain", "-d", "--path", "--secure", "--all-domains", "--all", "-a", "--tab", "--json", "-j"],
        "downloads": ["--wait", "-w", "--timeout", "-t", "--delete", "-d", "--clear", "--json", "-j"],
        "token": ["--header", "-H", "--json", "-j"],
        "playbook": ["--tab", "--wait", "-w", "--name", "--var", "-V", "--param"],
        "route": ["--tab", "--status", "--body", "--header", "--exact", "--method"],
        "hitl": ["--tab"]
    ]

    static func valueOptionKeys(for command: String) -> Set<String> {
        let cmd = command.lowercased()
        switch cmd {
        case "click", "dblclick", "double-click":
            return ["--tab", "--wait", "-w", "--port", "--socket", "--coords", "-c", "--offset", "--offset-coords", "--offset-x", "--offset-y", "--x", "-x", "--y", "-y"]
        case "hover":
            return ["--tab", "--wait", "-w", "--port", "--socket", "--coords", "-c", "--offset", "--offset-coords", "--offset-x", "--offset-y", "--x", "-x", "--y", "-y"]
        case "snap", "snapshot":
            return ["--tab", "--target", "-t", "--role", "-r", "--text", "--depth", "--limit", "--offset", "--port", "--socket"]
        case "diff":
            return ["--tab", "--port", "--socket"]
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
            return ["--pixels", "--tab", "--port", "--socket", "--target", "-t", "--selector", "-s", "--to"]
        case "wait":
            return ["--mode", "-m", "--duration", "--timeout", "--selector", "-s", "--target", "-t", "--url", "--text", "--state", "--tab", "--port", "--socket"]
        case "dialog":
            return ["--policy", "--response", "--tab", "--port", "--socket"]
        case "eval", "evaluate":
            return ["--world", "--tab", "--port", "--socket"]
        case "shot", "screenshot":
            return ["--clip", "-c", "--element", "-e", "--output", "-o", "--tab", "--scale", "--port", "--socket"]
        case "pdf":
            return ["--clip", "-c", "--output", "-o", "--tab", "--port", "--socket"]
        case "session":
            return ["--tab", "--port", "--socket"]
        case "extract":
            return ["--mode", "-m", "--tab", "--port", "--socket"]
        case "console":
            return ["--tab", "--level", "-l", "--port", "--socket"]
        case "network":
            return ["--tab", "--filter", "-f", "--body", "-b", "--port", "--socket"]
        case "downloads", "download":
            return ["--timeout", "-t", "--delete", "-d", "--wait", "-w", "--port", "--socket"]
        case "storage":
            return ["--tab", "--port", "--socket"]
        case "cookies", "cookie":
            return ["--tab", "--domain", "-d", "--path", "--port", "--socket"]
        case "playbook":
            return ["--name", "--tab", "--wait", "-w", "--var", "-V", "--param", "--port", "--socket"]
        case "route":
            return ["--status", "--body", "--header", "--method", "--tab", "--port", "--socket"]
        default:
            return valueOptionKeys
        }
    }

    static func parseArguments(_ args: [String], command: String = "") -> ParsedArgs {
        var parsed = ParsedArgs()
        var i = 0
        let activeValueKeys = valueOptionKeys(for: command)

        while i < args.count {
            let token = args[i]

            if (token.hasPrefix("--") || token.hasPrefix("-")) && token != "-" {
                if let eqIdx = token.firstIndex(of: "=") {
                    let key = String(token[..<eqIdx])
                    let val = String(token[token.index(after: eqIdx)...])
                    parsed.options[key] = val
                    parsed.multiOptions[key, default: []].append(val)
                    i += 1
                    continue
                }

                if activeValueKeys.contains(token) {
                    if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                        let val = args[i + 1]
                        parsed.options[token] = val
                        parsed.multiOptions[token, default: []].append(val)
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

    // MARK: - Main Command Dispatcher

    @discardableResult
    static func execute(command: String, rawArgs: [String], port: UInt16?, socketPath: String?) -> Bool {
        let args = parseArguments(rawArgs, command: command)
        let preferGUI = args.boolFlag(["--gui"])
        let preferWorker = args.boolFlag(["--worker"])
        let explicitPort = args.stringOption(["--port"]).flatMap(UInt16.init) ?? port
        let explicitSocket = args.stringOption(["--socket"]) ?? socketPath

        let target = DinoCLIManager.resolveTargetEndpoint(
            explicitPort: explicitPort,
            explicitSocket: explicitSocket,
            preferGUI: preferGUI,
            preferWorker: preferWorker
        )
        let activePort = target.port
        let activeSocket = target.socketPath

        if args.boolFlag(["--help", "-h"]) {
            showCommandHelp(command.lowercased())
            exit(0)
        }

        if let allowed = allowedCommandOptions[command.lowercased()] {
            var valid = allowed
            valid.formUnion(["--port", "--socket", "--gui", "--worker", "--help", "-h"])
            for f in args.flags {
                if !valid.contains(f) {
                    emitError("dino \(command): unknown option '\(f)'")
                    exit(1)
                }
            }
            for opt in args.options.keys {
                if !valid.contains(opt) {
                    emitError("dino \(command): unknown option '\(opt)'")
                    exit(1)
                }
            }
        }

        switch command.lowercased() {
        case "snap", "snapshot":
            handleSnap(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "diff":
            handleDiff(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "open", "nav", "navigate", "goto":
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

        case "pdf":
            handlePdf(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "session":
            handleSession(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "extract":
            handleExtract(args: args, port: activePort, socketPath: activeSocket)
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

        case "cookies", "cookie":
            handleCookies(args: args, port: activePort, socketPath: activeSocket)
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

        case "token":
            handleToken(args: args)
            return true

        case "playbook":
            handlePlaybook(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "route":
            handleRoute(args: args, port: activePort, socketPath: activeSocket)
            return true

        case "hitl":
            handleHitl(args: args, port: activePort, socketPath: activeSocket)
            return true

        default:
            return false
        }
    }

    static func showCommandHelp(_ cmd: String) {
        switch cmd {
        case "snap", "snapshot":
            emitOutput("""
            Usage: dino snap [options]

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

        case "diff":
            emitOutput("""
            Usage: dino diff [options]

            Inspect DOM mutations (added, removed, changed elements) since the previous action.

            Options:
              -v, --viewport           Limit mutation diff to visible viewport
              -j, --json               Output full structured diff JSON
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "open", "nav", "navigate":
            emitOutput("""
            Usage: dino open <url> [options]

            Navigate the active or specified tab to a URL.

            Arguments:
              <url>                    Target URL or domain (e.g. https://example.com)

            Options:
              -w, --wait [mode]        Wait after navigation (auto, networkidle, domcontentloaded, load)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "back", "forward", "reload":
            emitOutput("""
            Usage: dino \(cmd) [options]

            Navigate browser history or reload the tab.

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "click":
            emitOutput("""
            Usage: dino click <ref|selector> [options]

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
            Usage: dino type <ref|selector> <text> [options]

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
            Usage: dino press <key> [options]

            Send a keyboard key press or key chord to the active page.

            Arguments:
              <key>                    Key or chord (e.g. Enter, Escape, Tab, Backspace, Meta+A, Control+C)

            Options:
              --native                 Dispatch native hardware events via macOS CGEvent
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "drag":
            emitOutput("""
            Usage: dino drag <source-ref> <dest-ref> [options]

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
            Usage: dino hover <ref|selector> [options]

            Hover the mouse cursor over an element.

            Arguments:
              <ref|selector>           Element reference (e.g. e5) or CSS selector

            Options:
              --native                 Dispatch native hardware events via macOS CGEvent (default: true)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "select":
            emitOutput("""
            Usage: dino select <ref|selector> <value> [options]

            Select an option in a dropdown element.

            Arguments:
              <ref|selector>           Element reference (e.g. e4) or CSS selector
              <value>                  Option value or visible text to select

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "scroll":
            emitOutput("""
            Usage: dino scroll [direction] [amount] [options]

            Scroll the page in a given direction.

            Arguments:
              [direction]              Scroll direction: down, up, left, right (default: down)
              [amount]                 Scroll distance in pixels (default: 300)

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "wait":
            emitOutput("""
            Usage: dino wait [timeoutMs] [options]

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
            Usage: dino tabs [subcommand] [args] [options]

            Inspect and manage browser tabs.

            Subcommands:
              (no args)                List open tabs with IDs, titles, and URLs
              new [url]                Open a new tab (optionally navigating to URL)
              close [id|idx]           Close a tab by index or ID (default: active tab)
              focus <id|idx>           Switch active focus to a tab (alias: switch)
            """)

        case "eval", "evaluate":
            emitOutput("""
            Usage: dino eval <expression> [options]

            Execute JavaScript expression in page context.

            Arguments:
              <expression>             JavaScript expression to evaluate

            Options:
              --world <isolated|page>  Execution world: isolated (default) or page
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "shot", "screenshot":
            emitOutput("""
            Usage: dino shot [filepath] [options]

            Capture a PNG screenshot of the page or an element.

            Arguments:
              [filepath]               Output PNG path (prints to ~/.dino/screenshots if omitted, '-' for stdout pipe)

            Options:
              -l, --labeled            Annotate interactive elements with numbered visual badges
              -e, --element <ref|sel>  Capture only a specific element
              -c, --clip <x,y,w,h>     Capture a specific viewport bounding box
              --crop                   Auto-crop to active container/modal (Set-of-Marks)
              --scale <n>              Resolution scale factor (e.g. 1 for 1x logical downsampling)
              --full-page              Capture full document scrollHeight
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "pdf":
            emitOutput("""
            Usage: dino pdf [filepath] [options]

            Generate a pixel-perfect vector PDF of the current page.

            Arguments:
              [filepath]               Output PDF path (defaults to ~/.dino/pdfs/ if omitted, '-' for stdout pipe)

            Options:
              -c, --clip <x,y,w,h>     Clip PDF bounds to specific box
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "session":
            emitOutput("""
            Usage: dino session <save|restore> [name|path] [options]

            Manage portable browser session states (Playwright storageState.json format).

            Subcommands:
              save [name|path]         Export all active cookies and localStorage to session file
              restore <name|path>      Import cookies and localStorage from session file

            Options:
              -j, --json               Output raw session JSON to stdout
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "extract":
            emitOutput("""
            Usage: dino extract [selector] [options]

            Extract structured data from the page with 0 tokens using native DOM heuristics.

            Arguments:
              [selector]               Target table, container, or card list selector (e.g. 'table', '.item')

            Options:
              -m, --mode <mode>        Extraction mode: auto, table, jsonld, records (default: auto)
              -j, --json               Output formatted JSON (default: true)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "upload":
            emitOutput("""
            Usage: dino upload <ref|selector> <filepath...> [options]

            Set files on a file input (<input type="file">) element.

            Arguments:
              <ref|selector>           Element reference or CSS selector
              <filepath...>            One or more file paths to upload

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "find":
            emitOutput("""
            Usage: dino find [options]

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
            Usage: dino dialog [action|policy] [options]

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
            Usage: dino ext [subcommand] [args]

            Inspect and manage installed WebExtensions.

            Subcommands:
              (no args)                List installed extensions and their status
              toggle <id>              Toggle enabled state of an extension
              enable <id>              Enable an installed extension
              disable <id>             Disable an installed extension
            """)

        case "cookies", "cookie":
            emitOutput("""
            Usage: dino cookies [get|set|clear] [args] [options]

            Inspect and manage browser cookies.

            Commands:
              get                      List cookies for current or specified domain (default)
              set <name> <value>       Set a cookie value
              clear                    Clear cookies for domain

            Options:
              -d, --domain <domain>    Filter or target specific domain
              -a, --all-domains        Include cookies across all domains
              --path <path>            Cookie path (default: /)
              --secure                 Mark cookie as secure
              -j, --json               Output raw JSON
              --tab <id|idx>           Target specific tab by index or ID
            """)

        case "storage":
            emitOutput("""
            Usage: dino storage [get|set|clear] [args] [options]

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
            Usage: dino console [level] [options]

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
            Usage: dino network [filter] [options]

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
            Usage: dino downloads [subcommand] [options]

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

        case "token":
            emitOutput("""
            Usage: dino token [options]

            Display the agent authentication token for HTTP REST and WebSocket requests.

            Options:
              -H, --header             Output formatted HTTP Authorization header
              -j, --json               Output raw JSON with token field
            """)

        case "playbook":
            emitOutput("""
            Usage: dino playbook <subcommand> [options]

            Record and deterministically replay macros with zero LLM tokens.

            Subcommands:
              record [name]            Start recording actions into a playbook
              stop                     Stop recording and save playbook to ~/.dino/playbooks/
              run, replay <name>       Replay a saved playbook deterministically
              list                     List all saved playbooks
              export <name>            Export playbook steps as JSON
              delete, rm <name>        Delete a saved playbook

            Options:
              -V, --var, --param k=v   Substitute variables during replay (e.g. -V query="hello")
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "route":
            emitOutput("""
            Usage: dino route <subcommand> [options]

            Intercept, mock, or block network requests matching URL glob patterns.

            Subcommands:
              block <pattern>          Block network requests matching pattern (e.g. '*://*.ads.com/**')
              mock <pattern> [body]    Mock response body and status code (default: 200)
              list                     List active routing and blocking rules
              clear                    Clear all active network routes

            Options:
              --status <status>        HTTP status code for mock responses (default: 200)
              --body <body>            Mock response body (JSON string or text)
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "hitl":
            emitOutput("""
            Usage: dino hitl [subcommand] [options]

            Inspect and manage Human-in-the-Loop security challenge gates (Turnstile, reCAPTCHA, 2FA).

            Subcommands:
              status                   Check current HITL status (default)
              resolve                  Mark active challenge as resolved and unblock automation

            Options:
              --tab <id|idx>           Target specific tab by index or ID (default: active tab)
            """)

        case "start", "daemon":
            emitOutput("""
            Usage: dino start [options]

            Run Dino as a background daemon or spawn concurrent headless agent workers.

            Options:
              --profile <type>         Profile partition: agent (default), ephemeral, user
              --proxy <url>            HTTP or SOCKS5 proxy URL (e.g. http://127.0.0.1:8080)
              --idle-timeout <s>       Auto-reap idle countdown in seconds (default: 60)
              --no-reap                Disable auto-reaping idle shutdown
              --port <port>            Explicit loopback HTTP port (default: auto-allocated)
              --socket <path>          Explicit Unix domain socket path
            """)

        case "stop":
            emitOutput("""
            Usage: dino stop [options]

            Stop running Dino workers or instances.

            Options:
              --workers                Target all headless workers only (keeps GUI active)
              --gui                    Target GUI instance only
              --all                    Target all Dino instances (GUI + workers)
            """)

        case "status":
            emitOutput("""
            Usage: dino status [options]

            Check running Dino GUI and headless worker status, ports, and sockets.

            Options:
              --port <port>            Check specific port
            """)

        case "mcp":
            emitOutput("""
            Usage: dino mcp [subcommand] [options]

            Run Model Context Protocol (MCP) server over stdio for AI agents.

            Subcommands:
              (no args)                Start MCP server over stdio (JSON-RPC)
              install [target]         Auto-register in Claude Desktop, Cursor, or Windsurf
              config                   Print JSON configuration snippet for MCP registration

            Options:
              --claude                 Target Claude Desktop for install
              --cursor                 Target Cursor for install
              --windsurf               Target Windsurf for install
            """)

        default:
            emitOutput("No detailed help available for command '\(cmd)'. Run 'dino help' for all commands.")
        }
    }

}

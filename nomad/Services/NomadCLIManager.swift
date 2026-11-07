//
//  NomadCLIManager.swift
//  nomad
//
//  Created by tarun on 27/10/26.
//

import Foundation
import AppKit

/// Central CLI dispatcher and process lifecycle manager for Nomad.
/// Implements concurrent multi-instance orchestration, isolated agent profiles,
/// auto-reaping idle governance, and conflict-free daemon execution.
enum NomadCLIManager {

    private static var sigintSource: DispatchSourceSignal?
    private static var sigtermSource: DispatchSourceSignal?

    struct NomadWorkerDescriptor: Codable {
        let pid: Int32
        let port: UInt16
        let socketPath: String
        let profile: String
        let createdAt: Double
    }

    struct TargetEndpoint {
        let socketPath: String
        let port: UInt16
        let targetType: String
    }

    static var nomadDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.nomad"
    }

    static var workersDirectory: String {
        return "\(nomadDirectory)/workers"
    }

    static var guiPidFilePath: String {
        return "\(nomadDirectory)/nomad-gui.pid"
    }

    static var legacyPidFilePath: String {
        return "\(nomadDirectory)/nomad.pid"
    }

    static var pidFilePath: String {
        return legacyPidFilePath
    }

    static var logFilePath: String {
        return "\(nomadDirectory)/nomad.log"
    }

    static func ensureNomadDirectory() {
        let dir = nomadDirectory
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])
        let wDir = workersDirectory
        try? FileManager.default.createDirectory(atPath: wDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])
    }

    static func workerDescriptorPath(for pid: pid_t) -> String {
        return "\(workersDirectory)/worker-\(pid).json"
    }

    static func workerSocketPath(for pid: pid_t) -> String {
        return "\(workersDirectory)/worker-\(pid).sock"
    }

    /// Records an active headless worker descriptor to disk.
    static func recordWorker(pid: pid_t, port: UInt16, socketPath: String, profile: String) {
        ensureNomadDirectory()
        let desc = NomadWorkerDescriptor(
            pid: pid,
            port: port,
            socketPath: socketPath,
            profile: profile,
            createdAt: Date().timeIntervalSince1970
        )
        let path = workerDescriptorPath(for: pid)
        if let data = try? JSONEncoder().encode(desc) {
            try? data.write(to: URL(fileURLWithPath: path))
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }

    /// Scans and returns all actively running headless worker processes, purging stale records.
    static func getRunningWorkers() -> [NomadWorkerDescriptor] {
        ensureNomadDirectory()
        let dir = workersDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return []
        }
        var active: [NomadWorkerDescriptor] = []
        for file in files where file.hasSuffix(".json") && file.hasPrefix("worker-") {
            let fullPath = (dir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                  let desc = try? JSONDecoder().decode(NomadWorkerDescriptor.self, from: data) else {
                unlink(fullPath)
                continue
            }
            let res = kill(desc.pid, 0)
            if res == 0 || errno == EPERM {
                active.append(desc)
            } else if errno == ESRCH {
                unlink(fullPath)
                unlink(desc.socketPath)
            } else {
                active.append(desc)
            }
        }
        return active.sorted(by: { $0.createdAt < $1.createdAt })
    }

    /// Returns the PID of the active Nomad GUI browser if running.
    static func getRunningGUIPID() -> pid_t? {
        let path = guiPidFilePath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let res = kill(pid, 0)
        if res == 0 || errno == EPERM {
            return pid
        } else if errno == ESRCH {
            unlink(path)
            return nil
        } else {
            return pid
        }
    }

    /// Records the current process ID into ~/.nomad/nomad-gui.pid or worker registry.
    static func recordCurrentPID() {
        ensureNomadDirectory()
        let pid = getpid()
        if NomadHeadlessManager.isHeadless {
            if getRunningGUIPID() == nil {
                try? "\(pid)\n".write(toFile: legacyPidFilePath, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyPidFilePath)
            }
        } else {
            try? "\(pid)\n".write(toFile: guiPidFilePath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: guiPidFilePath)
            try? "\(pid)\n".write(toFile: legacyPidFilePath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyPidFilePath)
        }
    }

    /// Cleans up PID and socket files on process termination.
    static func cleanupOnExit() {
        let pid = getpid()
        if NomadHeadlessManager.isHeadless {
            unlink(workerDescriptorPath(for: pid))
            unlink(workerSocketPath(for: pid))
            if let legacyContent = try? String(contentsOfFile: legacyPidFilePath, encoding: .utf8),
               let legacyPid = Int32(legacyContent.trimmingCharacters(in: .whitespacesAndNewlines)),
               legacyPid == pid {
                unlink(legacyPidFilePath)
            }
        } else {
            if let guiContent = try? String(contentsOfFile: guiPidFilePath, encoding: .utf8),
               let guiPid = Int32(guiContent.trimmingCharacters(in: .whitespacesAndNewlines)),
               guiPid == pid {
                unlink(guiPidFilePath)
            }
            if let legacyContent = try? String(contentsOfFile: legacyPidFilePath, encoding: .utf8),
               let legacyPid = Int32(legacyContent.trimmingCharacters(in: .whitespacesAndNewlines)),
               legacyPid == pid {
                unlink(legacyPidFilePath)
            }
            unlink(NomadUnixSocketBridge.defaultSocketPath)
        }
    }

    /// Returns any running Nomad PID (GUI or worker) if alive.
    static func getRunningPID() -> pid_t? {
        if let gui = getRunningGUIPID() {
            return gui
        }
        let workers = getRunningWorkers()
        if let first = workers.first {
            return first.pid
        }
        let path = legacyPidFilePath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let res = kill(pid, 0)
        if res == 0 || errno == EPERM {
            return pid
        } else if errno == ESRCH {
            unlink(path)
            return nil
        } else {
            return pid
        }
    }

    /// Resolves the intended endpoint (worker vs GUI) for CLI driver commands.
    static func resolveTargetEndpoint(
        explicitPort: UInt16? = nil,
        explicitSocket: String? = nil,
        preferGUI: Bool = false,
        preferWorker: Bool = false
    ) -> TargetEndpoint {
        if let s = explicitSocket {
            let p = explicitPort ?? (s.contains("worker-") ? 9223 : NomadAgentServer.defaultPort)
            return TargetEndpoint(socketPath: s, port: p, targetType: "custom")
        }
        if let p = explicitPort {
            return TargetEndpoint(socketPath: NomadUnixSocketBridge.defaultSocketPath, port: p, targetType: "custom")
        }

        let guiPID = getRunningGUIPID()
        let workers = getRunningWorkers()

        if preferGUI {
            return TargetEndpoint(
                socketPath: NomadUnixSocketBridge.defaultSocketPath,
                port: NomadAgentServer.defaultPort,
                targetType: "gui"
            )
        }

        if preferWorker, let lastWorker = workers.last {
            return TargetEndpoint(
                socketPath: lastWorker.socketPath,
                port: lastWorker.port,
                targetType: "worker"
            )
        }

        // Default heuristic: If an isolated headless worker is active, route automation commands to worker!
        if let lastWorker = workers.last {
            return TargetEndpoint(
                socketPath: lastWorker.socketPath,
                port: lastWorker.port,
                targetType: "worker"
            )
        }

        // If no worker is active, route to the GUI browser
        if guiPID != nil {
            return TargetEndpoint(
                socketPath: NomadUnixSocketBridge.defaultSocketPath,
                port: NomadAgentServer.defaultPort,
                targetType: "gui"
            )
        }

        // Fallback default
        return TargetEndpoint(
            socketPath: NomadUnixSocketBridge.defaultSocketPath,
            port: NomadAgentServer.defaultPort,
            targetType: "default"
        )
    }

    /// Emits an error message to stderr.
    static func emitError(_ message: String) {
        let formatted = "\(message)\n"
        if let data = formatted.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    // MARK: - Main Dispatcher

    /// Inspects CommandLine arguments and executes CLI subcommands.
    /// Returns false if execution should proceed to regular AppKit / SwiftUI lifecycle (GUI or headless).
    @MainActor
    static func run() -> Bool {
        setlinebuf(stdout)
        setlinebuf(stderr)

        let rawArgs = Array(CommandLine.arguments.dropFirst())

        // 1. No arguments: launch native GUI browser (or activate existing GUI instance)
        if rawArgs.isEmpty {
            if let pid = getRunningGUIPID(), let app = NSRunningApplication(processIdentifier: pid) {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
                print("[nomad] Nomad GUI is already running (PID \(pid)). Brought window to front.")
                return true
            }
            return false
        }

        // 2. macOS LaunchServices / Finder process serial number argument
        if rawArgs.count == 1 && rawArgs[0].lowercased().hasPrefix("-psn_") {
            return false
        }

        // 3. Intercept browser automation driver subcommands (snap, click, type, etc.)
        let driverCommands: Set<String> = [
            "snap", "snapshot", "open", "nav", "navigate", "goto",
            "back", "forward", "reload", "click", "dblclick", "double-click", "type",
            "press", "drag", "hover", "select", "scroll",
            "wait", "tabs", "tab", "eval", "evaluate",
            "shot", "screenshot", "upload", "find", "dialog",
            "ext", "extensions", "storage", "console", "network",
            "downloads", "download", "token", "playbook", "hitl", "route"
        ]

        var driverCmdIndex: Int? = nil
        var scanIdx = 0
        while scanIdx < rawArgs.count {
            let tok = rawArgs[scanIdx]
            if tok == "--port" || tok == "--socket" || tok == "--profile" || tok == "--idle-timeout" {
                scanIdx += 2
                continue
            }
            if tok.hasPrefix("-") {
                scanIdx += 1
                continue
            }
            if driverCommands.contains(tok.lowercased()) {
                driverCmdIndex = scanIdx
                break
            }
            break
        }

        if let cmdIdx = driverCmdIndex {
            let cmd = rawArgs[cmdIdx].lowercased()
            var cmdArgs = rawArgs
            cmdArgs.remove(at: cmdIdx)
            return NomadCLIClient.execute(command: cmd, rawArgs: cmdArgs, port: nil, socketPath: nil)
        }

        // 4. Parse daemon options and process lifecycle subcommand tokens
        var subcommand: String? = nil
        var mcpAction: String? = nil
        var mcpTarget: String? = nil
        var configuredPort: UInt16? = nil
        var configuredSocket: String? = nil
        var configuredProfile: String? = nil
        var configuredIdleTimeout: Double? = nil
        var noReap = false
        var stopWorkersOnly = false
        var stopGUIOnly = false
        var stopAll = false
        var isDaemonChild = false
        var unrecognizedTokens: [String] = []

        var i = 0
        while i < rawArgs.count {
            let token = rawArgs[i]

            switch token {
            case "version", "--version", "-v":
                if subcommand == nil {
                    subcommand = "version"
                } else {
                    unrecognizedTokens.append(token)
                }

            case "help", "--help", "-h":
                if subcommand == nil {
                    subcommand = "help"
                } else {
                    unrecognizedTokens.append(token)
                }

            case "start", "daemon":
                if subcommand == nil {
                    subcommand = "start"
                } else {
                    unrecognizedTokens.append(token)
                }

            case "stop":
                if subcommand == nil {
                    subcommand = "stop"
                } else {
                    unrecognizedTokens.append(token)
                }

            case "status":
                if subcommand == nil {
                    subcommand = "status"
                } else {
                    unrecognizedTokens.append(token)
                }

            case "headless", "--headless":
                if subcommand == nil {
                    subcommand = "headless"
                } else {
                    unrecognizedTokens.append(token)
                }

            case "mcp", "--mcp":
                if subcommand == nil {
                    subcommand = "mcp"
                    if i + 1 < rawArgs.count {
                        let next = rawArgs[i + 1].lowercased()
                        if next == "install" || next == "config" {
                            i += 1
                            mcpAction = next
                            if i + 1 < rawArgs.count && !rawArgs[i + 1].hasPrefix("-") {
                                i += 1
                                mcpTarget = rawArgs[i]
                            }
                        }
                    }
                } else {
                    unrecognizedTokens.append(token)
                }

            case "--claude":
                mcpTarget = "claude"

            case "--cursor":
                mcpTarget = "cursor"

            case "--windsurf":
                mcpTarget = "windsurf"

            case "--daemon-child":
                isDaemonChild = true

            case "--profile":
                i += 1
                if i < rawArgs.count {
                    configuredProfile = rawArgs[i]
                } else {
                    emitError("nomad: option '--profile' requires an argument (agent, ephemeral, user)")
                    exit(1)
                }

            case "--idle-timeout":
                i += 1
                if i < rawArgs.count, let sec = Double(rawArgs[i]) {
                    configuredIdleTimeout = sec
                } else {
                    emitError("nomad: option '--idle-timeout' requires a number in seconds")
                    exit(1)
                }

            case "--no-reap":
                noReap = true

            case "--workers":
                stopWorkersOnly = true

            case "--all":
                stopAll = true

            case "--gui":
                stopGUIOnly = true

            case "--port":
                i += 1
                if i < rawArgs.count, let p = UInt16(rawArgs[i]) {
                    configuredPort = p
                    setenv("NOMAD_AGENT_PORT", rawArgs[i], 1)
                } else {
                    emitError("nomad: option '--port' requires a valid port number")
                    emitError("Run 'nomad help' for usage.")
                    exit(1)
                }

            case "--socket":
                i += 1
                if i < rawArgs.count {
                    let s = rawArgs[i]
                    configuredSocket = s
                    NomadUnixSocketBridge.configuredSocketPath = s
                    setenv("NOMAD_SOCKET_PATH", s, 1)
                } else {
                    emitError("nomad: option '--socket' requires a socket path")
                    emitError("Run 'nomad help' for usage.")
                    exit(1)
                }

            default:
                if token.hasPrefix("--port=") {
                    let val = String(token.dropFirst(7))
                    if let p = UInt16(val) {
                        configuredPort = p
                        setenv("NOMAD_AGENT_PORT", val, 1)
                    } else {
                        emitError("nomad: option '--port' requires a valid port number")
                        emitError("Run 'nomad help' for usage.")
                        exit(1)
                    }
                } else if token.hasPrefix("--socket=") {
                    let val = String(token.dropFirst(9))
                    configuredSocket = val
                    NomadUnixSocketBridge.configuredSocketPath = val
                    setenv("NOMAD_SOCKET_PATH", val, 1)
                } else if token.hasPrefix("--profile=") {
                    configuredProfile = String(token.dropFirst(10))
                } else if token.hasPrefix("--idle-timeout=") {
                    if let sec = Double(token.dropFirst(15)) {
                        configuredIdleTimeout = sec
                    } else {
                        emitError("nomad: option '--idle-timeout' requires a number in seconds")
                        exit(1)
                    }
                } else {
                    unrecognizedTokens.append(token)
                }
            }

            i += 1
        }

        // 4. Reject unrecognized tokens strictly (unless help <driver_command>)
        if let firstUnrecognized = unrecognizedTokens.first {
            if subcommand == "help", driverCommands.contains(firstUnrecognized.lowercased()) {
                NomadCLIClient.showCommandHelp(firstUnrecognized.lowercased())
                exit(0)
            }
            if firstUnrecognized.hasPrefix("-") {
                emitError("nomad: unknown option '\(firstUnrecognized)'")
            } else {
                emitError("nomad: unknown command '\(firstUnrecognized)'")
            }
            emitError("Run 'nomad help' for usage.")
            exit(1)
        }

        guard let cmd = subcommand else {
            return false
        }

        // 5. Dispatch subcommands
        switch cmd {
        case "version":
            handleVersion()
            return true

        case "help":
            handleHelp()
            return true

        case "start":
            handleStart(
                port: configuredPort,
                socket: configuredSocket,
                profile: configuredProfile,
                idleTimeout: configuredIdleTimeout,
                noReap: noReap
            )
            return true

        case "stop":
            handleStop(stopAll: stopAll, stopWorkersOnly: stopWorkersOnly, stopGUIOnly: stopGUIOnly)
            return true

        case "status":
            handleStatus(port: configuredPort)
            return true

        case "mcp":
            if mcpAction == "install" {
                NomadMCPServer.install(target: mcpTarget)
                exit(0)
            } else if mcpAction == "config" {
                NomadMCPServer.printConfig()
                exit(0)
            } else {
                NomadMCPServer.run()
                exit(0)
            }

        case "headless":
            return handleHeadless(
                isDaemonChild: isDaemonChild,
                profile: configuredProfile,
                idleTimeout: configuredIdleTimeout,
                noReap: noReap
            )

        default:
            emitError("nomad: unknown command '\(cmd)'")
            emitError("Run 'nomad help' for usage.")
            exit(1)
        }
    }

    // MARK: - Subcommand Implementations

    private static func handleVersion() {
        let version = NomadVersion.currentVersion
        let build = NomadVersion.currentBuild
        print("nomad version \(version) (build \(build))")
        exit(0)
    }

    private static func handleHelp() {
        let helpText = """
        Nomad - Native macOS browser engine and agent runtime

        Usage:
          nomad [command] [options]

        Daemon & Process Commands:
          start               Run as a background daemon in RAM (supports concurrent workers)
          stop                Stop running workers or instances (--workers, --gui, --all)
          status              Check running GUI and worker status
          headless            Run in foreground with live console logs
          mcp                 Run stdio Model Context Protocol (MCP) server
          mcp install         Auto-register MCP server in Claude Desktop, Cursor, Windsurf
          mcp config          Print JSON snippet for MCP server registration
          version             Print version information
          help                Show available commands and options

        Daemon & Worker Options:
          --profile <type>    Browser profile partition: agent (default), ephemeral, user
          --idle-timeout <s>  Worker auto-reap idle countdown in seconds (default: 60)
          --no-reap           Disable auto-reaping idle shutdown
          --port <port>       Explicit loopback HTTP port (default: auto-allocated)
          --socket <path>     Explicit Unix domain socket path
          --workers           Target all headless workers (for stop)
          --gui               Target GUI instance (for stop/snap/commands)
          --all               Target all Nomad instances (for stop)

        Browser Automation Commands (Token-Optimized Driver):
          snap [options]      Capture compact semantic markdown snapshot
          find [options]      Fast element lookup returning target ref (~15 tokens)
          open, goto <url>    Navigate active tab to URL
          click <ref>         Click element by reference (e.g. e5)
          dblclick <ref>      Double-click element by reference (or click --double)
          type <ref> <text>   Type text into input field (e.g. e2)
          press <key>         Dispatch key chord (e.g. Enter, Meta+A)
          drag <from> <to>    Drag source element to destination element
          hover <ref>         Hover over element
          select <ref> <val>  Select dropdown option by value or text
          scroll [dir] [px]   Scroll active page (default: down 300)
          wait [ms]           Wait for page stability, selector, text, or state
          dialog [action]     Inspect, accept, dismiss, or configure dialog handling
          ext [subcommand]    Inspect and manage installed WebExtensions
          tabs                List open tabs in clean tabular format
          tab new [url]       Open a new tab
          tab switch <id|idx> Switch active tab by index (1-based) or ID
          tab close [id|idx]  Close tab by index or ID (default: active)
          eval <script>       Evaluate JavaScript and print result
          shot [file]         Capture screenshot (saves PNG or '-' for stdout)
          upload <ref> <file> Stage and upload files to file input
          storage [op]        Inspect, set, or clear web storage & storageState
          console [level]     Inspect console entries (log, warn, error)
          network [filter]    Inspect HTTP/XHR network requests
          downloads [subcmd]  List or wait for active file downloads
          back, forward       Navigate history backward or forward
          reload              Reload the current page
          token [options]     Display agent authentication token (--header, --json)
          playbook <subcmd>   Record or replay macro playbooks (record, stop, run, list, export, rm, --var)
          route <subcmd>      Intercept, block, or mock network requests (block, mock, list, clear)
          hitl [subcmd]       Check or resolve Human-in-the-Loop challenges (status, resolve)

        Driver Options:
          --gui               Route action specifically to GUI window
          --worker            Route action specifically to headless worker
          --native            Dispatch native hardware events via macOS CGEvent
          --right, -r         Trigger context menu / right-click (for click)
          --submit            Press Enter after typing (for type)
          --clear             Clear input field before typing (for type)
          --json, -j          Output raw JSON AST (for snap)
          -v, --viewport      Capture viewport elements only (for snap/find)
          -t, --target <ref>  Target subtree or element ID (for snap)
          -r, --role <role>   Filter elements by ARIA role (for snap/find)
          --text <query>      Filter by text (for snap/find/wait)
          --state <state>     Filter by state (for wait: visible, enabled, checked)
          --mode <mode>       Wait mode: auto, selector, text, state, networkidle
          --tab <id|idx>      Target specific tab by index or ID
          -l, --labeled       Render element ID badges on screenshot (for shot)
          --crop              Auto-crop to active container/modal (for shot)
        """
        print(helpText)
        exit(0)
    }

    private static func handleStart(
        port: UInt16?,
        socket: String?,
        profile: String?,
        idleTimeout: Double?,
        noReap: Bool
    ) {
        ensureNomadDirectory()
        let guiPid = getRunningGUIPID()
        let selectedProfile = profile ?? "agent"

        if let gui = guiPid {
            print("[nomad] GUI instance detected (PID \(gui)). Spawning isolated headless agent worker...")
        }

        let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let proc = Process()
        proc.executableURL = execURL

        var childArgs = ["headless", "--daemon-child", "--profile", selectedProfile]
        if let p = port {
            childArgs.append(contentsOf: ["--port", "\(p)"])
        }
        if let s = socket {
            childArgs.append(contentsOf: ["--socket", s])
        }
        if noReap {
            childArgs.append("--no-reap")
        } else if let timeout = idleTimeout {
            childArgs.append(contentsOf: ["--idle-timeout", "\(timeout)"])
        }

        proc.arguments = childArgs
        proc.standardInput = FileHandle.nullDevice

        let logPath = logFilePath
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            logHandle.seekToEndOfFile()
            proc.standardOutput = logHandle
            proc.standardError = logHandle
        } else {
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
        }

        do {
            try proc.run()
            let childPid = proc.processIdentifier

            // Wait for child worker to initialize and register its descriptor
            var workerDesc: NomadWorkerDescriptor? = nil
            for _ in 0..<30 {
                usleep(50_000)
                let workers = getRunningWorkers()
                if let found = workers.first(where: { $0.pid == childPid }) {
                    workerDesc = found
                    break
                }
                if kill(childPid, 0) != 0 { break }
            }

            if kill(childPid, 0) == 0 {
                let activePort = workerDesc?.port ?? port ?? (guiPid != nil ? 9223 : NomadAgentServer.defaultPort)
                let activeSocket = workerDesc?.socketPath ?? socket ?? workerSocketPath(for: childPid)

                print("[nomad] Headless worker started (PID \(childPid), Profile: \(selectedProfile))")
                print("[nomad] HTTP: http://127.0.0.1:\(activePort)")
                print("[nomad] Socket: \(activeSocket)")
                if noReap {
                    print("[nomad] Auto-reaper: disabled")
                } else {
                    let to = idleTimeout ?? 60.0
                    print("[nomad] Auto-reaper: active (\(Int(to))s idle timeout)")
                }
                exit(0)
            } else {
                emitError("[nomad] Failed to start headless worker. Check \(logPath) for details.")
                exit(1)
            }
        } catch {
            emitError("[nomad] Error starting headless worker: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func handleStop(stopAll: Bool = false, stopWorkersOnly: Bool = false, stopGUIOnly: Bool = false) {
        let guiPid = getRunningGUIPID()
        let workers = getRunningWorkers()

        if stopGUIOnly {
            if let gui = guiPid {
                terminateProcess(gui)
                unlink(guiPidFilePath)
                unlink(NomadUnixSocketBridge.defaultSocketPath)
                print("[nomad] Nomad GUI (PID \(gui)) stopped")
            } else {
                print("[nomad] Nomad GUI is not running")
            }
            exit(0)
        }

        if stopWorkersOnly {
            if workers.isEmpty {
                print("[nomad] No headless workers running")
            } else {
                for w in workers {
                    terminateProcess(w.pid)
                    unlink(workerDescriptorPath(for: w.pid))
                    unlink(w.socketPath)
                }
                print("[nomad] Stopped \(workers.count) headless worker(s). GUI browser remains active.")
            }
            exit(0)
        }

        if stopAll {
            var stoppedCount = 0
            for w in workers {
                terminateProcess(w.pid)
                unlink(workerDescriptorPath(for: w.pid))
                unlink(w.socketPath)
                stoppedCount += 1
            }
            if let gui = guiPid {
                terminateProcess(gui)
                unlink(guiPidFilePath)
                unlink(NomadUnixSocketBridge.defaultSocketPath)
                stoppedCount += 1
                print("[nomad] Stopped all Nomad instances (GUI + \(workers.count) worker(s))")
            } else if stoppedCount > 0 {
                print("[nomad] Stopped \(stoppedCount) headless worker(s)")
            } else {
                print("[nomad] No running Nomad instances found")
            }
            unlink(legacyPidFilePath)
            exit(0)
        }

        // Default 'nomad stop':
        // If workers are running, stop workers cleanly!
        if !workers.isEmpty {
            for w in workers {
                terminateProcess(w.pid)
                unlink(workerDescriptorPath(for: w.pid))
                unlink(w.socketPath)
            }
            if let gui = guiPid {
                print("[nomad] Stopped \(workers.count) headless worker(s). Nomad GUI (PID \(gui)) is still active. Use 'nomad stop --all' to quit GUI.")
            } else {
                unlink(legacyPidFilePath)
                print("[nomad] Stopped \(workers.count) headless worker(s)")
            }
            exit(0)
        }

        // No workers running, but GUI is running
        if let gui = guiPid {
            print("[nomad] No headless workers are running. Nomad GUI is running (PID \(gui)). Run 'nomad stop --gui' or 'nomad stop --all' to quit GUI.")
            exit(0)
        }

        unlink(legacyPidFilePath)
        unlink(NomadUnixSocketBridge.defaultSocketPath)
        print("[nomad] No running Nomad instances found")
        exit(0)
    }

    private static func terminateProcess(_ pid: pid_t) {
        kill(pid, SIGTERM)
        for _ in 0..<20 {
            usleep(50_000)
            if kill(pid, 0) != 0 { return }
        }
        kill(pid, SIGKILL)
        usleep(50_000)
    }

    private static func handleStatus(port: UInt16?) {
        let guiPid = getRunningGUIPID()
        let workers = getRunningWorkers()

        if guiPid == nil && workers.isEmpty {
            print("Nomad: stopped")
            exit(0)
        }

        if let gui = guiPid {
            print("Nomad GUI: running (PID \(gui))")
            print("  HTTP: http://127.0.0.1:9222")
            print("  IPC Socket: \(NomadUnixSocketBridge.defaultSocketPath)")
        } else {
            print("Nomad GUI: stopped")
        }

        if workers.isEmpty {
            print("Headless Workers: 0 active")
        } else {
            print("Headless Workers (\(workers.count) active):")
            for w in workers {
                let age = Int(Date().timeIntervalSince1970 - w.createdAt)
                print("  - Worker \(w.pid): running (Port \(w.port), Profile: \(w.profile), Socket: \(w.socketPath), Uptime: \(age)s)")
            }
        }
        exit(0)
    }

    private static func handleHeadless(
        isDaemonChild: Bool,
        profile: String?,
        idleTimeout: Double?,
        noReap: Bool
    ) -> Bool {
        NomadHeadlessManager.isHeadless = true
        NSApplication.shared.setActivationPolicy(.accessory)

        if let profName = profile, let p = NomadProfileType(rawValue: profName) {
            NomadHeadlessManager.shared.profile = p
        } else {
            NomadHeadlessManager.shared.profile = .agent
        }

        if noReap {
            NomadHeadlessManager.shared.autoReapEnabled = false
        } else if let timeout = idleTimeout {
            NomadHeadlessManager.shared.idleTimeoutSeconds = timeout
        }

        if !isDaemonChild {
            if let guiPid = getRunningGUIPID() {
                print("[nomad] GUI instance detected (PID \(guiPid)). Running as concurrent headless worker.")
            }
        }

        recordCurrentPID()
        setupSignalHandlers()
        return false
    }

    // MARK: - Signal Handling

    private static func setupSignalHandlers() {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler {
            print("\n[nomad] Headless runtime stopped")
            cleanupOnExit()
            exit(0)
        }
        intSource.resume()
        sigintSource = intSource

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler {
            cleanupOnExit()
            exit(0)
        }
        termSource.resume()
        sigtermSource = termSource
    }

    // MARK: - HTTP Status Probe

    struct StatusProbeResult {
        let mode: String
        let tabCount: Int
        let port: Int
        let socketPath: String
    }

    static func probeStatus(port: UInt16) -> StatusProbeResult? {
        let sock = NomadUnixSocketBridge.defaultSocketPath
        if FileManager.default.fileExists(atPath: sock),
           let resp = NomadCLIClient.sendUnixSocketRequest(method: "GET", path: "/status", body: nil, socketPath: sock, timeoutSeconds: 1),
           resp.statusCode == 200, let json = resp.jsonObject {
            let mode = (json["mode"] as? String) ?? "daemon"
            let tabCount = (json["tabCount"] as? Int) ?? (json["tabsCount"] as? Int) ?? 0
            let p = (json["port"] as? Int) ?? Int(port)
            let unixSocket = json["unixSocket"] as? [String: Any]
            let socketPath = (unixSocket?["path"] as? String) ?? sock
            return StatusProbeResult(mode: mode, tabCount: tabCount, port: p, socketPath: socketPath)
        }

        guard let url = URL(string: "http://127.0.0.1:\(port)/status") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6
        if let token = ProcessInfo.processInfo.environment["NOMAD_TOKEN"] ?? (try? String(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nomad/agent-token"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: StatusProbeResult? = nil

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let mode = (json["mode"] as? String) ?? "daemon"
            let tabCount = (json["tabCount"] as? Int) ?? (json["tabsCount"] as? Int) ?? 0
            let port = (json["port"] as? Int) ?? Int(port)
            let unixSocket = json["unixSocket"] as? [String: Any]
            let socketPath = (unixSocket?["path"] as? String) ?? NomadUnixSocketBridge.defaultSocketPath
            result = StatusProbeResult(mode: mode, tabCount: tabCount, port: port, socketPath: socketPath)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 0.7)
        return result
    }
}

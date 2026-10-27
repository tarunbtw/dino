//
//  NomadCLIManager.swift
//  nomad
//
//  Created by tarun on 27/10/26.
//

import Foundation
import AppKit

/// Central CLI dispatcher and process lifecycle manager for Nomad.
/// Implements clean Go/Docker-style subcommands and flags for foreground and background execution.
enum NomadCLIManager {

    private static var sigintSource: DispatchSourceSignal?
    private static var sigtermSource: DispatchSourceSignal?

    static var pidFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.nomad/nomad.pid"
    }

    static var logFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.nomad/nomad.log"
    }

    static func ensureNomadDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.nomad"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])
    }

    /// Records the current process ID into ~/.nomad/nomad.pid.
    static func recordCurrentPID() {
        ensureNomadDirectory()
        let pid = getpid()
        let path = pidFilePath
        try? "\(pid)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// Cleans up the PID file and Unix socket on shutdown.
    static func cleanupOnExit() {
        let path = pidFilePath
        if FileManager.default.fileExists(atPath: path) {
            if let content = try? String(contentsOfFile: path, encoding: .utf8),
               let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)),
               pid == getpid() {
                unlink(path)
            }
        }
        unlink(NomadUnixSocketBridge.defaultSocketPath)
    }

    /// Returns the PID from ~/.nomad/nomad.pid if the process is currently alive.
    /// Automatically cleans up stale PID files if the process is dead.
    static func getRunningPID() -> pid_t? {
        let path = pidFilePath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        if kill(pid, 0) == 0 {
            return pid
        } else {
            unlink(path)
            return nil
        }
    }

    /// Emits an error message to stderr.
    private static func emitError(_ message: String) {
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

        // 1. No arguments: launch native GUI browser
        if rawArgs.isEmpty {
            return false
        }

        // 2. macOS LaunchServices / Finder process serial number argument
        if rawArgs.count == 1 && rawArgs[0].lowercased().hasPrefix("-psn_") {
            return false
        }

        // 3. Parse options and subcommand tokens
        var subcommand: String? = nil
        var configuredPort: UInt16? = nil
        var configuredSocket: String? = nil
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
                } else {
                    unrecognizedTokens.append(token)
                }

            case "--daemon-child":
                isDaemonChild = true

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
                } else {
                    unrecognizedTokens.append(token)
                }
            }

            i += 1
        }

        // 4. Reject unrecognized tokens strictly
        if let firstUnrecognized = unrecognizedTokens.first {
            if firstUnrecognized.hasPrefix("-") {
                emitError("nomad: unknown option '\(firstUnrecognized)'")
            } else {
                emitError("nomad: unknown command '\(firstUnrecognized)'")
            }
            emitError("Run 'nomad help' for usage.")
            exit(1)
        }

        guard let cmd = subcommand else {
            // Options were passed without a command (e.g. `nomad --port 9222`) -> run GUI with those options
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
            handleStart(port: configuredPort, socket: configuredSocket)
            return true

        case "stop":
            handleStop()
            return true

        case "status":
            handleStatus(port: configuredPort)
            return true

        case "mcp":
            NomadMCPServer.run()
            exit(0)

        case "headless":
            return handleHeadless(isDaemonChild: isDaemonChild)

        default:
            emitError("nomad: unknown command '\(cmd)'")
            emitError("Run 'nomad help' for usage.")
            exit(1)
        }
    }

    // MARK: - Subcommand Implementations

    private static func handleVersion() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        print("nomad version \(version) (build \(build))")
        exit(0)
    }

    private static func handleHelp() {
        let helpText = """
        Nomad - Native macOS browser engine and agent runtime

        Usage:
          nomad [command] [options]

        Commands:
          start         Run as a background daemon in RAM
          stop          Stop the running background daemon
          status        Check background daemon status
          headless      Run in foreground with live console logs
          mcp           Run stdio Model Context Protocol (MCP) server
          version       Print version information
          help          Show available commands and options

        Options:
          --port <port>       Set agent HTTP server port (default: 9222)
          --socket <path>     Set agent IPC Unix domain socket path
          --version, -v       Alias for 'version'
          --help, -h          Alias for 'help'
        """
        print(helpText)
        exit(0)
    }

    private static func handleStart(port: UInt16?, socket: String?) {
        ensureNomadDirectory()
        let activePort = port ?? NomadAgentServer.defaultPort
        let activeSocket = socket ?? NomadUnixSocketBridge.defaultSocketPath

        if let existingPID = getRunningPID() {
            print("[nomad] Daemon is already running (PID \(existingPID))")
            print("[nomad] HTTP: http://127.0.0.1:\(activePort)")
            print("[nomad] Socket: \(activeSocket)")
            exit(0)
        }

        let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let proc = Process()
        proc.executableURL = execURL

        var childArgs = ["headless", "--daemon-child"]
        if let p = port {
            childArgs.append(contentsOf: ["--port", "\(p)"])
        }
        if let s = socket {
            childArgs.append(contentsOf: ["--socket", s])
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
            let pid = proc.processIdentifier

            // Record initial PID
            let path = pidFilePath
            try? "\(pid)\n".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)

            // Allow child process initialization
            usleep(300_000)

            if kill(pid, 0) == 0 {
                print("[nomad] Daemon started (PID \(pid))")
                print("[nomad] HTTP: http://127.0.0.1:\(activePort)")
                print("[nomad] Socket: \(activeSocket)")
                exit(0)
            } else {
                emitError("[nomad] Failed to start daemon. Check \(logPath) for details.")
                unlink(path)
                exit(1)
            }
        } catch {
            emitError("[nomad] Error starting daemon: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func handleStop() {
        guard let pid = getRunningPID() else {
            unlink(NomadUnixSocketBridge.defaultSocketPath)
            print("[nomad] No running daemon found")
            exit(0)
        }

        // Send SIGTERM
        kill(pid, SIGTERM)

        // Wait up to 2 seconds for clean teardown
        var stopped = false
        for _ in 0..<20 {
            usleep(100_000)
            if kill(pid, 0) != 0 {
                stopped = true
                break
            }
        }

        if !stopped {
            kill(pid, SIGKILL)
            usleep(100_000)
        }

        unlink(pidFilePath)
        unlink(NomadUnixSocketBridge.defaultSocketPath)
        print("[nomad] Daemon stopped")
        exit(0)
    }

    private static func handleStatus(port: UInt16?) {
        let activePort = port ?? NomadAgentServer.defaultPort
        let pid = getRunningPID()

        let probe = probeStatus(port: activePort)

        if let probe = probe {
            let modeDesc = (probe.mode == "headless_daemon") ? "daemon" : "GUI"
            if let pid = pid {
                print("Nomad: running (mode: \(modeDesc), PID \(pid))")
            } else {
                print("Nomad: running (mode: \(modeDesc))")
            }
            print("HTTP endpoint: http://127.0.0.1:\(probe.port)")
            print("IPC socket: \(probe.socketPath)")
            print("Open tabs: \(probe.tabCount)")
            exit(0)
        }

        if let pid = pid {
            let socketPath = NomadUnixSocketBridge.defaultSocketPath
            print("Nomad: running (mode: daemon, PID \(pid))")
            print("HTTP endpoint: http://127.0.0.1:\(activePort)")
            print("IPC socket: \(socketPath)")
            exit(0)
        }

        print("Nomad: stopped")
        exit(0)
    }

    private static func handleHeadless(isDaemonChild: Bool) -> Bool {
        NomadHeadlessManager.isHeadless = true
        NSApplication.shared.setActivationPolicy(.accessory)

        if !isDaemonChild {
            if let pid = getRunningPID() {
                emitError("[nomad] Error: Another Nomad instance is already running (PID \(pid))")
                emitError("Run 'nomad stop' first.")
                exit(1)
            }
        }

        recordCurrentPID()
        setupSignalHandlers()
        return false
    }

    // MARK: - Signal Handling

    private static func setupSignalHandlers() {
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

    private struct StatusProbeResult {
        let mode: String
        let tabCount: Int
        let port: Int
        let socketPath: String
    }

    private static func probeStatus(port: UInt16) -> StatusProbeResult? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/status") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6

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

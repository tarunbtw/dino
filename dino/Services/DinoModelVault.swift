//
//  DinoModelVault.swift
//  dino
//
//  Created for Dino Browser.
//  Zero-prompt, user-private model API key vault for Google Gemini, Anthropic Claude,
//  OpenAI, and Local Ollama.
//  Stored in ~/Library/Application Support/dino/agent_vault.json with POSIX 0600 permissions
//  (user-private, encrypted at rest by FileVault).
//  Zero Keychain authorization dialogs across binary updates and ad-hoc builds.
//

import Foundation

enum DinoModelProvider: String, CaseIterable, Identifiable, Codable {
    case gemini = "gemini"
    case claude = "claude"
    case openai = "openai"
    case ollama = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .claude: return "Anthropic Claude"
        case .openai: return "OpenAI"
        case .ollama: return "Local Ollama"
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .claude: return "claude-3-5-sonnet-20241022"
        case .openai: return "gpt-4o"
        case .ollama: return "llama3.2"
        }
    }

    var availableModels: [String] {
        switch self {
        case .gemini: return ["gemini-2.5-flash", "gemini-flash-latest", "gemini-2.0-flash", "gemini-1.5-flash"]
        case .claude: return ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        case .openai: return ["gpt-4o", "gpt-4o-mini", "o1-mini", "o1-preview"]
        case .ollama: return ["llama3.2", "mistral", "qwen2.5-coder", "deepseek-r1"]
        }
    }

    var requiresAPIKey: Bool {
        self != .ollama
    }
}

final class DinoModelVault {
    static let shared = DinoModelVault()
    private var memoryCache: [DinoModelProvider: String] = [:]
    private var isLoaded: Bool = false

    private var vaultURL: URL {
        FileManager.dinoApplicationSupportDirectory.appendingPathComponent("agent_vault.json")
    }

    private init() {
        loadVault()
    }

    // MARK: - Active Selection & Preferences

    var activeProvider: DinoModelProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: "dino_agent_provider"),
               let p = DinoModelProvider(rawValue: raw) {
                return p
            }
            return .gemini
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "dino_agent_provider")
        }
    }

    var selectedModel: String {
        get {
            UserDefaults.standard.string(forKey: "dino_agent_model_\(activeProvider.rawValue)") ?? activeProvider.defaultModel
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "dino_agent_model_\(activeProvider.rawValue)")
        }
    }

    var ollamaEndpoint: String {
        get {
            UserDefaults.standard.string(forKey: "dino_ollama_endpoint") ?? "http://localhost:11434/v1"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "dino_ollama_endpoint")
        }
    }

    // MARK: - Key Storage & Retrieval (Zero-Prompt, User-Private 0600)

    func key(for provider: DinoModelProvider) -> String? {
        guard provider.requiresAPIKey else { return nil }

        // 1. Environment variable override
        switch provider {
        case .gemini:
            if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !env.isEmpty { return env }
        case .claude:
            if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty { return env }
        case .openai:
            if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty { return env }
        default:
            break
        }

        // 2. In-memory cache
        if !isLoaded {
            loadVault()
        }
        return memoryCache[provider]
    }

    func hasKey(for provider: DinoModelProvider) -> Bool {
        if !provider.requiresAPIKey { return true }
        return key(for: provider) != nil
    }

    @discardableResult
    func saveKey(_ secret: String, for provider: DinoModelProvider) -> Bool {
        let clean = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return deleteKey(for: provider)
        }

        memoryCache[provider] = clean
        persistVault()
        return true
    }

    @discardableResult
    func deleteKey(for provider: DinoModelProvider) -> Bool {
        memoryCache.removeValue(forKey: provider)
        persistVault()
        return true
    }

    func isConfigured(provider: DinoModelProvider) -> Bool {
        hasKey(for: provider)
    }

    // MARK: - Persistence (User-Private POSIX 0600)

    private func loadVault() {
        isLoaded = true
        let url = vaultURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else {
            return
        }

        for (raw, key) in dict {
            if let provider = DinoModelProvider(rawValue: raw) {
                memoryCache[provider] = key
            }
        }
    }

    private func persistVault() {
        var rawDict: [String: String] = [:]
        for (provider, key) in memoryCache {
            rawDict[provider.rawValue] = key
        }

        guard let data = try? JSONSerialization.data(withJSONObject: rawDict, options: [.prettyPrinted]) else { return }

        let url = vaultURL
        let folder = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        // Save with 0600 permissions (read/write only by user)
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [
            .posixPermissions: 0o600
        ])
    }
}

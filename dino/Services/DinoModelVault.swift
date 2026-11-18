//
//  DinoModelVault.swift
//  dino
//
//  Created for Dino Browser.
//  Hardware-backed model API key management via macOS Keychain (kSecClassGenericPassword).
//  Zero plaintext disk storage. Supports Gemini, Claude, OpenAI, and Local Ollama.
//

import Foundation
import Security

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
        case .gemini: return "gemini-1.5-pro"
        case .claude: return "claude-3-5-sonnet-20241022"
        case .openai: return "gpt-4o"
        case .ollama: return "llama3.2"
        }
    }

    var requiresAPIKey: Bool {
        self != .ollama
    }
}

final class DinoModelVault {
    static let shared = DinoModelVault()
    private static let serviceLabel = "DinoAgentModel"

    private init() {}

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

    // MARK: - Keychain CRUD

    func key(for provider: DinoModelProvider) -> String? {
        guard provider.requiresAPIKey else { return nil }

        // Also check environment variable overrides (e.g. GEMINI_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY)
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

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceLabel,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func saveKey(_ secret: String, for provider: DinoModelProvider) -> Bool {
        let clean = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let data = clean.data(using: .utf8) else {
            return deleteKey(for: provider)
        }

        // Try updating
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceLabel,
            kSecAttrAccount as String: provider.rawValue
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data
        ]

        if SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary) == errSecSuccess {
            return true
        }

        // Add fresh item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceLabel,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func deleteKey(for provider: DinoModelProvider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceLabel,
            kSecAttrAccount as String: provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func isConfigured(provider: DinoModelProvider) -> Bool {
        if provider == .ollama { return true }
        return key(for: provider) != nil
    }
}

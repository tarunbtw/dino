//
//  KeychainVault.swift
//  dino
//
//  Created by tarun on 11/10/26.
//

import Foundation
import Security
import LocalAuthentication

/// Represents a login credential stored securely in the native macOS Keychain.
struct StoredCredential: Identifiable, Equatable, Hashable {
    let host: String
    let user: String
    var lastUsed: Date?

    var id: String { "\(host):\(user)" }
}

/// Native macOS Keychain service for secure website password storage and Touch ID retrieval.
final class KeychainVault {
    static let shared = KeychainVault()
    private static let serviceLabel = "Dino"

    private init() {}

    // MARK: - Credential Queries

    /// Lists all stored credentials for a specific web host (matching domain and subdomains).
    func credentials(for host: String) -> [StoredCredential] {
        let cleanHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return allCredentials().filter { item in
            item.host == cleanHost || cleanHost.hasSuffix("." + item.host) || item.host.hasSuffix("." + cleanHost)
        }
    }

    /// Lists all stored credentials without reading password secrets.
    func allCredentials() -> [StoredCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: Self.serviceLabel,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { dict -> StoredCredential? in
            guard let server = dict[kSecAttrServer as String] as? String,
                  let account = dict[kSecAttrAccount as String] as? String else {
                return nil
            }
            let comment = dict[kSecAttrComment as String] as? String
            let date = comment.flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            return StoredCredential(host: server, user: account, lastUsed: date)
        }.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }

    /// Reads the password secret for a specific credential, prompting for Touch ID / Mac password if required.
    func readPassword(for credential: StoredCredential, prompt: String = "Access saved password for Dino") -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: Self.serviceLabel,
            kSecAttrServer as String: credential.host,
            kSecAttrAccount as String: credential.user,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let context = LAContext()
        context.localizedReason = prompt
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        updateLastUsed(credential: credential)
        return String(data: data, encoding: .utf8)
    }

    /// Saves or updates a login password in the native macOS Keychain.
    @discardableResult
    func save(host: String, user: String, secret: String) -> Bool {
        let cleanHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, !cleanUser.isEmpty, !secret.isEmpty,
              let data = secret.data(using: .utf8) else { return false }

        let now = String(Date().timeIntervalSince1970)

        // Try updating existing item
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: Self.serviceLabel,
            kSecAttrServer as String: cleanHost,
            kSecAttrAccount as String: cleanUser
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrComment as String: now
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        // Add new item if not found
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: Self.serviceLabel,
            kSecAttrServer as String: cleanHost,
            kSecAttrAccount as String: cleanUser,
            kSecValueData as String: data,
            kSecAttrComment as String: now
        ]

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Deletes a stored credential from the macOS Keychain.
    @discardableResult
    func delete(credential: StoredCredential) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: Self.serviceLabel,
            kSecAttrServer as String: credential.host,
            kSecAttrAccount as String: credential.user
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    private func updateLastUsed(credential: StoredCredential) {
        let now = String(Date().timeIntervalSince1970)
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: Self.serviceLabel,
            kSecAttrServer as String: credential.host,
            kSecAttrAccount as String: credential.user
        ]
        let attrs: [String: Any] = [
            kSecAttrComment as String: now
        ]
        _ = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    }
}


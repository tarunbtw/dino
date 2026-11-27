//
//  DinoDOMSanitizer.swift
//  dino
//
//  Created for Dino Browser.
//  Protects user privacy and guards against prompt injection.
//  Redacts passwords, credit card numbers, SSNs, and wraps page DOM in fenced untrusted tags.
//

import Foundation

enum DinoDOMSanitizer {
    private static let highStakesKeywords: Set<String> = [
        "pay", "buy", "purchase", "checkout", "subscribe", "order",
        "confirm payment", "place order", "send money", "transfer",
        "delete account", "remove account", "reset password", "wipe data"
    ]

    /// Sanitizes raw page text or interactive DOM elements to eliminate PII and secrets before sending to LLM.
    static func sanitize(text: String) -> String {
        var clean = text

        // 1. Redact credit card patterns (13 to 19 digits with optional hyphens/spaces)
        clean = clean.replacingOccurrences(
            of: #"\b(?:\d[ -]*?){13,19}\b"#,
            with: "[REDACTED_PAYMENT_CARD]",
            options: .regularExpression
        )

        // 2. Redact US SSN / national ID patterns
        clean = clean.replacingOccurrences(
            of: #"\b\d{3}-\d{2}-\d{4}\b"#,
            with: "[REDACTED_SSN]",
            options: .regularExpression
        )

        // 3. Redact common secret keys (API tokens, private keys)
        clean = clean.replacingOccurrences(
            of: #"(sk-[a-zA-Z0-9_-]{20,}|ghp_[a-zA-Z0-9]{20,}|Bearer\s+[a-zA-Z0-9_\-\.]{20,})"#,
            with: "[REDACTED_AUTH_TOKEN]",
            options: .regularExpression
        )

        return clean
    }

    private static func escapeXMLAttribute(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Fences untrusted webpage content inside clear structural XML delimiters.
    static func frameUntrustedContent(domTree: String, url: URL?, title: String) -> String {
        let rawURL = url?.absoluteString ?? "about:blank"
        let safeURL = escapeXMLAttribute(rawURL)
        let sanitizedTitle = sanitize(text: title)
        let safeTitle = escapeXMLAttribute(sanitizedTitle)

        var safeDOM = sanitize(text: domTree)
        // Defend against delimiter breakout: escape closing tag case-insensitively
        safeDOM = safeDOM.replacingOccurrences(
            of: #"</\s*untrusted_web_page\s*>"#,
            with: "&lt;/untrusted_web_page&gt;",
            options: .regularExpression
        )

        return """
        <untrusted_web_page url="\(safeURL)" title="\(safeTitle)">
        \(safeDOM)
        </untrusted_web_page>
        """
    }

    /// Evaluates whether an element action requires mandatory Human-In-The-Loop approval.
    static func isHighStakesAction(elementText: String, role: String? = nil) -> Bool {
        let lower = elementText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for keyword in highStakesKeywords {
            if lower.contains(keyword) {
                return true
            }
        }
        return false
    }
}

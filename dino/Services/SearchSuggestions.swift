//
//  SearchSuggestions.swift
//  dino
//
//  Created by tarun on 10/11/26.
//

import Foundation

public struct SearchSuggestion: Sendable, Identifiable, Equatable {
    public var id: String { text }
    public let text: String
    public let title: String?
    public let isNavigation: Bool
    public let url: URL?

    public init(text: String, title: String? = nil, isNavigation: Bool = false, url: URL? = nil) {
        self.text = text
        self.title = title
        self.isNavigation = isNavigation
        self.url = url
    }
}

/// Privacy-safe search suggestion streamer for the Omnibox.
/// Fetches autocomplete suggestions from OpenSearch endpoints without cookies, credentials, or caching.
public enum SearchSuggestions {
    public static let limit = 5
    static let longestQuery = 100
    static let longestSuggestion = 150
    static let largestReply = 64 * 1024

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = 2.0
        return URLSession(configuration: config)
    }()

    public static func mayAsk(about text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= longestQuery && !URLParser.isAddress(trimmed)
    }

    public static func fetch(_ text: String) async -> [SearchSuggestion] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mayAsk(about: query),
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=chrome&q=\(encoded)") else {
            return []
        }

        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        return parse(data, for: query)
    }

    static func parse(_ data: Data, for query: String) -> [SearchSuggestion] {
        guard data.count <= largestReply,
              let reply = try? JSONSerialization.jsonObject(with: data) as? [Any], reply.count >= 2,
              let echoed = reply[0] as? String, echoed.lowercased() == query.lowercased(),
              let lines = reply[1] as? [Any] else {
            return []
        }

        let descriptions = (reply.count > 2 ? reply[2] as? [Any] : nil) ?? []
        let extra = (reply.count > 4 ? reply[4] as? [String: Any] : nil) ?? [:]
        let suggestTypes = (extra["google:suggesttype"] as? [String]) ?? []

        var seen: Set<String> = [query.lowercased()]
        var results: [SearchSuggestion] = []

        for (i, rawLine) in lines.enumerated() {
            guard let line = rawLine as? String else { continue }
            let clean = line.unicodeScalars
                .filter { !CharacterSet.controlCharacters.contains($0) }
                .map(String.init)
                .joined()
                .trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, clean.count <= longestSuggestion,
                  seen.insert(clean.lowercased()).inserted else { continue }

            let desc = (i < descriptions.count ? descriptions[i] as? String : nil)?.trimmingCharacters(in: .whitespaces)
            let isNavType = (i < suggestTypes.count && suggestTypes[i] == "NAVIGATION")

            let isURL = isNavType || clean.hasPrefix("http://") || clean.hasPrefix("https://") || URLParser.isAddress(clean)
            let targetURL: URL?
            if isURL {
                if let direct = URL(string: clean), direct.scheme != nil, direct.host != nil {
                    targetURL = direct
                } else if URLParser.isAddress(clean) {
                    let candidate = (clean.hasPrefix("http://") || clean.hasPrefix("https://")) ? clean : "https://\(clean)"
                    targetURL = URL(string: candidate)
                } else {
                    targetURL = nil
                }
            } else {
                targetURL = nil
            }

            let item = SearchSuggestion(
                text: clean,
                title: (desc?.isEmpty == false ? desc : nil),
                isNavigation: targetURL != nil,
                url: targetURL
            )
            results.append(item)
            if results.count == limit { break }
        }

        return results
    }
}

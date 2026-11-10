//
//  SearchSuggestions.swift
//  nomad
//
//  Created by tarun on 10/11/26.
//

import Foundation

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
        return !trimmed.isEmpty && trimmed.count <= longestQuery && !AddressInput.isAddress(trimmed)
    }

    public static func fetch(_ text: String) async -> [String] {
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

    static func parse(_ data: Data, for query: String) -> [String] {
        guard data.count <= largestReply,
              let reply = try? JSONSerialization.jsonObject(with: data) as? [Any], reply.count >= 2,
              let echoed = reply[0] as? String, echoed.lowercased() == query.lowercased(),
              let lines = reply[1] as? [Any] else {
            return []
        }

        var seen: Set<String> = [query.lowercased()]
        var results: [String] = []

        for case let line as String in lines {
            let clean = line.unicodeScalars
                .filter { !CharacterSet.controlCharacters.contains($0) }
                .map(String.init)
                .joined()
                .trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, clean.count <= longestSuggestion,
                  seen.insert(clean.lowercased()).inserted else { continue }
            results.append(clean)
            if results.count == limit { break }
        }

        return results
    }
}


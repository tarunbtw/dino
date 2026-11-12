//
//  FindOnPage.swift
//  dino
//
//  Created by tarun on 10/11/26.
//

import Foundation

/// Find on page (⌘F) parameters, direction, and match count formatting.
public enum FindOnPage {
    public enum Direction: Sendable {
        case fromHere
        case next
        case previous
    }

    public static let countLimit = 1000
    public static let maxLength = 200

    public static func query(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return String(line.prefix(maxLength))
    }

    public static func label(count: Int) -> String {
        switch count {
        case ..<1:
            return "No matches"
        case 1:
            return "1 match"
        case countLimit...:
            return "\(countLimit.formatted())+ matches"
        default:
            return "\(count.formatted()) matches"
        }
    }

    /// JavaScript to count occurrences in the document body.
    public static let countScript = """
    (function(query, limit) {
        const text = document.body ? document.body.innerText.toLocaleLowerCase() : "";
        const needle = String(query).toLocaleLowerCase();
        if (!needle) return 0;
        let count = 0, at = text.indexOf(needle);
        while (at !== -1 && count < limit) {
            count++;
            at = text.indexOf(needle, at + needle.length);
        }
        return count;
    })
    """
}


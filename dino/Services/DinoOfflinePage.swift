//
//  DinoOfflinePage.swift
//  dino
//
//  Clean, minimal offline error page styled in Dino's dark palette.
//

import Foundation

enum DinoOfflinePage {
    /// Returns true if the error represents an offline, unreachable host, or network timeout condition.
    static func isOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorTimedOut,
             NSURLErrorResourceUnavailable,
             NSURLErrorCannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    /// Generates the self-contained offline page HTML for the requested URL.
    static func html(for url: URL, error: Error? = nil) -> String {
        let hostOrURL = url.host ?? url.absoluteString
        let safeHost = hostOrURL.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let rawError = error?.localizedDescription ?? "The Internet connection appears to be offline."
        let safeError = rawError.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>No Connection — Dino</title>
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
              background-color: #2B2826;
              color: #F5F1EC;
              display: flex;
              align-items: center;
              justify-content: center;
              min-height: 100vh;
              padding: 24px;
            }
            .card {
              max-width: 440px;
              text-align: center;
            }
            .icon {
              font-size: 40px;
              margin-bottom: 16px;
              opacity: 0.6;
            }
            h1 {
              font-size: 20px;
              font-weight: 600;
              margin-bottom: 8px;
            }
            p.host {
              font-size: 13px;
              color: #A0C4D6;
              margin-bottom: 6px;
              word-break: break-all;
            }
            p.error {
              font-size: 12px;
              color: #958D85;
              line-height: 1.5;
              margin-bottom: 24px;
            }
            button {
              background: rgba(245, 241, 236, 0.12);
              border: 1px solid rgba(245, 241, 236, 0.2);
              color: #F5F1EC;
              padding: 8px 20px;
              border-radius: 8px;
              font-size: 13px;
              cursor: pointer;
              transition: background 0.15s;
            }
            button:hover {
              background: rgba(245, 241, 236, 0.2);
            }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="icon">⚡️</div>
            <h1>No Internet Connection</h1>
            <p class="host">\(safeHost)</p>
            <p class="error">\(safeError)</p>
            <button onclick="location.reload()">Try Again</button>
          </div>
        </body>
        </html>
        """
    }
}

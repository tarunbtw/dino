//
//  DinoOfflinePage.swift
//  dino
//
//  Clean, minimal offline error page styled in Chromium Dark Mode.
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
              background-color: #202124;
              color: #E8EAED;
              display: flex;
              align-items: center;
              justify-content: center;
              min-height: 100vh;
              padding: 24px;
            }
            .card {
              max-width: 420px;
              width: 100%;
              background: #28292A;
              border: 1px solid rgba(255, 255, 255, 0.08);
              border-radius: 14px;
              padding: 28px 24px;
              text-align: center;
            }
            .icon {
              width: 40px;
              height: 40px;
              margin: 0 auto 16px;
              border-radius: 50%;
              background: rgba(138, 180, 248, 0.12);
              color: #8AB4F8;
              display: flex;
              align-items: center;
              justify-content: center;
            }
            h1 {
              font-size: 17px;
              font-weight: 600;
              margin-bottom: 6px;
              color: #E8EAED;
            }
            p.host {
              font-size: 13px;
              color: #8AB4F8;
              margin-bottom: 8px;
              word-break: break-all;
            }
            p.error {
              font-size: 12px;
              color: #9AA0A6;
              line-height: 1.5;
              margin-bottom: 22px;
            }
            button {
              background: #8AB4F8;
              border: none;
              color: #1F1F1F;
              font-weight: 600;
              padding: 8px 20px;
              border-radius: 8px;
              font-size: 13px;
              cursor: pointer;
              transition: background 0.15s;
            }
            button:hover {
              background: #AECBFA;
            }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <line x1="1" y1="1" x2="23" y2="23"></line>
                <path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55"></path>
                <path d="M5 12.55a10.94 10.94 0 0 1 5.17-2.39"></path>
                <path d="M10.71 5.05A16 16 0 0 1 22.58 9"></path>
                <path d="M1.42 9a15.91 15.91 0 0 1 4.7-2.88"></path>
                <path d="M8.53 16.11a6 6 0 0 1 6.95 0"></path>
                <line x1="12" y1="20" x2="12.01" y2="20"></line>
              </svg>
            </div>
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

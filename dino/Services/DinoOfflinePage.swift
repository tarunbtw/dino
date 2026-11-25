//
//  DinoOfflinePage.swift
//  dino
//
//  Minimalist, zen offline error page with tree illustration matching the Dino theme.
//

import Foundation

enum DinoOfflinePage {
    /// Returns true if the error represents an offline, unreachable host, or network timeout condition.
    static func isOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let offlineCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorTimedOut,
            NSURLErrorResourceUnavailable,
            NSURLErrorCannotLoadFromNetwork
        ]
        if offlineCodes.contains(nsError.code) {
            return true
        }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("offline") || desc.contains("internet connection") || desc.contains("server cannot be found") || desc.contains("network connection was lost") {
            return true
        }
        return false
    }

    /// Embedded clean defringed PNG of the tree illustration.
    private static let treeImageBase64: String = "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"

    /// Generates the self-contained offline page HTML for the requested URL.
    static func html(for url: URL, error: Error? = nil) -> String {
        let rawURL = url.absoluteString
        let safeURL = rawURL.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>uh oh! your internets broken — Dino</title>
          <style>
            * {
              box-sizing: border-box;
              margin: 0;
              padding: 0;
            }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
              background-color: #28292A;
              color: #E8EAED;
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              min-height: 100vh;
              padding: 32px 24px;
              user-select: none;
              -webkit-user-select: none;
              text-align: center;
              overflow: hidden;
            }
            .tree-container {
              margin-bottom: 24px;
              cursor: pointer;
            }
            .tree {
              width: 72px;
              height: auto;
              display: block;
              image-rendering: -webkit-optimize-contrast;
              transition: transform 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
            }
            .tree:hover {
              transform: scale(1.08);
            }
            .tree:active {
              transform: scale(0.96);
            }
            h1 {
              font-size: 20px;
              font-weight: 600;
              letter-spacing: -0.015em;
              color: #E8EAED;
              margin-bottom: 8px;
            }
            p.subtitle {
              font-size: 13.5px;
              font-weight: 400;
              color: #E8EAED;
              opacity: 0.50;
              margin-bottom: 8px;
            }
            p.grass {
              font-size: 13px;
              font-weight: 400;
              font-style: italic;
              color: #E8EAED;
              opacity: 0.38;
              margin-bottom: 24px;
            }
            .retry-btn {
              appearance: none;
              -webkit-appearance: none;
              background: rgba(255, 255, 255, 0.08);
              border: 1px solid rgba(255, 255, 255, 0.12);
              border-radius: 9999px;
              color: #E8EAED;
              font-size: 12.5px;
              font-weight: 500;
              padding: 7px 20px;
              cursor: pointer;
              outline: none;
              transition: background 0.15s ease, border-color 0.15s ease, transform 0.1s ease;
            }
            .retry-btn:hover {
              background: rgba(255, 255, 255, 0.14);
              border-color: rgba(255, 255, 255, 0.22);
            }
            .retry-btn:active {
              transform: scale(0.96);
            }
          </style>
        </head>
        <body>
          <div class="tree-container" onclick="retry()" title="Click to retry">
            <img class="tree" src="data:image/png;base64,\(treeImageBase64)" alt="Tree" />
          </div>
          <h1>uh oh! your internets broken</h1>
          <p class="subtitle">try restarting your wifi</p>
          <p class="grass">maybe it's high time you go touch some grass.</p>
          <button class="retry-btn" onclick="retry()">Try Again</button>

          <script>
            function retry() {
              var target = '\(safeURL)';
              if (target && target !== 'about:blank' && !target.startsWith('data:')) {
                window.location.href = target;
              } else {
                window.location.reload();
              }
            }
            window.addEventListener('keydown', function(e) {
              if (e.key === 'Enter' || e.key === ' ') {
                retry();
              }
            });
          </script>
        </body>
        </html>
        """
    }
}

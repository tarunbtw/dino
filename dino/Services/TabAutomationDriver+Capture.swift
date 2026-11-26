//
//  TabAutomationDriver.swift
//  dino
//

import AppKit
import WebKit
import PDFKit

@MainActor
extension TabAutomationDriver {
    // MARK: - Screenshot & PDF

    /// Captures a crisp screenshot directly from WebKit's in-memory compositing buffer (GPU RAM).
    func captureScreenshot(labeled: Bool = false, elementId: String? = nil, clip: CGRect? = nil, somCrop: Bool = false, fullPage: Bool = false) async throws -> NSImage {
        await ensureDinoScriptInjected()

        if labeled || (elementId != nil && elementId?.contains("f") == true) {
            let syncScript = """
            if (window.__dino && window.__dino.syncSubframes) {
                return await window.__dino.syncSubframes(250);
            }
            return { count: 0 };
            """
            await withCheckedContinuation { continuation in
                webView.callAsyncJavaScript(syncScript, arguments: [:], in: nil, in: .defaultClient) { _ in
                    continuation.resume()
                }
            }
        }

        var targetRect: CGRect? = clip

        if fullPage && targetRect == nil && elementId == nil {
            let dimsScript = """
            (function() {
                var w = Math.max(document.body ? document.body.scrollWidth : 0, document.documentElement ? document.documentElement.scrollWidth : 0, window.innerWidth || 1280);
                var h = Math.max(document.body ? document.body.scrollHeight : 0, document.documentElement ? document.documentElement.scrollHeight : 0, window.innerHeight || 800);
                return { width: w, height: h };
            })()
            """
            if let dims = (try? await evalIsolated(dimsScript)) as? [String: Any],
               let w = (dims["width"] as? NSNumber)?.doubleValue,
               let h = (dims["height"] as? NSNumber)?.doubleValue,
               w > 0 && h > 0 {
                targetRect = CGRect(x: 0, y: 0, width: w, height: h)
            }
        }

        // Set-of-Marks (SoM) Dynamic Container Cropping
        if targetRect == nil && somCrop {
            let safeEl = elementId ?? ""
            let safeElData = (try? JSONSerialization.data(withJSONObject: [safeEl])) ?? Data("[\"\"]".utf8)
            let safeElArray = String(data: safeElData, encoding: .utf8) ?? "[\"\"]"
            let somScript = """
            (function() {
                if (window.__dino && window.__dino.getSomContainerRect) {
                    var r = window.__dino.getSomContainerRect((\(safeElArray))[0]);
                    return r ? JSON.stringify(r) : null;
                }
                return null;
            })()
            """
            if let dictStr = try? await evalIsolatedString(somScript),
               let dictData = dictStr.data(using: .utf8),
               let rectDict = try? JSONSerialization.jsonObject(with: dictData) as? [String: Any],
               let x = (rectDict["x"] as? NSNumber)?.doubleValue,
               let y = (rectDict["y"] as? NSNumber)?.doubleValue,
               let w = (rectDict["width"] as? NSNumber)?.doubleValue,
               let h = (rectDict["height"] as? NSNumber)?.doubleValue,
               w > 0 && h > 0 {
                targetRect = CGRect(x: x, y: y, width: w, height: h)
            }
        }

        if targetRect == nil, let elId = elementId {
            let safeElIdData = (try? JSONSerialization.data(withJSONObject: [elId])) ?? Data("[\"\"]".utf8)
            let safeElIdArray = String(data: safeElIdData, encoding: .utf8) ?? "[\"\"]"
            let rectScript = """
            (function() {
                var targetId = (\(safeElIdArray))[0];
                if (!targetId || typeof targetId !== 'string') return null;

                function resolveRect(tid) {
                    // 1. Direct query via getElementViewportRect (handles frame IDs like 'f1:e2', selectors, and DOM IDs)
                    if (window.__dino && window.__dino.getElementViewportRect) {
                        try {
                            var r = window.__dino.getElementViewportRect(tid);
                            if (r && (r.width > 0 || r.height > 0)) {
                                var rx = r.left !== undefined ? r.left : (r.x !== undefined ? r.x : 0);
                                var ry = r.top !== undefined ? r.top : (r.y !== undefined ? r.y : 0);
                                return { x: rx, y: ry, width: r.width, height: r.height };
                            }
                        } catch(e) {}
                    }

                    // 2. Direct lookup in semantic tree bounds cache
                    var cache = (window.__dino && window.__dino.elementsBounds) || window.__dino_elements_bounds;
                    if (cache && cache[tid]) {
                        var b = cache[tid];
                        if (b && (b.width > 0 || b.height > 0)) {
                            var bx = b.left !== undefined ? b.left : (b.x !== undefined ? b.x : 0);
                            var by = b.top !== undefined ? b.top : (b.y !== undefined ? b.y : 0);
                            return { x: bx, y: by, width: b.width, height: b.height };
                        }
                    }

                    // 3. Fallback: resolve DOM element directly in top document or open shadow tree
                    var el = window.__dino && window.__dino.elements && window.__dino.elements[tid];
                    if (!el && window.__dino && window.__dino.findInTree) {
                        el = window.__dino.findInTree(document, tid);
                    }
                    if (!el) {
                        try { el = document.querySelector('[data-dino-id="' + CSS.escape(tid) + '"]'); } catch(e) {}
                    }
                    if (!el) {
                        try { el = document.getElementById(tid) || document.querySelector('#' + CSS.escape(tid)); } catch(e) {}
                    }
                    if (!el) {
                        try { el = document.querySelector('[name="' + CSS.escape(tid) + '"]') || document.querySelector('[data-testid="' + CSS.escape(tid) + '"]'); } catch(e) {}
                    }
                    if (!el) {
                        try { el = document.querySelector(tid); } catch(e) {}
                    }
                    if (el) {
                        var er = (window.__dino && window.__dino.getElementViewportRect) ? window.__dino.getElementViewportRect(el) : el.getBoundingClientRect();
                        if (er && (er.width > 0 || er.height > 0)) {
                            var erx = er.left !== undefined ? er.left : (er.x !== undefined ? er.x : 0);
                            var ery = er.top !== undefined ? er.top : (er.y !== undefined ? er.y : 0);
                            return { x: erx, y: ery, width: er.width, height: er.height };
                        }
                    }

                    return null;
                }

                var res = resolveRect(targetId);
                if (!res && window.__dino && window.__dino.getSemanticTree) {
                    try {
                        window.__dino.getSemanticTree();
                        res = resolveRect(targetId);
                    } catch(e) {}
                }
                return res;
            })()
            """
            if let dict = (try? await evalIsolated(rectScript)) as? [String: Any],
               let x = (dict["x"] as? NSNumber)?.doubleValue,
               let y = (dict["y"] as? NSNumber)?.doubleValue,
               let w = (dict["width"] as? NSNumber)?.doubleValue,
               let h = (dict["height"] as? NSNumber)?.doubleValue,
               w > 0 && h > 0 {
                targetRect = CGRect(x: x, y: y, width: w, height: h)
            } else {
                await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
                throw NSError(domain: "DinoAgent", code: -5, userInfo: [NSLocalizedDescriptionKey: "Element '\(elId)' not found or has zero dimensions for screenshot crop"])
            }
        }

        // Flush layout and apply sensitive input blurring (plus visual badges if labeled == true)
        let badgeRectArg = targetRect.map { "{ x: \($0.origin.x), y: \($0.origin.y), width: \($0.size.width), height: \($0.size.height) }" } ?? "null"
        let prepScript = """
        (function() {
            try {
                if (window.__dino) {
                    window.__dino.blurSensitiveInputs();
                    if (\(labeled ? "true" : "false")) {
                        window.__dino.getSemanticTree();
                        window.__dino.showBadges(\(badgeRectArg));
                    }
                }
                if (document.body) { void document.body.offsetHeight; }
                return true;
            } catch(e) {
                return false;
            }
        })()
        """
        await tryEvalIsolated(prepScript)

        let config = WKSnapshotConfiguration()
        if let rect = targetRect {
            config.rect = rect
        } else {
            let viewWidth = webView.frame.width > 0 ? webView.frame.width : 1280
            config.snapshotWidth = NSNumber(value: Double(viewWidth))
        }

        do {
            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
                self.webView.takeSnapshot(with: config) { img, err in
                    if let err = err {
                        continuation.resume(throwing: err)
                    } else if let img = img {
                        continuation.resume(returning: img)
                    } else {
                        continuation.resume(throwing: NSError(domain: "DinoAgent", code: -4, userInfo: [NSLocalizedDescriptionKey: "Snapshot returned nil"]))
                    }
                }
            }

            // In displayless sessions (remote SSH, display asleep), WindowServer has no hardware framebuffer,
            // producing a blank/transparent frame. Fall back to WebKit vector PDF layout rendering.
            if self.isBlankImage(image) {
                let pdfConfig = WKPDFConfiguration()
                if let rect = targetRect {
                    pdfConfig.rect = rect
                }
                if let pdfData = try? await self.generatePDF(configuration: pdfConfig),
                   let fallbackImg = self.renderPDFToImage(pdfData: pdfData) {
                    await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
                    return fallbackImg
                }
            }

            await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
            return image
        } catch {
            // If takeSnapshot failed due to display session absence, fall back to createPDF
            let pdfConfig = WKPDFConfiguration()
            if let rect = targetRect {
                pdfConfig.rect = rect
            }
            if let pdfData = try? await self.generatePDF(configuration: pdfConfig),
               let fallbackImg = self.renderPDFToImage(pdfData: pdfData) {
                await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
                return fallbackImg
            }

            await tryEvalIsolated("window.__dino && window.__dino.hideBadges && window.__dino.hideBadges();")
            throw error
        }
    }

    func generatePDF(configuration: WKPDFConfiguration? = nil) async throws -> Data {
        let config = configuration ?? WKPDFConfiguration()
        return try await withCheckedThrowingContinuation { continuation in
            self.webView.createPDF(configuration: config) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func renderPDFToImage(pdfData: Data) -> NSImage? {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            return nil
        }

        let pageRect = page.getBoxRect(.mediaBox)
        let width = Int(pageRect.width * 2.0)
        let height = Int(pageRect.height * 2.0)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: 2.0, y: 2.0)
        context.drawPDFPage(page)

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: pageRect.size)
    }

    private func isBlankImage(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return true }
        guard rep.pixelsWide > 0 && rep.pixelsHigh > 0 else { return true }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh

        var sampleColors: [NSColor] = []
        for xi in 1...4 {
            for yi in 1...4 {
                let x = min(w - 1, (w * xi) / 5)
                let y = min(h - 1, (h * yi) / 5)
                if let c = rep.colorAt(x: x, y: y) {
                    sampleColors.append(c)
                }
            }
        }
        guard !sampleColors.isEmpty else { return true }

        // If all pixels are transparent (alpha < 0.05), frame is blank
        if sampleColors.allSatisfy({ $0.alphaComponent < 0.05 }) {
            return true
        }

        // If all pixels are pure solid white (#FFFFFF, typical of WindowServer without display session), frame is blank
        if sampleColors.allSatisfy({ $0.redComponent > 0.99 && $0.greenComponent > 0.99 && $0.blueComponent > 0.99 }) {
            return true
        }

        return false
    }
}

//
//  Tab.swift
//  nomad
//
//  Created by tarun on 10/10/26.
//

import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers

/// Lightweight console message entry captured from the page.
struct ConsoleEntry: Identifiable, Sendable {
    let id: UUID
    let level: Level
    let message: String
    let timestamp: Date

    enum Level: String, Codable, Sendable {
        case log
        case info
        case warn
        case error
    }

    init(id: UUID = UUID(), level: Level, message: String, timestamp: Date = Date()) {
        self.id = id
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

/// Metadata describing an inspected live DOM node in the page.
struct InspectedElementInfo: Sendable {
    let selector: String
    let tag: String
    let idAttr: String
    let classes: String
    let text: String
    let width: Int
    let height: Int
    let agentId: String?
}

/// Network request telemetry captured from client fetch / XHR.
struct NetworkEntry: Identifiable, Sendable {
    let id: UUID
    let method: String
    let url: String
    let status: Int
    let durationMs: Int
    let timestamp: Date
    let type: String
    let error: String?

    var isError: Bool { status >= 400 || status == 0 }

    init(id: UUID = UUID(), method: String, url: String, status: Int, durationMs: Int, timestamp: Date = Date(), type: String = "fetch", error: String? = nil) {
        self.id = id
        self.method = method
        self.url = url
        self.status = status
        self.durationMs = durationMs
        self.timestamp = timestamp
        self.type = type
        self.error = error
    }
}

/// Represents an individual browser tab.
/// Owns its WKWebView instance so switching tabs is instant and preserves scroll state.
@MainActor
final class Tab: NSObject, Identifiable, ObservableObject {
    let id: UUID
    
    @Published var url: URL?
    @Published var title: String
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isBlank: Bool = true
    @Published var favicon: NSImage? = nil
    @Published var isIncognito: Bool = false

    // MARK: - Developer Drawer & Live Inspection State
    @Published var isDevDrawerVisible: Bool = false
    @Published var isInspectorActive: Bool = false
    @Published var isZapperActive: Bool = false
    @Published var isReaderModeActive: Bool = false
    @Published var isFloatingVideo: Bool = false
    @Published var readerArticle: ReaderArticle? = nil
    @Published var consoleEntries: [ConsoleEntry] = []
    @Published var networkEntries: [NetworkEntry] = []
    @Published var inspectedElementInfo: InspectedElementInfo? = nil

    /// Detects if this tab is on a Chrome Web Store extension detail page and extracts the 32-letter ID.
    var chromeWebStoreExtensionId: String? {
        guard let url = url,
              let host = url.host,
              host.contains("chromewebstore.google.com") || host.contains("chrome.google.com"),
              url.path.contains("/detail/") else {
            return nil
        }
        return CrxDownloader.extractID(from: url.absoluteString)
    }

    /// Clean display title for the extension detected on this tab.
    var chromeWebStoreExtensionName: String? {
        guard chromeWebStoreExtensionId != nil else { return nil }
        if !title.isEmpty && title != "Chrome Web Store" {
            let clean = title.replacingOccurrences(of: " - Chrome Web Store", with: "")
                             .replacingOccurrences(of: " - Chrome web store", with: "")
            if !clean.isEmpty { return clean }
        }
        if let pathComponents = url?.pathComponents, pathComponents.count >= 3 {
            let slug = pathComponents[pathComponents.count - 2]
            if slug != "detail" {
                return slug.replacingOccurrences(of: "-", with: " ").capitalized
            }
        }
        return "Extension"
    }

    // MARK: - Fluid Two-Finger Swipe Navigation State
    enum SwipeDirection {
        case back
        case forward
    }

    struct SwipeGestureState {
        var direction: SwipeDirection
        var progress: CGFloat
        var distance: CGFloat
        var isTriggered: Bool
    }

    enum PendingDialogType: String {
        case alert
        case confirm
        case prompt
    }

    struct PendingDialog {
        let type: PendingDialogType
        let message: String
        let defaultText: String?
        let timestamp: Date
        let resolve: (Any?) -> Void
    }

    @Published var swipeState: SwipeGestureState? = nil
    @Published var lastNavigationError: String? = nil
    @Published var lastDialog: String? = nil
    @Published var dialogPolicy: String = "dismiss"
    @Published var dialogPromptResponse: String = ""
    var pendingDialog: PendingDialog? = nil
    var dialogTimeoutTask: Task<Void, Never>? = nil
    @Published var navigationSeq: Int = 0
    @Published var lastNavigationStartTime: Date? = nil
    @Published var lastNavigationFinishTime: Date? = nil
    @Published var lastActionTime: Date? = nil
    var allowNextFileNavigation: Bool = false
    var currentNavigation: WKNavigation? = nil

    /// Staged file URLs ready for programmatic consumption by runOpenPanelWith during agent file uploads.
    var stagedUploadURLs: [URL]? = nil
    var stagedUploadTimeoutTimer: Timer? = nil

    func stageUpload(urls: [URL]) {
        stagedUploadURLs = urls
        stagedUploadTimeoutTimer?.invalidate()
        stagedUploadTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stagedUploadURLs = nil
            }
        }
    }

    func clearStagedUpload() {
        stagedUploadTimeoutTimer?.invalidate()
        stagedUploadTimeoutTimer = nil
        stagedUploadURLs = nil
    }
    
    /// The retained custom web view for this tab.
    private(set) var webView: BrowserWebView
    
    /// Optional hook called when web content requests opening a new window (e.g. target="_blank").
    var onOpenURLInNewTab: ((URL) -> Void)?

    /// Hook to create a full new tab and return its WKWebView when a page requests window.open / target="_blank"
    var onOpenTabWithWebView: ((WKWebViewConfiguration, WKNavigationAction) -> WKWebView?)?

    /// Hook to close this tab if it was opened solely for an immediate file download
    var onRequestCloseTab: (() -> Void)?
    
    private(set) var hasLoaded: Bool = false
    private var observers: [NSKeyValueObservation] = []

    init(id: UUID = UUID(), initialURL: URL? = nil, configuration: WKWebViewConfiguration? = nil, isIncognito: Bool = false, lazy: Bool = false) {
        self.id = id
        self.url = initialURL
        self.isIncognito = isIncognito

        if let initialURL = initialURL,
           (initialURL.scheme == ExtensionManager.scheme || initialURL.scheme == "webkit-extension"),
           let host = initialURL.host,
           let ext = ExtensionManager.shared.installed.first(where: { $0.id == host }) {
            self.title = ext.name
        } else if isIncognito && (initialURL == nil || initialURL?.absoluteString == "about:blank") {
            self.title = "Private Tab"
        } else {
            self.title = initialURL?.host ?? "New Tab"
        }

        self.isBlank = (initialURL == nil || initialURL?.absoluteString == "about:blank")
        
        let effectiveConfig = configuration ?? ExtensionManager.shared.configuration(for: initialURL) ?? WebKitPool.makeConfiguration(isIncognito: isIncognito)
        let webView = BrowserWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 730), configuration: effectiveConfig)
        webView.customUserAgent = WebKitPool.customUserAgent
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.setMagnification(1.0, centeredAt: .zero)
        webView.pageZoom = 1.0
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        if #available(macOS 14.0, *) {
            webView.configuration.preferences.inactiveSchedulingPolicy = .none
        }
        self.webView = webView
        
        super.init()
        
        webView.tab = self
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        
        let ucc = effectiveConfig.userContentController
        ucc.removeScriptMessageHandler(forName: "nomadConsole")
        ucc.removeScriptMessageHandler(forName: "nomadInspect")
        ucc.removeScriptMessageHandler(forName: "nomadNetwork")
        ucc.removeScriptMessageHandler(forName: "nomadZapper")
        ucc.removeScriptMessageHandler(forName: "nomadFrameBridge")
        ucc.add(WeakScriptMessageHandler(delegate: self), name: "nomadConsole")
        ucc.add(WeakScriptMessageHandler(delegate: self), name: "nomadInspect")
        ucc.add(WeakScriptMessageHandler(delegate: self), name: "nomadNetwork")
        ucc.add(WeakScriptMessageHandler(delegate: self), name: "nomadZapper")
        ucc.add(WeakScriptMessageHandler(delegate: self), name: "nomadFrameBridge")

        setupObservers()
        
        if let initialURL = initialURL {
            if lazy {
                self.hasLoaded = false
            } else {
                self.hasLoaded = true
                load(url: initialURL)
            }
        } else {
            self.hasLoaded = true
        }
    }

    /// Loads the URL if this tab was lazily preserved in the background on startup.
    func ensureLoaded() {
        guard !hasLoaded, let url = self.url, !isBlank, !isInternalPage else { return }
        hasLoaded = true
        load(url: url)
    }

    // MARK: - Swipe Gesture Coordinator
    func updateSwipeGesture(direction: SwipeDirection, progress: CGFloat, distance: CGFloat, isTriggered: Bool) {
        self.swipeState = SwipeGestureState(
            direction: direction,
            progress: progress,
            distance: distance,
            isTriggered: isTriggered
        )
    }

    func cancelSwipeGesture() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            self.swipeState = nil
        }
    }

    func finishSwipeGesture(commit: Bool, direction: SwipeDirection) {
        if commit {
            withAnimation(.easeOut(duration: 0.2)) {
                self.swipeState = nil
            }
            if direction == .back {
                self.goBack()
            } else {
                self.goForward()
            }
        } else {
            cancelSwipeGesture()
        }
    }

    /// Tear down observers and script handlers when tab is explicitly closed
    func cleanup() {
        FloatingVideoManager.shared.landIfTab(id: id)
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nomadConsole")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nomadInspect")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nomadNetwork")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nomadZapper")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nomadFrameBridge")
    }

    deinit {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
    }

    var isInternalPage: Bool {
        url?.scheme == "nomad"
    }

    /// Loads a user-typed string (resolved via URLParser).
    func load(text: String) {
        let destination = URLParser.parse(text)
        load(url: destination)
    }

    /// Loads a specific URL.
    func load(url: URL) {
        self.navigationSeq += 1
        self.lastNavigationStartTime = Date()
        self.url = url
        self.lastNavigationError = nil
        if url.scheme == "nomad" {
            self.isBlank = false
            self.isLoading = false
            self.title = "Settings"
            return
        }

        if url.scheme == ExtensionManager.scheme || url.scheme == "webkit-extension" {
            if let host = url.host, let ext = ExtensionManager.shared.installed.first(where: { $0.id == host }) {
                self.title = ext.name
            }
            ensureConfiguration(for: url)
        }

        self.isBlank = (url.absoluteString == "about:blank")
        self.favicon = nil
        self.lastDialog = nil
        if let pending = self.pendingDialog {
            self.pendingDialog = nil
            self.dialogTimeoutTask?.cancel()
            self.dialogTimeoutTask = nil
            pending.resolve(nil)
        }
        webView.setMagnification(1.0, centeredAt: .zero)
        if webView.isLoading {
            webView.stopLoading()
        }
        if url.isFileURL {
            self.allowNextFileNavigation = true
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let ext = resolved.pathExtension.lowercased()
            let isWebDocument = ["html", "htm", "xhtml", "svg", "pdf"].contains(ext)
            let readDir = resolved.pathComponents.count > 2 ? resolved.deletingLastPathComponent() : URL(fileURLWithPath: "/")
            self.url = resolved
            if isWebDocument {
                self.currentNavigation = webView.loadFileURL(resolved, allowingReadAccessTo: readDir)
            } else {
                if let data = try? Data(contentsOf: resolved) {
                    let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "text/plain"
                    self.currentNavigation = webView.load(data, mimeType: mimeType, characterEncodingName: "utf-8", baseURL: resolved)
                } else {
                    self.currentNavigation = webView.loadFileURL(resolved, allowingReadAccessTo: readDir)
                }
            }
        } else {
            let request = URLRequest(url: url)
            self.currentNavigation = webView.load(request)
        }
        fetchFavicon(for: url)
    }

    /// Dynamically switches the web view configuration if navigating to an extension that requires WKWebExtensionContext.webViewConfiguration.
    func ensureConfiguration(for targetURL: URL) {
        guard (targetURL.scheme == ExtensionManager.scheme || targetURL.scheme == "webkit-extension"),
              let host = targetURL.host,
              let targetConfig = ExtensionManager.shared.contexts[host]?.webViewConfiguration,
              webView.configuration !== targetConfig else {
            return
        }

        observers.forEach { $0.invalidate() }
        observers.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.tab = nil

        let newWebView = BrowserWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 730), configuration: targetConfig)
        newWebView.customUserAgent = WebKitPool.customUserAgent
        newWebView.allowsBackForwardNavigationGestures = false
        newWebView.allowsMagnification = false
        newWebView.setMagnification(1.0, centeredAt: .zero)
        newWebView.pageZoom = 1.0
        newWebView.tab = self
        newWebView.navigationDelegate = self
        newWebView.uiDelegate = self
        self.webView = newWebView
        setupObservers()
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    func reload() {
        if isInternalPage { return }
        self.currentNavigation = webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
    }

    // MARK: - Browser Page Zoom (Standards-compliant HTML reflow zoom: ⌘+, ⌘-, ⌘0)
    var currentZoom: Double {
        webView.pageZoom
    }

    func zoomIn() {
        guard !isInternalPage else { return }
        let next = min(webView.pageZoom + 0.1, 3.0)
        webView.pageZoom = (next * 10).rounded() / 10.0
    }

    func zoomOut() {
        guard !isInternalPage else { return }
        let next = max(webView.pageZoom - 0.1, 0.5)
        webView.pageZoom = (next * 10).rounded() / 10.0
    }

    func resetZoom() {
        guard !isInternalPage else { return }
        webView.pageZoom = 1.0
        if webView.magnification != 1.0 {
            webView.setMagnification(1.0, centeredAt: .zero)
        }
    }

    // MARK: - Find in Page (⌘F)
    @Published var isFindBarVisible: Bool = false
    @Published var findQuery: String = ""
    @Published var findHasMatches: Bool = false

    func findInPage(_ query: String, forward: Bool = true) {
        self.findQuery = query
        guard !query.isEmpty else {
            clearFind()
            return
        }

        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true

        webView.find(query, configuration: config) { [weak self] result in
            Task { @MainActor in
                self?.findHasMatches = result.matchFound
            }
        }
    }

    func clearFind() {
        findQuery = ""
        findHasMatches = false
        webView.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
    }

    func closeFind() {
        isFindBarVisible = false
        clearFind()
    }

    // MARK: - Native Print & PDF Export (⌘P)
    func printPage() {
        guard !isInternalPage else { return }
        let printInfo = NSPrintInfo.shared
        printInfo.orientation = .portrait
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic

        let printOperation = webView.printOperation(with: printInfo)
        if let window = webView.window {
            printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            printOperation.run()
        }
    }

    // MARK: - Developer Drawer & Live Inspection
    func appendConsoleEntry(level: ConsoleEntry.Level, message: String) {
        let entry = ConsoleEntry(level: level, message: message)
        if consoleEntries.count > 600 {
            consoleEntries.removeFirst(100)
        }
        consoleEntries.append(entry)
    }

    func startElementInspector() {
        guard !isInternalPage && !isBlank else { return }
        isInspectorActive = true
        webView.evaluateJavaScript(TabScripts.startInspector, completionHandler: nil)
    }

    func highlightInspectedElement() {
        guard let selector = inspectedElementInfo?.selector, !selector.isEmpty else { return }
        webView.evaluateJavaScript(TabScripts.highlightElement(selector: selector), completionHandler: nil)
    }

    // MARK: - Element Zapper (Hide Anything ⇧⌘H)
    func toggleElementZapper() {
        guard !isInternalPage && !isBlank else { return }
        if isZapperActive {
            stopElementZapper()
        } else {
            startElementZapper()
        }
    }

    func startElementZapper() {
        guard !isInternalPage && !isBlank else { return }
        isZapperActive = true
        NSCursor.crosshair.set()
        webView.evaluateJavaScript(TabScripts.startZapper, completionHandler: nil)
    }

    func stopElementZapper() {
        isZapperActive = false
        objectWillChange.send()
        NSCursor.arrow.set()
        webView.evaluateJavaScript(TabScripts.stopZapper, completionHandler: nil)
    }

    /// Clears all zapped selectors for current host and restores hidden elements on the page immediately
    func unhideAllZappedElements() {
        guard let host = url?.host ?? webView.url?.host else { return }
        ZapperStore.shared.clearSelectors(for: host)
        webView.evaluateJavaScript("document.getElementById('nomad-zapped-rules')?.remove()", completionHandler: nil)
    }

    // MARK: - Reading Mode (⇧⌘R)
    func toggleReaderMode() {
        if isReaderModeActive {
            withAnimation(.easeInOut(duration: 0.18)) {
                self.isReaderModeActive = false
                self.readerArticle = nil
            }
            return
        }
        guard !isInternalPage && !isBlank else { return }

        webView.evaluateJavaScript(TabScripts.extractReaderArticle) { [weak self] result, error in
            guard let self = self, let dict = result as? [String: Any] else { return }
            let title = dict["title"] as? String ?? self.title
            let byline = dict["byline"] as? String ?? ""
            let siteName = dict["siteName"] as? String ?? (self.url?.host ?? "")
            let paragraphs = dict["paragraphs"] as? [String] ?? []
            let wordCount = dict["wordCount"] as? Int ?? 0
            let readingTime = dict["readingTime"] as? Int ?? 1

            guard !paragraphs.isEmpty else { return }

            self.readerArticle = ReaderArticle(
                title: title,
                byline: byline,
                siteName: siteName,
                paragraphs: paragraphs,
                wordCount: wordCount,
                readingTimeMinutes: readingTime,
                url: self.url
            )
            withAnimation(.easeInOut(duration: 0.18)) {
                self.isReaderModeActive = true
            }
        }
    }

    // MARK: - Picture-in-Picture (Floating Video ⇧⌘P)
    func togglePictureInPicture() {
        FloatingVideoManager.shared.toggle(tab: self)
    }


    // MARK: - KVO Observers
    private func setupObservers() {
        observers.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let newTitle = wv.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor [weak self] in
                guard let self, !self.isInternalPage else { return }
                if !newTitle.isEmpty {
                    self.title = newTitle
                } else if let url = self.url ?? self.webView.url,
                          (url.scheme == ExtensionManager.scheme || url.scheme == "webkit-extension"),
                          let host = url.host,
                          let ext = ExtensionManager.shared.installed.first(where: { $0.id == host }) {
                    self.title = ext.name
                } else {
                    self.title = self.url?.host ?? "New Tab"
                }
                ExtensionManager.shared.tabDidChange(self, properties: [.title])
            }
        })

        observers.append(webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let newURL = wv.url
            Task { @MainActor [weak self] in
                guard let self, !self.isInternalPage else { return }
                if let newURL = newURL {
                    self.url = newURL
                    self.isBlank = (newURL.absoluteString == "about:blank")
                    self.fetchFavicon(for: newURL)
                } else if self.url == nil {
                    self.isBlank = true
                }
                ExtensionManager.shared.tabDidChange(self, properties: [.URL])
            }
        })

        observers.append(webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let loading = wv.isLoading
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = loading
                if !loading {
                    self.lastNavigationFinishTime = Date()
                } else {
                    self.lastNavigationStartTime = Date()
                }
                ExtensionManager.shared.tabDidChange(self, properties: [.loading])
            }
        })

        observers.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let progress = wv.estimatedProgress
            Task { @MainActor [weak self] in
                self?.estimatedProgress = progress
            }
        })

        observers.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let canBack = wv.canGoBack
            Task { @MainActor [weak self] in
                self?.canGoBack = canBack
            }
        })

        observers.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
            guard let self else { return }
            let canForward = wv.canGoForward
            Task { @MainActor [weak self] in
                self?.canGoForward = canForward
            }
        })
    }
    // MARK: - Favicon Fetching
    func fetchFavicon(for url: URL) {
        guard url.scheme == "http" || url.scheme == "https", let host = url.host, !host.isEmpty else {
            self.favicon = nil
            return
        }

        if let cached = FaviconService.shared.cachedFavicon(for: host) {
            self.favicon = cached
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let image = await FaviconService.shared.loadFavicon(for: url) {
                if self.url?.host == host || self.webView.url?.host == host {
                    self.favicon = image
                }
            }
        }
    }
}

//
//  WebKitPool.swift
//  dino
//
//  Created by tarun on 10/10/26.
//

import WebKit
import Network

/// Manages WebKit resources, configurations, and extension-readiness.
enum WebKitPool {
    /// Standard user-agent matching the system Safari version to prevent Google CAPTCHAs and compatibility warnings.
    static let customUserAgent: String = {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let safariVer = osVersion >= 26 ? "\(osVersion).0" : "\(osVersion + 3).0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVer) Safari/605.1.15"
    }()

    /// Creates a standardized WKWebViewConfiguration.
    /// Ready for WebExtensions (WKWebExtensionController) and custom user scripts.
    @MainActor
    static func makeConfiguration(profile: DinoProfileType? = nil, isIncognito: Bool = false) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let effectiveProfile = profile ?? DinoProfileManager.defaultProfile
        if isIncognito || effectiveProfile == .ephemeral {
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        } else if effectiveProfile == .agent {
            config.websiteDataStore = DinoProfileManager.websiteDataStore(for: .agent)
        } else {
            config.websiteDataStore = WKWebsiteDataStore.default()
        }

        if #available(macOS 14.0, *),
           let proxyStr = DinoHeadlessManager.shared.proxyURLString,
           let proxyURL = URL(string: proxyStr),
           let host = proxyURL.host {
            let port = UInt16(proxyURL.port ?? (proxyURL.scheme?.lowercased() == "socks5" ? 1080 : 8080))
            let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(integerLiteral: port))
            let proxyConfig: ProxyConfiguration
            if proxyURL.scheme?.lowercased() == "socks5" {
                proxyConfig = ProxyConfiguration(socksv5Proxy: endpoint)
            } else {
                proxyConfig = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
            }
            config.websiteDataStore.proxyConfigurations = [proxyConfig]
        }
        ExtensionManager.shared.attach(config)
        
        // Enable modern web preferences with full desktop mode
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        prefs.preferredContentMode = .desktop
        config.defaultWebpagePreferences = prefs
        
        // Developer extras for Web Inspector
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // Do not throttle background tabs so agent automation, timers, and mutations run at full speed
        config.preferences.inactiveSchedulingPolicy = .none
        // Enable HTML5 video fullscreen expansion
        config.preferences.isElementFullscreenEnabled = true
        // Automatically upgrade known hosts to HTTPS
        config.upgradeKnownHostsToHTTPS = true
        
        // Use the configuration's userContentController directly so WebExtensions stay bound
        let ucc = config.userContentController
        ContentBlockerService.shared.attach(to: ucc)
        
        // Suppress horizontal elastic overscroll bounce
        let globalFixes = """
        (function() {
            const s = document.createElement('style');
            s.id = 'dino-viewport-fixes';
            s.textContent = `
                html, body {
                    overscroll-behavior-x: none !important;
                }
            `;
            if (document.head) {
                document.head.appendChild(s);
            } else {
                document.addEventListener('DOMContentLoaded', () => {
                    if (document.head && !document.getElementById('dino-viewport-fixes')) {
                        document.head.appendChild(s);
                    }
                });
            }
        })();
        """
        let userScript = WKUserScript(source: globalFixes, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(userScript)

        // Dino Stealth & Anti-Bot Engine Script
        // Injected at .atDocumentStart across all frames (including challenge iframes)
        let stealthScript = """
        (function() {
            if (window.__dino_stealth_hooked) return;
            window.__dino_stealth_hooked = true;

            // 1. Mask navigator.webdriver (returns undefined instead of true)
            try {
                Object.defineProperty(navigator, 'webdriver', {
                    get: function() { return undefined; },
                    configurable: true,
                    enumerable: true
                });
            } catch(e) {}

            // 2. Mock authentic Safari plugins & mimeTypes
            try {
                const fakePlugins = [
                    { name: "WebKit built-in PDF", filename: "internal-pdf-viewer", description: "Portable Document Format" }
                ];
                Object.defineProperty(navigator, 'plugins', {
                    get: function() { return fakePlugins; },
                    configurable: true
                });
                Object.defineProperty(navigator, 'mimeTypes', {
                    get: function() {
                        return [{ type: "application/pdf", suffixes: "pdf", description: "Portable Document Format", enabledPlugin: fakePlugins[0] }];
                    },
                    configurable: true
                });
            } catch(e) {}

            // 3. Synthetic window.chrome runtime & client hints for Google Workspace compatibility
            try {
                if (!window.chrome) {
                    window.chrome = {
                        runtime: { id: "dino-runtime", connect: function() {}, sendMessage: function() {} },
                        app: { isInstalled: false, InstallState: { DISABLED: "disabled" } }
                    };
                }
                if (!navigator.userAgentData) {
                    navigator.userAgentData = {
                        brands: [
                            { brand: "Chromium", version: "131" },
                            { brand: "Google Chrome", version: "131" },
                            { brand: "Not_A Brand", version: "24" }
                        ],
                        mobile: false,
                        platform: "macOS"
                    };
                }
            } catch(e) {}

            // 4. WebGL Vendor & Renderer Hardware Mask (Apple Silicon GPU)
            try {
                function maskWebGL(proto) {
                    if (!proto || !proto.getParameter) return;
                    const origGetParam = proto.getParameter;
                    proto.getParameter = function(param) {
                        if (param === 37445) return "Apple Inc."; // UNMASKED_VENDOR_WEBGL
                        if (param === 37446) return "Apple M3 Max"; // UNMASKED_RENDERER_WEBGL
                        return origGetParam.apply(this, arguments);
                    };
                    try {
                        Object.defineProperty(proto.getParameter, 'name', { value: 'getParameter', configurable: true });
                    } catch(e) {}
                }
                if (typeof WebGLRenderingContext !== 'undefined') maskWebGL(WebGLRenderingContext.prototype);
                if (typeof WebGL2RenderingContext !== 'undefined') maskWebGL(WebGL2RenderingContext.prototype);
            } catch(e) {}
        })();
        """
        ucc.addUserScript(WKUserScript(source: stealthScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        // Capture console output for Dino DevX Console
        let consoleInterceptor = """
        (function() {
            if (window.__dino_console_hooked) return;
            window.__dino_console_hooked = true;
            const origLog = console.log;
            const origWarn = console.warn;
            const origError = console.error;
            function send(lvl, args) {
                try {
                    const str = Array.from(args).map(a => {
                        if (typeof a === 'object') {
                            try { return JSON.stringify(a); } catch(e) { return String(a); }
                        }
                        return String(a);
                    }).join(' ');
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dinoConsole) {
                        window.webkit.messageHandlers.dinoConsole.postMessage({ level: lvl, message: str });
                    }
                } catch(e) {}
            }
            function maskNative(fn, name) {
                try {
                    Object.defineProperty(fn, 'name', { value: name, configurable: true });
                    Object.defineProperty(fn, 'toString', {
                        value: function() { return 'function ' + name + '() { [native code] }'; },
                        configurable: true
                    });
                } catch(e) {}
            }
            console.log = function(...args) { origLog.apply(console, args); send('log', args); };
            console.warn = function(...args) { origWarn.apply(console, args); send('warn', args); };
            console.error = function(...args) { origError.apply(console, args); send('error', args); };
            maskNative(console.log, 'log');
            maskNative(console.warn, 'warn');
            maskNative(console.error, 'error');
        })();
        """
        ucc.addUserScript(WKUserScript(source: consoleInterceptor, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        // Capture fetch and XMLHttpRequest network activity for Dino DevX Network Tab
        let networkInterceptor = """
        (function() {
            if (window.__dino_network_hooked) return;
            window.__dino_network_hooked = true;
            window.__dino_inflight_count = 0;
            window.__dino_last_network_activity = performance.now();

            function maskNative(fn, name) {
                try {
                    Object.defineProperty(fn, 'name', { value: name, configurable: true });
                    Object.defineProperty(fn, 'toString', {
                        value: function() { return 'function ' + name + '() { [native code] }'; },
                        configurable: true
                    });
                } catch(e) {}
            }

            function sendNet(entry) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dinoNetwork) {
                        window.webkit.messageHandlers.dinoNetwork.postMessage(entry);
                    }
                } catch(e) {}
            }

            function matchesUrl(pattern, targetUrl, exact) {
                if (!pattern || !targetUrl) return false;
                if (pattern === '*' || pattern === '**') return true;
                if (exact) {
                    if (pattern === targetUrl) return true;
                    try {
                        var tu = new URL(targetUrl, window.location.href).href;
                        var pu = new URL(pattern, window.location.href).href;
                        return tu === pu;
                    } catch(e) { return false; }
                }
                if (pattern === targetUrl || targetUrl.indexOf(pattern) !== -1) return true;
                try {
                    var puResolved = new URL(pattern, window.location.href).href;
                    if (targetUrl === puResolved || targetUrl.indexOf(puResolved) !== -1) return true;
                } catch(e) {}

                var tuHref = targetUrl;
                var tuPath = '';
                var tuSearch = '';
                try {
                    var parsed = new URL(targetUrl, window.location.href);
                    tuHref = parsed.href;
                    tuPath = parsed.pathname;
                    tuSearch = parsed.search || '';
                    if (tuPath === pattern || (tuPath + tuSearch) === pattern) return true;
                } catch(e) {}

                if (pattern.indexOf('*') !== -1) {
                    var reStr = '^';
                    for (var i = 0; i < pattern.length; i++) {
                        var c = pattern.charAt(i);
                        if (c === '*') {
                            if (pattern.charAt(i + 1) === '*') i++;
                            reStr += '.*';
                        } else if ('.+?^${}()|[]\\\\'.indexOf(c) !== -1) {
                            reStr += '\\\\' + c;
                        } else {
                            reStr += c;
                        }
                    }
                    reStr += '$';
                    try {
                        var rx = new RegExp(reStr, 'i');
                        if (rx.test(targetUrl) || rx.test(tuHref)) return true;
                        if (tuPath && rx.test(tuPath)) return true;
                        if (tuPath && rx.test(tuPath + tuSearch)) return true;
                        if (rx.test(targetUrl.split('?')[0])) return true;
                        if (pattern.indexOf('://') === -1) {
                            var looseRx = new RegExp(reStr.replace(/^\\^/, ''), 'i');
                            if (looseRx.test(targetUrl) || (tuPath && looseRx.test(tuPath))) return true;
                        }
                    } catch(e) {}
                }

                return false;
            }

            // Hook window.fetch
            const origFetch = window.fetch;
            if (origFetch) {
                window.fetch = async function(...args) {
                    const startTime = performance.now();
                    window.__dino_inflight_count = (window.__dino_inflight_count || 0) + 1;
                    window.__dino_last_network_activity = performance.now();
                    let method = 'GET';
                    let url = '';
                    try {
                        if (typeof args[0] === 'string') {
                            url = args[0];
                        } else if (args[0] && args[0].url) {
                            url = args[0].url;
                            if (args[0].method) method = String(args[0].method).toUpperCase();
                        }
                        if (args[1] && args[1].method) {
                            method = String(args[1].method).toUpperCase();
                        }
                    } catch(e) {}
                    let resolvedUrl = url;
                    try {
                        resolvedUrl = new URL(url, window.location.href).href;
                    } catch(e) {}

                    try {
                        if (window.__dino_mock_routes && window.__dino_mock_routes.length) {
                            const matched = window.__dino_mock_routes.find(m => {
                                if (!m || !m.url) return false;
                                if (m.method && m.method.toUpperCase() !== method) return false;
                                return matchesUrl(m.url, resolvedUrl, m.exact) || matchesUrl(m.url, url, m.exact);
                            });
                            if (matched) {
                                if (matched.block) {
                                    const duration = Math.round(performance.now() - startTime);
                                    sendNet({
                                        method: method,
                                        url: url,
                                        status: 0,
                                        duration: duration,
                                        type: 'fetch (blocked)',
                                        isError: true,
                                        error: 'Blocked by client'
                                    });
                                    throw new TypeError('Failed to fetch (blocked by client)');
                                }
                                const mockStatus = matched.status || 200;
                                const rawBody = matched.responseBody !== undefined ? matched.responseBody : (matched.body !== undefined ? matched.body : '');
                                const mockBody = (typeof rawBody === 'object' && rawBody !== null) ? JSON.stringify(rawBody) : String(rawBody);
                                const defaultContentType = (typeof rawBody === 'object' && rawBody !== null) ? 'application/json' : 'text/plain';
                                const mockHeaders = new Headers(matched.headers || { 'content-type': matched.contentType || defaultContentType });
                                const duration = Math.round(performance.now() - startTime);
                                sendNet({
                                    method: method,
                                    url: url,
                                    status: mockStatus,
                                    duration: duration,
                                    type: 'fetch (mocked)'
                                });
                                return new Response(mockBody, {
                                    status: mockStatus,
                                    statusText: (mockStatus >= 200 && mockStatus < 300) ? 'OK' : 'Mock Response',
                                    headers: mockHeaders
                                });
                            }
                        }

                        const res = await origFetch.apply(this, args);
                        const duration = Math.round(performance.now() - startTime);
                        sendNet({
                            method: method,
                            url: url || (res ? res.url : ''),
                            status: res ? res.status : 200,
                            duration: duration,
                            type: 'fetch'
                        });
                        return res;
                    } catch(err) {
                        const duration = Math.round(performance.now() - startTime);
                        sendNet({
                            method: method,
                            url: url,
                            status: 0,
                            duration: duration,
                            type: 'fetch',
                            error: err ? err.message : 'Network error'
                        });
                        throw err;
                    } finally {
                        window.__dino_inflight_count = Math.max(0, (window.__dino_inflight_count || 1) - 1);
                        window.__dino_last_network_activity = performance.now();
                    }
                };
                maskNative(window.fetch, 'fetch');
            }

            // Hook XMLHttpRequest
            const origOpen = XMLHttpRequest.prototype.open;
            const origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url, ...rest) {
                this.__dino_method = (method || 'GET').toUpperCase();
                this.__dino_url = url;
                try {
                    this.__dino_resolved_url = new URL(url, window.location.href).href;
                } catch(e) {
                    this.__dino_resolved_url = url;
                }
                return origOpen.apply(this, [method, url, ...rest]);
            };
            XMLHttpRequest.prototype.send = function(...args) {
                const startTime = performance.now();
                window.__dino_inflight_count = (window.__dino_inflight_count || 0) + 1;
                window.__dino_last_network_activity = performance.now();
                const xhr = this;

                if (window.__dino_mock_routes && window.__dino_mock_routes.length) {
                    const reqUrl = this.__dino_url || '';
                    const reqResolvedUrl = this.__dino_resolved_url || reqUrl;
                    const reqMethod = this.__dino_method || 'GET';
                    const matched = window.__dino_mock_routes.find(m => {
                        if (!m || !m.url) return false;
                        if (m.method && m.method.toUpperCase() !== reqMethod) return false;
                        return matchesUrl(m.url, reqResolvedUrl, m.exact) || matchesUrl(m.url, reqUrl, m.exact);
                    });
                    if (matched) {
                        if (matched.block) {
                            const duration = Math.round(performance.now() - startTime);
                            sendNet({
                                method: reqMethod,
                                url: reqUrl,
                                status: 0,
                                duration: duration,
                                type: 'xhr (blocked)',
                                isError: true,
                                error: 'Blocked by client'
                            });
                            Object.defineProperty(xhr, 'readyState', { value: 4, configurable: true });
                            Object.defineProperty(xhr, 'status', { value: 0, configurable: true });
                            Object.defineProperty(xhr, 'statusText', { value: 'Blocked', configurable: true });
                            setTimeout(() => {
                                window.__dino_inflight_count = Math.max(0, (window.__dino_inflight_count || 1) - 1);
                                window.__dino_last_network_activity = performance.now();
                                xhr.dispatchEvent(new Event('readystatechange'));
                                xhr.dispatchEvent(new ProgressEvent('error'));
                                xhr.dispatchEvent(new ProgressEvent('loadend'));
                            }, 1);
                            return;
                        }
                        const mockStatus = matched.status || 200;
                        const rawBody = matched.responseBody !== undefined ? matched.responseBody : (matched.body !== undefined ? matched.body : '');
                        const mockBody = (typeof rawBody === 'object' && rawBody !== null) ? JSON.stringify(rawBody) : String(rawBody);
                        const duration = Math.round(performance.now() - startTime);
                        sendNet({
                            method: reqMethod,
                            url: reqUrl,
                            status: mockStatus,
                            duration: duration,
                            type: 'xhr (mocked)'
                        });
                        Object.defineProperty(xhr, 'readyState', { value: 4, configurable: true });
                        Object.defineProperty(xhr, 'status', { value: mockStatus, configurable: true });
                        Object.defineProperty(xhr, 'statusText', { value: 'OK', configurable: true });
                        Object.defineProperty(xhr, 'responseText', { value: mockBody, configurable: true });
                        Object.defineProperty(xhr, 'response', { value: mockBody, configurable: true });
                        setTimeout(() => {
                            window.__dino_inflight_count = Math.max(0, (window.__dino_inflight_count || 1) - 1);
                            window.__dino_last_network_activity = performance.now();
                            xhr.dispatchEvent(new Event('readystatechange'));
                            xhr.dispatchEvent(new Event('load'));
                            xhr.dispatchEvent(new Event('loadend'));
                        }, 1);
                        return;
                    }
                }

                this.addEventListener('loadend', function() {
                    window.__dino_inflight_count = Math.max(0, (window.__dino_inflight_count || 1) - 1);
                    window.__dino_last_network_activity = performance.now();
                    const duration = Math.round(performance.now() - startTime);
                    sendNet({
                        method: xhr.__dino_method || 'GET',
                        url: xhr.__dino_url || '',
                        status: xhr.status || 0,
                        duration: duration,
                        type: 'xhr'
                    });
                }, { once: true });
                return origSend.apply(this, args);
            };
            maskNative(XMLHttpRequest.prototype.open, 'open');
            maskNative(XMLHttpRequest.prototype.send, 'send');
        })();
        """
        ucc.addUserScript(WKUserScript(source: networkInterceptor, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        ucc.addUserScript(WKUserScript(source: networkInterceptor, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))

        // Dino Sub-Frame Script: Pierces cross-origin iframes (Stripe, OAuth, reCAPTCHA, embeds)
        // Injected with forMainFrameOnly: false at document start so nested execution contexts are captured immediately.
        let framePiercerScript = """
        (function() {
            if (window.__dino_frame_injected) return;
            window.__dino_frame_injected = true;

            // Only run agent message listener and element scanner inside subframes (window !== window.top)
            if (window !== window.top) {
                function scanFrameElements() {
                    var list = [];
                    var sel = 'a, button, input, textarea, select, details, summary, h1, h2, h3, h4, h5, h6, img, li, p, td, th, pre, code, blockquote, canvas, [draggable], [ondragstart], [ondrop], [id*="hit"], [id*="drag"], [id*="drop"], [class*="drag"], [class*="drop"], [class*="dropzone"], [role="button"], [role="link"], [role="checkbox"], [role="radio"], [role="combobox"], [role="menuitem"], [role="tab"], [role="switch"], [role="option"], [role="heading"], [role="listitem"], [role="status"], [role="alert"], [role="cell"], [tabindex]:not([tabindex="-1"]), [contenteditable="true"]';
                    try {
                        var found = document.querySelectorAll(sel);
                        var counter = 1;
                        for (var i = 0; i < found.length; i++) {
                            var el = found[i];
                            var rect = el.getBoundingClientRect();
                            if (rect.width <= 0 || rect.height <= 0) continue;
                            var style = window.getComputedStyle(el);
                            if (style.display === 'none' || style.visibility === 'hidden') continue;
                            
                            var id = el.getAttribute('data-dino-id') || ('e' + (counter++));
                            el.setAttribute('data-dino-id', id);
                            var tag = el.tagName.toLowerCase();
                            var domId = el.id ? String(el.id).trim() : null;
                            var text = (el.getAttribute('aria-label') || el.placeholder || el.innerText || el.textContent || '').trim().replace(/\\s+/g, ' ').substring(0, 120);
                            if (!text && (tag === 'input' || tag === 'select' || tag === 'textarea')) {
                                if (el.id) {
                                    var lbl = document.querySelector('label[for="' + el.id + '"]');
                                    if (lbl) text = (lbl.innerText || lbl.textContent || '').trim();
                                }
                                if (!text && el.closest) {
                                    var parentLbl = el.closest('label');
                                    if (parentLbl) {
                                        var cloned = parentLbl.cloneNode(true);
                                        var chInputs = cloned.querySelectorAll('input, select, textarea');
                                        for (var ci = 0; ci < chInputs.length; ci++) chInputs[ci].remove();
                                        text = (cloned.innerText || cloned.textContent || '').trim();
                                    }
                                }
                            }
                            if (!text && (tag === 'canvas' || el.draggable === true || el.id === 'hit')) {
                                text = domId ? ('#' + domId) : (tag === 'canvas' ? 'canvas' : '');
                            }
                            var val = (tag === 'input' || tag === 'textarea' || tag === 'select') ? String(el.value || '').substring(0, 50) : null;
                            var rawType = (el.type || el.getAttribute('type') || '').toLowerCase();
                            var isChecked = Boolean(
                                el.checked ||
                                el.getAttribute('aria-checked') === 'true' ||
                                (el.querySelector && el.querySelector('input') && (el.querySelector('input').checked || el.querySelector('input').getAttribute('aria-checked') === 'true'))
                            );
                            
                            list.push({
                                id: id,
                                tag: tag,
                                domId: domId,
                                role: el.getAttribute('role') || tag,
                                text: text,
                                value: val,
                                type: rawType || null,
                                checked: isChecked,
                                disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true'),
                                selected: Boolean(el.selected || el.getAttribute('aria-selected') === 'true'),
                                readOnly: Boolean(el.readOnly || el.getAttribute('aria-readonly') === 'true'),
                                bounds: {
                                    x: Math.round(rect.left),
                                    y: Math.round(rect.top),
                                    width: Math.round(rect.width),
                                    height: Math.round(rect.height)
                                }
                            });
                        }
                    } catch(e) {}

                    // Fallback for raw text, JSON, or minimal bodies rendered in navigated subframes
                    if (list.length === 0 && document.body) {
                        try {
                            var bText = (document.body.innerText || document.body.textContent || '').trim().replace(/\\s+/g, ' ').substring(0, 200);
                            if (bText.length > 0) {
                                var br = document.body.getBoundingClientRect();
                                list.push({
                                    id: 'e1',
                                    tag: 'body',
                                    role: 'document',
                                    text: bText,
                                    value: null,
                                    type: null,
                                    checked: false,
                                    disabled: false,
                                    selected: false,
                                    readOnly: false,
                                    bounds: {
                                        x: Math.max(0, Math.round(br.left)),
                                        y: Math.max(0, Math.round(br.top)),
                                        width: Math.max(20, Math.round(br.width || window.innerWidth)),
                                        height: Math.max(20, Math.round(br.height || window.innerHeight))
                                    }
                                });
                            }
                        } catch(e) {}
                    }
                    return list;
                }

                function reportToTop(assignedId) {
                    try {
                        var fid = assignedId || window.__dino_frame_id || null;
                        var elements = scanFrameElements();
                        var payload = {
                            type: '__dino_frame_report',
                            frameId: fid,
                            url: window.location.href,
                            title: document.title || '',
                            elements: elements
                        };
                        try { window.top.postMessage(payload, '*'); } catch(e) {}
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dinoFrameBridge) {
                            try {
                                window.webkit.messageHandlers.dinoFrameBridge.postMessage({
                                    frameId: fid,
                                    url: window.location.href,
                                    title: document.title || '',
                                    elementCount: elements.length,
                                    elements: elements
                                });
                            } catch(e) {}
                        }
                        return payload;
                    } catch(e) {
                        return { type: '__dino_frame_report', frameId: assignedId, url: '', title: '', elements: [] };
                    }
                }

                // Listen for scan requests and action execution dispatched from top frame
                window.addEventListener('message', function(e) {
                    if (!e.data || typeof e.data !== 'object') return;
                    if (e.data.type === '__dino_frame_request_scan') {
                        if (e.data.frameId) {
                            window.__dino_frame_id = e.data.frameId;
                        }
                        var fid = e.data.frameId || window.__dino_frame_id || null;
                        var rep = reportToTop(fid);
                        if (e.ports && e.ports[0]) {
                            try { e.ports[0].postMessage({ success: true, count: rep.elements.length, frameId: fid, report: rep }); } catch(err) {}
                        }
                    } else if (e.data.type === '__dino_frame_action') {
                        var targetId = e.data.target;
                        var actionObj = e.data.action || {};
                        var act = (actionObj.action || actionObj.type || 'click').toLowerCase();
                        var targetEl = document.querySelector('[data-dino-id="' + targetId + '"]') || document.getElementById(targetId);
                        if (!targetEl) {
                            try {
                                e.source.postMessage({
                                    type: '__dino_frame_action_result',
                                    actionId: e.data.actionId,
                                    result: { success: false, code: 'ELEMENT_NOT_FOUND', message: 'Element ' + targetId + ' not found in frame' }
                                }, '*');
                            } catch(err) {}
                            return;
                        }
                        try { targetEl.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(err) {}
                        if (act === 'click') {
                            try { targetEl.focus(); } catch(err) {}
                            targetEl.click();
                            if (targetEl.tagName !== 'INPUT') {
                                var innerInput = targetEl.querySelector ? targetEl.querySelector('input') : null;
                                if (innerInput) {
                                    try { innerInput.focus(); } catch(err) {}
                                    innerInput.click();
                                }
                            }
                            var isLink = (targetEl.tagName === 'A' || Boolean(targetEl.closest && targetEl.closest('a')));
                            if (!isLink) {
                                reportToTop(window.__dino_frame_id);
                            }
                        } else if (act === 'type') {
                            try { targetEl.focus(); } catch(err) {}
                            targetEl.value = actionObj.text || '';
                            targetEl.dispatchEvent(new Event('input', { bubbles: true }));
                            targetEl.dispatchEvent(new Event('change', { bubbles: true }));
                            if (actionObj.submit) {
                                targetEl.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
                                targetEl.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
                            }
                            reportToTop(window.__dino_frame_id);
                        } else if (act === 'clear') {
                            try { targetEl.focus(); } catch(err) {}
                            targetEl.value = '';
                            targetEl.dispatchEvent(new Event('input', { bubbles: true }));
                            targetEl.dispatchEvent(new Event('change', { bubbles: true }));
                            reportToTop(window.__dino_frame_id);
                        }
                        try {
                            e.source.postMessage({
                                type: '__dino_frame_action_result',
                                actionId: e.data.actionId,
                                result: { success: true, message: 'Executed ' + act + ' on ' + targetId + ' in frame', elementId: targetId }
                            }, '*');
                        } catch(err) {}
                    }
                });

                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', function() { reportToTop(); });
                } else {
                    reportToTop();
                }
                window.addEventListener('load', function() { reportToTop(); });
                window.addEventListener('pageshow', function() { reportToTop(); });
            }
        })();
        """
        ucc.addUserScript(WKUserScript(source: framePiercerScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: DinoDOMScript.core, injectionTime: .atDocumentEnd, forMainFrameOnly: false))

        return config
    }
}

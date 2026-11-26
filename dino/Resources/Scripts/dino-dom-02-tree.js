        var coreEngine = {
            elements: {},
            isTextEditable: isTextEditable,
            isSensitiveField: isSensitiveField,
            isSensitiveValue: isSensitiveValue,
            isLuhnValid: isLuhnValid,
            dispatchHtml5Drag: dispatchHtml5Drag,

            // Actively synchronize and scan all visible subframes (fixes async timing and in-frame navigation)
            syncSubframes: function(timeoutMs) {
                return new Promise(function(resolve) {
                    var iframes = document.querySelectorAll('iframe');
                    if (!iframes || iframes.length === 0) {
                        resolve({ count: 0 });
                        return;
                    }
                    var targets = [];
                    for (var fi = 0; fi < iframes.length; fi++) {
                        var ifr = iframes[fi];
                        var rect = ifr.getBoundingClientRect();
                        if (rect.width <= 5 || rect.height <= 5) continue;
                        var style = window.getComputedStyle(ifr);
                        if (style.display === 'none' || style.visibility === 'hidden') continue;
                        var fId = ifr.getAttribute('data-dino-frame') || ('f' + (fi + 1));
                        ifr.setAttribute('data-dino-frame', fId);
                        targets.push({ ifr: ifr, frameId: fId });
                    }
                    if (targets.length === 0) {
                        resolve({ count: 0 });
                        return;
                    }

                    var pending = targets.length;
                    var settled = false;
                    var timer = setTimeout(function() {
                        if (!settled) {
                            settled = true;
                            resolve({ count: targets.length, timedOut: true });
                        }
                    }, Math.max(50, timeoutMs || 180));

                    function checkDone() {
                        if (pending <= 0 && !settled) {
                            settled = true;
                            clearTimeout(timer);
                            resolve({ count: targets.length, ready: true });
                        }
                    }

                    for (var ti = 0; ti < targets.length; ti++) {
                        var target = targets[ti];
                        try {
                            if (target.ifr.contentWindow) {
                                var ch = new MessageChannel();
                                (function(tgt) {
                                    ch.port1.onmessage = function(ev) {
                                        if (ev && ev.data && ev.data.report) {
                                            var r = ev.data.report;
                                            var fid = ev.data.frameId || tgt.frameId;
                                            if (!window.__dino_frames) window.__dino_frames = {};
                                            window.__dino_frames[fid] = {
                                                frameId: fid,
                                                url: r.url || '',
                                                title: r.title || '',
                                                elements: r.elements || [],
                                                source: tgt.ifr.contentWindow,
                                                updatedAt: Date.now()
                                            };
                                        }
                                        pending--;
                                        checkDone();
                                    };
                                    tgt.ifr.contentWindow.postMessage({
                                        type: '__dino_frame_request_scan',
                                        frameId: tgt.frameId
                                    }, '*', [ch.port2]);
                                })(target);
                            } else {
                                pending--;
                                checkDone();
                            }
                        } catch(e) {
                            pending--;
                            checkDone();
                        }
                    }
                    if (pending === 0) checkDone();
                });
            },

            // Viewport-relative bounding rect accounting for parent frame offsets
            getElementViewportRect: function(element) {
                if (!element) return { left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0, isEditable: false, tagName: '' };
                if (typeof element === 'string') {
                    var frameTarget = parseFrameTarget(element);
                    if (!frameTarget && /^f[0-9]+$/i.test(element)) {
                        frameTarget = { frameId: element, elementId: null };
                    }
                    if (frameTarget) {
                        var fId = frameTarget.frameId;
                        var eId = frameTarget.elementId;
                        var ifr = document.querySelector('iframe[data-dino-frame="' + fId + '"]');
                        if (!ifr && fId.indexOf('f') === 0) {
                            var fIdx = parseInt(fId.substring(1), 10) - 1;
                            var allIframes = document.querySelectorAll('iframe');
                            if (fIdx >= 0 && fIdx < allIframes.length) {
                                ifr = allIframes[fIdx];
                                try { ifr.setAttribute('data-dino-frame', fId); } catch(e) {}
                            }
                        }
                        if (!ifr && this.findInTree) {
                            try {
                                ifr = this.findInTree(document, 'iframe[data-dino-frame="' + fId + '"]') || (fId === 'f1' ? this.findInTree(document, 'iframe') : null);
                            } catch(e) {}
                        }
                        if (ifr) {
                            var ifrRect = ifr.getBoundingClientRect();
                            if (eId) {
                                // 1. Attempt live resolution in same-origin frame DOM
                                try {
                                    var fDoc = ifr.contentDocument || (ifr.contentWindow ? ifr.contentWindow.document : null);
                                    if (fDoc) {
                                        var subEl = null;
                                        if (ifr.contentWindow && ifr.contentWindow.__dino && ifr.contentWindow.__dino.elements) {
                                            subEl = ifr.contentWindow.__dino.elements[eId];
                                        }
                                        if (!subEl) {
                                            try { subEl = fDoc.querySelector('[data-dino-id="' + CSS.escape(eId) + '"]'); } catch(e) {}
                                        }
                                        if (!subEl) {
                                            try { subEl = fDoc.querySelector('[data-dino-id="' + CSS.escape(element) + '"]'); } catch(e) {}
                                        }
                                        if (!subEl) {
                                            try { subEl = fDoc.querySelector(eId); } catch(e) {}
                                        }
                                        if (subEl) {
                                            var subRect = subEl.getBoundingClientRect();
                                            if (subRect.width > 0 && subRect.height > 0) {
                                                return {
                                                    left: Math.round(ifrRect.left + subRect.left),
                                                    top: Math.round(ifrRect.top + subRect.top),
                                                    right: Math.round(ifrRect.left + subRect.left + subRect.width),
                                                    bottom: Math.round(ifrRect.top + subRect.top + subRect.height),
                                                    width: Math.round(subRect.width),
                                                    height: Math.round(subRect.height),
                                                    isEditable: isTextEditable(subEl),
                                                    tagName: (subEl.tagName || '').toLowerCase()
                                                };
                                            }
                                        }
                                    }
                                } catch(e) {}

                                // 2. Cross-origin / postMessage cached frame elements
                                var fData = window.__dino_frames && window.__dino_frames[fId];
                                if (fData && fData.elements) {
                                    for (var ei = 0; ei < fData.elements.length; ei++) {
                                        var fel = fData.elements[ei];
                                        if (fel.id === eId || fel.id === element || fel.id === (fId + ':' + eId)) {
                                            var eb = fel.bounds;
                                            if (eb && (eb.width > 0 || eb.height > 0)) {
                                                var fTag = (fel.tag || '').toLowerCase();
                                                var fType = (fel.type || 'text').toLowerCase();
                                                var nonText = ['checkbox', 'radio', 'button', 'submit', 'reset', 'image', 'file', 'range', 'color', 'hidden'];
                                                var fEditable = (fTag === 'textarea' || (fTag === 'input' && nonText.indexOf(fType) === -1)) && !fel.readOnly && !fel.disabled;
                                                return {
                                                    left: Math.round(ifrRect.left + eb.x),
                                                    top: Math.round(ifrRect.top + eb.y),
                                                    right: Math.round(ifrRect.left + eb.x + eb.width),
                                                    bottom: Math.round(ifrRect.top + eb.y + eb.height),
                                                    width: Math.round(eb.width),
                                                    height: Math.round(eb.height),
                                                    isEditable: fEditable,
                                                    tagName: fTag
                                                };
                                            }
                                        }
                                    }
                                }
                            } else {
                                return {
                                    left: Math.round(ifrRect.left),
                                    top: Math.round(ifrRect.top),
                                    right: Math.round(ifrRect.right),
                                    bottom: Math.round(ifrRect.bottom),
                                    width: Math.round(ifrRect.width),
                                    height: Math.round(ifrRect.height),
                                    isEditable: false,
                                    tagName: 'iframe'
                                };
                            }
                        }
                    }

                    // 3. Resolve live top-level DOM node first (accurate geometry & isTextEditable)
                    var resolvedNode = (this.elements && this.elements[element] && this.isNodeConnected(this.elements[element]) ? this.elements[element] : null) || this.findInTree(document, element);
                    if (!resolvedNode) {
                        resolvedNode = this.reanchorElement(element);
                    }
                    if (resolvedNode) {
                        element = resolvedNode;
                        this.lastInteractedElement = resolvedNode;
                    } else {
                        // 4. Fallback to elementsBounds cache from getSemanticTree (e.g. cross-origin subframes)
                        var cache = this.elementsBounds || window.__dino_elements_bounds;
                        if (cache && cache[element]) {
                            var cb = cache[element];
                            if (cb && (cb.width > 0 || cb.height > 0)) {
                                return cb;
                            }
                        }
                        return { left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0, isEditable: false, tagName: '' };
                    }
                }
                var r = element.getBoundingClientRect();
                var curWin = (element.ownerDocument && element.ownerDocument.defaultView) ? element.ownerDocument.defaultView : window;
                var x = r.left;
                var y = r.top;
                try {
                    while (curWin && curWin !== window && curWin.frameElement) {
                        var fr = curWin.frameElement.getBoundingClientRect();
                        x += fr.left;
                        y += fr.top;
                        curWin = curWin.parent;
                    }
                } catch(e) {}
                return {
                    left: Math.round(x),
                    top: Math.round(y),
                    right: Math.round(x + r.width),
                    bottom: Math.round(y + r.height),
                    width: Math.round(r.width),
                    height: Math.round(r.height),
                    isEditable: isTextEditable(element),
                    tagName: (element.tagName || '').toLowerCase()
                };
            },

            // Checks whether an element is connected to the live DOM tree, even inside nested frames
            isNodeConnected: function(node) {
                if (!node) return false;
                if (typeof node.isConnected === 'boolean') {
                    if (!node.isConnected) return false;
                    var doc = node.ownerDocument;
                    if (doc && doc !== document && doc.defaultView && doc.defaultView.frameElement) {
                        return this.isNodeConnected(doc.defaultView.frameElement);
                    }
                    return true;
                }
                var root = node.getRootNode ? node.getRootNode() : null;
                return root === document;
            },

            // Searches for an element by ID/selector across document, open Shadow DOM, and nested iframes
            findInTree: function(root, sel) {
                if (!root) return null;
                try {
                    var dinoId = root.querySelector('[data-dino-id="' + CSS.escape(sel) + '"]');
                    if (dinoId) return dinoId;
                } catch(e) {}
                try {
                    var byId = (root.getElementById ? root.getElementById(sel) : null) || root.querySelector('#' + CSS.escape(sel));
                    if (byId) return byId;
                } catch(e) {}
                try {
                    var byAttr = root.querySelector('[name="' + CSS.escape(sel) + '"]') ||
                                 root.querySelector('[data-testid="' + CSS.escape(sel) + '"]') ||
                                 root.querySelector('[aria-label="' + CSS.escape(sel) + '"]');
                    if (byAttr) return byAttr;
                } catch(e) {}
                try {
                    var found = root.querySelector(sel);
                    if (found) return found;
                } catch(e) {}
                try {
                    var all = root.querySelectorAll('*');
                    for (var i = 0; i < all.length; i++) {
                        var n = all[i];
                        if (n.shadowRoot) {
                            var sFound = this.findInTree(n.shadowRoot, sel);
                            if (sFound) return sFound;
                        } else if (n.tagName === 'IFRAME') {
                            try {
                                var fDoc = n.contentDocument || (n.contentWindow ? n.contentWindow.document : null);
                                if (fDoc) {
                                    var iFound = this.findInTree(fDoc, sel);
                                    if (iFound) return iFound;
                                }
                            } catch(err) {}
                        }
                    }
                } catch(e) {}
                return null;
            },

            // Reliably scrolls and focuses an editable target, verifying activeElement state
            focusElement: function(element) {
                if (!element) return { success: false, code: 'MISSING_TARGET', message: 'No target element to focus' };
                if (typeof element === 'string') {
                    var frameTarget = parseFrameTarget(element);
                    if (frameTarget) {
                        var fId = frameTarget.frameId;
                        var eId = frameTarget.elementId;
                        var ifr = document.querySelector('iframe[data-dino-frame="' + fId + '"]');
                        if (!ifr && fId.indexOf('f') === 0) {
                            var fIdx = parseInt(fId.substring(1), 10) - 1;
                            var allIfrs = document.querySelectorAll('iframe');
                            if (fIdx >= 0 && fIdx < allIfrs.length) ifr = allIfrs[fIdx];
                        }
                        if (ifr) {
                            try {
                                if (ifr.scrollIntoViewIfNeeded) ifr.scrollIntoViewIfNeeded();
                                else ifr.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                            } catch(e) {}
                            try { if (ifr.contentWindow) ifr.contentWindow.focus(); } catch(e) {}
                            try {
                                if (ifr.contentDocument && eId) {
                                    var fEl = (ifr.contentWindow.__dino && ifr.contentWindow.__dino.elements && ifr.contentWindow.__dino.elements[eId]) ||
                                              ifr.contentDocument.querySelector('[data-dino-id="' + eId + '"]') ||
                                              ifr.contentDocument.querySelector(eId);
                                    if (fEl) {
                                        try { fEl.focus({ preventScroll: true }); } catch(e) {}
                                        return { success: true, activeTag: (fEl.tagName || '').toLowerCase(), code: 'SUCCESS', message: 'Element focused in frame' };
                                    }
                                }
                            } catch(e) {}
                            return { success: true, activeTag: 'iframe', code: 'SUCCESS', message: 'Frame focused' };
                        }
                    }
                    var resolvedNode = (this.elements && this.elements[element] && this.isNodeConnected(this.elements[element]) ? this.elements[element] : null) || this.findInTree(document, element);
                    if (resolvedNode) element = resolvedNode;
                    else return { success: false, code: 'ELEMENT_NOT_FOUND', message: 'Target element not found to focus' };
                }
                try {
                    if (element.ownerDocument && element.ownerDocument !== document && element.ownerDocument.defaultView && element.ownerDocument.defaultView.frameElement) {
                        try { element.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                        try { element.ownerDocument.defaultView.focus(); } catch(e) {}
                    }
                    if (element.scrollIntoView) {
                        try { element.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                    }
                    element.focus({ preventScroll: true });
                } catch(e) {
                    return { success: false, code: 'FOCUS_ERROR', message: e.message || 'Error focusing element' };
                }
                var doc = element.ownerDocument || document;
                var active = doc.activeElement;
                var isFocused = (active === element) || (element.contains && element.contains(active));
                if (!isFocused && element.isContentEditable) {
                    try {
                        var win = doc.defaultView || window;
                        var sel = win.getSelection();
                        if (sel) {
                            var range = doc.createRange();
                            range.selectNodeContents(element);
                            range.collapse(false);
                            sel.removeAllRanges();
                            sel.addRange(range);
                        }
                        isFocused = true;
                    } catch(e) {}
                }
                var activeTag = active && active.tagName ? active.tagName.toLowerCase() : 'body';
                return {
                    success: isFocused,
                    activeTag: activeTag,
                    code: isFocused ? 'SUCCESS' : 'FOCUS_FAILED',
                    message: isFocused ? 'Element focused' : ('Failed to establish focus on <' + (element.tagName || '').toLowerCase() + '>; activeElement is <' + activeTag + '>')
                };
            },

            // 1. Scans visible interactive targets across Light and Shadow DOM and iframes
            getSemanticTree: function(options) {
                options = options || {};
                var limit = options.limit !== undefined ? Number(options.limit) : 100;
                var offset = options.offset !== undefined ? Number(options.offset) : 0;
                var viewportOnly = Boolean(options.viewportOnly);
                var includeText = options.includeText !== undefined ? Boolean(options.includeText) : true;
                var roleFilter = options.role ? String(options.role).toLowerCase().trim() : null;
                var textFilter = options.text ? String(options.text).toLowerCase().trim() : null;
                var targetFilter = options.target ? String(options.target).trim() : null;
                var depthLimit = (options.depth !== undefined && options.depth !== null) ? Number(options.depth) : null;
                var trackMutations = Boolean(options.track);

                if (!this.elements) this.elements = {};
                if (!this.elementSignatures) this.elementSignatures = {};
                this.elementsBounds = {};
                for (var oldId in this.elements) {
                    if (!this.isNodeConnected(this.elements[oldId])) {
                        delete this.elements[oldId];
                    }
                }
                var results = [];
                var counter = 1;

                if (document.body) { void document.body.offsetHeight; }
                var vpW = window.innerWidth;
                var vpH = window.innerHeight;

                // Scoping root resolution for target filter
                var scopeRoot = document;
                var resolvedTargetEl = null;
                if (targetFilter) {
                    if (this.elements && this.elements[targetFilter] && this.isNodeConnected(this.elements[targetFilter])) {
                        resolvedTargetEl = this.elements[targetFilter];
                    } else {
                        try {
                            resolvedTargetEl = (this.findInTree ? this.findInTree(document, targetFilter) : null) || document.querySelector(targetFilter);
                        } catch(e) {}
                    }
                    if (resolvedTargetEl) {
                        scopeRoot = resolvedTargetEl;
                    } else {
                        var notFoundOrigin = window.location.href || '';
                        var notFoundSummary = '<!-- BEGIN UNTRUSTED WEB CONTENT (origin: ' + notFoundOrigin + ') -->\\n[Page: ' + (document.title || 'Untitled') + ' | Target: ' + targetFilter + ' (not found) | URL: ' + notFoundOrigin + ']\\nInteractive Elements (0 of 0):\\n<!-- Target not found in DOM -->\\n<!-- END UNTRUSTED WEB CONTENT -->';
                        return {
                            title: document.title || '',
                            url: notFoundOrigin,
                            target: targetFilter,
                            tracked: null,
                            viewportWidth: vpW,
                            viewportHeight: vpH,
                            totalElements: 0,
                            filteredTotal: 0,
                            unfilteredTotal: 0,
                            elements: [],
                            summary: notFoundSummary,
                            securityBoundary: { untrusted: true, origin: notFoundOrigin },
                            tokenEstimate: Math.round(notFoundSummary.length / 4)
                        };
                    }
                }

                // Relative tree depth calculator
                function getNodeDepth(node, root) {
                    if (!node || node === root) return 0;
                    var d = 0;
                    var cur = node;
                    while (cur && cur !== root && cur !== document.documentElement && cur !== document.body) {
                        d++;
                        cur = cur.parentNode || (cur.getRootNode && cur.getRootNode().host);
                    }
                    return d;
                }

                // Recursive collector penetrating open Shadow DOM roots and same-origin / srcdoc iframes
                function collectNodes(root, list) {
                    if (!root) return;
                    if (root.shadowRoot) {
                        collectNodes(root.shadowRoot, list);
                    }
                    var selector = 'a, button, input, textarea, select, details, summary, h1, h2, h3, h4, h5, h6, img, li, p, td, th, pre, code, blockquote, canvas, [draggable], [ondragstart], [ondrop], [id*="hit"], [id*="drag"], [id*="drop"], [class*="drag"], [class*="drop"], [class*="dropzone"], [role="button"], [role="link"], [role="checkbox"], [role="radio"], [role="combobox"], [role="menuitem"], [role="tab"], [role="switch"], [role="option"], [role="heading"], [role="listitem"], [role="status"], [role="alert"], [role="cell"], [tabindex]:not([tabindex="-1"]), [contenteditable="true"], [oncontextmenu], [data-contextmenu], [data-context-menu], [contextmenu], [aria-haspopup="menu"], [onclick], [data-toggle], [data-action], [data-target], [data-pages], [class*="sidebar"], [class*="hamburger"], [class*="nav-toggle"], [class*="menu-toggle"], [class*="navbar-toggler"], iframe';
                    try {
                        var found = root.querySelectorAll(selector);
                        for (var i = 0; i < found.length; i++) {
                            var fn = found[i];
                            if (depthLimit !== null && getNodeDepth(fn, scopeRoot) > depthLimit) continue;
                            if (list.indexOf(fn) === -1) list.push(fn);
                        }
                        var all = root.querySelectorAll('*');
                        for (var j = 0; j < all.length; j++) {
                            var n = all[j];
                            if (depthLimit !== null && getNodeDepth(n, scopeRoot) > depthLimit) continue;
                            if (n.shadowRoot) {
                                collectNodes(n.shadowRoot, list);
                            } else if (n.tagName === 'CANVAS' || n.draggable === true || n.id === 'hit' || (n.id && (n.id.indexOf('hit') !== -1 || n.id.indexOf('drag') !== -1 || n.id.indexOf('drop') !== -1)) || isMeaningfulTextLeaf(n) || isDropzone(n)) {
                                if (list.indexOf(n) === -1) list.push(n);
                            }
                        }
                    } catch(e) {}
                }

                // Resolves implicit ARIA role based on W3C HTML-AAM mapping if not explicitly defined
                function getImplicitAriaRole(el) {
                    if (!el || !el.tagName) return 'generic';
                    var explicit = el.getAttribute('role');
                    if (explicit) return explicit.trim().toLowerCase();
                    var tag = el.tagName.toLowerCase();
                    if (tag === 'a' || tag === 'area') {
                        return (el.hasAttribute('href') || el.href) ? 'link' : 'generic';
                    }
                    if (tag === 'button') return 'button';
                    if (tag === 'input') {
                        var type = (el.type || 'text').toLowerCase();
                        if (type === 'button' || type === 'submit' || type === 'reset' || type === 'image') return 'button';
                        if (type === 'checkbox') return 'checkbox';
                        if (type === 'radio') return 'radio';
                        if (type === 'search') return 'searchbox';
                        if (type === 'number') return 'spinbutton';
                        if (type === 'range') return 'slider';
                        if (type === 'email' || type === 'password' || type === 'tel' || type === 'text' || type === 'url' || !type) return 'textbox';
                        return type;
                    }
                    if (tag === 'textarea') return 'textbox';
                    if (tag === 'select') return 'combobox';
                    if (tag === 'option') return 'option';
                    if (tag === 'summary') return 'button';
                    if (tag === 'details') return 'group';
                    if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') return 'heading';
                    if (tag === 'img') return 'img';
                    if (tag === 'li') return 'listitem';
                    if (tag === 'ul' || tag === 'ol') return 'list';
                    if (tag === 'table') return 'table';
                    if (tag === 'tr') return 'row';
                    if (tag === 'td') return 'cell';
                    if (tag === 'th') return 'columnheader';
                    if (tag === 'p' || tag === 'pre' || tag === 'code' || tag === 'blockquote') return 'paragraph';
                    if (tag === 'nav') return 'navigation';
                    if (tag === 'main') return 'main';
                    if (tag === 'header') return 'banner';
                    if (tag === 'footer') return 'contentinfo';
                    if (tag === 'article') return 'article';
                    if (tag === 'section') return 'region';
                    if (tag === 'form') return 'form';
                    if (isMeaningfulTextLeaf(el)) return 'text';
                    return tag;
                }

                // Infers human-readable labels for icon-only buttons, menus, and controls
                function resolveIconLabel(el, rawText) {
                    if (!el) return '';
                    var txt = (rawText || '').trim();

                    // 1. Check known icon unicode characters and common ligatures
                    if (/[\u2630\u2261\uE5D2\u268C]/.test(txt) || txt === 'menu' || txt === 'bars') {
                        return 'Navigation Menu (☰)';
                    }
                    if (/[\uD83D\uDD0D\u2315]/.test(txt) || txt === 'search') {
                        return 'Search';
                    }
                    if (/[\u2715\u2716\u00D7\u2573]/.test(txt) || txt === 'close' || txt === 'clear') {
                        return 'Close';
                    }
                    if (/[\uD83D\uDD14\u220E]/.test(txt) || txt === 'notifications' || txt === 'bell' || txt === 'notifications_none') {
                        return 'Notifications';
                    }
                    if (txt === 'account_circle' || txt === 'person' || txt === 'user') {
                        return 'Profile / Account';
                    }
                    if (txt === 'settings' || txt === 'tune' || txt === 'gear') {
                        return 'Settings';
                    }
                    if (txt === 'arrow_back' || txt === 'chevron_left' || txt === '←') {
                        return 'Back';
                    }
                    if (txt === 'arrow_forward' || txt === 'chevron_right' || txt === '→') {
                        return 'Next';
                    }

                    // If rawText already has meaningful alphanumeric content (>1 char), use it
                    if (txt && /[a-zA-Z0-9]{2,}/.test(txt)) {
                        return txt;
                    }

                    // 2. Check tooltip, data attributes, and titles
                    var dataToggle = el.getAttribute ? (
                        el.getAttribute('data-toggle') ||
                        el.getAttribute('data-action') ||
                        el.getAttribute('data-target') ||
                        el.getAttribute('data-pages') ||
                        el.getAttribute('data-init') ||
                        ''
                    ) : '';
                    if (dataToggle) {
                        var dtLow = dataToggle.toLowerCase();
                        if (dtLow.indexOf('sidebar') !== -1 || dtLow.indexOf('menu') !== -1 || dtLow.indexOf('nav') !== -1) {
                            return 'Navigation Menu (☰)';
                        }
                        if (dtLow.indexOf('dropdown') !== -1) return 'Dropdown Menu';
                        if (dtLow.indexOf('collapse') !== -1) return 'Toggle Menu (☰)';
                    }
                    var origTitle = el.getAttribute ? (el.getAttribute('data-original-title') || el.getAttribute('title')) : null;
                    if (origTitle && origTitle.trim()) return origTitle.trim();

                    // 3. Check SVG title / desc / aria-label / data-icon
                    if (el.querySelector) {
                        var svg = el.querySelector('svg');
                        if (svg) {
                            var st = svg.querySelector('title, desc');
                            if (st && st.textContent && st.textContent.trim()) return st.textContent.trim();
                            if (svg.getAttribute('aria-label')) return svg.getAttribute('aria-label').trim();
                            var dIcon = (svg.getAttribute('data-icon') || svg.getAttribute('id') || '').toLowerCase();
                            if (dIcon.indexOf('bars') !== -1 || dIcon.indexOf('menu') !== -1) return 'Navigation Menu (☰)';
                            if (dIcon.indexOf('search') !== -1) return 'Search';
                            if (dIcon.indexOf('bell') !== -1) return 'Notifications';
                            if (dIcon.indexOf('user') !== -1) return 'Profile / Account';
                            if (dIcon.indexOf('cog') !== -1 || dIcon.indexOf('gear') !== -1) return 'Settings';
                        }
                    }

                    // 4. Check class names of element and child icon tags (i, span, svg)
                    var classAndId = (
                        (el.className && typeof el.className === 'string' ? el.className : '') + ' ' +
                        (el.id || '')
                    ).toLowerCase();

                    if (el.querySelectorAll) {
                        var iconNodes = el.querySelectorAll('i, span, em, svg');
                        for (var idx = 0; idx < iconNodes.length && idx < 6; idx++) {
                            var inNode = iconNodes[idx];
                            if (inNode.className && typeof inNode.className === 'string') {
                                classAndId += ' ' + inNode.className.toLowerCase();
                            }
                            if (inNode.getAttribute) {
                                var dIconSub = inNode.getAttribute('data-icon') || inNode.getAttribute('data-feather') || '';
                                if (dIconSub) classAndId += ' ' + dIconSub.toLowerCase();
                            }
                        }
                    }

                    if (/hamburger|fa-bars|icon-bars|icon-menu|navbar-toggler|sidebar-toggle|sidebar-nav|nav-toggle|menu-toggle|drawer-toggle|\bmenu\b|\bnavigation\b|\bnav-item\b/.test(classAndId)) {
                        return 'Navigation Menu (☰)';
                    }
                    if (/search|magnif/.test(classAndId)) {
                        return 'Search';
                    }
                    if (/close|dismiss|clear|times/.test(classAndId)) {
                        return 'Close';
                    }
                    if (/bell|notif|alert/.test(classAndId)) {
                        return 'Notifications';
                    }
                    if (/user|avatar|profile|account/.test(classAndId)) {
                        return 'Profile / Account';
                    }
                    if (/gear|cog|settings|config/.test(classAndId)) {
                        return 'Settings';
                    }
                    if (/filter/.test(classAndId)) {
                        return 'Filter';
                    }
                    if (/refresh|reload|sync/.test(classAndId)) {
                        return 'Refresh';
                    }
                    if (/download/.test(classAndId)) {
                        return 'Download';
                    }
                    if (/upload/.test(classAndId)) {
                        return 'Upload';
                    }
                    if (/chevron-down|caret-down|angle-down|dropdown/.test(classAndId)) {
                        return 'Dropdown';
                    }
                    if (/chevron-up|caret-up|angle-up/.test(classAndId)) {
                        return 'Collapse';
                    }
                    if (/chevron-right|caret-right|angle-right|arrow-right/.test(classAndId)) {
                        return 'Next';
                    }
                    if (/chevron-left|caret-left|angle-left|arrow-left/.test(classAndId)) {
                        return 'Back';
                    }
                    if (/grid|apps|th-large/.test(classAndId)) {
                        return 'Apps Grid';
                    }

                    return txt;
                }

                // Resolve accessible label using ARIA, label tags, placeholder, title, adjacent labels, and text
                function getAccessibleLabel(el) {
                    try {
                        // Strict redaction of password and sensitive inputs: NEVER return value or prefilled text
                        if (isSensitiveField(el) || isSensitiveValue(el.value)) {
                            if (el.getAttribute('aria-label')) return el.getAttribute('aria-label').trim();
                            if (el.placeholder) return el.placeholder.trim();
                            if (el.id) {
                                var pwL = document.querySelector('label[for="' + el.id + '"]');
                                if (pwL) return (pwL.innerText || pwL.textContent || '').trim();
                            }
                            return '';
                        }

                        if (el.getAttribute('aria-label')) {
                            return el.getAttribute('aria-label').trim();
                        }
                        var labelledBy = el.getAttribute('aria-labelledby');
                        if (labelledBy) {
                            var ref = document.getElementById(labelledBy);
                            if (ref) return (ref.innerText || ref.textContent || '').trim();
                        }
                        if (el.id && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT')) {
                            var l = document.querySelector('label[for="' + el.id + '"]');
                            if (l) return (l.innerText || l.textContent || '').trim();
                        }
                        var parentLabel = el.closest('label');
                        if (parentLabel) {
                            var cloned = parentLabel.cloneNode(true);
                            var inputs = cloned.querySelectorAll('input, select, textarea');
                            for (var k = 0; k < inputs.length; k++) inputs[k].remove();
                            var txt = (cloned.innerText || cloned.textContent || '').trim();
                            if (txt) return txt;
                        }
                        // Adjacent label ONLY for form controls (prevents <label> text bleeding onto unrelated links/buttons)
                        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
                            var prev = el.previousElementSibling;
                            var next = el.nextElementSibling;
                            var adjLabel = (prev && prev.tagName === 'LABEL') ? prev : ((next && next.tagName === 'LABEL') ? next : null);
                            if (adjLabel) {
                                var adjText = (adjLabel.innerText || adjLabel.textContent || '').trim();
                                if (adjText) return adjText;
                            }
                        }
                        if (el.placeholder) return el.placeholder.trim();
                        if (el.getAttribute('title')) return el.getAttribute('title').trim();
                        if (el.tagName === 'INPUT' && (el.type === 'submit' || el.type === 'button') && el.value) {
                            return String(el.value).trim();
                        }
                        var fallbackVal = (isSensitiveField(el) || isSensitiveValue(el.value)) ? '' : (el.value || '');
                        var rawText = (el.innerText || el.textContent || fallbackVal).trim();
                        if (!rawText && (el.tagName === 'CANVAS' || el.draggable === true || el.getAttribute('draggable') !== null || el.id === 'hit' || (el.id && el.id.indexOf('hit') !== -1))) {
                            if (el.id) return '#' + el.id;
                            if (el.className) return '.' + String(el.className).trim().split(' ')[0];
                            if (el.tagName === 'CANVAS') return 'canvas';
                        }
                        if (isSensitiveValue(rawText)) return '';
                        var resolvedIcon = resolveIconLabel(el, rawText);
                        if (resolvedIcon) return resolvedIcon;
                        return rawText;
                    } catch(e) {
                        return '';
                    }
                }

                // Extracts list ordinal index or rank (search results, table rows, ordered lists)
                function getItemRank(el) {
                    try {
                        var item = el.closest('li, tr, article, [role="listitem"]');
                        if (!item) return null;
                        var r = item.querySelector('.rank, [class*="rank"], [class*="index"]');
                        if (r) {
                            var num = (r.innerText || r.textContent || '').replace(/\\D/g, '');
                            if (num) return num;
                        }
                        if (item.tagName === 'LI' && item.parentElement && item.parentElement.tagName === 'OL') {
                            var idx = Array.prototype.indexOf.call(item.parentElement.children, item);
                            if (idx >= 0) return String(idx + 1);
                        }
                    } catch(e) {}
                    return null;
                }

                var allInteractive = [];
                if (scopeRoot !== document) {
                    var rootSel = 'a, button, input, textarea, select, details, summary, h1, h2, h3, h4, h5, h6, img, li, p, td, th, pre, code, blockquote, canvas, [draggable], [ondragstart], [ondrop], [id*="hit"], [id*="drag"], [id*="drop"], [class*="drag"], [class*="drop"], [class*="dropzone"], [role="button"], [role="link"], [role="checkbox"], [role="radio"], [role="combobox"], [role="menuitem"], [role="tab"], [role="switch"], [role="option"], [role="heading"], [role="listitem"], [role="status"], [role="alert"], [role="cell"], [tabindex]:not([tabindex="-1"]), [contenteditable="true"]';
                    if (scopeRoot.matches && (scopeRoot.matches(rootSel) || isMeaningfulTextLeaf(scopeRoot) || isDropzone(scopeRoot))) {
                        allInteractive.push(scopeRoot);
                    }
                }
                collectNodes(scopeRoot, allInteractive);

                // Tracking initialization for mutation detection across snapshots
                var prevTracked = (this._lastTrackedIds && typeof this._lastTrackedIds === 'object') ? this._lastTrackedIds : null;
                var addedCount = 0;
                var unchangedCount = 0;

                // Pre-scan existing elements to preserve identity across DOM mutations
                var assignedIds = {};
                var maxIdNum = 0;
                for (var oldK in this.elements) {
                    var nOld = parseInt(oldK.substring(1), 10);
                    if (!isNaN(nOld) && nOld > maxIdNum) maxIdNum = nOld;
                    assignedIds[oldK] = this.elements[oldK];
                }
                for (var k = 0; k < allInteractive.length; k++) {
                    var exId = allInteractive[k].getAttribute('data-dino-id');
                    if (exId && exId.indexOf('e') === 0) {
                        var n = parseInt(exId.substring(1), 10);
                        if (!isNaN(n) && n > 0 && !assignedIds[exId]) {
                            assignedIds[exId] = allInteractive[k];
                            if (n > maxIdNum) maxIdNum = n;
                        }
                    }
                }
                var nextCounter = maxIdNum + 1;

                for (var i = 0; i < allInteractive.length; i++) {
                    var el = allInteractive[i];
                    var d = getNodeDepth(el, scopeRoot);
                    if (depthLimit !== null && d > depthLimit) continue;

                    var rect = this.getElementViewportRect(el);
                    var isInputToggle = (el.tagName === 'INPUT' && (el.type === 'checkbox' || el.type === 'radio'));

                    // Geometry check: elements with zero size are non-rendered
                    if (!isInputToggle && (rect.width <= 0 || rect.height <= 0)) continue;

                    var elWin = (el.ownerDocument && el.ownerDocument.defaultView) || window;
                    var style = elWin.getComputedStyle(el);
                    if (style.display === 'none' || style.visibility === 'hidden') continue;
                    if (parseFloat(style.opacity) < 0.05 && !isInputToggle) continue;
                    if (style.pointerEvents === 'none' && !isInputToggle) continue;

                    var tag = el.tagName.toLowerCase();
                    var role = getImplicitAriaRole(el);
                    var type = el.getAttribute('type') || null;
                    var isTextNode = (tag === 'li' || tag === 'p' || tag === 'td' || tag === 'th' || tag === 'blockquote' || tag === 'pre' || tag === 'code' || tag === 'article' || role === 'listitem' || role === 'status' || role === 'alert' || role === 'cell' || role === 'text' || role === 'paragraph' || isMeaningfulTextLeaf(el));
                    var maxLabelLen = isTextNode ? 600 : 120;

                    var text = getAccessibleLabel(el).replace(/\\s+/g, ' ').substring(0, maxLabelLen);
                    if (isSensitiveValue(text)) {
                        text = '[REDACTED]';
                    }

                    var isSensitive = isSensitiveField(el) || isSensitiveValue(el.value);
                    var val = null;
                    var hasFormValue = (tag === 'input' || tag === 'textarea' || tag === 'select' || tag === 'option' || (tag === 'button' && el.type === 'submit'));
                    if (hasFormValue) {
                        if (isSensitive) {
                            if (el.value) val = '[REDACTED]';
                        } else if (el.value !== undefined && el.value !== '') {
                            val = String(el.value).substring(0, 50);
                        }
                    }

                    var isHeading = (role === 'heading' || tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6');
                    var isImg = (role === 'img' || tag === 'img');
                    var isTextNode = (tag === 'li' || tag === 'p' || tag === 'td' || tag === 'th' || role === 'listitem' || role === 'status' || role === 'alert' || role === 'cell' || role === 'text' || role === 'paragraph' || isMeaningfulTextLeaf(el));

                    // Filter out meaningless whitespace links or empty non-interactive anchors
                    var hasActionableAffordance = Boolean(
                        text || val ||
                        el.querySelector('img, svg') ||
                        (el.getAttribute && (el.getAttribute('data-toggle') || el.getAttribute('data-action') || el.getAttribute('data-target') || el.getAttribute('data-pages') || el.getAttribute('aria-label') || el.getAttribute('title'))) ||
                        (el.className && typeof el.className === 'string' && /menu|nav|sidebar|toggle|btn|icon|action|bars|hamburger/i.test(el.className)) ||
                        (el.id && /menu|nav|sidebar|toggle|btn/i.test(el.id))
                    );
                    if ((tag === 'a' || tag === 'button') && !hasActionableAffordance) {
                        continue;
                    }
                    if (isHeading && !text) {
                        continue;
                    }
                    if (isTextNode) {
                        if (!includeText || (!text && !val)) continue;
                        // Skip parent container if an interactive child already has identical text
                        var childControl = el.querySelector('a, button, input, textarea, select');
                        if (childControl) {
                            var cTxt = (childControl.innerText || childControl.textContent || '').trim();
                            var pTxt = (el.innerText || el.textContent || '').trim();
                            if (cTxt && pTxt === cTxt) continue;
                        }
                    }
                    var src = isImg ? (el.currentSrc || el.src || el.getAttribute('src') || null) : null;
                    var alt = isImg ? (el.alt || el.getAttribute('alt') || null) : null;
                    if (isImg && !src && !alt) {
                        continue;
                    }
                    if (isImg && !text && alt) {
                        text = alt.substring(0, 80);
                    }

                    // Assign persistent, identity-stable id
                    var id = el.getAttribute('data-dino-id');
                    if (!id || assignedIds[id] !== el) {
                        id = 'e' + (nextCounter++);
                        assignedIds[id] = el;
                        try { el.setAttribute('data-dino-id', id); } catch(e) {}
                    }
                    this.elements[id] = el;
                    this.elementSignatures[id] = {
                        tag: tag,
                        id: el.id || null,
                        name: el.getAttribute('name') || null,
                        type: type,
                        role: role,
                        className: (el.className && typeof el.className === 'string') ? el.className.trim() : null,
                        text: text,
                        value: val,
                        placeholder: el.placeholder || null,
                        ariaLabel: el.getAttribute('aria-label') || null,
                        testId: el.getAttribute('data-testid') || null,
                        docY: Math.round(window.scrollY + rect.top),
                        docX: Math.round(window.scrollX + rect.left),
                        width: Math.round(rect.width),
                        height: Math.round(rect.height),
                        ordinal: i
                    };

                    // In-viewport check (top/bottom/left/right relative to viewport)
                    var inViewport = (rect.bottom >= 0 && rect.top <= vpH && rect.right >= 0 && rect.left <= vpW);

                    // Occlusion Hit-Testing (Center Point Check)
                    var isObscured = false;
                    var cx = Math.round(rect.left + rect.width / 2);
                    var cy = Math.round(rect.top + rect.height / 2);
                    if (cx >= 0 && cx <= vpW && cy >= 0 && cy <= vpH && !isInputToggle) {
                        try {
                            var topEl = document.elementFromPoint(cx, cy);
                            var curFrame = (el.ownerDocument && el.ownerDocument.defaultView) ? el.ownerDocument.defaultView.frameElement : null;
                            if (curFrame && topEl === curFrame) {
                                var localRect = el.getBoundingClientRect();
                                var lcx = Math.round(localRect.left + localRect.width / 2);
                                var lcy = Math.round(localRect.top + localRect.height / 2);
                                var innerTop = el.ownerDocument.elementFromPoint(lcx, lcy);
                                if (innerTop && innerTop !== el && !el.contains(innerTop) && !innerTop.contains(el)) {
                                    isObscured = true;
                                }
                            } else if (topEl && topEl !== el && !el.contains(topEl) && !topEl.contains(el)) {
                                var rootNode = el.getRootNode ? el.getRootNode() : null;
                                var host = (rootNode && rootNode.host) ? rootNode.host : null;
                                if (topEl !== host && (!host || !host.contains(topEl))) {
                                    isObscured = true;
                                }
                            }
                        } catch(e) {}
                    }

                    var cls = (el.className && typeof el.className === 'string') ? el.className.trim().split(/\\s+/).slice(0, 2).join('.') : null;
                    var itemRank = getItemRank(el);

                    var disabled = Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true');
                    var checked = Boolean(el.checked || el.getAttribute('aria-checked') === 'true');
                    var selected = Boolean(el.selected || el.getAttribute('aria-selected') === 'true');
                    var focused = Boolean(document.activeElement === el);
                    var readOnly = Boolean(el.readOnly || el.getAttribute('aria-readonly') === 'true');
                    var inShadow = Boolean(el.getRootNode && el.getRootNode().host);
                    var href = (tag === 'a' || tag === 'area') ? (el.getAttribute('href') || el.href || null) : null;
                    var domId = el.id ? String(el.id).trim() : null;
                    var isNew = false;
                    if (trackMutations) {
                        if (prevTracked) {
                            if (!prevTracked[id]) {
                                isNew = true;
                                addedCount++;
                            } else {
                                unchangedCount++;
                            }
                        } else {
                            isNew = true;
                            addedCount++;
                        }
                    }

                    results.push({
                        id: id,
                        tag: tag,
                        role: role,
                        text: text,
                        value: val,
                        type: type,
                        depth: d,
                        isNew: isNew,
                        className: cls,
                        domId: domId,
                        rank: itemRank,
                        isObscured: isObscured,
                        inViewport: inViewport,
                        hasContextMenu: hasContextMenuSupport(el),
                        disabled: disabled,
                        checked: checked,
                        selected: selected,
                        focused: focused,
                        readOnly: readOnly,
                        isInShadowRoot: inShadow,
                        src: src,
                        alt: alt,
                        href: href,
                        bounds: {
                            x: Math.round(rect.left),
                            y: Math.round(rect.top),
                            width: Math.round(rect.width),
                            height: Math.round(rect.height)
                        },
                        box: [
                            Math.round(rect.top),
                            Math.round(rect.left),
                            Math.round(rect.width),
                            Math.round(rect.height)
                        ],
                        norm: [
                            Math.max(0, Math.min(1000, Math.round((rect.top / Math.max(1, vpH)) * 1000))),
                            Math.max(0, Math.min(1000, Math.round((rect.left / Math.max(1, vpW)) * 1000))),
                            Math.max(0, Math.min(1000, Math.round(((rect.top + rect.height) / Math.max(1, vpH)) * 1000))),
                            Math.max(0, Math.min(1000, Math.round(((rect.left + rect.width) / Math.max(1, vpW)) * 1000)))
                        ]
                    });
                }

                // Cross-Origin / Nested Sub-Frame Piercing: aggregate elements from registered iframes
                var iframes = [];
                if (resolvedTargetEl) {
                    if (resolvedTargetEl.tagName === 'IFRAME') {
                        iframes = [resolvedTargetEl];
                    } else if (resolvedTargetEl.querySelectorAll) {
                        iframes = Array.prototype.slice.call(resolvedTargetEl.querySelectorAll('iframe'));
                    }
                } else {
                    iframes = Array.prototype.slice.call(document.querySelectorAll('iframe'));
                }
                for (var fi = 0; fi < iframes.length; fi++) {
                    var ifr = iframes[fi];
                    var ifrRect = ifr.getBoundingClientRect();
                    if (ifrRect.width <= 5 || ifrRect.height <= 5) continue;
                    var ifrStyle = window.getComputedStyle(ifr);
                    if (ifrStyle.display === 'none' || ifrStyle.visibility === 'hidden') continue;

                    var frameId = ifr.getAttribute('data-dino-frame') || ('f' + (fi + 1));
                    ifr.setAttribute('data-dino-frame', frameId);

                    try {
                        ifr.contentWindow.postMessage({ type: '__dino_frame_request_scan', frameId: frameId }, '*');
                    } catch(err) {}

                    var frameData = window.__dino_frames && window.__dino_frames[frameId];
                    if (!frameData || !frameData.elements || frameData.elements.length === 0) {
                        try {
                            if (ifr.contentDocument && ifr.contentWindow) {
                                var doc = ifr.contentDocument;
                                var subEls = [];
                                var subSel = 'a, button, input, textarea, select, details, summary, h1, h2, h3, h4, h5, h6, img, li, p, td, th, [role="button"], [role="link"], [role="checkbox"], [contenteditable="true"]';
                                var foundSub = doc.querySelectorAll(subSel);
                                for (var si = 0; si < foundSub.length; si++) {
                                    var se = foundSub[si];
                                    var sRect = se.getBoundingClientRect();
                                    if (sRect.width <= 0 || sRect.height <= 0) continue;
                                    var sStyle = ifr.contentWindow.getComputedStyle(se);
                                    if (sStyle.display === 'none' || sStyle.visibility === 'hidden') continue;
                                    var sid = se.getAttribute('data-dino-id') || ('e' + (si + 1));
                                    se.setAttribute('data-dino-id', sid);
                                    var sTag = se.tagName.toLowerCase();
                                    var sText = (se.getAttribute('aria-label') || se.placeholder || se.innerText || se.textContent || '').trim().replace(/\\s+/g, ' ').substring(0, 120);
                                    subEls.push({
                                        id: sid,
                                        tag: sTag,
                                        role: se.getAttribute('role') || sTag,
                                        text: sText,
                                        value: se.value || null,
                                        type: se.type || null,
                                        bounds: {
                                            x: Math.round(sRect.left),
                                            y: Math.round(sRect.top),
                                            width: Math.round(sRect.width),
                                            height: Math.round(sRect.height)
                                        },
                                        box: [
                                            Math.round(sRect.top),
                                            Math.round(sRect.left),
                                            Math.round(sRect.width),
                                            Math.round(sRect.height)
                                        ],
                                        norm: [
                                            Math.max(0, Math.min(1000, Math.round((sRect.top / Math.max(1, vpH)) * 1000))),
                                            Math.max(0, Math.min(1000, Math.round((sRect.left / Math.max(1, vpW)) * 1000))),
                                            Math.max(0, Math.min(1000, Math.round(((sRect.top + sRect.height) / Math.max(1, vpH)) * 1000))),
                                            Math.max(0, Math.min(1000, Math.round(((sRect.left + sRect.width) / Math.max(1, vpW)) * 1000)))
                                        ]
                                    });
                                }
                                if (subEls.length > 0) {
                                    frameData = {
                                        frameId: frameId,
                                        elements: subEls
                                    };
                                }
                            }
                        } catch(e) {}
                    }
                    if (frameData && frameData.elements && frameData.elements.length > 0) {
                        for (var fei = 0; fei < frameData.elements.length; fei++) {
                            var fel = frameData.elements[fei];
                            var qualifiedId = frameId + ':' + fel.id;
                            var absX = Math.round(ifrRect.left + fel.bounds.x);
                            var absY = Math.round(ifrRect.top + fel.bounds.y);
                            var visibleLeft = Math.max(0, ifrRect.left, absX);
                            var visibleTop = Math.max(0, ifrRect.top, absY);
                            var visibleRight = Math.min(vpW, ifrRect.right, absX + fel.bounds.width);
                            var visibleBottom = Math.min(vpH, ifrRect.bottom, absY + fel.bounds.height);
                            var inVp = (visibleRight > visibleLeft && visibleBottom > visibleTop);

                            results.push({
                                id: qualifiedId,
                                tag: fel.tag,
                                role: fel.role,
                                text: fel.text,
                                value: fel.value,
                                type: fel.type,
                                className: null,
                                domId: fel.domId || null,
                                rank: null,
                                isObscured: false,
                                inViewport: inVp,
                                hasContextMenu: Boolean(fel.hasContextMenu),
                                disabled: Boolean(fel.disabled),
                                checked: Boolean(fel.checked),
                                selected: Boolean(fel.selected),
                                focused: false,
                                readOnly: Boolean(fel.readOnly),
                                isInShadowRoot: false,
                                src: null,
                                alt: null,
                                href: null,
                                bounds: {
                                    x: absX,
                                    y: absY,
                                    width: fel.bounds.width,
                                    height: fel.bounds.height
                                },
                                box: [
                                    absY,
                                    absX,
                                    fel.bounds.width,
                                    fel.bounds.height
                                ],
                                norm: [
                                    Math.max(0, Math.min(1000, Math.round((absY / Math.max(1, vpH)) * 1000))),
                                    Math.max(0, Math.min(1000, Math.round((absX / Math.max(1, vpW)) * 1000))),
                                    Math.max(0, Math.min(1000, Math.round(((absY + fel.bounds.height) / Math.max(1, vpH)) * 1000))),
                                    Math.max(0, Math.min(1000, Math.round(((absX + fel.bounds.width) / Math.max(1, vpW)) * 1000)))
                                ]
                            });
                        }
                    }
                }

                if (!this.elementsBounds) this.elementsBounds = {};
                for (var ri = 0; ri < results.length; ri++) {
                    var rItem = results[ri];
                    if (rItem && rItem.id && rItem.bounds) {
                        var rTag = (rItem.tag || '').toLowerCase();
                        var rType = (rItem.type || 'text').toLowerCase();
                        var nonText = ['checkbox', 'radio', 'button', 'submit', 'reset', 'image', 'file', 'range', 'color', 'hidden'];
                        var rEditable = (rTag === 'textarea' || (rTag === 'input' && nonText.indexOf(rType) === -1)) && !rItem.readOnly && !rItem.disabled;
                        if (this.elements && this.elements[rItem.id]) {
                            rEditable = isTextEditable(this.elements[rItem.id]);
                        }
                        this.elementsBounds[rItem.id] = {
                            left: rItem.bounds.x,
                            top: rItem.bounds.y,
                            right: rItem.bounds.x + rItem.bounds.width,
                            bottom: rItem.bounds.y + rItem.bounds.height,
                            width: rItem.bounds.width,
                            height: rItem.bounds.height,
                            isEditable: rEditable,
                            tagName: rTag
                        };
                    }
                }
                window.__dino_elements_bounds = this.elementsBounds;

                // Filter elements for summary if viewportOnly, role, or text is specified
                var summaryCandidates = results;
                if (viewportOnly) {
                    summaryCandidates = summaryCandidates.filter(function(item) { return item.inViewport; });
                    // Visual on-screen sorting: sort from top to bottom (Y coordinate), then left to right (X coordinate)
                    summaryCandidates.sort(function(a, b) {
                        var ya = (a.bounds && a.bounds.y !== undefined) ? a.bounds.y : 0;
                        var yb = (b.bounds && b.bounds.y !== undefined) ? b.bounds.y : 0;
                        var diffY = ya - yb;
                        // For elements on approximately the same horizontal line (within 8px), sort left to right
                        if (Math.abs(diffY) > 8) {
                            return diffY;
                        }
                        var xa = (a.bounds && a.bounds.x !== undefined) ? a.bounds.x : 0;
                        var xb = (b.bounds && b.bounds.x !== undefined) ? b.bounds.x : 0;
                        return xa - xb;
                    });
                }
                if (roleFilter) {
                    summaryCandidates = summaryCandidates.filter(function(item) {
                        var r = (item.role || '').toLowerCase();
                        var tg = (item.tag || '').toLowerCase();
                        var tp = (item.type || '').toLowerCase();
                        if (r === roleFilter) return true;
                        // Semantic dual-direction mapping:
                        if (roleFilter === 'link' && (tg === 'a' || tg === 'area' || r === 'link')) return true;
                        if (roleFilter === 'button' && (r === 'button' || tg === 'button' || tp === 'submit' || tp === 'button' || tg === 'summary')) return true;
                        if (roleFilter === 'checkbox' && (r === 'checkbox' || tp === 'checkbox')) return true;
                        if (roleFilter === 'radio' && (r === 'radio' || tp === 'radio')) return true;
                        if (roleFilter === 'textbox') {
                            if (r === 'textbox' || r === 'searchbox') return true;
                            if (tg === 'textarea') return true;
                            if (tg === 'input') {
                                var nonText = ['checkbox', 'radio', 'button', 'submit', 'reset', 'image', 'file', 'range', 'color', 'hidden'];
                                if (tp && nonText.indexOf(tp) !== -1) return false;
                                return true;
                            }
                            return false;
                        }
                        if (roleFilter === 'searchbox' && (r === 'searchbox' || tp === 'search')) return true;
                        if (roleFilter === 'heading' && (r === 'heading' || (tg.indexOf('h') === 0 && tg.length === 2))) return true;
                        if ((roleFilter === 'img' || roleFilter === 'image') && (tg === 'img' || r === 'img')) return true;
                        if (roleFilter === 'text' && (r === 'text' || r === 'paragraph' || tg === 'p' || tg === 'span' || tg === 'div')) return true;
                        if (tg === roleFilter) return true;
                        return false;
                    });
                }
                if (textFilter) {
                    summaryCandidates = summaryCandidates.filter(function(item) {
                        var t = (item.text || '').toLowerCase();
                        var v = (item.value || '').toLowerCase();
                        return t.indexOf(textFilter) !== -1 || v.indexOf(textFilter) !== -1;
                    });
                }

                var totalCount = summaryCandidates.length;
                var pagedItems = (limit < 0) ? (offset > 0 ? summaryCandidates.slice(offset) : summaryCandidates) : summaryCandidates.slice(offset, offset + limit);

                var pageUrl = window.location.href || '';
                var displayUrl = pageUrl;
                if (displayUrl.indexOf('data:') === 0) {
                    var comma = displayUrl.indexOf(',');
                    var mime = comma > 0 ? displayUrl.substring(0, comma) : 'data:text/html';
                    displayUrl = mime + ';length=' + pageUrl.length;
                } else if (displayUrl.length > 200) {
                    displayUrl = displayUrl.substring(0, 197) + '...';
                }

                // Compute tracking mutation counts
                var curTrackedIds = {};
                for (var rki = 0; rki < results.length; rki++) {
                    if (results[rki] && results[rki].id) curTrackedIds[results[rki].id] = true;
                }
                var removedCount = 0;
                if (trackMutations && prevTracked) {
                    for (var prevKey in prevTracked) {
                        if (!curTrackedIds[prevKey]) removedCount++;
                    }
                }
                this._lastTrackedIds = curTrackedIds;

                var trackedInfo = null;
                if (trackMutations) {
                    trackedInfo = {
                        added: addedCount,
                        removed: prevTracked ? removedCount : 0,
                        unchanged: unchangedCount
                    };
                }

                // Build compact markdown semantic summary for LLM prompt ingestion
                var headerParts = ['Page: ' + (document.title || 'Untitled')];
                if (targetFilter && resolvedTargetEl) headerParts.push('Target: ' + targetFilter);
                if (depthLimit !== null) headerParts.push('MaxDepth: ' + depthLimit);
                if (trackedInfo) headerParts.push('Tracked: +' + trackedInfo.added + ' -' + trackedInfo.removed);
                headerParts.push('URL: ' + displayUrl);

                var summaryLines = [
                    '[' + headerParts.join(' | ') + ']',
                    'Interactive Elements (' + pagedItems.length + ' of ' + totalCount + (totalCount > limit ? ' | pass limit/offset for more' : '') + '):'
                ];

                var includeCoords = Boolean(options.coords || options.includeCoords);
                for (var j = 0; j < pagedItems.length; j++) {
                    var item = pagedItems[j];
                    var desc = '[' + item.id + ']';
                    if (includeCoords && item.norm) {
                        desc += ' [' + item.norm.join(',') + ']';
                    }
                    if (item.isNew) desc += ' [NEW]';
                    if (item.depth !== undefined && item.depth > 0) desc += ' (d=' + item.depth + ')';
                    if (item.rank) desc += ' #' + item.rank;
                    desc += ' <' + item.tag;
                    if (item.domId) desc += ' id="' + item.domId + '"';
                    if (item.type) desc += ' type="' + item.type + '"';
                    if (item.role && item.role !== item.tag) desc += ' role="' + item.role + '"';
                    if (item.href) {
                        var h = item.href;
                        if (h.length > 50) h = h.substring(0, 47) + '...';
                        desc += ' href="' + h + '"';
                    }
                    if (item.src) {
                        var s = item.src;
                        if (s.length > 40) s = s.substring(0, 37) + '...';
                        desc += ' src="' + s + '"';
                    }
                    if (item.className) {
                        var c = item.className;
                        if (c.length > 25) c = c.substring(0, 22) + '...';
                        desc += ' class="' + c + '"';
                    }
                    if (item.text) desc += ' "' + item.text + '"';
                    if (item.value) desc += ' value="' + item.value + '"';
                    if (item.checked) desc += ' checked';
                    if (item.disabled) desc += ' disabled';
                    if (item.selected) desc += ' selected';
                    if (item.focused) desc += ' focused';
                    if (item.isInShadowRoot) desc += ' shadow';
                    if (!item.inViewport) desc += ' (offscreen)';
                    desc += '>';
                    if (item.hasContextMenu) desc += ' (context-menu)';
                    if (item.tag === 'canvas') desc += ' (interactive-canvas)';
                    if (item.isObscured) desc += ' (obscured)';
                    summaryLines.push(desc);
                }

                if (offset + limit < totalCount) {
                    summaryLines.push('[... and ' + (totalCount - (offset + limit)) + ' more elements. Use offset=' + (offset + limit) + ']');
                }

                var bodyText = summaryLines.join('\\n');
                var fullSummary = '<!-- BEGIN UNTRUSTED WEB CONTENT (origin: ' + displayUrl + ') -->\\n' + bodyText + '\\n<!-- END UNTRUSTED WEB CONTENT -->';
                var tokenEst = Math.round(fullSummary.length / 4);
                this.lastResults = results;

                return {
                    title: document.title || '',
                    url: displayUrl,
                    target: (targetFilter && resolvedTargetEl) ? targetFilter : null,
                    tracked: trackedInfo,
                    viewportWidth: vpW,
                    viewportHeight: vpH,
                    totalElements: totalCount,
                    filteredTotal: totalCount,
                    unfilteredTotal: results.length,
                    elements: pagedItems,
                    summary: fullSummary,
                    securityBoundary: { untrusted: true, origin: displayUrl },
                    tokenEstimate: tokenEst
                };
            },

            // Re-anchors a virtualized or unmounted element by scrolling to its last known document offset
            reanchorElement: function(targetId) {
                if (!targetId) return null;
                var sig = (this.elementSignatures && this.elementSignatures[targetId]) || null;
                if (!sig || sig.docY === undefined) return null;

                // 1. Scroll document to anchor position
                var targetScrollY = Math.max(0, sig.docY - Math.round(window.innerHeight / 2));
                window.scrollTo({ top: targetScrollY, behavior: 'instant' });

                // 2. Allow synchronous layout / virtual list to register new scroll position
                if (document.body) { void document.body.offsetHeight; }

                // 3. Attempt to find the re-mounted live node
                var el = this.elements && this.elements[targetId] && this.isNodeConnected(this.elements[targetId]) ? this.elements[targetId] : null;
                if (!el) el = this.selfHealElement(targetId);
                if (!el) {
                    try { el = document.querySelector('[data-dino-id="' + CSS.escape(targetId) + '"]'); } catch(e) {}
                }
                if (el) {
                    this.elements[targetId] = el;
                    if (el.scrollIntoView) {
                        try { el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                    }
                    return el;
                }
                return null;
            },

            // Resolves a replacement node for a stale reference when DOM changes occurred without intermediate snapshot
            selfHealElement: function(targetId, action) {
                if (!targetId) return null;
                var oldEl = (this.elements && this.elements[targetId]) || null;
                var sig = (this.elementSignatures && this.elementSignatures[targetId]) || null;

                var tag = (sig && sig.tag) || (oldEl && oldEl.tagName && oldEl.tagName.toLowerCase()) || null;
                var domId = (sig && sig.id) || (oldEl && oldEl.id) || null;
                var name = (sig && sig.name) || (oldEl && oldEl.getAttribute && oldEl.getAttribute('name')) || null;
                var testId = (sig && sig.testId) || (oldEl && oldEl.getAttribute && oldEl.getAttribute('data-testid')) || null;
                var ariaLabel = (sig && sig.ariaLabel) || (oldEl && oldEl.getAttribute && oldEl.getAttribute('aria-label')) || null;
                var text = (sig && sig.text) || (oldEl && (oldEl.innerText || oldEl.textContent || '').trim().replace(/\\s+/g, ' ')) || null;
                var placeholder = (sig && sig.placeholder) || (oldEl && oldEl.placeholder) || null;
                var type = (sig && sig.type) || (oldEl && oldEl.getAttribute && oldEl.getAttribute('type')) || null;
                var role = (sig && sig.role) || (oldEl && oldEl.getAttribute && oldEl.getAttribute('role')) || null;
                var className = (sig && sig.className) || (oldEl && oldEl.className && typeof oldEl.className === 'string' ? oldEl.className.trim() : null);

                var requiresInput = (action === 'type' || action === 'clear');
                var requiresSelect = (action === 'selectoption');

                // If the action requires a text-editable control, but the element signature was snapshotted
                // as a non-editable tag (e.g. <img>, <a>, <p>, <h1>), NEVER attempt to heal it into an input!
                if (requiresInput && tag) {
                    var isSigEditable = (tag === 'input' || tag === 'textarea' || (sig && sig.isContentEditable));
                    if (!isSigEditable) return null;
                    if (tag === 'input' && type) {
                        var nonText = ['checkbox', 'radio', 'button', 'submit', 'reset', 'image', 'file', 'range', 'color', 'hidden'];
                        if (nonText.indexOf(type.toLowerCase()) !== -1) return null;
                    }
                }
                if (requiresSelect && tag && tag !== 'select') {
                    return null;
                }

                // Fast path 1: query by element ID
                if (domId) {
                    try {
                        var byId = document.getElementById(domId);
                        if (byId && this.isNodeConnected(byId)) {
                            if ((!requiresInput || isTextEditable(byId)) &&
                                (!requiresSelect || byId.tagName.toLowerCase() === 'select')) {
                                return byId;
                            }
                        }
                    } catch(e) {}
                }
                // Fast path 2: query by data-testid
                if (testId) {
                    try {
                        var byTest = document.querySelector('[data-testid="' + CSS.escape(testId) + '"]');
                        if (byTest && this.isNodeConnected(byTest)) {
                            if ((!requiresInput || isTextEditable(byTest)) &&
                                (!requiresSelect || byTest.tagName.toLowerCase() === 'select')) {
                                return byTest;
                            }
                        }
                    } catch(e) {}
                }
                // Fast path 3: query by name and tag
                if (name && tag) {
                    try {
                        var byName = document.querySelectorAll(tag + '[name="' + CSS.escape(name) + '"]');
                        for (var ni = 0; ni < byName.length; ni++) {
                            var bn = byName[ni];
                            if (this.isNodeConnected(bn)) {
                                if ((!requiresInput || isTextEditable(bn)) &&
                                    (!requiresSelect || bn.tagName.toLowerCase() === 'select')) {
                                    return bn;
                                }
                            }
                        }
                    } catch(e) {}
                }
                // Fast path 4: query by aria-label and tag
                if (ariaLabel && tag) {
                    try {
                        var byAria = document.querySelectorAll(tag + '[aria-label="' + CSS.escape(ariaLabel) + '"]');
                        for (var ai = 0; ai < byAria.length; ai++) {
                            var ba = byAria[ai];
                            if (this.isNodeConnected(ba)) {
                                if ((!requiresInput || isTextEditable(ba)) &&
                                    (!requiresSelect || ba.tagName.toLowerCase() === 'select')) {
                                    return ba;
                                }
                            }
                        }
                    } catch(e) {}
                }

                // Scored search across candidates in the live document
                var selector = tag || (requiresInput ? 'input, textarea, [contenteditable="true"]' : (requiresSelect ? 'select' : 'a, button, input, textarea, select, details, summary, [role="button"], [role="link"], [contenteditable="true"]'));
                var candidates = [];
                try {
                    var found = document.querySelectorAll(selector);
                    for (var ci = 0; ci < found.length; ci++) {
                        var cand = found[ci];
                        if (this.isNodeConnected(cand)) {
                            if (requiresInput && !isTextEditable(cand)) continue;
                            if (requiresSelect && cand.tagName.toLowerCase() !== 'select') continue;
                            candidates.push(cand);
                        }
                    }
                } catch(e) {}

                var bestEl = null;
                var bestScore = -1;

                for (var k = 0; k < candidates.length; k++) {
                    var c = candidates[k];
                    var score = 0;
                    var cTag = c.tagName.toLowerCase();
                    if (tag && cTag === tag) score += 20;
                    if (domId && c.id === domId) score += 50;
                    if (name && c.getAttribute('name') === name) score += 35;
                    if (testId && c.getAttribute('data-testid') === testId) score += 50;
                    if (type && c.getAttribute('type') === type) score += 20;
                    if (role && c.getAttribute('role') === role) score += 20;
                    if (placeholder && c.placeholder === placeholder) score += 25;
                    if (ariaLabel && c.getAttribute('aria-label') === ariaLabel) score += 30;

                    var cText = (c.innerText || c.textContent || '').trim().replace(/\\s+/g, ' ');
                    if (text && cText === text) {
                        score += 40;
                    } else if (text && cText && (cText.indexOf(text) !== -1 || text.indexOf(cText) !== -1)) {
                        score += 20;
                    }

                    if (className && c.className && typeof c.className === 'string') {
                        if (c.className.trim() === className) score += 15;
                        else if (c.className.indexOf(className) !== -1) score += 10;
                    }

                    if (score > bestScore) {
                        bestScore = score;
                        bestEl = c;
                    }
                }

                if (bestScore >= 35 && bestEl) {
                    return bestEl;
                }

                // Positional guessing (candidates[n - 1]) is intentionally removed.
                // Ref-shifts that lack semantic signature match must fail cleanly with STALE_REF.
                return null;
            },


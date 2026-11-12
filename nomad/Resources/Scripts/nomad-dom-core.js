    (function() {
        if (window.__nomad) return;

        // Parses frame-qualified target ID (e.g. 'f1:e2' or 'e2_f1')
        function parseFrameTarget(id) {
            if (!id || typeof id !== 'string' || (id.indexOf(':') === -1 && id.indexOf('_') === -1)) return null;
            var sep = id.indexOf(':') !== -1 ? ':' : '_';
            var parts = id.split(sep);
            return {
                frameId: parts[0].indexOf('f') === 0 ? parts[0] : parts[1],
                elementId: parts[0].indexOf('f') === 0 ? parts[1] : parts[0]
            };
        }

        // Validates whether an element is truly editable for typing or clearing
        function isTextEditable(node) {
            if (!node) return false;
            if (node.isContentEditable) return true;
            var t = node.tagName ? node.tagName.toLowerCase() : '';
            if (t === 'textarea') return !node.readOnly && !node.disabled;
            if (t === 'input') {
                var it = (node.type || 'text').toLowerCase();
                var nonTextTypes = ['checkbox', 'radio', 'button', 'submit', 'reset', 'image', 'file', 'range', 'color', 'hidden'];
                if (nonTextTypes.indexOf(it) !== -1) return false;
                return !node.readOnly && !node.disabled;
            }
            return false;
        }

        // Resolves an <input type="file"> from an element, associated <label>, aria-controls, container, or form
        function resolveFileInput(node) {
            if (!node) return null;
            if (node.tagName === 'INPUT' && (node.type || '').toLowerCase() === 'file') {
                return node;
            }
            if (node.tagName === 'LABEL') {
                var forId = node.htmlFor || (node.getAttribute && node.getAttribute('for'));
                if (forId) {
                    var doc = node.ownerDocument || document;
                    var targetInput = doc.getElementById(forId);
                    if (targetInput && targetInput.tagName === 'INPUT' && (targetInput.type || '').toLowerCase() === 'file') {
                        return targetInput;
                    }
                }
                var childInput = node.querySelector ? node.querySelector('input[type="file"]') : null;
                if (childInput) return childInput;
            }
            if (node.getAttribute) {
                var ariaCtrl = node.getAttribute('aria-controls');
                if (ariaCtrl) {
                    var docA = node.ownerDocument || document;
                    var ctrlEl = docA.getElementById(ariaCtrl);
                    if (ctrlEl && ctrlEl.tagName === 'INPUT' && (ctrlEl.type || '').toLowerCase() === 'file') {
                        return ctrlEl;
                    }
                }
            }
            if (node.querySelector) {
                var directChild = node.querySelector('input[type="file"]');
                if (directChild) return directChild;
            }
            // Check enclosing form or dropzone container
            if (node.closest) {
                var container = node.closest('form, [class*="drop"], [class*="upload"], [id*="drop"], [id*="upload"], section, div');
                if (container && container.querySelector) {
                    var containerInput = container.querySelector('input[type="file"]');
                    if (containerInput) return containerInput;
                }
            }
            // Document fallback if page has an input[type="file"]
            var docFallback = node.ownerDocument || document;
            return docFallback.querySelector ? docFallback.querySelector('input[type="file"]') : null;
        }

        // Checks whether an element is an upload dropzone target
        function isDropzone(node) {
            if (!node || !node.getAttribute) return false;
            if (node.getAttribute('ondrop') !== null || node.getAttribute('ondragover') !== null) return true;
            var cls = String(node.className || '').toLowerCase();
            var nid = String(node.id || '').toLowerCase();
            var aria = String(node.getAttribute('aria-label') || '').toLowerCase();
            return cls.indexOf('drop') !== -1 || cls.indexOf('upload') !== -1 ||
                   nid.indexOf('drop') !== -1 || nid.indexOf('upload') !== -1 ||
                   aria.indexOf('drop') !== -1 || aria.indexOf('upload') !== -1;
        }

        // Checks if an element is a meaningful leaf text container (div/span/article without block children)
        function isMeaningfulTextLeaf(node) {
            if (!node || !node.tagName) return false;
            var tag = node.tagName.toLowerCase();
            if (tag !== 'div' && tag !== 'span' && tag !== 'article' && tag !== 'section') return false;
            if (node.querySelector && node.querySelector('a, button, input, textarea, select, details, canvas, iframe')) return false;
            if (node.querySelector && node.querySelector('div, p, ul, ol, table, form, h1, h2, h3, h4, h5, h6')) return false;
            var txt = (node.innerText || node.textContent || '').trim();
            return txt.length > 0 && txt.length <= 400;
        }

        // Luhn algorithm check for payment cards
        function isLuhnValid(val) {
            var digits = String(val).replace(/[\\s-]/g, '');
            if (!/^\\d{13,19}$/.test(digits)) return false;
            var sum = 0, alt = false;
            for (var i = digits.length - 1; i >= 0; i--) {
                var n = parseInt(digits.charAt(i), 10);
                if (alt) {
                    n *= 2;
                    if (n > 9) n -= 9;
                }
                sum += n;
                alt = !alt;
            }
            return (sum % 10 === 0);
        }

        // Payment cards, CVVs, SSNs, and sensitive tokens
        function isSensitiveValue(val) {
            if (val === undefined || val === null) return false;
            var str = String(val).trim();
            if (!str) return false;
            var digitsOnly = str.replace(/[\\s-]/g, '');
            if (/^\\d{13,19}$/.test(digitsOnly)) {
                if (isLuhnValid(digitsOnly) || /^(?:4\\d{12}(?:\\d{3})?|5[1-5]\\d{14}|6(?:011|5\\d{2})\\d{12}|3[47]\\d{13}|3(?:0[0-5]|[68]\\d)\\d{11}|2[2-7]\\d{14})$/.test(digitsOnly)) {
                    return true;
                }
            }
            if (/^\\d{3}-\\d{2}-\\d{4}$/.test(str)) return true;
            return false;
        }

        // Sensitive field detection (passwords, credentials, credit cards, CVVs, SSNs, tokens, PINs)
        function isSensitiveField(el) {
            if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA')) return false;
            if (el.type === 'password') return true;
            var rawHint = (
                (el.name || el.getAttribute('name') || '') + ' ' +
                (el.id || '') + ' ' +
                (el.autocomplete || '') + ' ' +
                (el.placeholder || '') + ' ' +
                (el.getAttribute('aria-label') || '') + ' ' +
                (el.getAttribute('aria-placeholder') || '') + ' ' +
                (el.className || '')
            ).toLowerCase();
            var hint = rawHint.replace(/[-_.]/g, ' ');
            var sensitive = ['password', 'passwd', 'passcode', 'pass', 'api key', 'apikey', 'otp', 'pin', 'card', 'cvv', 'cvc', 'ssn', 'social security', 'secret', 'token', 'credit card', 'cc number', 'cc csc', 'cc exp', 'auth token', 'private key'];
            for (var s = 0; s < sensitive.length; s++) {
                var kw = sensitive[s];
                if (kw === 'pin' || kw === 'otp' || kw === 'pass') {
                    var re = new RegExp('\\\\b' + kw + '\\\\b', 'i');
                    if (re.test(hint)) return true;
                } else {
                    if (hint.indexOf(kw) !== -1 || rawHint.indexOf(kw) !== -1) return true;
                }
            }
            if (isSensitiveValue(el.value)) return true;
            return false;
        }

        // Context menu / right-click trigger detection
        function hasContextMenuSupport(el) {
            if (!el) return false;
            try {
                if (el.hasAttribute && (
                    el.hasAttribute('oncontextmenu') ||
                    el.getAttribute('aria-haspopup') === 'menu' ||
                    el.getAttribute('aria-haspopup') === 'true' ||
                    el.hasAttribute('data-contextmenu') ||
                    el.hasAttribute('data-context-menu') ||
                    el.hasAttribute('contextmenu')
                )) return true;
                if (el.oncontextmenu !== null && el.oncontextmenu !== undefined) return true;
                var cls = (el.className && typeof el.className === 'string') ? el.className.toLowerCase() : '';
                if (cls.indexOf('context-menu') !== -1 || cls.indexOf('contextmenu') !== -1 || cls.indexOf('right-click') !== -1) return true;
            } catch(e) {}
            return false;
        }

        // Dispatches full HTML5 Drag and Drop event sequence with DataTransfer
        function dispatchHtml5Drag(targetId, fromX, fromY, toX, toY, optEl, optDest) {
            var nomad = (typeof window !== 'undefined' && window.__nomad) ? window.__nomad : (this || {});
            var el = optEl || null;
            if (!el && targetId) {
                el = (nomad.elements && nomad.elements[targetId] && nomad.isNodeConnected && nomad.isNodeConnected(nomad.elements[targetId]) ? nomad.elements[targetId] : null) || (nomad.findInTree ? nomad.findInTree(document, targetId) : document.getElementById(targetId));
            }
            if (!el && fromX !== undefined && fromY !== undefined) {
                el = document.elementFromPoint(fromX, fromY);
            }
            if (!el) return { success: false, code: 'MISSING_TARGET', message: 'No source element for drag action', elementId: targetId };

            var destEl = null;
            if (optDest && typeof optDest === 'object' && optDest.dispatchEvent) {
                destEl = optDest;
            } else if (typeof optDest === 'string' && optDest) {
                destEl = (nomad.elements && nomad.elements[optDest] && nomad.isNodeConnected && nomad.isNodeConnected(nomad.elements[optDest]) ? nomad.elements[optDest] : null) || (nomad.findInTree ? nomad.findInTree(document, optDest) : null) || document.querySelector('[data-nomad-id="' + optDest + '"]') || document.querySelector(optDest);
            }

            var destX = (toX !== undefined && toX !== null) ? Number(toX) : null;
            var destY = (toY !== undefined && toY !== null) ? Number(toY) : null;

            if ((destX === null || destY === null) && destEl) {
                var dRect = destEl.getBoundingClientRect ? destEl.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                destX = Math.round(dRect.left + dRect.width / 2);
                destY = Math.round(dRect.top + dRect.height / 2);
            } else if ((destX === null || destY === null) && typeof optDest === 'string' && optDest) {
                var vRect = nomad.getElementViewportRect ? nomad.getElementViewportRect(optDest) : null;
                if (vRect && (vRect.width > 0 || vRect.height > 0)) {
                    destX = Math.round(vRect.left + vRect.width / 2);
                    destY = Math.round(vRect.top + vRect.height / 2);
                }
            }

            if (destX === null || destY === null) {
                return { success: false, code: 'MISSING_DESTINATION', message: 'Missing destination coordinates (toX, toY) or destination element (toElementId/toTarget) for drag action', elementId: targetId };
            }

            if (el.scrollIntoView) {
                try { el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
            }

            var srcRect = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
            var startX = (fromX !== undefined && fromX !== null) ? Number(fromX) : Math.round(srcRect.left + srcRect.width / 2);
            var startY = (fromY !== undefined && fromY !== null) ? Number(fromY) : Math.round(srcRect.top + srcRect.height / 2);

            var elDoc = el.ownerDocument || document;
            var elWin = elDoc.defaultView || window;

            // 1. Dispatch pointerdown and mousedown on source element (for Pointer-driven sortables / canvas / sliders)
            var ptrDownOpts = {
                bubbles: true,
                cancelable: true,
                view: elWin,
                clientX: startX,
                clientY: startY,
                screenX: startX,
                screenY: startY,
                button: 0,
                buttons: 1,
                pointerId: 1,
                pointerType: 'mouse',
                isPrimary: true,
                pressure: 0.5
            };
            try { el.dispatchEvent(new elWin.PointerEvent('pointerdown', ptrDownOpts)); } catch(e) {}
            try { el.dispatchEvent(new elWin.MouseEvent('mousedown', ptrDownOpts)); } catch(e) {}

            if (!destEl) {
                destEl = document.elementFromPoint(destX, destY);
                if (destEl && destEl.tagName === 'IFRAME') {
                    try {
                        var fDoc = destEl.contentDocument || (destEl.contentWindow ? destEl.contentWindow.document : null);
                        if (fDoc) {
                            var ifrRect = destEl.getBoundingClientRect();
                            var subEl = fDoc.elementFromPoint(destX - ifrRect.left, destY - ifrRect.top);
                            if (subEl) destEl = subEl;
                        }
                    } catch(e) {}
                }
            }

            if (!destEl) {
                return { success: false, code: 'NO_DROP_TARGET', message: 'No drop target element found at destination coordinates (' + destX + ', ' + destY + ')', elementId: targetId };
            }

            // 2. Dispatch interpolated pointermove and mousemove events (SortableJS, canvas stroke, sliders)
            var steps = 5;
            for (var s = 1; s <= steps; s++) {
                var factor = s / steps;
                var currX = Math.round(startX + (destX - startX) * factor);
                var currY = Math.round(startY + (destY - startY) * factor);
                var moveEl = document.elementFromPoint(currX, currY) || destEl || el;
                var moveDoc = moveEl.ownerDocument || document;
                var moveWin = moveDoc.defaultView || window;
                var mOpts = {
                    bubbles: true,
                    cancelable: true,
                    view: moveWin,
                    clientX: currX,
                    clientY: currY,
                    screenX: currX,
                    screenY: currY,
                    button: 0,
                    buttons: 1,
                    pointerId: 1,
                    pointerType: 'mouse',
                    isPrimary: true,
                    pressure: 0.5
                };
                try { moveEl.dispatchEvent(new moveWin.PointerEvent('pointermove', mOpts)); } catch(e) {}
                try { moveEl.dispatchEvent(new moveWin.MouseEvent('mousemove', mOpts)); } catch(e) {}
            }

            // 3. Dispatch HTML5 Drag and Drop event pipeline (DataTransfer)
            var dt = new DataTransfer();
            try { dt.effectAllowed = 'all'; } catch(e) {}

            try {
                var dragStartEvt = new DragEvent('dragstart', {
                    bubbles: true,
                    cancelable: true,
                    clientX: startX,
                    clientY: startY,
                    dataTransfer: dt
                });
                el.dispatchEvent(dragStartEvt);
            } catch(e) {}

            try {
                var dragEnterEvt = new DragEvent('dragenter', {
                    bubbles: true,
                    cancelable: true,
                    clientX: destX,
                    clientY: destY,
                    dataTransfer: dt
                });
                destEl.dispatchEvent(dragEnterEvt);
            } catch(e) {}

            try {
                var dragOverEvt = new DragEvent('dragover', {
                    bubbles: true,
                    cancelable: true,
                    clientX: destX,
                    clientY: destY,
                    dataTransfer: dt
                });
                destEl.dispatchEvent(dragOverEvt);
            } catch(e) {}

            try {
                var dropEvt = new DragEvent('drop', {
                    bubbles: true,
                    cancelable: true,
                    clientX: destX,
                    clientY: destY,
                    dataTransfer: dt
                });
                destEl.dispatchEvent(dropEvt);
            } catch(e) {}

            try {
                var dragEndEvt = new DragEvent('dragend', {
                    bubbles: true,
                    cancelable: true,
                    clientX: destX,
                    clientY: destY,
                    dataTransfer: dt
                });
                el.dispatchEvent(dragEndEvt);
            } catch(e) {}

            // 4. Dispatch pointerup, mouseup, click at destination
            var ptrUpOpts = {
                bubbles: true,
                cancelable: true,
                view: elWin,
                clientX: destX,
                clientY: destY,
                screenX: destX,
                screenY: destY,
                button: 0,
                buttons: 0,
                pointerId: 1,
                pointerType: 'mouse',
                isPrimary: true,
                pressure: 0
            };
            try { destEl.dispatchEvent(new elWin.PointerEvent('pointerup', ptrUpOpts)); } catch(e) {}
            try { destEl.dispatchEvent(new elWin.MouseEvent('mouseup', ptrUpOpts)); } catch(e) {}

            var destLabel = (typeof optDest === 'string' && optDest) ? ("'" + optDest + "' (" + destX + ", " + destY + ")") : ('(' + destX + ', ' + destY + ')');
            return { success: true, code: 'SUCCESS', message: 'Dragged ' + (targetId || 'element') + ' to ' + destLabel, elementId: targetId };
        }

        if (!window.__nomad_frames) window.__nomad_frames = {};
        if (!window.__nomad_frame_listener_attached) {
            window.__nomad_frame_listener_attached = true;
            window.addEventListener('message', function(e) {
                if (!e.data || typeof e.data !== 'object') return;
                if (e.data.type === '__nomad_frame_report') {
                    var iframes = document.querySelectorAll('iframe');
                    var matchedId = e.data.frameId || null;
                    if (!matchedId) {
                        for (var i = 0; i < iframes.length; i++) {
                            try {
                                if (iframes[i].contentWindow === e.source) {
                                    matchedId = iframes[i].getAttribute('data-nomad-frame') || ('f' + (i + 1));
                                    iframes[i].setAttribute('data-nomad-frame', matchedId);
                                    break;
                                }
                            } catch(err) {}
                        }
                    }
                    if (!matchedId && iframes.length === 1) {
                        matchedId = iframes[0].getAttribute('data-nomad-frame') || 'f1';
                        iframes[0].setAttribute('data-nomad-frame', matchedId);
                    }
                    if (!matchedId && e.data.url) {
                        for (var j = 0; j < iframes.length; j++) {
                            var src = iframes[j].getAttribute('src') || '';
                            if (src && (e.data.url.indexOf(src) !== -1 || src.indexOf(e.data.url) !== -1)) {
                                matchedId = iframes[j].getAttribute('data-nomad-frame') || ('f' + (j + 1));
                                iframes[j].setAttribute('data-nomad-frame', matchedId);
                                break;
                            }
                        }
                    }
                    if (matchedId) {
                        window.__nomad_frames[matchedId] = {
                            frameId: matchedId,
                            url: e.data.url,
                            title: e.data.title,
                            elements: e.data.elements || [],
                            source: e.source,
                            updatedAt: Date.now()
                        };
                    }
                }
            });
        }

        window.__nomad = {
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
                        var fId = ifr.getAttribute('data-nomad-frame') || ('f' + (fi + 1));
                        ifr.setAttribute('data-nomad-frame', fId);
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
                                            if (!window.__nomad_frames) window.__nomad_frames = {};
                                            window.__nomad_frames[fid] = {
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
                                        type: '__nomad_frame_request_scan',
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
                        var ifr = document.querySelector('iframe[data-nomad-frame="' + fId + '"]');
                        if (!ifr && fId.indexOf('f') === 0) {
                            var fIdx = parseInt(fId.substring(1), 10) - 1;
                            var allIframes = document.querySelectorAll('iframe');
                            if (fIdx >= 0 && fIdx < allIframes.length) {
                                ifr = allIframes[fIdx];
                                try { ifr.setAttribute('data-nomad-frame', fId); } catch(e) {}
                            }
                        }
                        if (!ifr && this.findInTree) {
                            try {
                                ifr = this.findInTree(document, 'iframe[data-nomad-frame="' + fId + '"]') || (fId === 'f1' ? this.findInTree(document, 'iframe') : null);
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
                                        if (ifr.contentWindow && ifr.contentWindow.__nomad && ifr.contentWindow.__nomad.elements) {
                                            subEl = ifr.contentWindow.__nomad.elements[eId];
                                        }
                                        if (!subEl) {
                                            try { subEl = fDoc.querySelector('[data-nomad-id="' + CSS.escape(eId) + '"]'); } catch(e) {}
                                        }
                                        if (!subEl) {
                                            try { subEl = fDoc.querySelector('[data-nomad-id="' + CSS.escape(element) + '"]'); } catch(e) {}
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
                                var fData = window.__nomad_frames && window.__nomad_frames[fId];
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
                    if (resolvedNode) {
                        element = resolvedNode;
                    } else {
                        // 4. Fallback to elementsBounds cache from getSemanticTree (e.g. cross-origin subframes)
                        var cache = this.elementsBounds || window.__nomad_elements_bounds;
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
                    var found = root.querySelector('[data-nomad-id="' + sel + '"]') || root.querySelector(sel);
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
                        var ifr = document.querySelector('iframe[data-nomad-frame="' + fId + '"]');
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
                                    var fEl = (ifr.contentWindow.__nomad && ifr.contentWindow.__nomad.elements && ifr.contentWindow.__nomad.elements[eId]) ||
                                              ifr.contentDocument.querySelector('[data-nomad-id="' + eId + '"]') ||
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
                    var selector = 'a, button, input, textarea, select, details, summary, h1, h2, h3, h4, h5, h6, img, li, p, td, th, pre, code, blockquote, canvas, [draggable], [ondragstart], [ondrop], [id*="hit"], [id*="drag"], [id*="drop"], [class*="drag"], [class*="drop"], [class*="dropzone"], [role="button"], [role="link"], [role="checkbox"], [role="radio"], [role="combobox"], [role="menuitem"], [role="tab"], [role="switch"], [role="option"], [role="heading"], [role="listitem"], [role="status"], [role="alert"], [role="cell"], [tabindex]:not([tabindex="-1"]), [contenteditable="true"], [oncontextmenu], [data-contextmenu], [data-context-menu], [contextmenu], [aria-haspopup="menu"], iframe';
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
                            } else if (n.tagName === 'IFRAME') {
                                try {
                                    var fDoc = n.contentDocument || (n.contentWindow ? n.contentWindow.document : null);
                                    if (fDoc) collectNodes(fDoc, list);
                                } catch(e) {}
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
                    var exId = allInteractive[k].getAttribute('data-nomad-id');
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
                    if ((tag === 'a' || tag === 'button') && !text && !val && !el.querySelector('img, svg')) {
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
                    var id = el.getAttribute('data-nomad-id');
                    if (!id || assignedIds[id] !== el) {
                        id = 'e' + (nextCounter++);
                        assignedIds[id] = el;
                        try { el.setAttribute('data-nomad-id', id); } catch(e) {}
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

                    var frameId = ifr.getAttribute('data-nomad-frame') || ('f' + (fi + 1));
                    ifr.setAttribute('data-nomad-frame', frameId);

                    try {
                        ifr.contentWindow.postMessage({ type: '__nomad_frame_request_scan', frameId: frameId }, '*');
                    } catch(err) {}

                    var frameData = window.__nomad_frames && window.__nomad_frames[frameId];
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
                                    var sid = se.getAttribute('data-nomad-id') || ('e' + (si + 1));
                                    se.setAttribute('data-nomad-id', sid);
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
                window.__nomad_elements_bounds = this.elementsBounds;

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
                    if (item.isObscured) desc += ' (obscured)';
                    summaryLines.push(desc);
                }

                if (offset + limit < totalCount) {
                    summaryLines.push('[... and ' + (totalCount - (offset + limit)) + ' more elements. Call nomad_snapshot with offset=' + (offset + limit) + ']');
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

            // 2. Dispatches synthetic and realistic user actions
            performAction: function(actionObj) {
                try {
                    var nomad = this || (typeof window !== 'undefined' ? (window.__nomad || window.nomad) : {});
                    var action = (actionObj.action || actionObj.type || '').trim().toLowerCase();
                    var targetId = actionObj.target || actionObj.elementId || actionObj.selector;
                    var el = null;
                    var wasHealed = false;

                    if (!action) {
                        return { success: false, code: 'INVALID_ACTION', message: "Missing required 'type' or 'action' field" };
                    }

                    if (targetId) {
                        if (this.elements && this.elements[targetId] && this.isNodeConnected(this.elements[targetId])) {
                            el = this.elements[targetId];
                        } else {
                            el = this.findInTree(document, targetId);
                            if (el && this.elements) this.elements[targetId] = el;
                        }

                        // Validate compatibility with the requested action
                        var sig = (this.elementSignatures && this.elementSignatures[targetId]) || null;
                        var isIncompatible = false;
                        if (el) {
                            var elTag = el.tagName ? el.tagName.toLowerCase() : '';
                            if (action === 'type' || action === 'clear') {
                                if (!isTextEditable(el)) isIncompatible = true;
                            } else if (action === 'selectoption') {
                                if (elTag !== 'select') isIncompatible = true;
                            } else if (action === 'upload') {
                                if (!resolveFileInput(el) && !isDropzone(el)) isIncompatible = true;
                            }
                        }

                    // In-place self-healing for stale node references or incompatible nodes
                    if ((!el || isIncompatible) && this.selfHealElement) {
                        var healed = this.selfHealElement(targetId, action);
                        if (healed) {
                            el = healed;
                            wasHealed = true;
                            isIncompatible = false;
                            if (!this.elements) this.elements = {};
                            this.elements[targetId] = el;
                            try { el.setAttribute('data-nomad-id', targetId); } catch(e) {}
                        }
                    }

                    // If still incompatible after healing attempt, explicitly report STALE_REF
                    if (el && isIncompatible) {
                        var currentDesc = '<' + (el.tagName ? el.tagName.toLowerCase() : 'element') + '>';
                        var expectedDesc = (sig && sig.tag) ? '<' + sig.tag + '>' : (action === 'upload' ? 'a file input control' : 'an editable control');
                        return {
                            success: false,
                            staleRef: true,
                            code: 'STALE_REF',
                            message: "Stale element reference '" + targetId + "': target was snapshotted as " + expectedDesc + " but currently resolves to " + currentDesc + " which is incompatible with '" + action + "'. The DOM shifted or reloaded. Please call nomad_snapshot to get fresh element refs.",
                            elementId: targetId
                        };
                    }
                }

                var targetRequiredActions = ['type', 'clear', 'selectoption', 'highlight', 'upload'];
                if (targetRequiredActions.indexOf(action) !== -1 && !targetId) {
                    return { success: false, code: 'MISSING_TARGET', message: 'No target element specified for ' + action + ' action' };
                }
                if (action === 'drag' && !targetId && (actionObj.x === undefined || actionObj.y === undefined)) {
                    return { success: false, code: 'MISSING_TARGET', message: 'No target element or coordinates specified for drag action' };
                }

                // Sub-frame action routing for frame-qualified targets (e.g. 'f1:e2' or 'e2:f1')
                var frameTarget = parseFrameTarget(targetId);
                if (frameTarget) {
                    var fId = frameTarget.frameId;
                    var eId = frameTarget.elementId;
                    var ifr = document.querySelector('iframe[data-nomad-frame="' + fId + '"]');
                    if (!ifr && fId.indexOf('f') === 0) {
                        var ifrIdx = parseInt(fId.substring(1), 10) - 1;
                        var allIfrs = document.querySelectorAll('iframe');
                        if (ifrIdx >= 0 && ifrIdx < allIfrs.length) {
                            ifr = allIfrs[ifrIdx];
                            try { ifr.setAttribute('data-nomad-frame', fId); } catch(e) {}
                        }
                    }
                    if (ifr && ifr.contentWindow) {
                        try {
                            ifr.contentWindow.postMessage({
                                type: '__nomad_frame_action',
                                target: eId,
                                action: actionObj
                            }, '*');
                            return {
                                success: true,
                                message: 'Routed ' + action + ' to subframe ' + fId + ' on element ' + eId,
                                elementId: targetId
                            };
                        } catch(err) {
                            return {
                                success: false,
                                code: 'FRAME_ROUTING_ERROR',
                                message: 'Failed to dispatch action to frame ' + fId + ': ' + String(err),
                                elementId: targetId
                            };
                        }
                    }
                }

                if (!el && actionObj.x !== undefined && actionObj.y !== undefined) {
                    el = document.elementFromPoint(actionObj.x, actionObj.y);
                }

                if (targetId && !el && action !== 'scroll' && action !== 'press') {
                    var isExplicitSelector = Boolean(actionObj.selector && !actionObj.elementId);
                    var isRefPattern = /^(f[0-9]+:)?[e][0-9]+$/i.test(targetId);
                    var isCssSelectorString = /^([#.\[:]|[a-z0-9_-]+[ >+~])/i.test(targetId);
                    if (isExplicitSelector || isCssSelectorString) {
                        return {
                            success: false,
                            staleRef: false,
                            code: 'SELECTOR_NOT_FOUND',
                            message: "Target element matching selector '" + targetId + "' not found in DOM.",
                            elementId: targetId
                        };
                    }
                    if (isRefPattern) {
                        return {
                            success: false,
                            staleRef: true,
                            code: 'STALE_REF',
                            message: "Target element '" + targetId + "' not found or no longer in DOM. Please re-snapshot the page.",
                            elementId: targetId
                        };
                    }
                    return {
                        success: false,
                        staleRef: false,
                        code: 'ELEMENT_NOT_FOUND',
                        message: "Target element '" + targetId + "' not found.",
                        elementId: targetId
                    };
                }

                var actionOutcome = (function(self) {
                    switch (action) {
                    case 'click':
                        if (el) {
                            if (el.ownerDocument && el.ownerDocument !== document && el.ownerDocument.defaultView && el.ownerDocument.defaultView.frameElement) {
                                try { el.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                            }
                            el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                            try { el.focus(); } catch(e) {}

                            // If el is a label, delegate directly to its associated form control
                            if (el.tagName === 'LABEL') {
                                var targetInput = el.htmlFor ? (el.ownerDocument ? el.ownerDocument.getElementById(el.htmlFor) : document.getElementById(el.htmlFor)) : el.querySelector('input, select, textarea');
                                if (targetInput) el = targetInput;
                            }

                            var elDoc = el.ownerDocument || document;
                            var elWin = elDoc.defaultView || window;

                            var targetToClick = el;
                            var wasObscured = false;
                            var interceptorTag = null;

                            var rectC = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                            var cxC = Math.round(rectC.left + (rectC.width ? rectC.width / 2 : 0));
                            var cyC = Math.round(rectC.top + (rectC.height ? rectC.height / 2 : 0));

                            // Occlusion hit-testing: unless force: true, clicks hit what is physically on top
                            if (!actionObj.force) {
                                try {
                                    var topEl = elDoc.elementFromPoint(cxC, cyC);
                                    if (topEl && topEl !== el && !el.contains(topEl) && !topEl.contains(el)) {
                                        var rootNode = el.getRootNode ? el.getRootNode() : null;
                                        var host = (rootNode && rootNode.host) ? rootNode.host : null;
                                        if (topEl !== host && (!host || !host.contains(topEl))) {
                                            wasObscured = true;
                                            interceptorTag = topEl.tagName ? topEl.tagName.toLowerCase() : 'overlay';
                                            targetToClick = topEl;
                                        }
                                    }
                                } catch(e) {}
                            }

                            // Full pointer and mouse event simulation sequence with realistic coordinates
                            var pointerInit = {
                                bubbles: true,
                                cancelable: true,
                                view: elWin,
                                clientX: cxC,
                                clientY: cyC,
                                screenX: cxC,
                                screenY: cyC,
                                button: 0,
                                buttons: 1,
                                pointerId: 1,
                                pointerType: 'mouse',
                                isPrimary: true,
                                width: 1,
                                height: 1
                            };
                            var pdown = new elWin.PointerEvent('pointerdown', pointerInit);
                            var mdown = new elWin.MouseEvent('mousedown', {
                                bubbles: true,
                                cancelable: true,
                                view: elWin,
                                clientX: cxC,
                                clientY: cyC,
                                screenX: cxC,
                                screenY: cyC,
                                button: 0,
                                buttons: 1
                            });
                            var pointerUpInit = Object.assign({}, pointerInit, { buttons: 0 });
                            var pup = new elWin.PointerEvent('pointerup', pointerUpInit);
                            var mup = new elWin.MouseEvent('mouseup', {
                                bubbles: true,
                                cancelable: true,
                                view: elWin,
                                clientX: cxC,
                                clientY: cyC,
                                screenX: cxC,
                                screenY: cyC,
                                button: 0,
                                buttons: 0
                            });

                            targetToClick.dispatchEvent(pdown);
                            targetToClick.dispatchEvent(mdown);
                            targetToClick.dispatchEvent(pup);
                            targetToClick.dispatchEvent(mup);

                            // Native click triggers standard activation behavior (checkboxes, buttons, navigation)
                            try {
                                targetToClick.click();
                            } catch(e) {
                                targetToClick.dispatchEvent(new elWin.MouseEvent('click', {
                                    bubbles: true,
                                    cancelable: true,
                                    view: elWin,
                                    clientX: cxC,
                                    clientY: cyC,
                                    screenX: cxC,
                                    screenY: cyC,
                                    button: 0,
                                    buttons: 0
                                }));
                            }

                            if (wasObscured) {
                                return {
                                    success: true,
                                    message: 'Clicked point of ' + (targetId || 'element') + ' (intercepted by <' + interceptorTag + '>)',
                                    elementId: targetId,
                                    obscured: true,
                                    isObscured: true,
                                    interceptedBy: interceptorTag,
                                    occludedBy: interceptorTag,
                                    centerCoordinates: { x: Math.round(cxC), y: Math.round(cyC) }
                                };
                            }

                            return {
                                success: true,
                                message: 'Clicked ' + (targetId || 'element'),
                                elementId: targetId,
                                obscured: false,
                                isObscured: false,
                                centerCoordinates: { x: Math.round(cxC), y: Math.round(cyC) }
                            };
                        } else if (actionObj.x !== undefined && actionObj.y !== undefined) {
                            var hit = document.elementFromPoint(actionObj.x, actionObj.y);
                            if (hit) {
                                hit.click();
                                return { success: true, message: 'Clicked coordinates (' + actionObj.x + ', ' + actionObj.y + ')' };
                            }
                            return { success: false, code: 'ELEMENT_NOT_FOUND', message: 'No element at coordinates (' + actionObj.x + ', ' + actionObj.y + ')' };
                        }
                        return { success: false, code: 'MISSING_TARGET', message: 'No target element or coordinates specified for click action' };

                    case 'dblclick':
                    case 'double_click':
                    case 'doubleclick':
                        if (el) {
                            var elDocD = el.ownerDocument || document;
                            var elWinD = elDocD.defaultView || window;
                            if (elDocD !== document && elWinD.frameElement) {
                                try { elWinD.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                            }
                            el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                            var rectD = el.getBoundingClientRect();
                            var cxD = rectD.left + rectD.width / 2;
                            var cyD = rectD.top + rectD.height / 2;

                            var targetToDbl = el;
                            var hitTopD = elDocD.elementFromPoint(cxD, cyD);
                            var wasObscuredD = false;
                            var interceptorTagD = '';
                            if (hitTopD && hitTopD !== el && !el.contains(hitTopD)) {
                                wasObscuredD = true;
                                interceptorTagD = hitTopD.tagName ? hitTopD.tagName.toLowerCase() : 'overlay';
                                targetToDbl = hitTopD;
                            }

                            function dispatchClickSeq(detail) {
                                var pOpts = { bubbles: true, cancelable: true, view: elWinD, clientX: cxD, clientY: cyD, isPrimary: true, pointerId: 1, pointerType: 'mouse', button: 0, buttons: 1, detail: detail };
                                targetToDbl.dispatchEvent(new elWinD.PointerEvent('pointerdown', pOpts));
                                targetToDbl.dispatchEvent(new elWinD.MouseEvent('mousedown', { bubbles: true, cancelable: true, view: elWinD, clientX: cxD, clientY: cyD, button: 0, buttons: 1, detail: detail }));
                                try { targetToDbl.focus(); } catch(e) {}
                                var upOpts = { bubbles: true, cancelable: true, view: elWinD, clientX: cxD, clientY: cyD, isPrimary: true, pointerId: 1, pointerType: 'mouse', button: 0, buttons: 0, detail: detail };
                                targetToDbl.dispatchEvent(new elWinD.PointerEvent('pointerup', upOpts));
                                targetToDbl.dispatchEvent(new elWinD.MouseEvent('mouseup', { bubbles: true, cancelable: true, view: elWinD, clientX: cxD, clientY: cyD, button: 0, buttons: 0, detail: detail }));
                                targetToDbl.dispatchEvent(new elWinD.MouseEvent('click', { bubbles: true, cancelable: true, view: elWinD, clientX: cxD, clientY: cyD, button: 0, buttons: 0, detail: detail }));
                            }

                            dispatchClickSeq(1);
                            dispatchClickSeq(2);
                            targetToDbl.dispatchEvent(new elWinD.MouseEvent('dblclick', { bubbles: true, cancelable: true, view: elWinD, clientX: cxD, clientY: cyD, button: 0, buttons: 0, detail: 2 }));

                            if (wasObscuredD) {
                                return {
                                    success: true,
                                    message: 'Double-clicked point of ' + (targetId || 'element') + ' (intercepted by <' + interceptorTagD + '>)',
                                    elementId: targetId,
                                    obscured: true,
                                    isObscured: true,
                                    interceptedBy: interceptorTagD,
                                    occludedBy: interceptorTagD,
                                    centerCoordinates: { x: Math.round(cxD), y: Math.round(cyD) }
                                };
                            }
                            return {
                                success: true,
                                message: 'Double-clicked ' + (targetId || 'element'),
                                elementId: targetId,
                                obscured: false,
                                isObscured: false,
                                centerCoordinates: { x: Math.round(cxD), y: Math.round(cyD) }
                            };
                        } else if (actionObj.x !== undefined && actionObj.y !== undefined) {
                            var hitD = document.elementFromPoint(actionObj.x, actionObj.y);
                            if (hitD) {
                                hitD.dispatchEvent(new MouseEvent('dblclick', { bubbles: true, cancelable: true, clientX: actionObj.x, clientY: actionObj.y, detail: 2 }));
                                return { success: true, message: 'Double-clicked coordinates (' + actionObj.x + ', ' + actionObj.y + ')' };
                            }
                            return { success: false, code: 'ELEMENT_NOT_FOUND', message: 'No element at coordinates (' + actionObj.x + ', ' + actionObj.y + ')' };
                        }
                        return { success: false, code: 'MISSING_TARGET', message: 'No target element or coordinates specified for dblclick action' };

                    case 'right_click':
                    case 'rightclick':
                    case 'context_menu':
                    case 'contextmenu':
                        if (el) {
                            if (el.ownerDocument && el.ownerDocument !== document && el.ownerDocument.defaultView && el.ownerDocument.defaultView.frameElement) {
                                try { el.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                            }
                            if (el.scrollIntoView) {
                                try { el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                            }
                            try { el.focus(); } catch(e) {}

                            var elDocR = el.ownerDocument || document;
                            var elWinR = elDocR.defaultView || window;
                            var rectR = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                            var cxR = Math.round(rectR.left + (rectR.width ? rectR.width / 2 : 0));
                            var cyR = Math.round(rectR.top + (rectR.height ? rectR.height / 2 : 0));

                            var targetToRClick = el;
                            if (!actionObj.force) {
                                try {
                                    var topR = elDocR.elementFromPoint(cxR, cyR);
                                    if (topR && topR !== el && !el.contains(topR) && !topR.contains(el)) {
                                        targetToRClick = topR;
                                    }
                                } catch(e) {}
                            }

                            var rPointerInit = {
                                bubbles: true,
                                cancelable: true,
                                view: elWinR,
                                clientX: cxR,
                                clientY: cyR,
                                screenX: cxR,
                                screenY: cyR,
                                button: 2,
                                buttons: 2,
                                pointerId: 1,
                                pointerType: 'mouse',
                                isPrimary: true
                            };
                            targetToRClick.dispatchEvent(new elWinR.PointerEvent('pointerdown', rPointerInit));
                            targetToRClick.dispatchEvent(new elWinR.MouseEvent('mousedown', {
                                bubbles: true, cancelable: true, view: elWinR, clientX: cxR, clientY: cyR, screenX: cxR, screenY: cyR, button: 2, buttons: 2
                            }));
                            targetToRClick.dispatchEvent(new elWinR.PointerEvent('pointerup', Object.assign({}, rPointerInit, { buttons: 0 })));
                            targetToRClick.dispatchEvent(new elWinR.MouseEvent('mouseup', {
                                bubbles: true, cancelable: true, view: elWinR, clientX: cxR, clientY: cyR, screenX: cxR, screenY: cyR, button: 2, buttons: 0
                            }));
                            var ctxEvt = new elWinR.MouseEvent('contextmenu', {
                                bubbles: true, cancelable: true, view: elWinR, clientX: cxR, clientY: cyR, screenX: cxR, screenY: cyR, button: 2, buttons: 0
                            });
                            targetToRClick.dispatchEvent(ctxEvt);
                            return { success: true, message: 'Context menu (right-click) dispatched on ' + (targetId || 'element'), elementId: targetId };
                        } else if (actionObj.x !== undefined && actionObj.y !== undefined) {
                            var hitR = document.elementFromPoint(actionObj.x, actionObj.y);
                            if (hitR) {
                                hitR.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: actionObj.x, clientY: actionObj.y, button: 2 }));
                                return { success: true, message: 'Context menu dispatched at (' + actionObj.x + ', ' + actionObj.y + ')' };
                            }
                            return { success: false, code: 'ELEMENT_NOT_FOUND', message: 'No element at coordinates (' + actionObj.x + ', ' + actionObj.y + ')' };
                        }
                        return { success: false, code: 'MISSING_TARGET', message: 'No target element or coordinates specified for right-click action' };

                    case 'hover':
                        if (!el) return { success: false, code: 'MISSING_TARGET', message: 'No target element for hover action' };
                        if (el.ownerDocument && el.ownerDocument !== document && el.ownerDocument.defaultView && el.ownerDocument.defaultView.frameElement) {
                            try { el.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                        }
                        el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                        var elDocH = el.ownerDocument || document;
                        var elWinH = elDocH.defaultView || window;
                        var rH = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                        var cxH = Math.round(rH.left + rH.width / 2);
                        var cyH = Math.round(rH.top + rH.height / 2);
                        var pH = { bubbles: true, cancelable: true, view: elWinH, clientX: cxH, clientY: cyH, screenX: cxH, screenY: cyH, pointerId: 1, pointerType: 'mouse', isPrimary: true };
                        var eH = { bubbles: false, cancelable: false, view: elWinH, clientX: cxH, clientY: cyH, screenX: cxH, screenY: cyH, pointerId: 1, pointerType: 'mouse', isPrimary: true };
                        el.dispatchEvent(new elWinH.PointerEvent('pointerover', pH));
                        el.dispatchEvent(new elWinH.PointerEvent('pointerenter', eH));
                        el.dispatchEvent(new elWinH.PointerEvent('pointermove', pH));
                        el.dispatchEvent(new elWinH.MouseEvent('mouseover', pH));
                        el.dispatchEvent(new elWinH.MouseEvent('mouseenter', eH));
                        el.dispatchEvent(new elWinH.MouseEvent('mousemove', pH));

                        this.emulateHover(el, cxH, cyH);

                        return {
                            success: true,
                            message: 'Hovered over ' + targetId,
                            elementId: targetId,
                            centerCoordinates: { x: cxH, y: cyH }
                        };

                    case 'clear':
                        if (!el) return { success: false, code: 'MISSING_TARGET', message: 'No target element for clear action' };
                        if (!isTextEditable(el)) {
                            return { success: false, code: 'NOT_EDITABLE', message: 'Target element <' + el.tagName.toLowerCase() + '> is not an input or editable element' };
                        }
                        if (el.ownerDocument && el.ownerDocument !== document && el.ownerDocument.defaultView && el.ownerDocument.defaultView.frameElement) {
                            try { el.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                        }
                        el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                        try { el.focus(); } catch(e) {}
                        var elDocC = el.ownerDocument || document;
                        var elWinC = elDocC.defaultView || window;
                        if (el.isContentEditable) {
                            try {
                                elDocC.execCommand('selectAll', false, null);
                                elDocC.execCommand('delete', false, null);
                            } catch(e) {
                                el.innerText = '';
                            }
                            el.dispatchEvent(new (elWinC.Event || Event)('input', { bubbles: true }));
                            return { success: true, message: 'Cleared value in ' + targetId, elementId: targetId };
                        }
                        var clearTag = el.tagName ? el.tagName.toUpperCase() : '';
                        try {
                            var protoC = (clearTag === 'TEXTAREA') ? ((elWinC.HTMLTextAreaElement && elWinC.HTMLTextAreaElement.prototype) || window.HTMLTextAreaElement.prototype) : ((elWinC.HTMLInputElement && elWinC.HTMLInputElement.prototype) || window.HTMLInputElement.prototype);
                            var descC = Object.getOwnPropertyDescriptor(protoC, 'value');
                            var setterC = descC && descC.set;
                            if (setterC) { setterC.call(el, ''); } else { el.value = ''; }
                        } catch(e) {
                            el.value = '';
                        }
                        el.dispatchEvent(new (elWinC.Event || Event)('input', { bubbles: true }));
                        el.dispatchEvent(new (elWinC.Event || Event)('change', { bubbles: true }));
                        return { success: true, message: 'Cleared value in ' + targetId, elementId: targetId };

                    case 'type':
                        if (!el) return { success: false, code: 'MISSING_TARGET', message: 'No target element for type action' };
                        if (!isTextEditable(el)) {
                            return { success: false, code: 'NOT_EDITABLE', message: 'Target element <' + el.tagName.toLowerCase() + '> is not editable or an input control' };
                        }
                        if (el.ownerDocument && el.ownerDocument !== document && el.ownerDocument.defaultView && el.ownerDocument.defaultView.frameElement) {
                            try { el.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                        }
                        el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                        try { el.focus(); } catch(e) {}
                        var typeTag = el.tagName ? el.tagName.toUpperCase() : '';
                        var hasExplicitText = actionObj.text !== undefined && actionObj.text !== null;
                        var textToType = hasExplicitText ? String(actionObj.text) : '';
                        var shouldUpdateValue = hasExplicitText && (textToType.length > 0 || actionObj.clear === true || !actionObj.submit);
                        var elDocT = el.ownerDocument || document;
                        var elWinT = elDocT.defaultView || window;
                        if (el.isContentEditable) {
                            if (shouldUpdateValue) {
                                try {
                                    elDocT.execCommand('selectAll', false, null);
                                    elDocT.execCommand('insertText', false, textToType);
                                } catch(e) {
                                    el.innerText = textToType;
                                }
                                el.dispatchEvent(new (elWinT.Event || Event)('input', { bubbles: true }));
                            }
                            if (actionObj.submit) {
                                var cEnterDown = new (elWinT.KeyboardEvent || KeyboardEvent)('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                                var cEnterUp = new (elWinT.KeyboardEvent || KeyboardEvent)('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                                el.dispatchEvent(cEnterDown);
                                el.dispatchEvent(cEnterUp);
                            }
                            var ceMsg = shouldUpdateValue ? ('Typed into ' + (targetId || 'element')) : ('Submitted ' + (targetId || 'element'));
                            return { success: true, message: ceMsg, elementId: targetId };
                        }
                        if (shouldUpdateValue) {
                            try {
                                // React 16+ controlled component compatibility
                                var protoType = (typeTag === 'TEXTAREA') ? ((elWinT.HTMLTextAreaElement && elWinT.HTMLTextAreaElement.prototype) || window.HTMLTextAreaElement.prototype) : ((elWinT.HTMLInputElement && elWinT.HTMLInputElement.prototype) || window.HTMLInputElement.prototype);
                                var descType = Object.getOwnPropertyDescriptor(protoType, 'value');
                                var setterType = descType && descType.set;
                                if (setterType) { setterType.call(el, textToType); } else { el.value = textToType; }
                            } catch(e) {
                                el.value = textToType;
                            }
                            el.dispatchEvent(new (elWinT.Event || Event)('input', { bubbles: true }));
                        }
                        if (actionObj.submit || actionObj.blur || actionObj.change) {
                            el.dispatchEvent(new (elWinT.Event || Event)('change', { bubbles: true }));
                        }
                        if (actionObj.blur) {
                            try { el.blur(); } catch(e) {}
                        }
                        if (actionObj.submit) {
                            var enterDown = new (elWinT.KeyboardEvent || KeyboardEvent)('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                            var enterUp = new (elWinT.KeyboardEvent || KeyboardEvent)('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                            el.dispatchEvent(enterDown);
                            el.dispatchEvent(enterUp);
                            var f = el.form || (el.closest ? el.closest('form') : null);
                            if (f) {
                                try {
                                    if (typeof f.requestSubmit === 'function') f.requestSubmit();
                                    else f.submit();
                                } catch(e) {}
                            }
                        }
                        var inputMsg = shouldUpdateValue ? ('Typed into ' + (targetId || 'element')) : ('Submitted ' + (targetId || 'element'));
                        return { success: true, message: inputMsg, elementId: targetId };

                    case 'drag':
                        if (!el) return { success: false, code: 'MISSING_TARGET', message: 'No target element for drag action', elementId: targetId };
                        var nomad = (typeof window !== 'undefined' && window.__nomad) ? window.__nomad : (this || {});
                        var toTargetId = actionObj.toTarget || actionObj.toElementId || actionObj.toSelector || null;
                        var destEl = null;
                        var destX = (actionObj.toX !== undefined && actionObj.toX !== null) ? Number(actionObj.toX) : null;
                        var destY = (actionObj.toY !== undefined && actionObj.toY !== null) ? Number(actionObj.toY) : null;
                        if (toTargetId) {
                            destEl = (nomad.elements && nomad.elements[toTargetId] && nomad.isNodeConnected && nomad.isNodeConnected(nomad.elements[toTargetId]) ? nomad.elements[toTargetId] : null) || (nomad.findInTree ? nomad.findInTree(document, toTargetId) : null) || document.querySelector('[data-nomad-id="' + toTargetId + '"]') || document.querySelector(toTargetId);
                            if (destEl) {
                                var dRect = destEl.getBoundingClientRect ? destEl.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                                if (destX === null) destX = Math.round(dRect.left + dRect.width / 2);
                                if (destY === null) destY = Math.round(dRect.top + dRect.height / 2);
                            } else {
                                var vRect = nomad.getElementViewportRect ? nomad.getElementViewportRect(toTargetId) : null;
                                if (vRect && (vRect.width > 0 || vRect.height > 0)) {
                                    if (destX === null) destX = Math.round(vRect.left + vRect.width / 2);
                                    if (destY === null) destY = Math.round(vRect.top + vRect.height / 2);
                                }
                            }
                        }
                        if (destX === null || destY === null) {
                            return { success: false, code: 'MISSING_DESTINATION', message: 'Missing destination coordinates (toX, toY) or destination element (toElementId/toTarget) for drag action', elementId: targetId };
                        }
                        return dispatchHtml5Drag(targetId, actionObj.x, actionObj.y, destX, destY, el, destEl || toTargetId);

                    case 'press':
                        var rawKey = actionObj.key || actionObj.text || 'Enter';
                        var targetNode = el || document.activeElement || document.body;

                        // Parse modifiers from chords like "Meta+A", "Control+Enter", "Shift+Tab"
                        var parts = rawKey.split('+');
                        var mainKey = parts[parts.length - 1];
                        var hasMeta = parts.includes('Meta') || parts.includes('Cmd') || parts.includes('Command');
                        var hasCtrl = parts.includes('Control') || parts.includes('Ctrl');
                        var hasShift = parts.includes('Shift');
                        var hasAlt = parts.includes('Alt') || parts.includes('Option');

                        var validNamedKeys = {
                            'enter': 'Enter', 'tab': 'Tab', 'escape': 'Escape', 'esc': 'Escape',
                            'backspace': 'Backspace', 'delete': 'Delete', 'del': 'Delete',
                            'arrowup': 'ArrowUp', 'up': 'ArrowUp',
                            'arrowdown': 'ArrowDown', 'down': 'ArrowDown',
                            'arrowleft': 'ArrowLeft', 'left': 'ArrowLeft',
                            'arrowright': 'ArrowRight', 'right': 'ArrowRight',
                            'home': 'Home', 'end': 'End', 'pageup': 'PageUp', 'pagedown': 'PageDown',
                            'space': ' ', 'spacebar': ' ',
                            'capslock': 'CapsLock', 'insert': 'Insert',
                            'f1': 'F1', 'f2': 'F2', 'f3': 'F3', 'f4': 'F4',
                            'f5': 'F5', 'f6': 'F6', 'f7': 'F7', 'f8': 'F8',
                            'f9': 'F9', 'f10': 'F10', 'f11': 'F11', 'f12': 'F12',
                            'meta': 'Meta', 'cmd': 'Meta', 'command': 'Meta',
                            'control': 'Control', 'ctrl': 'Control',
                            'shift': 'Shift', 'alt': 'Alt', 'option': 'Alt'
                        };

                        var normMain = mainKey.trim().toLowerCase();
                        if (mainKey.length > 1) {
                            if (!validNamedKeys[normMain]) {
                                return { success: false, code: 'INVALID_KEY', message: 'Unknown or unsupported key: ' + rawKey };
                            }
                            mainKey = validNamedKeys[normMain];
                        }

                        var kopts = {
                            key: mainKey,
                            code: mainKey,
                            bubbles: true,
                            cancelable: true,
                            metaKey: hasMeta,
                            ctrlKey: hasCtrl,
                            shiftKey: hasShift,
                            altKey: hasAlt
                        };

                        var kdown = new KeyboardEvent('keydown', kopts);
                        var kup = new KeyboardEvent('keyup', kopts);
                        targetNode.dispatchEvent(kdown);
                        targetNode.dispatchEvent(kup);

                        // Execute standard browser editing actions for chords like Meta+A, Backspace
                        if (hasMeta && (normMain === 'a')) {
                            if (typeof targetNode.select === 'function') {
                                targetNode.select();
                            } else {
                                try {
                                    var docSel = targetNode.ownerDocument || document;
                                    var range = docSel.createRange();
                                    range.selectNodeContents(targetNode);
                                    var sel = (docSel.defaultView || window).getSelection();
                                    if (sel) {
                                        sel.removeAllRanges();
                                        sel.addRange(range);
                                    }
                                } catch(e) {}
                            }
                        } else if (normMain === 'backspace' || normMain === 'delete') {
                            if (isTextEditable(targetNode)) {
                                if (targetNode.tagName === 'INPUT' || targetNode.tagName === 'TEXTAREA') {
                                    var start = targetNode.selectionStart;
                                    var end = targetNode.selectionEnd;
                                    if (start !== null && end !== null && start !== end) {
                                        var oldVal = targetNode.value || '';
                                        targetNode.value = oldVal.slice(0, start) + oldVal.slice(end);
                                        targetNode.selectionStart = targetNode.selectionEnd = start;
                                        targetNode.dispatchEvent(new Event('input', { bubbles: true }));
                                        targetNode.dispatchEvent(new Event('change', { bubbles: true }));
                                    } else if (start !== null && start > 0) {
                                        var oldVal = targetNode.value || '';
                                        targetNode.value = oldVal.slice(0, start - 1) + oldVal.slice(start);
                                        targetNode.selectionStart = targetNode.selectionEnd = start - 1;
                                        targetNode.dispatchEvent(new Event('input', { bubbles: true }));
                                        targetNode.dispatchEvent(new Event('change', { bubbles: true }));
                                    }
                                } else if (targetNode.isContentEditable) {
                                    try {
                                        var docCe = targetNode.ownerDocument || document;
                                        docCe.execCommand('delete', false, null);
                                    } catch(e) {}
                                }
                            }
                        }

                        // Native form control stepping for <input type="range"> and <input type="number">
                        if (targetNode.tagName === 'INPUT' && (targetNode.type === 'range' || targetNode.type === 'number')) {
                            if (normMain === 'arrowright' || normMain === 'arrowup' || normMain === 'right' || normMain === 'up') {
                                if (typeof targetNode.stepUp === 'function') {
                                    try { targetNode.stepUp(); } catch(e) {}
                                } else {
                                    var step = Number(targetNode.step) || 1;
                                    var max = targetNode.max !== '' ? Number(targetNode.max) : Infinity;
                                    var cur = Number(targetNode.value) || 0;
                                    targetNode.value = String(Math.min(max, cur + step));
                                }
                                targetNode.dispatchEvent(new Event('input', { bubbles: true }));
                                targetNode.dispatchEvent(new Event('change', { bubbles: true }));
                            } else if (normMain === 'arrowleft' || normMain === 'arrowdown' || normMain === 'left' || normMain === 'down') {
                                if (typeof targetNode.stepDown === 'function') {
                                    try { targetNode.stepDown(); } catch(e) {}
                                } else {
                                    var step = Number(targetNode.step) || 1;
                                    var min = targetNode.min !== '' ? Number(targetNode.min) : -Infinity;
                                    var cur = Number(targetNode.value) || 0;
                                    targetNode.value = String(Math.max(min, cur - step));
                                }
                                targetNode.dispatchEvent(new Event('input', { bubbles: true }));
                                targetNode.dispatchEvent(new Event('change', { bubbles: true }));
                            }
                        }

                        // If Enter is pressed, trigger form submit if inside a form
                        if (mainKey === 'Enter' || rawKey === 'Enter') {
                            var formNode = (targetNode && targetNode.form) || (targetNode && targetNode.closest ? targetNode.closest('form') : null);
                            if (formNode) {
                                try {
                                    if (typeof formNode.requestSubmit === 'function') {
                                        formNode.requestSubmit();
                                    } else {
                                        formNode.submit();
                                    }
                                } catch(e) {}
                            }
                        }
                        return { success: true, message: 'Pressed key ' + rawKey };

                    case 'selectoption':
                    case 'selectOption':
                        if (!el || el.tagName !== 'SELECT') {
                            return { success: false, code: !el ? 'MISSING_TARGET' : 'NOT_A_SELECT', message: 'Target ' + targetId + ' is not a <select> element' };
                        }
                        var desiredVal = actionObj.optionValue;
                        var desiredTxt = actionObj.optionText;
                        var matched = false;
                        for (var s = 0; s < el.options.length; s++) {
                            var opt = el.options[s];
                            if ((desiredVal && opt.value === desiredVal) || (desiredTxt && opt.text.trim() === desiredTxt.trim())) {
                                el.selectedIndex = s;
                                opt.selected = true;
                                matched = true;
                                break;
                            }
                        }
                        if (matched) {
                            el.dispatchEvent(new Event('input', { bubbles: true }));
                            el.dispatchEvent(new Event('change', { bubbles: true }));
                            return { success: true, message: 'Selected option in ' + targetId, elementId: targetId };
                        }
                        return { success: false, code: 'OPTION_NOT_FOUND', message: 'Option not found in ' + targetId };

                    case 'scroll':
                        var dx = 0;
                        var dy = 0;
                        if (actionObj.scrollDeltaY !== undefined && actionObj.scrollDeltaY !== null) {
                            dy = Number(actionObj.scrollDeltaY) || 0;
                        } else if (actionObj.deltaY !== undefined && actionObj.deltaY !== null) {
                            dy = Number(actionObj.deltaY) || 0;
                        }
                        if (actionObj.scrollDeltaX !== undefined && actionObj.scrollDeltaX !== null) {
                            dx = Number(actionObj.scrollDeltaX) || 0;
                        } else if (actionObj.deltaX !== undefined && actionObj.deltaX !== null) {
                            dx = Number(actionObj.deltaX) || 0;
                        }

                        if (dx === 0 && dy === 0) {
                            var dir = actionObj.direction || 'down';
                            var amt = actionObj.amount !== undefined ? Number(actionObj.amount) : 400;
                            if (dir === 'down') dy = amt;
                            else if (dir === 'up') dy = -amt;
                            else if (dir === 'right') dx = amt;
                            else if (dir === 'left') dx = -amt;
                        }

                        var prevScrollY = window.scrollY || window.pageYOffset || 0;
                        var prevScrollX = window.scrollX || window.pageXOffset || 0;
                        window.scrollBy({ left: dx, top: dy, behavior: 'instant' });
                        var actualDy = Math.round((window.scrollY || window.pageYOffset || 0) - prevScrollY);
                        var actualDx = Math.round((window.scrollX || window.pageXOffset || 0) - prevScrollX);

                        var desc = '';
                        if (actualDy !== 0) {
                            desc = actualDy > 0 ? 'down by ' + actualDy + 'px' : 'up by ' + Math.abs(actualDy) + 'px';
                            if (dy !== 0 && Math.abs(actualDy) < Math.abs(dy)) {
                                desc += ' (clamped from requested ' + Math.abs(dy) + 'px)';
                            }
                        } else if (actualDx !== 0) {
                            desc = actualDx > 0 ? 'right by ' + actualDx + 'px' : 'left by ' + Math.abs(actualDx) + 'px';
                            if (dx !== 0 && Math.abs(actualDx) < Math.abs(dx)) {
                                desc += ' (clamped from requested ' + Math.abs(dx) + 'px)';
                            }
                        } else {
                            desc = '0px (already at boundary)';
                        }
                        return { success: true, message: 'Scrolled ' + desc };

                    case 'highlight':
                        if (!el) return { success: false, code: 'MISSING_TARGET', message: 'No target element to highlight' };
                        self.showHighlight(el);
                        return { success: true, message: 'Highlighted ' + targetId, elementId: targetId };

                    case 'upload':
                        if (!el) return { success: false, code: 'MISSING_TARGET', message: 'No target element for upload action' };
                        var fileInput = resolveFileInput(el);
                        var isDrop = isDropzone(el);
                        if (!fileInput && !isDrop) {
                            var tagDesc = el.tagName ? el.tagName.toLowerCase() : 'element';
                            return {
                                success: false,
                                code: 'INVALID_TARGET',
                                message: "Target element '" + (targetId || 'element') + "' (<" + tagDesc + ">) is not an <input type='file'> or dropzone",
                                elementId: targetId
                            };
                        }
                        if (fileInput && fileInput.disabled) {
                            return {
                                success: false,
                                code: 'ELEMENT_DISABLED',
                                message: "Target file input '" + (targetId || 'element') + "' is disabled",
                                elementId: targetId
                            };
                        }

                        var incomingPaths = actionObj.paths || actionObj.files || [];
                        if (fileInput && !fileInput.multiple && incomingPaths.length > 1) {
                            return {
                                success: false,
                                code: 'MULTIPLE_NOT_ALLOWED',
                                message: "Target file input does not accept multiple files (missing 'multiple' attribute). Received " + incomingPaths.length + " files.",
                                elementId: targetId
                            };
                        }

                        // If element is a drag-and-drop dropzone, dispatch simulated HTML5 DragEvent sequence
                        if (isDrop) {
                            try {
                                var elWinD = (el.ownerDocument && el.ownerDocument.defaultView) || window;
                                var filePaths = actionObj.paths || actionObj.files || [];
                                var fakeFiles = filePaths.map(function(p) {
                                    var name = p.split('/').pop() || 'upload.bin';
                                    return new elWinD.File([''], name, { type: 'application/octet-stream' });
                                });
                                var dt = new elWinD.DataTransfer();
                                for (var fIdx = 0; fIdx < fakeFiles.length; fIdx++) {
                                    dt.items.add(fakeFiles[fIdx]);
                                }
                                var dOpts = { bubbles: true, cancelable: true, view: elWinD, dataTransfer: dt };
                                el.dispatchEvent(new elWinD.DragEvent('dragenter', dOpts));
                                el.dispatchEvent(new elWinD.DragEvent('dragover', dOpts));
                                el.dispatchEvent(new elWinD.DragEvent('drop', dOpts));
                            } catch(dropErr) {}
                        }

                        // If an associated file input was resolved, scroll into view and trigger click to activate native staged file injection
                        if (fileInput) {
                            if (fileInput.ownerDocument && fileInput.ownerDocument !== document && fileInput.ownerDocument.defaultView && fileInput.ownerDocument.defaultView.frameElement) {
                                try { fileInput.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                            }
                            fileInput.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                            try { fileInput.focus(); } catch(e) {}

                            try {
                                fileInput.click();
                            } catch(e) {
                                var elDocU = fileInput.ownerDocument || document;
                                var elWinU = elDocU.defaultView || window;
                                fileInput.dispatchEvent(new elWinU.MouseEvent('click', { bubbles: true, cancelable: true, view: elWinU }));
                            }
                        }
                        return { success: true, message: 'Triggered file upload on ' + (targetId || 'element'), elementId: targetId };

                    default:
                        return { success: false, code: 'UNKNOWN_ACTION', message: 'Unknown action: ' + action };
                }
            }).call(this, this);

            if (actionOutcome && actionOutcome.success && wasHealed) {
                actionOutcome.healed = true;
            }
            return actionOutcome;
        } catch (actionErr) {
            var errMsg = (actionErr && actionErr.message) ? actionErr.message : String(actionErr);
            var errStack = (actionErr && actionErr.stack) ? actionErr.stack : null;
            return {
                success: false,
                code: 'ACTION_JS_ERROR',
                error: errMsg,
                message: "Action '" + (actionObj && (actionObj.action || actionObj.type)) + "' threw JavaScript error: " + errMsg,
                stack: errStack,
                elementId: (actionObj && (actionObj.target || actionObj.elementId || actionObj.selector)) || null
            };
        }
    },

            // 3. Visual Element Highlighter for DevX & Inspection
            showHighlight: function(el) {
                var prev = document.getElementById('__nomad_highlight');
                if (prev) prev.remove();

                var rect = this.getElementViewportRect(el);
                var div = document.createElement('div');
                div.id = '__nomad_highlight';
                div.style.position = 'fixed';
                div.style.left = (rect.left - 2) + 'px';
                div.style.top = (rect.top - 2) + 'px';
                div.style.width = (rect.width + 4) + 'px';
                div.style.height = (rect.height + 4) + 'px';
                div.style.border = '2px solid rgba(0, 0, 0, 0.85)';
                div.style.outline = '1px solid rgba(255, 255, 255, 0.85)';
                div.style.borderRadius = '4px';
                div.style.backgroundColor = 'rgba(0, 0, 0, 0.12)';
                div.style.pointerEvents = 'none';
                div.style.zIndex = '2147483646';
                div.style.transition = 'all 0.15s ease-out';
                document.body.appendChild(div);

                setTimeout(function() {
                    if (div.parentNode) div.remove();
                }, 3000);
            },

            // Obscures sensitive values (passwords, cards, CVVs, PINs) during screenshot capture
            blurSensitiveInputs: function() {
                try {
                    var inputs = document.querySelectorAll('input, textarea');
                    for (var i = 0; i < inputs.length; i++) {
                        var elIn = inputs[i];
                        if (isSensitiveField(elIn) || isSensitiveValue(elIn.value)) {
                            if (!elIn.hasAttribute('data-nomad-blur')) {
                                elIn.setAttribute('data-nomad-blur', elIn.style.filter || 'none');
                                elIn.style.setProperty('filter', 'blur(6px)', 'important');
                            }
                        }
                    }
                } catch(e) {}
            },

            unblurSensitiveInputs: function() {
                try {
                    var blurred = document.querySelectorAll('[data-nomad-blur]');
                    for (var b = 0; b < blurred.length; b++) {
                        var prevFilter = blurred[b].getAttribute('data-nomad-blur');
                        if (prevFilter && prevFilter !== 'none') {
                            blurred[b].style.filter = prevFilter;
                        } else {
                            blurred[b].style.removeProperty('filter');
                        }
                        blurred[b].removeAttribute('data-nomad-blur');
                    }
                } catch(e) {}
            },

            // In-app Virtual Cursor for Agent Actions (stays strictly inside Nomad canvas)
            updateVirtualCursor: function(x, y) {
                try {
                    if (x === undefined || y === undefined) return;
                    var cursor = document.getElementById('__nomad_virtual_cursor');
                    if (!cursor) {
                        cursor = document.createElement('div');
                        cursor.id = '__nomad_virtual_cursor';
                        cursor.style.cssText = 'position:fixed;width:24px;height:24px;pointer-events:none;z-index:2147483647;transition:left 0.08s ease-out,top 0.08s ease-out,opacity 0.2s;opacity:0.95;';
                        cursor.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" style="filter:drop-shadow(0 1px 3px rgba(0,0,0,0.6));"><path d="M2 2L18.5 13.5L11.5 15L9 21.5L2 2Z" fill="#ffffff" stroke="#111111" stroke-width="1.6" stroke-linejoin="round"/></svg>';
                        (document.body || document.documentElement).appendChild(cursor);
                    }
                    cursor.style.left = (Math.round(x) - 2) + 'px';
                    cursor.style.top = (Math.round(y) - 2) + 'px';
                    cursor.style.display = 'block';
                } catch(e) {}
            },

            hideVirtualCursor: function() {
                try {
                    var cur = document.getElementById('__nomad_virtual_cursor');
                    if (cur) cur.style.display = 'none';
                } catch(e) {}
            },

            // Comprehensive CSS :hover & DOM tree emulation for submenus and tooltips
            emulateHover: function(el, x, y) {
                if (!el) return;
                var elDoc = el.ownerDocument || document;

                // 1. Clear previous hover markers
                try {
                    elDoc.querySelectorAll('[data-nomad-hover]').forEach(function(prev) {
                        prev.removeAttribute('data-nomad-hover');
                    });
                } catch(e) {}

                // 2. Set [data-nomad-hover="true"] on target and all ancestors up to documentElement
                var curr = el;
                while (curr && curr.nodeType === 1 && curr !== elDoc.documentElement) {
                    try { curr.setAttribute('data-nomad-hover', 'true'); } catch(e) {}
                    curr = curr.parentElement;
                }

                // 3. Transparently patch Element.prototype.matches for :hover
                if (!Element.prototype.__nomad_orig_matches) {
                    Element.prototype.__nomad_orig_matches = Element.prototype.matches;
                    Element.prototype.matches = function(sel) {
                        if (sel === ':hover' || sel === '*:hover') {
                            return this.hasAttribute('data-nomad-hover') || Element.prototype.__nomad_orig_matches.call(this, sel);
                        }
                        return Element.prototype.__nomad_orig_matches.call(this, sel);
                    };
                }

                // 4. Transparently patch Document.prototype.querySelector/querySelectorAll for :hover
                if (!Document.prototype.__nomad_orig_qs) {
                    Document.prototype.__nomad_orig_qs = Document.prototype.querySelector;
                    Document.prototype.querySelector = function(sel) {
                        if (sel === ':hover' || sel === '*:hover') {
                            return this.querySelector('[data-nomad-hover="true"]') || Document.prototype.__nomad_orig_qs.call(this, sel);
                        }
                        return Document.prototype.__nomad_orig_qs.call(this, sel);
                    };
                }
                if (!Document.prototype.__nomad_orig_qsa) {
                    Document.prototype.__nomad_orig_qsa = Document.prototype.querySelectorAll;
                    Document.prototype.querySelectorAll = function(sel) {
                        if (sel === ':hover' || sel === '*:hover') {
                            var found = this.querySelectorAll('[data-nomad-hover="true"]');
                            return found.length > 0 ? found : Document.prototype.__nomad_orig_qsa.call(this, sel);
                        }
                        return Document.prototype.__nomad_orig_qsa.call(this, sel);
                    };
                }

                // 5. Emulate CSS :hover stylesheet rules (including @media and nested blocks)
                try {
                    var sheet = elDoc.getElementById('nomad-hover-emulation');
                    if (!sheet) {
                        sheet = elDoc.createElement('style');
                        sheet.id = 'nomad-hover-emulation';
                        (elDoc.head || elDoc.documentElement).appendChild(sheet);
                    }

                    function extractHoverRules(rulesList) {
                        var extracted = [];
                        if (!rulesList) return extracted;
                        for (var i = 0; i < rulesList.length; i++) {
                            var r = rulesList[i];
                            if (r.selectorText && r.selectorText.indexOf(':hover') !== -1) {
                                var emulated = r.selectorText.replace(/:hover/g, '[data-nomad-hover="true"]');
                                extracted.push(emulated + ' { ' + r.style.cssText + ' }');
                            } else if (r.cssRules) {
                                var inner = extractHoverRules(r.cssRules);
                                if (inner.length > 0) {
                                    if (r.conditionText) {
                                        extracted.push('@media ' + r.conditionText + ' { ' + inner.join('\n') + ' }');
                                    } else {
                                        extracted = extracted.concat(inner);
                                    }
                                }
                            }
                        }
                        return extracted;
                    }

                    var newRules = [];
                    for (var s = 0; s < elDoc.styleSheets.length; s++) {
                        try {
                            newRules = newRules.concat(extractHoverRules(elDoc.styleSheets[s].cssRules));
                        } catch(err) {}
                    }
                    sheet.textContent = newRules.join('\n');
                } catch(cssErr) {}

                // 6. Update in-app virtual cursor inside viewport
                if (x !== undefined && y !== undefined) {
                    this.updateVirtualCursor(x, y);
                }
            },

            // 4. Overlays indexed visual badges [e1], [e2] and obscures sensitive values for Vision Model Screenshots
            showBadges: function(filterRect) {
                this.hideBadges();
                this.blurSensitiveInputs();

                var container = document.createElement('div');
                container.id = '__nomad_badges_layer';
                container.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;pointer-events:none;z-index:2147483647;';
                container.innerHTML = '<style>.__nb{position:fixed;background:#000;color:#fff;border:1px solid rgba(255,255,255,0.85);font:bold 10px monospace;padding:1px 3px;border-radius:3px;box-shadow:0 1px 3px rgba(0,0,0,0.6);z-index:2147483647;pointer-events:none;line-height:1;white-space:nowrap;}</style>';

                var vpW = window.innerWidth || 2000;
                var vpH = window.innerHeight || 2000;
                var renderedBadges = {};

                // 1. Overlay badges for interactive elements only, with spatial collision avoidance and max badge cap
                var sourceList = this.lastResults || [];
                var countRendered = 0;
                var maxBadges = 75;
                var occupiedBoxes = [];

                var interactiveRoles = {
                    'button': true, 'link': true, 'textbox': true, 'checkbox': true,
                    'radio': true, 'combobox': true, 'menuitem': true, 'tab': true,
                    'switch': true, 'option': true, 'searchbox': true
                };

                for (var ri = 0; ri < sourceList.length; ri++) {
                    if (countRendered >= maxBadges) break;
                    var item = sourceList[ri];
                    if (!item || !item.id || !item.bounds) continue;
                    if (!item.inViewport || item.isObscured) continue;

                    // Filter to actionable elements only (skip passive text nodes: p, li, td, etc.)
                    var tag = (item.tag || '').toLowerCase();
                    var role = (item.role || '').toLowerCase();
                    var isActionable = (tag === 'button' || tag === 'a' || tag === 'input' || tag === 'select' || tag === 'textarea' || tag === 'details' || tag === 'summary' || interactiveRoles[role]);
                    if (!isActionable) continue;

                    var b = item.bounds;
                    if (b.width <= 0 || b.height <= 0) continue;
                    if (b.y + b.height < 0 || b.y > vpH || b.x + b.width < 0 || b.x > vpW) continue;

                    // Filter by Set-of-Marks container crop rect if provided
                    if (filterRect) {
                        var inFilter = (b.x + b.width >= filterRect.x && b.x <= filterRect.x + filterRect.width &&
                                        b.y + b.height >= filterRect.y && b.y <= filterRect.y + filterRect.height);
                        if (!inFilter) continue;
                    }

                    var badgeLeft = Math.max(0, Math.min(vpW - 60, b.x));
                    var badgeTop = (b.y >= 14) ? (b.y - 12) : Math.max(0, b.y + 2);

                    // Spatial collision avoidance: skip if another badge is within 12px horizontally and 10px vertically
                    var collides = false;
                    for (var oi = 0; oi < occupiedBoxes.length; oi++) {
                        var ob = occupiedBoxes[oi];
                        if (Math.abs(badgeLeft - ob.x) < 12 && Math.abs(badgeTop - ob.y) < 10) {
                            collides = true;
                            break;
                        }
                    }
                    if (collides) continue;

                    occupiedBoxes.push({ x: badgeLeft, y: badgeTop });
                    var badge = document.createElement('span');
                    badge.className = '__nb';
                    badge.textContent = item.id;
                    badge.style.left = badgeLeft + 'px';
                    badge.style.top = badgeTop + 'px';
                    container.appendChild(badge);
                    renderedBadges[item.id] = true;
                    countRendered++;
                }

                if (document.body) {
                    document.body.appendChild(container);
                    void document.body.offsetHeight;
                } else if (document.documentElement) {
                    document.documentElement.appendChild(container);
                    void document.documentElement.offsetHeight;
                }
            },

            hideBadges: function() {
                var layers = document.querySelectorAll('#__nomad_badges_layer');
                for (var l = 0; l < layers.length; l++) {
                    layers[l].remove();
                }
                this.unblurSensitiveInputs();
            },

            // 5. Waits for DOM mutation quiescence (stability)
            waitForStability: function(quietMs, timeoutMs) {
                return new Promise(function(resolve) {
                    var quiet = quietMs || 250;
                    var maxWait = timeoutMs || 5000;
                    var lastMutationTime = performance.now();
                    var mutationCount = 0;
                    var intervalTimer = null;
                    var maxTimer = null;
                    var resolved = false;
                    var observer = null;
                    var recentMutationTimes = [];

                    function recordMutation(count) {
                        var t = performance.now();
                        lastMutationTime = t;
                        mutationCount += count;
                        recentMutationTimes.push(t);
                        if (recentMutationTimes.length > 20) {
                            recentMutationTimes.shift();
                        }
                    }

                    function done(res) {
                        if (resolved) return;
                        resolved = true;
                        if (maxTimer) clearTimeout(maxTimer);
                        if (intervalTimer) clearInterval(intervalTimer);
                        if (observer) {
                            try { observer.disconnect(); } catch(e) {}
                            observer = null;
                        }
                        resolve(res);
                    }

                    maxTimer = setTimeout(function() {
                        done({ success: false, reason: 'timeout', message: 'Exceeded max wait of ' + maxWait + 'ms (' + mutationCount + ' mutations observed)', mutations: mutationCount });
                    }, maxWait);

                    try {
                        observer = new MutationObserver(function(mutations) {
                            var added = (mutations ? mutations.length : 1);
                            recordMutation(added);
                        });
                        var targetNode = document;
                        observer.observe(targetNode, {
                            childList: true,
                            subtree: true,
                            attributes: true,
                            characterData: true
                        });
                    } catch(e) {}

                    intervalTimer = setInterval(function() {
                        if (resolved) return;
                        if (observer) {
                            try {
                                var records = observer.takeRecords();
                                if (records && records.length > 0) {
                                    recordMutation(records.length);
                                }
                            } catch(e) {}
                        }
                        var now = performance.now();
                        var isReady = (document.readyState === 'complete' || document.readyState === 'interactive');

                        // Dynamic cadence detection: if recurring periodic mutations occur (e.g. 50ms churn with timer jitter),
                        // require silence that strictly exceeds the observed interval cadence to avoid false-settling mid-churn.
                        var requiredQuiet = quiet;
                        if (recentMutationTimes.length >= 2) {
                            var intervals = [];
                            for (var k = 1; k < recentMutationTimes.length; k++) {
                                var diff = recentMutationTimes[k] - recentMutationTimes[k - 1];
                                if (diff > 10 && diff <= 800) {
                                    intervals.push(diff);
                                }
                            }
                            if (intervals.length >= 1) {
                                var sum = 0;
                                var maxInt = 0;
                                for (var m = 0; m < intervals.length; m++) {
                                    sum += intervals[m];
                                    if (intervals[m] > maxInt) maxInt = intervals[m];
                                }
                                var avgInt = sum / intervals.length;
                                var dynamicFloor = Math.max(Math.round(avgInt * 2.5), Math.round(maxInt * 1.8));
                                if (dynamicFloor > requiredQuiet) {
                                    requiredQuiet = dynamicFloor;
                                }
                            }
                        }

                        if (isReady && (now - lastMutationTime) >= requiredQuiet) {
                            done({ success: true, message: 'DOM stabilized for ' + quiet + 'ms (' + mutationCount + ' mutations observed)', mutations: mutationCount });
                        }
                    }, 25);
                });
            },

            // 6. Playwright-Grade Auto-Waiting & Action Settlement
            performActionAsync: async function(actionObj) {
                var self = this;
                var action = (actionObj.action || actionObj.type || '').trim().toLowerCase();
                var targetId = actionObj.target || actionObj.elementId || actionObj.selector;
                var timeout = actionObj.timeout || actionObj.timeoutMs || 800;

                // Pre-action readiness auto-wait: wait for element to exist, attach to DOM, and become enabled
                if (targetId && action !== 'scroll' && action !== 'press') {
                    var start = performance.now();
                    while (performance.now() - start < timeout) {
                        var el = null;
                        if (self.elements && self.elements[targetId] && self.isNodeConnected(self.elements[targetId])) {
                            el = self.elements[targetId];
                        } else {
                            el = self.findInTree(document, targetId);
                        }
                        if (el) {
                            var isInteractive = !el.disabled;
                            if (isInteractive) break;
                        }
                        await new Promise(function(r) { setTimeout(r, 25); });
                    }
                }

                // Dispatch action via full synthetic pipeline
                var res = self.performAction(actionObj);

                // Post-action settlement: observe DOM mutation quiescence (50ms quiet window, max 250ms)
                if (res && res.success && actionObj.settle !== false) {
                    try {
                        await self.waitForStability(50, 250);
                    } catch(e) {}
                }

                return res;
            },

            // Computes compact DOM mutation diff between sequential actions
            getDiff: function(options) {
                options = options || {};
                var snap = this.getSemanticTree({
                    limit: -1,
                    viewportOnly: options.viewportOnly || false,
                    includeText: true
                });
                var currentElements = (snap && snap.elements) ? snap.elements : [];
                var currentMap = {};
                for (var i = 0; i < currentElements.length; i++) {
                    var el = currentElements[i];
                    if (el && el.id) {
                        currentMap[el.id] = {
                            id: el.id,
                            tag: el.tag,
                            role: el.role,
                            text: (el.text || '').trim(),
                            value: (el.value || '').trim(),
                            type: el.type,
                            disabled: Boolean(el.disabled),
                            checked: Boolean(el.checked),
                            selected: Boolean(el.selected),
                            domId: el.domId,
                            href: el.href,
                            bounds: el.bounds
                        };
                    }
                }

                var prevMap = this._lastSnapshotMap;
                var hasBaseline = Boolean(prevMap);
                var added = [];
                var removed = [];
                var changed = [];

                if (prevMap) {
                    for (var curId in currentMap) {
                        var cur = currentMap[curId];
                        var prev = prevMap[curId];
                        if (!prev) {
                            added.push(cur);
                        } else {
                            var textDiff = cur.text !== prev.text;
                            var valDiff = cur.value !== prev.value;
                            var stateDiff = cur.disabled !== prev.disabled || cur.checked !== prev.checked || cur.selected !== prev.selected;
                            if (textDiff || valDiff || stateDiff) {
                                changed.push({
                                    id: cur.id,
                                    tag: cur.tag,
                                    role: cur.role,
                                    domId: cur.domId,
                                    current: cur,
                                    previous: prev,
                                    changes: {
                                        text: textDiff ? { from: prev.text, to: cur.text } : null,
                                        value: valDiff ? { from: prev.value, to: cur.value } : null,
                                        disabled: cur.disabled !== prev.disabled ? cur.disabled : null,
                                        checked: cur.checked !== prev.checked ? cur.checked : null,
                                        selected: cur.selected !== prev.selected ? cur.selected : null
                                    }
                                });
                            }
                        }
                    }
                    for (var oldId in prevMap) {
                        if (!currentMap[oldId]) {
                            removed.push(prevMap[oldId]);
                        }
                    }
                } else {
                    added = currentElements.slice(0, Math.min(25, currentElements.length));
                }

                this._lastSnapshotMap = currentMap;

                var lines = [];
                var displayUrl = window.location.href;
                if (displayUrl.length > 80) displayUrl = displayUrl.substring(0, 77) + '...';

                lines.push('=== Nomad DOM Mutation Diff ===');
                lines.push('URL: ' + displayUrl);

                var totalMutations = added.length + removed.length + changed.length;
                if (!hasBaseline) {
                    lines.push('Status: Baseline established (' + currentElements.length + ' elements total) | Next call returns diffs');
                    for (var b = 0; b < added.length; b++) {
                        var bItem = added[b];
                        lines.push('[*] [' + bItem.id + '] <' + bItem.tag + (bItem.role ? ' role="' + bItem.role + '"' : '') + (bItem.text ? ' "' + bItem.text.substring(0, 50) + '"' : '') + '>');
                    }
                } else if (totalMutations === 0) {
                    lines.push('Changes: 0 mutations (DOM stable)');
                } else {
                    lines.push('Changes: +' + added.length + ' added, -' + removed.length + ' removed, ~' + changed.length + ' changed:');
                    for (var a = 0; a < added.length; a++) {
                        var aItem = added[a];
                        var aText = aItem.text ? ' "' + aItem.text.substring(0, 60) + '"' : (aItem.value ? ' value="' + aItem.value.substring(0, 40) + '"' : '');
                        lines.push('[+] [' + aItem.id + '] <' + aItem.tag + (aItem.role ? ' role="' + aItem.role + '"' : '') + aText + '>');
                    }
                    for (var r = 0; r < removed.length; r++) {
                        var rItem = removed[r];
                        var rText = rItem.text ? ' "' + rItem.text.substring(0, 40) + '"' : '';
                        lines.push('[-] [' + rItem.id + '] <' + rItem.tag + rText + '>');
                    }
                    for (var c = 0; c < changed.length; c++) {
                        var cItem = changed[c];
                        var details = [];
                        if (cItem.changes.text) details.push('text: "' + cItem.changes.text.from.substring(0, 30) + '" -> "' + cItem.changes.text.to.substring(0, 30) + '"');
                        if (cItem.changes.value) details.push('value: "' + cItem.changes.value.from.substring(0, 20) + '" -> "' + cItem.changes.value.to.substring(0, 20) + '"');
                        if (cItem.changes.disabled !== null) details.push(cItem.changes.disabled ? 'disabled' : 'enabled');
                        if (cItem.changes.checked !== null) details.push(cItem.changes.checked ? 'checked' : 'unchecked');
                        lines.push('[~] [' + cItem.id + '] <' + cItem.tag + '> (' + details.join(', ') + ')');
                    }
                }

                var diffText = lines.join('\n');
                var tokens = Math.max(1, Math.ceil(diffText.length / 4.0));

                return {
                    success: true,
                    hasBaseline: hasBaseline,
                    totalMutations: totalMutations,
                    addedCount: added.length,
                    removedCount: removed.length,
                    changedCount: changed.length,
                    added: added,
                    removed: removed,
                    changed: changed,
                    summary: diffText,
                    tokenEstimate: tokens,
                    url: window.location.href,
                    title: document.title || ''
                };
            },

            // Natural language semantic element locator with heuristic scoring
            findSemantic: function(query, options) {
                if (!query || typeof query !== 'string' || !query.trim()) {
                    return { success: false, code: "MISSING_QUERY", message: "Query string is required" };
                }
                options = options || {};
                var rawQuery = query.trim().toLowerCase();
                var queryTokens = rawQuery.split(/[\s_\-\/\.,]+/).filter(function(t) { return t.length > 1; });

                var roleHints = {
                    'button': ['button', 'submit', 'reset'],
                    'btn': ['button', 'submit'],
                    'link': ['link', 'a'],
                    'input': ['textbox', 'searchbox', 'input'],
                    'text': ['textbox', 'searchbox'],
                    'search': ['searchbox', 'textbox'],
                    'checkbox': ['checkbox'],
                    'check': ['checkbox'],
                    'radio': ['radio'],
                    'select': ['combobox', 'select', 'listbox'],
                    'dropdown': ['combobox', 'select', 'menu'],
                    'tab': ['tab'],
                    'heading': ['heading', 'h1', 'h2', 'h3'],
                    'image': ['img', 'image'],
                    'img': ['img', 'image']
                };

                var expectedRoles = [];
                for (var q = 0; q < queryTokens.length; q++) {
                    var token = queryTokens[q];
                    if (roleHints[token]) {
                        expectedRoles = expectedRoles.concat(roleHints[token]);
                    }
                }

                var snap = this.getSemanticTree({
                    limit: -1,
                    viewportOnly: options.viewportOnly || false,
                    includeText: true
                });
                var elements = (snap && snap.elements) ? snap.elements : [];
                var candidates = [];

                for (var i = 0; i < elements.length; i++) {
                    var el = elements[i];
                    if (options.viewportOnly && !el.inViewport) continue;
                    if (options.role && (el.role || '').toLowerCase() !== options.role.toLowerCase()) continue;

                    var score = 0;
                    var textStr = ((el.text || '') + ' ' + (el.value || '')).toLowerCase();
                    var ariaStr = '';
                    var domNode = this.elements && this.elements[el.id];
                    if (domNode) {
                        ariaStr = ((domNode.getAttribute('aria-label') || '') + ' ' +
                                   (domNode.getAttribute('title') || '') + ' ' +
                                   (domNode.getAttribute('placeholder') || '') + ' ' +
                                   (domNode.id || '') + ' ' +
                                   (domNode.className || '')).toLowerCase();
                    }

                    var elRole = (el.role || el.tag || '').toLowerCase();

                    // 1. Exact full query match in text or aria
                    if (textStr === rawQuery) {
                        score += 0.85;
                    } else if (textStr.indexOf(rawQuery) !== -1) {
                        score += 0.65;
                    } else if (ariaStr.indexOf(rawQuery) !== -1) {
                        score += 0.55;
                    }

                    // 2. Token overlap score
                    var matchedTokens = 0;
                    for (var t = 0; t < queryTokens.length; t++) {
                        var tk = queryTokens[t];
                        if (textStr.indexOf(tk) !== -1) {
                            matchedTokens++;
                            score += 0.20;
                        } else if (ariaStr.indexOf(tk) !== -1) {
                            matchedTokens++;
                            score += 0.15;
                        }
                    }

                    // 3. Expected role bonus
                    if (expectedRoles.length > 0) {
                        for (var er = 0; er < expectedRoles.length; er++) {
                            if (elRole === expectedRoles[er] || (el.tag && el.tag.toLowerCase() === expectedRoles[er])) {
                                score += 0.25;
                                break;
                            }
                        }
                    }

                    // 4. Viewport visibility bonus
                    if (el.inViewport) score += 0.10;
                    if (!el.isObscured) score += 0.05;

                    var finalScore = Math.min(1.0, Math.round(score * 100) / 100);

                    if (finalScore >= 0.30 || matchedTokens > 0) {
                        candidates.push({
                            id: el.id,
                            tag: el.tag,
                            role: el.role,
                            text: el.text || el.value || '',
                            domId: el.domId,
                            score: finalScore,
                            inViewport: el.inViewport,
                            bounds: el.bounds
                        });
                    }
                }

                candidates.sort(function(a, b) { return b.score - a.score; });

                if (candidates.length === 0) {
                    return { success: false, code: "SEMANTIC_MATCH_NOT_FOUND", message: "No element matching semantic query '" + query + "'" };
                }

                var bestMatch = candidates[0];
                var alternatives = candidates.slice(1, 4);

                return {
                    success: true,
                    query: query,
                    bestMatch: bestMatch,
                    matchCount: candidates.length,
                    alternatives: alternatives
                };
            },

            // Resolves bounding rectangle for Set-of-Marks (SoM) dynamic container cropping
            getSomContainerRect: function(elementId) {
                var container = null;
                var el = null;

                if (elementId) {
                    if (this.elements && this.elements[elementId]) {
                        el = this.elements[elementId];
                    } else {
                        el = this.findInTree(document, elementId);
                    }
                }

                if (el) {
                    container = el.closest('dialog, [role="dialog"], [aria-modal="true"], form, [class*="modal"], [class*="popup"], [class*="overlay"], [class*="card"], [class*="panel"], main, article');
                    if (!container) container = el.parentElement;
                } else {
                    // 1. Active Modals & Dialogs
                    container = document.querySelector('dialog[open], [role="dialog"], [aria-modal="true"], .modal.show, .modal.active, .modal.open, .popup.show, .popup.active');
                    // 2. Focused element container
                    if (!container && document.activeElement && document.activeElement !== document.body) {
                        container = document.activeElement.closest('form, dialog, [role="dialog"], [class*="modal"], [class*="card"], [class*="panel"]');
                    }
                    // 3. Primary visible form / search box
                    if (!container) {
                        var forms = document.querySelectorAll('form:not([hidden]), [role="form"]:not([hidden]), [role="search"]:not([hidden])');
                        for (var fi = 0; fi < forms.length; fi++) {
                            var fr = forms[fi].getBoundingClientRect();
                            if (fr.width >= 160 && fr.height >= 32 && fr.top < window.innerHeight && fr.bottom > 0) {
                                container = forms[fi];
                                break;
                            }
                        }
                    }
                    // 4. Bounded content card or region
                    if (!container) {
                        var mainCards = document.querySelectorAll('.card:not([hidden]), article:not([hidden]), [role="region"]:not([hidden]), [class*="content-wrapper"]:not([hidden])');
                        for (var ci = 0; ci < mainCards.length; ci++) {
                            var cr = mainCards[ci].getBoundingClientRect();
                            if (cr.width >= 240 && cr.height >= 120 && cr.width <= window.innerWidth * 0.95 && cr.top < window.innerHeight && cr.bottom > 0) {
                                container = mainCards[ci];
                                break;
                            }
                        }
                    }
                }

                if (container) {
                    var r = container.getBoundingClientRect();
                    if (r && r.width > 30 && r.height > 30) {
                        var pad = 16;
                        var left = Math.max(0, r.left - pad);
                        var top = Math.max(0, r.top - pad);
                        var right = Math.min(window.innerWidth, r.right + pad);
                        var bottom = Math.min(window.innerHeight, r.bottom + pad);
                        return {
                            x: Math.round(left),
                            y: Math.round(top),
                            width: Math.round(right - left),
                            height: Math.round(bottom - top),
                            containerTag: container.tagName ? container.tagName.toLowerCase() : 'container',
                            isModal: Boolean(container.matches && container.matches('dialog, [role="dialog"], [aria-modal="true"], [class*="modal"]'))
                        };
                    }
                }

                if (el) {
                    var er = el.getBoundingClientRect();
                    if (er && er.width > 0 && er.height > 0) {
                        var epad = 40;
                        var eleft = Math.max(0, er.left - epad);
                        var etop = Math.max(0, er.top - epad);
                        var eright = Math.min(window.innerWidth, er.right + epad);
                        var ebottom = Math.min(window.innerHeight, er.bottom + epad);
                        return {
                            x: Math.round(eleft),
                            y: Math.round(etop),
                            width: Math.round(eright - eleft),
                            height: Math.round(ebottom - etop),
                            containerTag: el.tagName ? el.tagName.toLowerCase() : 'element',
                            isModal: false
                        };
                    }
                }

                return null;
            },

            // Anti-bot gate and 2FA challenge detection for minimal Human-in-the-Loop
            detectChallenge: function() {
                // 1. Cloudflare Turnstile / Under Attack
                var cfIframe = document.querySelector('iframe[src*="challenges.cloudflare.com"], iframe[src*="cloudflare.com/cdn-cgi/challenge"]');
                var cfInput = document.querySelector('input[name="cf-turnstile-response"]');
                var cfForm = document.querySelector('#challenge-form, #cf-challenge-running, .cf-turnstile');
                if (cfIframe || (cfInput && !cfInput.value) || cfForm) {
                    var resolved = Boolean(cfInput && cfInput.value && cfInput.value.length > 5);
                    return {
                        detected: true,
                        type: 'Cloudflare Turnstile',
                        resolved: resolved,
                        selector: 'iframe[src*="challenges.cloudflare.com"]'
                    };
                }

                // 2. Google reCAPTCHA
                var rcIframe = document.querySelector('iframe[src*="recaptcha"]');
                var rcResp = document.querySelector('textarea[name="g-recaptcha-response"], input[name="g-recaptcha-response"]');
                if (rcIframe || rcResp) {
                    var rcResolved = Boolean(rcResp && rcResp.value && rcResp.value.trim().length > 5);
                    if (!rcResolved && typeof window.grecaptcha !== 'undefined' && window.grecaptcha.getResponse) {
                        try { rcResolved = Boolean(window.grecaptcha.getResponse().length > 0); } catch(e) {}
                    }
                    return {
                        detected: true,
                        type: 'Google reCAPTCHA',
                        resolved: rcResolved,
                        selector: 'iframe[src*="recaptcha"]'
                    };
                }

                // 3. hCaptcha
                var hIframe = document.querySelector('iframe[src*="hcaptcha.com"]');
                var hResp = document.querySelector('textarea[name="h-captcha-response"], input[name="h-captcha-response"]');
                if (hIframe || hResp) {
                    var hResolved = Boolean(hResp && hResp.value && hResp.value.trim().length > 5);
                    return {
                        detected: true,
                        type: 'hCaptcha',
                        resolved: hResolved,
                        selector: 'iframe[src*="hcaptcha.com"]'
                    };
                }

                // 4. Arkose Labs / FunCaptcha
                var arkIframe = document.querySelector('iframe[src*="arkoselabs"], iframe[src*="funcaptcha"]');
                if (arkIframe) {
                    return {
                        detected: true,
                        type: 'Arkose Challenge',
                        resolved: false,
                        selector: 'iframe[src*="arkoselabs"]'
                    };
                }

                // 5. 2FA / One-Time Passcode Gate
                var otpInput = document.querySelector('input[autocomplete="one-time-code"], input[name*="otp" i], input[name*="2fa" i], input[id*="otp" i], input[id*="2fa" i]');
                if (otpInput && !otpInput.disabled && !otpInput.readOnly) {
                    var otpFilled = Boolean(otpInput.value && otpInput.value.length >= 4);
                    return {
                        detected: true,
                        type: 'Two-Factor Authentication (2FA)',
                        resolved: otpFilled,
                        selector: 'input[autocomplete="one-time-code"]'
                    };
                }

                return { detected: false, type: null, resolved: true };
            }
        };

        if (typeof window !== 'undefined') {
            window.nomad = window.__nomad;
        }
    })();

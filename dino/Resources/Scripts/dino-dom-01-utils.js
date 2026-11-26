    (function() {
        if (window.__dino || window.__dino) return;

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

        // Computes a deterministic, persistent CSS selector for an element
        function getCssSelector(el) {
            if (!el || el.nodeType !== 1) return null;
            if (el.id) {
                return '#' + (typeof CSS !== 'undefined' && CSS.escape ? CSS.escape(el.id) : el.id);
            }
            var testId = el.getAttribute('data-testid') || el.getAttribute('data-test');
            if (testId) {
                var attr = el.hasAttribute('data-testid') ? 'data-testid' : 'data-test';
                return '[' + attr + '="' + (typeof CSS !== 'undefined' && CSS.escape ? CSS.escape(testId) : testId) + '"]';
            }
            var name = el.getAttribute('name');
            if (name) {
                return el.tagName.toLowerCase() + '[name="' + (typeof CSS !== 'undefined' && CSS.escape ? CSS.escape(name) : name) + '"]';
            }
            var ariaLabel = el.getAttribute('aria-label');
            if (ariaLabel) {
                return el.tagName.toLowerCase() + '[aria-label="' + (typeof CSS !== 'undefined' && CSS.escape ? CSS.escape(ariaLabel) : ariaLabel) + '"]';
            }
            var path = [];
            var curr = el;
            while (curr && curr.nodeType === 1 && curr !== document.body && curr !== document.documentElement) {
                var tag = curr.tagName.toLowerCase();
                if (curr.id) {
                    path.unshift('#' + (typeof CSS !== 'undefined' && CSS.escape ? CSS.escape(curr.id) : curr.id));
                    break;
                }
                var parent = curr.parentElement;
                if (parent) {
                    var siblings = parent.children;
                    var sameTag = 0;
                    var index = 1;
                    for (var i = 0; i < siblings.length; i++) {
                        if (siblings[i] === curr) { index = sameTag + 1; break; }
                        if (siblings[i].tagName === curr.tagName) sameTag++;
                    }
                    path.unshift(tag + (sameTag > 0 || siblings.length > 1 ? ':nth-of-type(' + index + ')' : ''));
                } else {
                    path.unshift(tag);
                }
                curr = parent;
                if (path.length >= 4) break;
            }
            return path.join(' > ');
        }

        // Dispatches full HTML5 Drag and Drop event sequence with DataTransfer
        function dispatchHtml5Drag(targetId, fromX, fromY, toX, toY, optEl, optDest) {
            var dino = (typeof window !== 'undefined' && window.__dino) ? window.__dino : (this || {});
            var el = optEl || null;
            if (!el && targetId) {
                el = (dino.elements && dino.elements[targetId] && dino.isNodeConnected && dino.isNodeConnected(dino.elements[targetId]) ? dino.elements[targetId] : null) || (dino.findInTree ? dino.findInTree(document, targetId) : document.getElementById(targetId));
            }
            if (!el && fromX !== undefined && fromY !== undefined) {
                el = document.elementFromPoint(fromX, fromY);
            }
            if (!el) return { success: false, code: 'MISSING_TARGET', message: 'No source element for drag action', elementId: targetId };

            var destEl = null;
            if (optDest && typeof optDest === 'object' && optDest.dispatchEvent) {
                destEl = optDest;
            } else if (typeof optDest === 'string' && optDest) {
                destEl = (dino.elements && dino.elements[optDest] && dino.isNodeConnected && dino.isNodeConnected(dino.elements[optDest]) ? dino.elements[optDest] : null) || (dino.findInTree ? dino.findInTree(document, optDest) : null) || document.querySelector('[data-dino-id="' + optDest + '"]') || document.querySelector(optDest);
            }

            var destX = (toX !== undefined && toX !== null) ? Number(toX) : null;
            var destY = (toY !== undefined && toY !== null) ? Number(toY) : null;

            if ((destX === null || destY === null) && destEl) {
                var dRect = destEl.getBoundingClientRect ? destEl.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                destX = Math.round(dRect.left + dRect.width / 2);
                destY = Math.round(dRect.top + dRect.height / 2);
            } else if ((destX === null || destY === null) && typeof optDest === 'string' && optDest) {
                var vRect = dino.getElementViewportRect ? dino.getElementViewportRect(optDest) : null;
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

        if (!window.__dino_frames) window.__dino_frames = {};
        if (!window.__dino_frame_listener_attached) {
            window.__dino_frame_listener_attached = true;
            window.addEventListener('message', function(e) {
                if (!e.data || typeof e.data !== 'object') return;
                if (e.data.type === '__dino_frame_report') {
                    var iframes = document.querySelectorAll('iframe');
                    var matchedId = e.data.frameId || null;
                    if (!matchedId) {
                        for (var i = 0; i < iframes.length; i++) {
                            try {
                                if (iframes[i].contentWindow === e.source) {
                                    matchedId = iframes[i].getAttribute('data-dino-frame') || ('f' + (i + 1));
                                    iframes[i].setAttribute('data-dino-frame', matchedId);
                                    break;
                                }
                            } catch(err) {}
                        }
                    }
                    if (!matchedId && iframes.length === 1) {
                        matchedId = iframes[0].getAttribute('data-dino-frame') || 'f1';
                        iframes[0].setAttribute('data-dino-frame', matchedId);
                    }
                    if (!matchedId && e.data.url) {
                        for (var j = 0; j < iframes.length; j++) {
                            var src = iframes[j].getAttribute('src') || '';
                            if (src && (e.data.url.indexOf(src) !== -1 || src.indexOf(e.data.url) !== -1)) {
                                matchedId = iframes[j].getAttribute('data-dino-frame') || ('f' + (j + 1));
                                iframes[j].setAttribute('data-dino-frame', matchedId);
                                break;
                            }
                        }
                    }
                    if (matchedId) {
                        window.__dino_frames[matchedId] = {
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


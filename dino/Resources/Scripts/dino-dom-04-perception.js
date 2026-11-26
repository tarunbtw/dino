            // 4. Overlays indexed visual badges [e1], [e2] and obscures sensitive values for Vision Model Screenshots
            showBadges: function(filterRect) {
                this.hideBadges();
                this.blurSensitiveInputs();

                var container = document.createElement('div');
                container.id = '__dino_badges_layer';
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
                var layers = document.querySelectorAll('#__dino_badges_layer');
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

                lines.push('=== Dino DOM Mutation Diff ===');
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
                if (!el && this.lastInteractedElement && this.isNodeConnected(this.lastInteractedElement)) {
                    el = this.lastInteractedElement;
                }
                if (!el && document.activeElement && document.activeElement !== document.body && document.activeElement !== document.documentElement) {
                    el = document.activeElement;
                }

                if (el) {
                    container = el.closest('dialog, [role="dialog"], [aria-modal="true"], form, [class*="modal"], [class*="popup"], [class*="overlay"], [class*="card"], [class*="panel"], [role="region"], table, tr, li, article, section');
                    if (container) {
                        var cr = container.getBoundingClientRect();
                        // Reject full-page wrappers: if container spans >85% width AND >80% height, fall back to localized element
                        if (cr.width > window.innerWidth * 0.85 && cr.height > window.innerHeight * 0.8) {
                            container = null;
                        }
                    }
                    if (!container) container = (el.parentElement && el.parentElement !== document.body && el.parentElement !== document.documentElement) ? el.parentElement : el;
                } else {
                    // 1. Active Modals, Dialogs, Popovers & Menus
                    container = document.querySelector('dialog[open], [role="dialog"], [aria-modal="true"], .modal.show, .modal.active, .modal.open, .popup.show, .popup.active, [role="menu"][aria-hidden="false"]');
                    // 2. Focused element container
                    if (!container && document.activeElement && document.activeElement !== document.body) {
                        var foc = document.activeElement.closest('form, dialog, [role="dialog"], [class*="modal"], [class*="card"], [class*="panel"], table, tr, li');
                        if (foc) {
                            var focr = foc.getBoundingClientRect();
                            if (focr.width <= window.innerWidth * 0.85 || focr.height <= window.innerHeight * 0.8) {
                                container = foc;
                            }
                        }
                    }
                    // 3. Primary visible form / search box
                    if (!container) {
                        var forms = document.querySelectorAll('form:not([hidden]), [role="form"]:not([hidden]), [role="search"]:not([hidden])');
                        for (var fi = 0; fi < forms.length; fi++) {
                            var fr = forms[fi].getBoundingClientRect();
                            if (fr.width >= 160 && fr.height >= 32 && fr.width <= window.innerWidth * 0.85 && fr.top < window.innerHeight && fr.bottom > 0) {
                                container = forms[fi];
                                break;
                            }
                        }
                    }
                    // 4. Bounded content card, article, or list item
                    if (!container) {
                        var mainCards = document.querySelectorAll('.card:not([hidden]), article:not([hidden]), [role="region"]:not([hidden]), [class*="content-wrapper"]:not([hidden]), tr.athing, [class*="item"]:not([hidden])');
                        for (var ci = 0; ci < mainCards.length; ci++) {
                            var mcr = mainCards[ci].getBoundingClientRect();
                            if (mcr.width >= 160 && mcr.height >= 24 && (mcr.width <= window.innerWidth * 0.85 || mcr.height <= window.innerHeight * 0.8) && mcr.top < window.innerHeight && mcr.bottom > 0) {
                                container = mainCards[ci];
                                break;
                            }
                        }
                    }
                }

                if (container) {
                    var r = container.getBoundingClientRect();
                    if (r && r.width > 20 && r.height > 20) {
                        var pad = 16;
                        var left = Math.max(0, r.left - pad);
                        var top = Math.max(0, r.top - pad);
                        var right = Math.min(window.innerWidth, r.right + pad);
                        var bottom = Math.min(window.innerHeight, r.bottom + pad);
                        var rw = Math.round(right - left);
                        var rh = Math.round(bottom - top);
                        if (rw > 0 && rh > 0) {
                            return {
                                x: Math.round(left),
                                y: Math.round(top),
                                width: rw,
                                height: rh,
                                containerTag: container.tagName ? container.tagName.toLowerCase() : 'container',
                                isModal: Boolean(container.matches && container.matches('dialog, [role="dialog"], [aria-modal="true"], [class*="modal"]'))
                            };
                        }
                    }
                }

                if (el) {
                    var er = el.getBoundingClientRect();
                    if (er && er.width > 0 && er.height > 0) {
                        var epad = 24;
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

                // 5. Viewport fallback: bounding box of visible interactive elements
                if (this.elementsBounds) {
                    var minX = window.innerWidth, minY = window.innerHeight, maxX = 0, maxY = 0, count = 0;
                    for (var bId in this.elementsBounds) {
                        var b = this.elementsBounds[bId];
                        if (b && b.width > 0 && b.height > 0) {
                            if (b.right > 0 && b.left < window.innerWidth && b.bottom > 0 && b.top < window.innerHeight) {
                                if (b.left < minX) minX = Math.max(0, b.left);
                                if (b.top < minY) minY = Math.max(0, b.top);
                                if (b.right > maxX) maxX = Math.min(window.innerWidth, b.right);
                                if (b.bottom > maxY) maxY = Math.min(window.innerHeight, b.bottom);
                                count++;
                            }
                        }
                    }
                    if (count > 0 && maxX > minX && maxY > minY) {
                        var vpad = 16;
                        var vLeft = Math.max(0, Math.round(minX - vpad));
                        var vTop = Math.max(0, Math.round(minY - vpad));
                        var vRight = Math.min(window.innerWidth, Math.round(maxX + vpad));
                        var vBottom = Math.min(window.innerHeight, Math.round(maxY + vpad));
                        var vWidth = Math.round(vRight - vLeft);
                        var vHeight = Math.round(vBottom - vTop);
                        // If interactive elements span full viewport height, focus on the top hero / cluster
                        if (vHeight > window.innerHeight * 0.8) {
                            vHeight = Math.min(window.innerHeight, Math.max(300, Math.round(window.innerHeight * 0.5)));
                        }
                        return {
                            x: vLeft,
                            y: vTop,
                            width: vWidth,
                            height: vHeight,
                            containerTag: 'viewport-content',
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
            },

            extract: function(selector, mode) {
                mode = (mode || 'auto').toLowerCase();

                // 1. JSON-LD Mode
                if (mode === 'jsonld' || (mode === 'auto' && (!selector || selector === 'ld+json' || selector === 'jsonld'))) {
                    var scripts = document.querySelectorAll('script[type="application/ld+json"]');
                    var ldList = [];
                    for (var i = 0; i < scripts.length; i++) {
                        try {
                            var parsed = JSON.parse(scripts[i].textContent || '{}');
                            ldList.push(parsed);
                        } catch(e) {}
                    }
                    if (ldList.length > 0 || mode === 'jsonld') {
                        return { success: true, mode: 'jsonld', count: ldList.length, data: ldList };
                    }
                }

                // 2. Table Mode
                var targetTable = null;
                if (selector && selector.trim().toLowerCase() !== 'table') {
                    try {
                        var selEl = document.querySelector(selector);
                        if (selEl) {
                            if (selEl.tagName === 'TABLE') {
                                targetTable = selEl;
                            } else {
                                targetTable = selEl.querySelector('table');
                            }
                        }
                    } catch(e) {}
                }
                function pickBestDataTable() {
                    var tables = document.querySelectorAll('table');
                    var best = null, bestScore = -1;
                    for (var i = 0; i < tables.length; i++) {
                        var t = tables[i];
                        var rect = t.getBoundingClientRect();
                        if (rect.width === 0 || rect.height === 0) continue;
                        var rowCount = t.rows ? t.rows.length : 0;
                        if (rowCount === 0) continue;
                        var cellCount = 0;
                        var hasHeaders = Boolean(t.tHead);
                        for (var r = 0; r < rowCount; r++) {
                            var row = t.rows[r];
                            cellCount += row.cells ? row.cells.length : 0;
                            if (!hasHeaders && row.querySelector('th')) hasHeaders = true;
                        }
                        if (cellCount === 0) continue;
                        var score = rowCount * cellCount * (hasHeaders ? 3 : 1);
                        if (rowCount < 2) score = Math.floor(score * 0.2);
                        if (score > bestScore) { bestScore = score; best = t; }
                    }
                    return best || tables[0] || null;
                }

                var isGenericTable = Boolean(selector && selector.trim().toLowerCase() === 'table');
                if (!targetTable && (mode === 'table' || isGenericTable)) {
                    targetTable = pickBestDataTable();
                }

                if (targetTable || (mode === 'auto' && !selector && document.querySelector('table'))) {
                    if (!targetTable) targetTable = pickBestDataTable();
                    if (targetTable) {
                        var headers = [];
                        var ths = targetTable.querySelectorAll('thead th, tr:first-child th, tr:first-child td');
                        for (var h = 0; h < ths.length; h++) {
                            var hText = (ths[h].innerText || ths[h].textContent || '').trim();
                            headers.push(hText || ('col_' + (h + 1)));
                        }
                        var rows = [];
                        var trs = targetTable.querySelectorAll('tbody tr, tr');
                        for (var r = 0; r < trs.length; r++) {
                            var tr = trs[r];
                            if (tr.querySelector('th') && r === 0) continue;
                            var cells = tr.querySelectorAll('td');
                            if (cells.length === 0) continue;
                            var rowObj = {};
                            for (var c = 0; c < cells.length; c++) {
                                var key = headers[c] || ('col_' + (c + 1));
                                var val = (cells[c].innerText || cells[c].textContent || '').trim();
                                var link = cells[c].querySelector('a');
                                if (link && link.href) {
                                    rowObj[key] = val;
                                    rowObj[key + '_url'] = link.href;
                                } else {
                                    rowObj[key] = val;
                                }
                            }
                            rows.push(rowObj);
                        }
                        return { success: true, mode: 'table', count: rows.length, data: rows };
                    }
                }

                // 3. Repeated card / list records extraction
                var targetSelector = selector || 'article, [role="article"], .item, .card, li';
                var matched = [];
                try {
                    matched = document.querySelectorAll(targetSelector);
                } catch(e) {}

                if (matched.length > 0) {
                    var records = [];
                    for (var m = 0; m < matched.length; m++) {
                        var item = matched[m];
                        var itemText = (item.innerText || item.textContent || '').trim();
                        if (!itemText && !item.querySelector('img, a')) continue;

                        var record = {
                            text: itemText.split('\n').map(function(s) { return s.trim(); }).filter(Boolean).slice(0, 5).join(' ')
                        };
                        var a = item.tagName === 'A' ? item : item.querySelector('a');
                        if (a && a.href) {
                            record.url = a.href;
                            var title = (a.innerText || a.getAttribute('title') || '').trim();
                            if (title) record.title = title;
                        }
                        var img = item.tagName === 'IMG' ? item : item.querySelector('img');
                        if (img && img.src) {
                            record.image = img.src;
                        }
                        records.push(record);
                    }
                    return { success: true, mode: 'records', count: records.length, data: records };
                }

                return { success: false, code: 'NO_DATA_EXTRACTED', message: 'No extractable data found with selector: ' + (selector || 'auto') };
            }
        };

        window.__dino = coreEngine;
        window.__dino = coreEngine;

        if (typeof window !== 'undefined') {
            window.dino = coreEngine;
            window.dino = coreEngine;
        }
    })();

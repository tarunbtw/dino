            // 2. Dispatches synthetic and realistic user actions
            performAction: function(actionObj) {
                try {
                    var dino = this || (typeof window !== 'undefined' ? (window.__dino || window.dino) : {});
                    var action = (actionObj.action || actionObj.type || '').trim().toLowerCase();
                    var targetId = actionObj.target || actionObj.elementId || actionObj.selector;
                    var el = null;
                    var wasHealed = false;

                    if (!action) {
                        return { success: false, code: 'INVALID_ACTION', message: "Missing required 'type' or 'action' field" };
                    }

                    if (targetId) {
                        if (typeof targetId === 'string') {
                            if (/^\[(f[0-9]+:)?[e][0-9]+\]$/i.test(targetId.trim())) {
                                targetId = targetId.trim().slice(1, -1);
                            }
                        }
                        var rawId = (typeof targetId === 'string' && targetId.indexOf('#') === 0) ? targetId.substring(1) : targetId;
                        if (this.elements && this.elements[targetId] && this.isNodeConnected(this.elements[targetId])) {
                            el = this.elements[targetId];
                        } else if (this.elements && this.elements[rawId] && this.isNodeConnected(this.elements[rawId])) {
                            el = this.elements[rawId];
                        } else {
                            el = this.findInTree(document, targetId);
                            if (!el) {
                                try { el = document.querySelector(targetId); } catch(e) {}
                            }
                            if (el && this.elements) this.elements[targetId] = el;
                        }

                        // Validate compatibility with the requested action
                        var sig = (this.elementSignatures && this.elementSignatures[targetId]) || null;
                        var isIncompatible = false;
                        if (el) {
                            var elTag = el.tagName ? el.tagName.toLowerCase() : '';
                            if (action === 'type' || action === 'fill' || action === 'clear') {
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
                            try { el.setAttribute('data-dino-id', targetId); } catch(e) {}
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
                            message: "Stale element reference '" + targetId + "': target was snapshotted as " + expectedDesc + " but currently resolves to " + currentDesc + " which is incompatible with '" + action + "'. The DOM shifted or reloaded. Please call dino_snap to get fresh element refs.",
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
                    var ifr = document.querySelector('iframe[data-dino-frame="' + fId + '"]');
                    if (!ifr && fId.indexOf('f') === 0) {
                        var ifrIdx = parseInt(fId.substring(1), 10) - 1;
                        var allIfrs = document.querySelectorAll('iframe');
                        if (ifrIdx >= 0 && ifrIdx < allIfrs.length) {
                            ifr = allIfrs[ifrIdx];
                            try { ifr.setAttribute('data-dino-frame', fId); } catch(e) {}
                        }
                    }
                    if (ifr && ifr.contentWindow) {
                        try {
                            ifr.contentWindow.postMessage({
                                type: '__dino_frame_action',
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
                            if (actionObj.x !== undefined && actionObj.y !== undefined) {
                                cxC = Math.round(rectC.left + actionObj.x);
                                cyC = Math.round(rectC.top + actionObj.y);
                            }

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
                            var clickEvt = new elWin.MouseEvent('click', {
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
                            targetToClick.dispatchEvent(clickEvt);

                            var isStandardClickTarget = (targetToClick.tagName === 'BUTTON' || targetToClick.tagName === 'A' || targetToClick.tagName === 'INPUT');
                            if (isStandardClickTarget && actionObj.x === undefined && actionObj.y === undefined) {
                                try { targetToClick.click(); } catch(e) {}
                            }

                            if (this.pulseVirtualCursor) this.pulseVirtualCursor(cxC, cyC);

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
                                var hitDoc = hit.ownerDocument || document;
                                var hitWin = hitDoc.defaultView || window;
                                var pInit = { bubbles: true, cancelable: true, view: hitWin, clientX: actionObj.x, clientY: actionObj.y, screenX: actionObj.x, screenY: actionObj.y, button: 0, buttons: 1, pointerId: 1, pointerType: 'mouse', isPrimary: true };
                                hit.dispatchEvent(new hitWin.PointerEvent('pointerdown', pInit));
                                hit.dispatchEvent(new hitWin.MouseEvent('mousedown', pInit));
                                hit.dispatchEvent(new hitWin.PointerEvent('pointerup', Object.assign({}, pInit, { buttons: 0 })));
                                hit.dispatchEvent(new hitWin.MouseEvent('mouseup', Object.assign({}, pInit, { buttons: 0 })));
                                hit.dispatchEvent(new hitWin.MouseEvent('click', Object.assign({}, pInit, { buttons: 0 })));
                                if (this.pulseVirtualCursor) this.pulseVirtualCursor(actionObj.x, actionObj.y);
                                return { success: true, message: 'Clicked coordinates (' + actionObj.x + ', ' + actionObj.y + ')', centerCoordinates: { x: actionObj.x, y: actionObj.y } };
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
                            var rectD = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                            var cxD = Math.round(rectD.left + (rectD.width ? rectD.width / 2 : 0));
                            var cyD = Math.round(rectD.top + (rectD.height ? rectD.height / 2 : 0));
                            if (actionObj.x !== undefined && actionObj.y !== undefined) {
                                cxD = Math.round(rectD.left + actionObj.x);
                                cyD = Math.round(rectD.top + actionObj.y);
                            }

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
                        if (!el && actionObj.x !== undefined && actionObj.y !== undefined) {
                            el = document.elementFromPoint(actionObj.x, actionObj.y);
                        }
                        if (!el) {
                            if (actionObj.x !== undefined && actionObj.y !== undefined) {
                                if (this.updateVirtualCursor) this.updateVirtualCursor(actionObj.x, actionObj.y);
                                return {
                                    success: true,
                                    message: 'Hovered at (' + actionObj.x + ', ' + actionObj.y + ')',
                                    centerCoordinates: { x: actionObj.x, y: actionObj.y }
                                };
                            }
                            return { success: false, code: 'MISSING_TARGET', message: 'No target element or coordinates for hover action' };
                        }
                        if (el.ownerDocument && el.ownerDocument !== document && el.ownerDocument.defaultView && el.ownerDocument.defaultView.frameElement) {
                            try { el.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                        }
                        if (actionObj.x === undefined && actionObj.y === undefined) {
                            el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                        }
                        var elDocH = el.ownerDocument || document;
                        var elWinH = elDocH.defaultView || window;
                        var rH = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                        var cxH = Math.round(rH.left + (rH.width ? rH.width / 2 : 0));
                        var cyH = Math.round(rH.top + (rH.height ? rH.height / 2 : 0));
                        if (actionObj.x !== undefined && actionObj.y !== undefined) {
                            cxH = (targetId && rH && (rH.width > 0 || rH.height > 0)) ? Math.round(rH.left + actionObj.x) : Math.round(actionObj.x);
                            cyH = (targetId && rH && (rH.width > 0 || rH.height > 0)) ? Math.round(rH.top + actionObj.y) : Math.round(actionObj.y);
                        }
                        var pH = { bubbles: true, cancelable: true, view: elWinH, clientX: cxH, clientY: cyH, screenX: cxH, screenY: cyH, pointerId: 1, pointerType: 'mouse', isPrimary: true };
                        var eH = { bubbles: false, cancelable: false, view: elWinH, clientX: cxH, clientY: cyH, screenX: cxH, screenY: cyH, pointerId: 1, pointerType: 'mouse', isPrimary: true };
                        el.dispatchEvent(new elWinH.PointerEvent('pointerover', pH));
                        el.dispatchEvent(new elWinH.PointerEvent('pointerenter', eH));
                        el.dispatchEvent(new elWinH.PointerEvent('pointermove', pH));
                        el.dispatchEvent(new elWinH.MouseEvent('mouseover', pH));
                        el.dispatchEvent(new elWinH.MouseEvent('mouseenter', eH));
                        el.dispatchEvent(new elWinH.MouseEvent('mousemove', pH));

                        this.emulateHover(el, cxH, cyH);
                        if (this.updateVirtualCursor) this.updateVirtualCursor(cxH, cyH);

                        return {
                            success: true,
                            message: targetId ? ('Hovered over ' + targetId) : ('Hovered at (' + cxH + ', ' + cyH + ')'),
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

                    case 'fill':
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
                                var cEnterPress = new (elWinT.KeyboardEvent || KeyboardEvent)('keypress', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                                var cEnterUp = new (elWinT.KeyboardEvent || KeyboardEvent)('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                                el.dispatchEvent(cEnterDown);
                                el.dispatchEvent(cEnterPress);
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
                            var enterPress = new (elWinT.KeyboardEvent || KeyboardEvent)('keypress', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                            var enterUp = new (elWinT.KeyboardEvent || KeyboardEvent)('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                            el.dispatchEvent(enterDown);
                            el.dispatchEvent(enterPress);
                            el.dispatchEvent(enterUp);
                            var f = el.form || (el.closest ? el.closest('form') : null);
                            if (f) {
                                var submitBtn = f.querySelector('button[type="submit"], #search-icon-legacy, button#search-icon, button[aria-label*="Search"]');
                                if (submitBtn) {
                                    try { submitBtn.click(); } catch(e) {}
                                }
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
                        var dino = (typeof window !== 'undefined' && window.__dino) ? window.__dino : (this || {});
                        var toTargetId = actionObj.toTarget || actionObj.toElementId || actionObj.toSelector || null;
                        var destEl = null;
                        var destX = (actionObj.toX !== undefined && actionObj.toX !== null) ? Number(actionObj.toX) : null;
                        var destY = (actionObj.toY !== undefined && actionObj.toY !== null) ? Number(actionObj.toY) : null;
                        if (toTargetId) {
                            destEl = (dino.elements && dino.elements[toTargetId] && dino.isNodeConnected && dino.isNodeConnected(dino.elements[toTargetId]) ? dino.elements[toTargetId] : null) || (dino.findInTree ? dino.findInTree(document, toTargetId) : null) || document.querySelector('[data-dino-id="' + toTargetId + '"]') || document.querySelector(toTargetId);
                            if (destEl) {
                                var dRect = destEl.getBoundingClientRect ? destEl.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
                                if (destX === null) destX = Math.round(dRect.left + dRect.width / 2);
                                if (destY === null) destY = Math.round(dRect.top + dRect.height / 2);
                            } else {
                                var vRect = dino.getElementViewportRect ? dino.getElementViewportRect(toTargetId) : null;
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
                        if (targetId) {
                            if (!el) {
                                try { el = document.querySelector(targetId); } catch(e) {}
                            }
                            if (!el) {
                                return {
                                    success: false,
                                    code: 'ELEMENT_NOT_FOUND',
                                    message: "Target element '" + targetId + "' not found to scroll into view.",
                                    elementId: targetId
                                };
                            }
                            if (el.ownerDocument && el.ownerDocument !== document && el.ownerDocument.defaultView && el.ownerDocument.defaultView.frameElement) {
                                try { el.ownerDocument.defaultView.frameElement.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch(e) {}
                            }
                            el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
                            return { success: true, message: 'Scrolled ' + targetId + ' into view', elementId: targetId };
                        }

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

            if (actionOutcome && actionOutcome.success) {
                if (wasHealed) {
                    actionOutcome.healed = true;
                }
                if (el && !actionOutcome.selector) {
                    actionOutcome.selector = getCssSelector(el);
                }
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
                var prev = document.getElementById('__dino_highlight');
                if (prev) prev.remove();

                var rect = this.getElementViewportRect(el);
                var div = document.createElement('div');
                div.id = '__dino_highlight';
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
                            if (!elIn.hasAttribute('data-dino-blur')) {
                                elIn.setAttribute('data-dino-blur', elIn.style.filter || 'none');
                                elIn.style.setProperty('filter', 'blur(6px)', 'important');
                            }
                        }
                    }
                } catch(e) {}
            },

            unblurSensitiveInputs: function() {
                try {
                    var blurred = document.querySelectorAll('[data-dino-blur]');
                    for (var b = 0; b < blurred.length; b++) {
                        var prevFilter = blurred[b].getAttribute('data-dino-blur');
                        if (prevFilter && prevFilter !== 'none') {
                            blurred[b].style.filter = prevFilter;
                        } else {
                            blurred[b].style.removeProperty('filter');
                        }
                        blurred[b].removeAttribute('data-dino-blur');
                    }
                } catch(e) {}
            },

            // In-app Virtual Cursor for Agent Actions (stays strictly inside Dino canvas)
            updateVirtualCursor: function(x, y, label) {
                try {
                    if (x === undefined || y === undefined) return;
                    var cursor = document.getElementById('__dino_virtual_cursor');
                    if (!cursor) {
                        cursor = document.createElement('div');
                        cursor.id = '__dino_virtual_cursor';
                        cursor.style.cssText = 'position:fixed;width:auto;height:24px;pointer-events:none;z-index:2147483647;transition:left 0.12s cubic-bezier(0.2, 0.8, 0.2, 1),top 0.12s cubic-bezier(0.2, 0.8, 0.2, 1),opacity 0.2s;opacity:0.96;display:flex;align-items:center;gap:6px;';
                        cursor.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" style="filter:drop-shadow(0 2px 5px rgba(0,0,0,0.45));flex-shrink:0;"><path d="M2 2L18.5 13.5L11.5 15L9 21.5L2 2Z" fill="#023121" stroke="#ffe5cc" stroke-width="1.8" stroke-linejoin="round"/></svg><span id="__dino_cursor_label" style="display:none;background:#023121;color:#ffe5cc;font-size:11px;font-weight:600;font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:2px 7px;border-radius:6px;border:1px solid rgba(255,229,204,0.3);box-shadow:0 2px 6px rgba(0,0,0,0.3);white-space:nowrap;"></span>';
                        (document.body || document.documentElement).appendChild(cursor);
                    }
                    cursor.style.left = (Math.round(x) - 2) + 'px';
                    cursor.style.top = (Math.round(y) - 2) + 'px';
                    cursor.style.display = 'flex';
                    var lblEl = document.getElementById('__dino_cursor_label');
                    if (lblEl) {
                        if (label && label.length > 0) {
                            lblEl.textContent = label;
                            lblEl.style.display = 'inline-block';
                        } else {
                            lblEl.style.display = 'none';
                        }
                    }
                } catch(e) {}
            },

            pulseVirtualCursor: function(x, y) {
                try {
                    this.updateVirtualCursor(x, y);
                    var ripple = document.createElement('div');
                    ripple.style.cssText = 'position:fixed;left:' + (Math.round(x) - 12) + 'px;top:' + (Math.round(y) - 12) + 'px;width:24px;height:24px;border-radius:50%;border:2px solid #023121;background:rgba(255,229,204,0.35);pointer-events:none;z-index:2147483646;animation:__dino_ripple 0.4s ease-out forwards;';
                    if (!document.getElementById('__dino_ripple_style')) {
                        var style = document.createElement('style');
                        style.id = '__dino_ripple_style';
                        style.textContent = '@keyframes __dino_ripple { 0% { transform:scale(0.5); opacity:1; } 100% { transform:scale(2.2); opacity:0; } }';
                        document.head.appendChild(style);
                    }
                    (document.body || document.documentElement).appendChild(ripple);
                    setTimeout(function() { if (ripple.parentNode) ripple.parentNode.removeChild(ripple); }, 450);
                } catch(e) {}
            },

            hideVirtualCursor: function() {
                try {
                    var cur = document.getElementById('__dino_virtual_cursor');
                    if (cur) cur.style.display = 'none';
                } catch(e) {}
            },

            // Comprehensive CSS :hover & DOM tree emulation for submenus and tooltips
            emulateHover: function(el, x, y) {
                if (!el) return;
                var elDoc = el.ownerDocument || document;

                // 1. Clear previous hover markers
                try {
                    elDoc.querySelectorAll('[data-dino-hover]').forEach(function(prev) {
                        prev.removeAttribute('data-dino-hover');
                    });
                } catch(e) {}

                // 2. Set [data-dino-hover="true"] on target and all ancestors up to documentElement
                var curr = el;
                while (curr && curr.nodeType === 1 && curr !== elDoc.documentElement) {
                    try { curr.setAttribute('data-dino-hover', 'true'); } catch(e) {}
                    curr = curr.parentElement;
                }

                // 3. Transparently patch Element.prototype.matches for :hover
                if (!Element.prototype.__dino_orig_matches) {
                    Element.prototype.__dino_orig_matches = Element.prototype.matches;
                    Element.prototype.matches = function(sel) {
                        if (sel === ':hover' || sel === '*:hover') {
                            return this.hasAttribute('data-dino-hover') || Element.prototype.__dino_orig_matches.call(this, sel);
                        }
                        return Element.prototype.__dino_orig_matches.call(this, sel);
                    };
                }

                // 4. Transparently patch Document.prototype.querySelector/querySelectorAll for :hover
                if (!Document.prototype.__dino_orig_qs) {
                    Document.prototype.__dino_orig_qs = Document.prototype.querySelector;
                    Document.prototype.querySelector = function(sel) {
                        if (sel === ':hover' || sel === '*:hover') {
                            return this.querySelector('[data-dino-hover="true"]') || Document.prototype.__dino_orig_qs.call(this, sel);
                        }
                        return Document.prototype.__dino_orig_qs.call(this, sel);
                    };
                }
                if (!Document.prototype.__dino_orig_qsa) {
                    Document.prototype.__dino_orig_qsa = Document.prototype.querySelectorAll;
                    Document.prototype.querySelectorAll = function(sel) {
                        if (sel === ':hover' || sel === '*:hover') {
                            var found = this.querySelectorAll('[data-dino-hover="true"]');
                            return found.length > 0 ? found : Document.prototype.__dino_orig_qsa.call(this, sel);
                        }
                        return Document.prototype.__dino_orig_qsa.call(this, sel);
                    };
                }

                // 5. Emulate CSS :hover stylesheet rules (including @media and nested blocks)
                try {
                    var sheet = elDoc.getElementById('dino-hover-emulation');
                    if (!sheet) {
                        sheet = elDoc.createElement('style');
                        sheet.id = 'dino-hover-emulation';
                        (elDoc.head || elDoc.documentElement).appendChild(sheet);
                    }

                    function extractHoverRules(rulesList) {
                        var extracted = [];
                        if (!rulesList) return extracted;
                        for (var i = 0; i < rulesList.length; i++) {
                            var r = rulesList[i];
                            if (r.selectorText && r.selectorText.indexOf(':hover') !== -1) {
                                var emulated = r.selectorText.replace(/:hover/g, '[data-dino-hover="true"]');
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


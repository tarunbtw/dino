---
name: nomad-browser
description: Direct control, token-optimized perception, and vision-grounded automation of the Nomad macOS browser engine. Use whenever interacting with Nomad, navigating web pages, inspecting DOM nodes, or automating browser tasks.
---

# Nomad Browser Agent Skill

Nomad is an ultra-lightweight, native macOS WebKit browser engine featuring an embedded local agent server on `127.0.0.1:9222`, token-optimized semantic perception, and an in-app Dev Drawer (`⌘⌥I`).

## Key Principles & Token Efficiency

> [!IMPORTANT]
> **Never request raw page HTML (`outerHTML`).**
> Raw HTML on modern websites consumes between 50,000 and 150,000 tokens per page, rapidly exhausting context windows and introducing hallucination.
> **Always use `nomad_snapshot`** which yields a curated semantic tree costing ~500–2,100 tokens for 100 elements (~20–23 tokens/element; recommend `limit: 40-50` for ~700–1,100 tokens, or `limit: 100` for ~1,400–2,100 tokens).

## Available Agent Tools

| Tool | Purpose | Token Cost |
| :--- | :--- | :--- |
| `nomad_status` | Check engine status, open tabs, active page, and supported capabilities (gated capabilities for minimal token footprint) | ~40 tokens |
| `nomad_tabs` | List all open tabs (id, title, url, active status; supports 1-based index or UUID) | ~100 tokens |
| `nomad_new_tab` | Open a new tab (optional `url`, `isIncognito`, `select`) | ~50 tokens |
| `nomad_switch_tab` | Switch focused active tab by `id` or index | ~30 tokens |
| `nomad_close_tab` | Close tab by `id` or index | ~30 tokens |
| `nomad_navigate` | Navigate active tab to URL, or go back, forward, reload (`action: 'back'|'forward'|'reload'|'url'`, optional `allowLocalFiles: true` for `file://` URLs) | ~50 tokens |
| `nomad_wait` | Wait for page settlement (`mode: 'auto'` default: checks navigation, inflight requests, selector, and DOM stability), or specific mode (`stability`, `selector`, `networkidle`, `url`, `timeout`, `text`) | ~40 tokens |
| `nomad_find` | Fast element lookup matching role, text query, or selector across entire document tree | ~15 tokens |
| `nomad_cookies` | Inspect, inject, or clear session cookies for authentication and state (`action: 'get'|'set'|'clear'`, optional `allDomains: true`). Acts on active tab's store (profile vs ephemeral incognito). | ~80 tokens |
| `nomad_storage` | Inspect, inject, or clear `localStorage`, `sessionStorage`, and WKHTTPCookieStore state (`action: 'get'|'set'|'clear'`) with automatic credential token redaction | ~80 tokens |
| `nomad_snapshot` | **Primary perception:** Dense semantic markdown of interactive & text elements (`li`, `p`, `td`, `th`), deterministic IDs, cross-origin iframe piercing (`f1:e1`), prompt-injection boundaries, redaction, pagination, and JSON mode | ~400–2,000 tokens |
| `nomad_action` | Atomic interactions (`click`, `dblclick`, `right_click`, `context_menu`, `hover`, `type`, `clear`, `press`, `selectOption`, `scroll`, `drag`, `highlight`, `upload`) with optional `native: true` (`isTrusted: true`) | ~40 tokens |
| `nomad_upload` | Programmatic file upload to `<input type="file">`, label, or dropzone without modal system dialogs (`paths: string[]`) | ~40 tokens |
| `nomad_downloads` | List recent file downloads, showing destination paths in `~/Downloads` (with auto-fallback to `~/.nomad/downloads` on macOS TCC permission restrictions), file sizes, and states | ~80 tokens |
| `nomad_wait_for_download` | Await active or impending file download to complete; returns local disk path, size, and SHA-256 hash | ~60 tokens |
| `nomad_screenshot` | GPU snapshot; set `labeled: true` for vision badges (max 75 with anti-collision), or `elementId` / `clip` for cropped region capture | Base64 image |
| `nomad_evaluate` | Run expression-oriented JavaScript in page or isolated context (`world: 'isolated'` default, or `'page'`); returns value or descriptive error | Minimal |
| `nomad_dialog` | Inspect or configure JavaScript dialog handling (`policy: 'accept' \| 'dismiss' \| 'wait'`, `action: 'accept' \| 'dismiss'`, optional prompt response text; default safe policy `'dismiss'`) | ~40 tokens |
| `nomad_console` | Inspect recent page console logs (`log`, `warn`, `error`) or clear log buffer | ~100 tokens |
| `nomad_network` | Inspect recent HTTP requests (fetch/XHR), status codes, latencies, and errors | ~150 tokens |
| `nomad_extensions` | List installed WebExtensions (`action: 'list'|'enable'|'disable'`) | ~50 tokens |

---

## Standard Workflow

### 1. Navigation & State Verification
```json
// Navigate to page (pass allowLocalFiles: true for file:// URLs)
nomad_navigate({ "url": "https://example.com" })

// Check status or verify active tab (on engine launch, poll /status until ready)
nomad_status({})
```

### 2. Dense Semantic Perception (~400–2,000 tokens)
Call `nomad_snapshot`. It returns a distilled tree with deterministic `[eN]` refs, text elements (`li`, `p`, `td`) for outcome verification, `(offscreen)` flags, and automatic redaction of sensitive credentials/payment data:
```markdown
=== Nomad Semantic Perception ===
Tokens: ~380
URL: https://example.com/todos
Title: Todo App

[e1] <h1 "Tasks">
[e2] <input id="new-todo" placeholder="What needs to be done?" type="text">
[e3] <button id="add">Add</button>
[e4] <li "Buy milk">
[e5] <a href="/login">Sign In</a> (offscreen)
```
Default mode returns the token-efficient semantic perception markdown (~700–1,100 tokens @ `limit: 40-50`, ~1,400–2,100 tokens @ `limit: 100`, ~20–23 tokens/element on dense pages). To receive the full JSON AST array of elements, pass `mode: 'json'`:
```json
nomad_snapshot({ "limit": 40, "offset": 0, "viewportOnly": true, "includeText": true })
// Or full JSON AST element array:
nomad_snapshot({ "mode": "json" })
```

#### Advanced Perception Parameters
- **`target`**: CSS selector or element ID (e.g. `'#app'`, `'.modal'`, `'e5'`). Restricts scanning to this subtree only, saving tokens when automating focused UI components.
- **`depth`**: Maximum hierarchy depth relative to root/target (e.g. `depth: 1` for direct children, `depth: 2` for grandchildren).
- **`track`**: Set `track: true` to detect mutations across snapshots. Newly rendered elements are flagged with `[NEW]` badge in markdown summary (and `isNew: true` in JSON), returning mutation counts (`tracked: { added, removed, unchanged }`).
- **`viewportOnly`**: Filter to elements currently visible in the on-screen viewport sorted top-to-bottom and left-to-right, without mutating document scroll position.
- **`role` & `text`**: Filter by ARIA/HTML role (`role: 'link'`, `role: 'textbox'`, `role: 'button'`, `role: 'heading'`) or case-insensitive text match.

> [!WARNING]
> **JSON Mode Token Cost Guard:**
> Full JSON AST mode serializes coordinates, tags, roles, attributes, and bounds for every element (~110 tokens/element vs ~20 in text mode). On a 1,000-element page, JSON mode consumes ~100k+ tokens. To prevent runaway context exhaustion, `mode: "json"` defaults to a 250-element limit and includes self-documenting metadata (`isClamped: true`, `unclampedTotal: <count>`, and an actionable `notice`).
> - Pass `"unrestricted": true` (or `"force": true`) to bypass the clamp and return the complete AST (`limit: -1`).
> - Passing `"limit": -1` explicitly returns all elements without array truncation.
> - In `mode: "json"`, the text `summary` is omitted by default, saving ~22% of payload tokens. Pass `"includeSummary": true` if you require both the markdown summary and the JSON element tree.
> - For normal agent perception loops, prefer the default `mode: "text"`.

> [!NOTE]
> **URL Display & Filter Totals in Header:** Snapshot headers echo the current page URL for context grounding. `totalElements` (and `filteredTotal`) reflects the count of elements matching any active filters (`role`, `text`, `viewportOnly`), while `unfilteredTotal` returns the raw element count on the page.
> Page accessibility text inside markdown snapshots is securely wrapped within prompt-injection boundary tags: `<!-- BEGIN UNTRUSTED WEB CONTENT (origin: ...) --> ... <!-- END UNTRUSTED WEB CONTENT -->`.

### 3. Precision Action Dispatch
Interact with elements directly by reference:
```json
// Type into input
nomad_action({
  "type": "type",
  "elementId": "e1",
  "text": "MacBook Pro"
})

// Click button
nomad_action({
  "type": "click",
  "elementId": "e2"
})
```

Supported action types:
- `click`: Triggers synthetic PointerDown, PointerUp, and Click events at the element's center. Occlusion-aware: returns `isObscured`, `occludedBy`, and `centerCoordinates` in response payloads. If an overlay covers the element, the click hits the topmost covering element unless `force: true` is passed.
- `dblclick` / `double_click`: Dispatches double-click DOM sequence (`detail: 1`, `detail: 2`, and `dblclick`) and native `mouseEventClickState = 2`.
- `right_click` / `context_menu`: Dispatches native/synthetic right-click mouse events and `contextmenu` event to reveal custom and native context menus. Nodes supporting right-click menus are flagged with `(context-menu)` in `nomad_snapshot`.
- `hover`: Dispatches pointerover/pointerenter/mousemove sequence to open dropdown menus, submenus, or tooltips. Emulates CSS `:hover` states dynamically via `[data-nomad-hover]` so newly revealed menus are captured in subsequent DOM snapshots. Operates identically across GUI and headless daemon modes without stealing window focus or switching macOS workspaces. Displays an in-app canvas virtual cursor (`#__nomad_virtual_cursor`) shaped as a crisp macOS arrow pointer anchored at `(x, y)` without hijacking the user's macOS hardware mouse pointer.
- `type`: Focuses element and sets value via prototype setter (React 16+ and contentEditable compatible). Dispatches `input` events per keystroke. If text is empty/omitted and `submit: true` is passed, existing field content is preserved. To commit changes, pass `submit: true` (presses Enter), `blur: true`, or `change: true`.
- `clear`: Wipes input/textarea/contentEditable value and triggers change events.
- `press`: Simulates key press or modifier chord (e.g. `key: "Enter"`, `key: "Meta+A"`, `key: "Escape"`). Validates key names against standard named keys (`Enter`, `Tab`, `Escape`, `Backspace`, `Delete`, `ArrowUp/Down/Left/Right`, `Space`, function keys `F1`–`F12`, and modifier chords); rejects unknown key names. Supports keyboard stepping on `<input type="range">` and `<input type="number">`: `ArrowRight`/`ArrowUp` steps up (`stepUp()`) and `ArrowLeft`/`ArrowDown` steps down (`stepDown()`) with `input` and `change` event dispatch.
- `selectOption`: Chooses native HTML `<select>` dropdown option by `optionValue` or `optionText`. For custom ARIA/div dropdowns (e.g. Radix, HeadlessUI, React-Select), click the dropdown trigger element, wait/snapshot, and click the option element.
- `scroll`: Scrolls the viewport by `scrollDeltaY` pixels (e.g. `300` to scroll down, `-300` to scroll up) or `scrollDeltaX`.
- `drag`: Dispatches standard HTML5 drag-and-drop sequence (`dragstart`, `dragenter`, `dragover`, `drop`, `dragend`) AND interpolated pointer event sequence (`pointerdown`, 5 moves, `pointerup`). Operates seamlessly on modern pointer-driven sortables (SortableJS, React DnD), custom sliders, and HTML5 canvas. Supports element-to-element drag directly via `toElementId` (e.g. `{ "type": "drag", "elementId": "e3", "toElementId": "e8" }` or `toTarget`), or explicit destination pixel coordinates (`toX`, `toY`).
- `highlight`: Briefly flashes a high-contrast visual outline over the element for visual confirmation.
- `upload`: Programmatically injects local files into `<input type="file">`, associated `<label>`, or dropzone containers without triggering blocking macOS `NSOpenPanel` sheets (`paths: string[]`). Automatically validates file existence on disk before dispatch.
- **Native Hardware Input (`native: true` | `isTrusted: true`)**: Pass `"native": true` (or use `native_click`, `native_right_click`, `native_type`, `native_press`, `native_drag`) on any action to bypass synthetic JS dispatch and route through macOS AppKit and CoreGraphics HID queues directly into WebKit's window event pipeline without stealing OS window focus or switching macOS spaces. Produces DOM events with `event.isTrusted === true`, which is required for Canvas-based web apps (Figma, Google Docs), WebGL 3D scenes, Monaco/VSCode web editors, and anti-bot verification sliders.

> [!TIP]
> **Cross-Origin Sub-Frame Piercing (Stripe, OAuth, reCAPTCHA):**
> Nomad automatically pierces through cross-origin iframes by injecting `NomadFrameScript` (`forMainFrameOnly: false`) across all nested browsing contexts. Interactive controls inside sub-frames appear directly in `nomad_snapshot` tagged with their frame ID (e.g. `[f1:e1] <input placeholder="Card number">`).
> - Target sub-frame elements directly via `elementId: "f1:e1"`.
> - Actions are automatically routed to the child frame via WebKit's secure message bridge.
> - Sub-frame coordinates are translated to top-level viewport coordinates, so both labeled visual badges and native hardware clicks hit the exact screen coordinates inside the iframe seamlessly!
> - Sub-frame controls are automatically synchronized on each snapshot. When pages mount iframes asynchronously via delayed timers (e.g. `setTimeout`), use `nomad_wait({ mode: 'selector', selector: 'iframe' })` or poll `nomad_snapshot` until the frame mounts.

> [!TIP]
> **Download Interception & Local Handoff:**
> When an agent interaction triggers a file download (clicking an export button, PDF download, or CSV report), Nomad intercepts the `WKDownload` stream, saves the file without blocking system dialogs, and records full file metadata.
> - **Unified Location & TCC Auto-Fallback:** In GUI mode, downloads target standard `~/Downloads`. In headless daemon mode (or when macOS TCC blocks `com.apple.WebKit.Networking.xpc` from `~/Downloads`), Nomad directs WebKit to `~/.nomad/downloads` for guaranteed write permissions, and automatically promotes completed files to `~/Downloads` when writable by the main process.
> - Call `nomad_wait_for_download({ "timeoutMs": 15000 })` to await the completion of an active or impending download.
> - Returns `{ "success": true, "download": { "filename": "report.csv", "path": "/Users/.../Downloads/report.csv", "size": 1048576, "sha256": "e3b0c442..." } }`.
> - Call `nomad_downloads({ "limit": 20 })` to inspect recent completed or in-progress downloads.

> [!TIP]
> **Ref Self-Healing, Stale Ref & Selector Protection:**
> When asynchronous DOM shifts alter element indices between calls, Nomad automatically executes semantic signature matching (by ID, testId, name, or aria-label) to find the intended control. If an element reference is no longer in the DOM, was snapshotted as a non-editable tag, or resolves to an incompatible node (e.g. attempting to type into a shifted image, link, or checkbox), Nomad strictly returns `{ "success": false, "staleRef": true, "code": "STALE_REF" }` prompting you to call `nomad_snapshot` for fresh element refs instead of silently executing actions on arbitrary elements.
> If an explicit CSS selector is provided (or a non-ref target fails to match in the live DOM), Nomad returns `{ "success": false, "staleRef": false, "code": "SELECTOR_NOT_FOUND", "message": "Target element matching selector '...' not found in DOM." }` providing a distinct, actionable error code.

> [!NOTE]
> **JavaScript Evaluation (`nomad_evaluate`):**
> Evaluates expression-oriented JavaScript in page context. To run multi-statement scripts or declare variables, wrap the code in an IIFE: `(() => { const x = 1; return x + 1; })()`.
> Pass `world: "isolated"` to execute in an isolated WebKit content world (`.defaultClient`) that bypasses page-level CSP or script interference.

### 4. Vision Grounding (Multimodal Verification)
When visual spatial layout is required, capture a vision-grounded screenshot:
```json
nomad_screenshot({ "labeled": true })
```
This renders numbered visual badges matching the snapshot references (`[1]`, `[2]`, ...) directly on the WebKit GPU frame before capturing the PNG, giving vision models exact pixel grounding.

> [!TIP]
> **Animated SPAs & Entrance Transitions (Framer, WebGL, Canvas):**
> Modern landing pages (such as Framer or WebGL showcases) frequently utilize initial entrance fade-in animations (`opacity: 0 -> 1` over 500–1000ms). When observing such pages, call `nomad_wait({ mode: "timeout", durationMs: 1200 })` or wait for stability before capturing the reference screenshot, and visually inspect the frame before proceeding.
>
> **Choosing the Right Wait Mode:**
> - `mode: "auto"` (Default): The smart auto-wait pipeline. Automatically performs: (1) Navigation check (waits if page is actively loading), (2) Target readiness check (if selector is provided, awaits node mounting), (3) Inflight network check (awaits active fetch/XHR requests settling with a 200ms quiet window, capped at 2.5s to avoid polling deadlocks), and (4) DOM mutation stability check.
> - `mode: "stability"`: Waits for ongoing DOM mutation bursts to quiet down (great after clicks, modal opens, or accordion transitions). It settles once active churn stops; it does not wait for delayed future timers.
> - `mode: "selector"`: Best for async UI renders or API fetches — returns immediately once the target node mounts in the DOM. Automatically pierces open Shadow DOM roots and nested same-origin frames.
> - `mode: "networkidle"`: Best for data-heavy SPAs that perform background fetch/XHR queries before rendering content. Waits until in-flight requests settle for 500ms (for pages with recurring polling intervals like `setInterval(fetch, 200ms)`, use `auto` or `selector` instead).
> - `mode: "navigation"` or `mode: "url"`: Best when awaiting full-page redirects or SPA history transitions. Matches against both raw and percent-decoded URLs (e.g. `Special:Search` matches `Special%3ASearch`). When called without a URL pattern, waits for active navigation loading to complete or URL to change, preventing premature returns.

---

## Developer Drawer (In-App DevX)

- **Keyboard Shortcut:** `⌘⌥I` toggles the minimalist Dev Drawer at the bottom of the active web tab.
- **Inspect Tab:** Crosshair picker (`Pick Element`) highlights hovered nodes and displays Tag, ID, Classes, Bounding Size, Inner Text, and Agent Reference (`[eN]`).
- **Console Tab:** Streams live `console.log`, `console.warn`, and `console.error` messages from the active page, with a 1-line JS REPL bar.
- **Agent Tab:** Displays live status of the local server (`127.0.0.1:9222`), request counters, live Semantic Tree capture, and Labeled Screenshot preview.
- **Safari Web Inspector Fallback:** `webView.isInspectable = true` is enabled by default. Right-click any element and select "Inspect Element" to open Safari Web Inspector.

---

## Authentication & Security

Nomad's embedded local server (`127.0.0.1:9222`) is protected by bearer token authentication:
- **Token Location:** Automatically generated on launch at `~/.nomad/agent-token` with strict POSIX `0600` permissions (only accessible to the current user).
- **Native MCP Auto-Auth:** When launched via `nomad --mcp`, the native Swift MCP server automatically reads `~/.nomad/agent-token` (or the `NOMAD_TOKEN` environment variable) and authenticates all tool calls to the running browser.
- **Direct HTTP Calls:** If communicating with the server directly (e.g. via `curl` or custom scripts), pass the token in the `Authorization` or `X-Nomad-Token` header:
  ```bash
  TOKEN=$(cat ~/.nomad/agent-token)
  curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:9222/snapshot
  ```
- **Health & Liveness Probes:** `GET /status` returns `{ "nomad": "active", "version": "0.1", "port": 9222, "authRequired": true }` unauthenticated. When authenticated with your Bearer token, it returns full engine status: `tabsCount`, `tabCount`, `activeTabId`, `activeURL`, `activeUrl`, `activeTitle`, `capabilities`, and `lastDialog`.

---

## Direct HTTP REST API Reference (`127.0.0.1:9222`)

For environments driving Nomad directly without MCP (e.g. `curl`, Python, Node.js scripts), authenticate with `Authorization: Bearer <token>` or `X-Nomad-Token: <token>`.

| Method | Endpoint | Description / Parameters |
| :--- | :--- | :--- |
| `GET` | `/status` | Engine health, tab counts, active tab/URL. Token-optimized: `capabilities` dictionary is gated behind `?capabilities=true` or `?verbose=true` (~40 tokens default vs ~590 tokens verbose) |
| `GET` | `/capabilities` | Dedicated inspection of engine features, supported action types, and capabilities |
| `GET` | `/tabs` | List open tabs (`id`, `title`, `url`, `active`, `isActive`, `isLoading`, `isIncognito`, `tabsCount`, `tabCount`) |
| `POST` | `/tabs/new` | Body: `{ "url"?: string, "select"?: bool, "isIncognito"?: bool }` |
| `POST` | `/tabs/switch` | Body: `{ "id": string }` (supports 1-based index, 0-based index, UUID, or UUID prefix) |
| `POST` | `/tabs/close` | Body: `{ "id": string }` (supports tab index or UUID) |
| `POST` | `/navigate` | Body: `{ "url"?: string, "action"?: "url"|"back"|"forward"|"reload", "allowLocalFiles"?: bool }` (for `file://` URLs, pass `allowLocalFiles: true`; concurrent navigations automatically cancel superseded loads) |
| `POST` | `/navigate/back` | Navigate back in browser history |
| `POST` | `/navigate/forward`| Navigate forward in browser history |
| `GET` / `POST` | `/snapshot` \| `/tree` | Query / Body: `limit`, `offset`, `viewportOnly=true`, `includeText=true`, `target="#modal"|"e5"`, `depth=2`, `track=true`, `role="link"|"textbox"|"button"|"heading"`, `text="..."`, `mode="text"|"json"`, `unrestricted=true`, `includeSummary=true`, `tabId` (default cap 250 in JSON mode; summary omitted by default in JSON) |
| `POST` | `/find` | Body: `{ "text"?: string, "role"?: string, "selector"?: string, "tabId"?: string }` (full-tree element search in ~15 tokens) |
| `POST` | `/action` | Body: `{ "type": "click"|"dblclick"|"hover"|"type"|"clear"|"press"|"selectOption"|"scroll"|"drag"|"highlight"|"upload"|"native_click"|"native_type"`, `"elementId"?: string`, `"selector"?: string`, `"native"?: bool` (sets `isTrusted: true`), `"paths"?: string[]`, ... } (returns `isObscured`, `occludedBy`, `centerCoordinates`; under `dialogPolicy: "wait"`, returns immediately with `hasPendingDialog: true` and `code: "PENDING_DIALOG"`) |
| `POST` | `/upload` | Body: `{ "elementId": string, "paths": string[], "tabId"?: string }` (programmatic file upload without modal GUI sheets) |
| `GET` | `/downloads` | Query: `limit=20`, returns list of recent file downloads (`filename`, `path`, `size`, `state`, `sha256`) in `~/Downloads` (or fallback `~/.nomad/downloads`) |
| `GET` | `/downloads/last` | Returns metadata of the most recent download |
| `POST` / `GET` | `/downloads/wait` | Body / Query: `{ "timeoutMs"?: int, "since"?: string|number }`, awaits download completion returning destination path and SHA-256 hash |
| `DELETE` | `/downloads` | Query / Body: `filename=agent_dl.txt` or `path=...` (deletes downloaded file from disk and clears download history) |
| `POST` | `/wait` | Body: `{ "mode": "stability"|"selector"|"url"|"timeout"|"networkidle"|"navigation"|"text", "selector"?: string, "text"?: string, "urlPattern"?: string` (supports regex or plain substring), `"quietMs"?: int, "timeoutMs"?: int }` |
| `GET` | `/cookies` | Query: `domain` (filter by target domain), `allDomains=true`, `tabId` |
| `POST` | `/cookies` | Body: `{ "action": "set"|"get"|"clear", "domain"?: string, "name"?: string, "value"?: string, "cookies"?: [...], "allDomains"?: bool }` |
| `DELETE` | `/cookies` | Query / Body: `domain` (clears cookies for domain), `allDomains=true` (clears all profile cookies) |
| `GET` / `POST` / `DELETE` | `/storage` | Inspect, inject, or clear `localStorage`, `sessionStorage`, and cookies with auto-redaction (`action: 'get'|'set'|'clear'`). Supports direct key/values (`key: "...", value: "...", type: "localStorage"|"sessionStorage"`), bulk dictionaries, and cookies |
| `POST` | `/evaluate` | Body: `{ "script": string }` (alias: `expression`), `world`: `"isolated"` (default, CSP-proof) \| `"page"`; returns structured uppercase `code: "SYNTAX_ERROR"|"EVAL_CSP"|"TYPE_ERROR"|"REFERENCE_ERROR"|"EVAL_ERROR"` on failure; unblocks immediately on dialog |
| `GET` / `POST` | `/dialog` | Body / Query: `{ "policy"?: "accept"|"dismiss"|"wait", "action"?: "accept"|"dismiss", "response"?: string }` (default safe policy is `"dismiss"`; `"wait"` returns `hasPendingDialog: true` immediately; safe dismiss is restored upon completion) |
| `GET` | `/console` | Query: `level=all|log|warn|error`, `clear=true`, `tabId` |
| `GET` | `/network` | Query: `statusFilter=all|errors|success`, `clear=true`, `tabId` |
| `GET` | `/events` | Real-time Server-Sent Events (SSE) telemetry stream pushing navigation, console, network, and dialog events without polling |
| `POST` / `GET` / `DELETE` | `/network/mock` | In-flight request mocking: intercept fetch / XHR requests with custom status, headers, and body. Supports `"pattern"` with globs (`*`, `**`), exact URLs, and relative paths; matches authored and resolved URLs; persists across navigations |
| `POST` / `GET` / `DELETE` | `/network/block` | In-flight request blocking: block specific URLs or patterns (`urls: [...]`, `url: "..."`, `pattern: "..."`); blocked requests reject with network error; persists across navigations |
| `GET` / `POST` / `DELETE` | `/policy` \| `/allowlist` | Inspect or configure agent security policy (`mode: "permissive"|"strict"|"ask"`) and domain allowlist (`allowedDomains`/`allowlist`/`domains`). In `strict` mode, navigations to unlisted domains are blocked with `403 DOMAIN_NOT_ALLOWED` |
| `GET` / `POST` / `DELETE` | `/cache/routes` | Learned route cache: inspect and store reliable selector mappings for recurring flows |
| `GET` / `POST` / `DELETE` | `/trace` \| `/trajectory` | Export (`GET`), record custom step (`POST`), or clear (`DELETE`) chronological trajectory journal with action logs, console outputs, and network entries |
| `POST` | `/tabs/tier` | Set tab lifecycle virtualization tier (`id: string, tier: "hot"|"warm"|"cold"`) for memory governance |
| `GET` | `/status` \| `/health` \| `/version` | System health check, release version/build, active tab, capabilities, and Unix socket status |
| `GET` / `POST` / `DELETE` | `/socket` \| `/daemon` \| `/headless` | Inspect socket/daemon (`GET`), dynamically rebind/activate Unix socket path at runtime (`POST { "socketPath": "./nomad.sock" }`), or unbind/clear socket (`DELETE /socket` or `POST /socket {}`) |
| `GET` / `POST` | `/updater` | Inspect auto-update state, version, and build (`GET`), or trigger background update check (`POST`) |

> [!TIP]
> **Sub-Millisecond IPC & Zero-Friction Socket Auth:**
> For local agents running in the shell or CI, Nomad exposes a POSIX Unix Domain Socket at `~/.nomad/nomad.sock` (mode `0600`).
> For sandboxed agents confined to a working directory (`pwd`), send `POST /socket` with `{ "socketPath": "./nomad.sock" }` to instantly bind the socket right inside your `pwd` at runtime without restarting. To clean up or unbind, send `DELETE /socket` or `POST /socket {}`.
> Connections over this socket are inherently authenticated by Darwin filesystem permissions and automatically inject bearer tokens, eliminating the need to pass `-H "Authorization: Bearer ..."` on every request:
> ```bash
> curl --unix-socket ~/.nomad/nomad.sock http://localhost/health
> ```

> [!CAUTION]
> **Profile Cookies & State Isolation:**
> Nomad runs against your live profile sessions. Passing `allDomains: true` to `/cookies` inspects or clears cookies across all domains in the profile. For isolated automated testing without affecting personal logins, open tabs with `"isIncognito": true`.

---

## CLI Quick Reference

When installed via Homebrew (`brew install --cask tarunbtw/tap/nomad`), `nomad` and `nomadd` are directly accessible on your `PATH`:

```
Nomad - Native macOS browser engine and agent runtime

Usage:
  nomad [command] [options]
```

### Daemon & Process Commands

| Command | Description |
| :--- | :--- |
| `nomad` | Launch native macOS GUI browser (default with no arguments) |
| `nomad start` | Run as a detached background daemon in RAM; returns terminal prompt immediately, writes PID to `~/.nomad/nomad.pid`, and redirects logs to `~/.nomad/nomad.log` |
| `nomad stop` | Gracefully stop the running background daemon (SIGTERM), free RAM, and unlink PID & socket files |
| `nomad status` | Check running daemon / GUI status, reporting process PID, HTTP endpoint, IPC socket path, and live open tab count |
| `nomad headless` | Run in foreground with live console logs streaming to terminal; handles `Ctrl+C` (SIGINT) cleanly with graceful socket and PID cleanup |
| `nomad mcp` | Run stdio Model Context Protocol (MCP) server for Claude Code, Cursor, and Antigravity |
| `nomad version` | Print version and build information (`nomad version 0.1 (build 1)`) |
| `nomad help` | Display available commands and options |
| `nomadd` | Direct alias for `nomad headless` |

### Browser Automation CLI Driver (Token-Optimized Shell Control)

When driving Nomad from the terminal, shell scripts, or an AI agent without MCP tools, use these first-class driver subcommands. They connect over the sub-millisecond POSIX Unix Domain Socket (`~/.nomad/nomad.sock`) and consume **~90% fewer tokens** than crafting verbose `curl` HTTP calls.

| Verbose Shell `curl` (~75 tokens) | Concise Nomad CLI (~4 tokens) | Purpose |
| :--- | :--- | :--- |
| `curl -s http://127.0.0.1:9222/snapshot` | **`nomad snap`** | Outputs compact semantic markdown tree (default: `--limit 50`, `-v`/`--viewport`, `--track`, `--role <r>`, `--text <t>`, `-u`) |
| `curl -s http://127.0.0.1:9222/snapshot?mode=json` | **`nomad snap --json`** | Outputs raw JSON AST (`-u`/`--unrestricted` to bypass 250 clamp) |
| `curl -s -X POST http://.../navigate -d '{"url":"..."}'` | **`nomad open <url>`** | Navigates active tab to URL (`--wait [mode]`, `nomad nav`, `nomad navigate`) |
| `curl -s -X POST http://.../action -d '{"type":"click","elementId":"e5"}'` | **`nomad click <ref>`** | Clicks element by ref (`--wait [mode]`, `--native`, `--right` / `-r`; flag-order flexible) |
| `curl -s -X POST http://.../action -d '{"type":"dblclick","elementId":"e5"}'` | **`nomad dblclick <ref>`** | Double-clicks element by ref (alias: `nomad click <ref> --double`) |
| `curl -s -X POST http://.../action -d '{"type":"type","elementId":"e2","text":"..."}'` | **`nomad type <ref> <text>`** | Types into input field (`--submit`, `-p`/`--press <key>`, `--clear`, `--native`) |
| `curl -s -X POST http://.../action -d '{"type":"press","key":"Enter"}'` | **`nomad press <key>`** | Presses key chord (e.g. `Enter`, `Escape`, `Meta+A`) or steps range controls |
| `curl -s -X POST http://.../action -d '{"type":"drag","elementId":"e3","toElementId":"e8"}'` | **`nomad drag <from> <to>`** | Drags element to destination element (`--native`, supports pointer sortables & canvas) |
| `curl -s -X POST http://.../action -d '{"type":"hover","elementId":"e5"}'` | **`nomad hover <ref>`** | Hovers over element (`--native`, activates `:hover` and reveals submenus) |
| `curl -s -X POST http://.../action -d '{"type":"selectOption","elementId":"e4","optionValue":"US"}'` | **`nomad select <ref> <val>`** | Selects dropdown option by value or text |
| `curl -s -X POST http://.../action -d '{"type":"scroll","direction":"down","amount":300}'` | **`nomad scroll [dir] [px]`** | Scrolls active viewport (default: `down 300`) |
| `curl -s -X POST http://.../wait` | **`nomad wait [timeout_ms]`** | Waits for auto-stability, element, or content (`--text`, `--state`, `--selector`, `--url`, `--mode`) |
| `curl -s -X POST http://.../find -d '{"text":"..."}'` | **`nomad find <query>`** | Fast element lookup in ~15 tokens across full document tree (`--role`, `--text`, `--selector`, `--ref-only`) |
| `curl -s -X POST http://.../storage` | **`nomad storage [get\|set\|clear]`** | Inspects, injects, or clears localStorage, sessionStorage, and cookies |
| `curl -s http://127.0.0.1:9222/console` | **`nomad console [level]`** | Streams or dumps console log entries (`all`, `log`, `warn`, `error`, `--clear`) |
| `curl -s http://127.0.0.1:9222/network` | **`nomad network [filter]`** | Inspects HTTP requests (`all`, `errors`, `success`, `--clear`) |
| `curl -s http://127.0.0.1:9222/downloads` | **`nomad downloads [wait\|list\|delete]`** | Manages file downloads, lists completion states and SHA-256 hashes |
| `curl -s -X POST http://.../dialog` | **`nomad dialog [accept\|dismiss\|wait]`** | Controls modal dialog handling policy and sends prompt responses |
| `curl -s http://127.0.0.1:9222/extensions` | **`nomad ext`** | Lists installed WebExtensions (`enable <id>`, `disable <id>`) |
| `curl -s http://127.0.0.1:9222/tabs` | **`nomad tabs`** | Lists open tabs in clean tabular format |
| `curl -s -X POST http://.../tabs/new` | **`nomad tab new [url]`** | Opens a new tab |
| `curl -s -X POST http://.../tabs/switch` | **`nomad tab switch <id\|idx>`** | Switches tab by 1-based index, 0-based index, or UUID prefix |
| `curl -s -X POST http://.../tabs/close` | **`nomad tab close [id\|idx]`** | Closes tab by index or UUID (default: active tab) |
| `curl -s -X POST http://.../evaluate` | **`nomad eval <js_code>`** | Evaluates JavaScript in isolated world by default (`--world isolated|page`) |
| `curl -s http://127.0.0.1:9222/screenshot` | **`nomad shot [file.png]`** | Saves screenshot (`-l`/`--labeled`, `-e <ref>`, `-` for stdout pipe) |
| `curl -s -X POST http://.../upload` | **`nomad upload <ref> <files>`** | Stages and uploads files to file input |
| `curl -s -X POST http://.../navigate -d '{"action":"back"}'` | **`nomad back`**, **`nomad forward`**, **`nomad reload`** | History and page reload navigation |

### Options & Subcommand Help

Every subcommand supports `--help` or `-h` (e.g. `nomad snap --help`, `nomad click -h`, or `nomad help snap`) for detailed flags and argument syntax.

| Option | Description |
| :--- | :--- |
| `--port <port>` | Set agent HTTP server port (default: `9222`, or via `NOMAD_AGENT_PORT` env) |
| `--socket <path>` | Set agent IPC Unix domain socket path (default: `~/.nomad/nomad.sock`, or via `NOMAD_SOCKET_PATH` env) |
| `--version, -v` | Alias for `version` |
| `--help, -h` | Alias for `help` (global or subcommand-specific) |

> [!NOTE]
> **Strict Command Validation:**
> Nomad strictly validates subcommands and options. Any typos or unrecognized arguments (e.g. `nomad hrlp` or `nomad --unknown`) exit immediately with code `1` and print usage instructions without launching the browser or starting servers.

### Daemon Lifecycle & Process Files

* **`~/.nomad/nomad.pid`**: Stores the active daemon / runner process ID (mode `0600`). Managed automatically by `nomad start`, `nomad headless`, and `nomad stop`. Stale PID files from abruptly terminated processes are automatically detected and cleaned up on subsequent runs.
* **`~/.nomad/nomad.log`**: Standard output and error stream from background daemons spawned with `nomad start`.
* **`~/.nomad/nomad.sock`**: POSIX Unix domain socket bridge for sub-millisecond local IPC (mode `0600`).
* **`~/.nomad/agent-token`**: Cryptographically secure 64-character Bearer token for HTTP API authorization.

---

## MCP Configuration for Agent Runtimes

Nomad includes a 100% native Swift Model Context Protocol (MCP) server directly inside the app bundle. It communicates over stdio using JSON-RPC 2.0 with zero external dependencies (no Node.js or npm required).

### Claude Code (`~/.claude/desktop_config.json` or project config)
```json
{
  "mcpServers": {
    "nomad": {
      "command": "nomad",
      "args": ["mcp"]
    }
  }
}
```

### Cursor / Antigravity (`mcp_config.json`)
```json
{
  "mcpServers": {
    "nomad-browser": {
      "command": "nomad",
      "args": ["mcp"]
    }
  }
}
```

> [!TIP]
> - **Homebrew Install:** Use `"command": "nomad"`, `"args": ["mcp"]` (linked into `/opt/homebrew/bin/nomad`).
> - **Direct App Bundle:** Or point directly to `"/Applications/Nomad.app/Contents/MacOS/nomad"`.
> - **Xcode Debug Build:** When developing in Xcode, point to your DerivedData build:
>   `"command": "/Users/.../Library/Developer/Xcode/DerivedData/nomad-*/Build/Products/Debug/nomad.app/Contents/MacOS/nomad"`

### Native MCP Resources & Prompts

- **MCP Resources:**
  - `nomad://tabs`: Live JSON summary of open tabs and active states.
  - `nomad://console`: Stream of recent page console errors and logs.
  - `nomad://network`: Stream of recent HTTP requests, statuses, and latencies.
  - `nomad://status`: Engine health and operational statistics.
- **MCP Prompts:**
  - `nomad_browser_task`: Pre-configured guided agentic workflow prompt for autonomous browsing tasks.

# Dino

A native macOS WebKit browser engine with an embedded driver interface and autonomous agent runtime.

Dino combines a lightweight daily-driver browser with a local automation server. It can be driven externally via CLI, Python/TypeScript SDKs, CDP, UNIX domain socket, or MCP—or directly from within the app using the built-in Copilot (`⌘⇧A`).

---

## Highlights

- **Lightweight**: Native WebKit binary (<15MB on disk), ~35MB baseline RAM, cold starts in <80ms.
- **Dual-Mode Automation**: Run headless or GUI workers for external scripts, or automate directly inside the browser window.
- **Token-Efficient Perception**: Accessibility tree snapshots with deterministic element references (`[e1]`, `[e2]`) instead of raw HTML dumps.
- **In-App Copilot**: Docked bottom-right card interface (`⌘⇧A`) powered by Gemini, Claude, OpenAI, or local Ollama.
- **Zero Keychain Prompt Loops**: Model keys are stored locally with user-only `0600` permissions (`~/Library/Application Support/dino/agent_vault.json`).
- **No Heavy Drivers**: No Chromium, Electron, ChromeDriver, or Node.js runtime required to drive the native binary.

---

## Installation

### Homebrew

```bash
brew install tarunbtw/tap/dino
```

### Direct Download

Download the latest `Dino-<version>.zip` from [GitHub Releases](https://github.com/tarunbtw/dino/releases). Unzip and drag `Dino.app` to `/Applications`.

### Build from Source

Requirements: macOS 13.0+ and Xcode 15.0+ (or Command Line Tools).

```bash
git clone https://github.com/tarunbtw/dino.git
cd dino
./scripts/test.sh
```

The compiled binary will be placed at `build/DerivedData/Build/Products/Release/Dino.app`.

---

## CLI Usage

When installed, the `dino` CLI communicates directly with the running GUI instance or spawns an isolated headless worker.

```bash
# Open a URL in the browser
dino goto https://github.com

# Inspect page structure (compact token-optimized semantic tree)
dino snap -v

# Interact with elements using reference IDs
dino click e2
dino type e4 "search query" --submit

# Take a screenshot
dino shot screenshot.png

# Run JavaScript in the active tab
dino eval "document.title"

# Run as a Model Context Protocol (MCP) server for Claude / Cursor / Antigravity
dino mcp
```

### Headless Worker Mode

Run automated scripts in background headless processes without opening GUI windows:

```bash
dino --headless --port 9223 goto https://example.com
```

---

## SDKs

### TypeScript / JavaScript

```bash
npm install dino-browser
```

```typescript
import { Dino } from 'dino-browser';

const browser = await Dino.launch();
await browser.goto('https://news.ycombinator.com');

const snapshot = await browser.snapshot({ viewportOnly: true });
console.log(snapshot);

await browser.click('e2');
await browser.close();
```

### Python

```bash
pip install dino-browser
```

```python
from dino_browser import dino

dino.goto("https://news.ycombinator.com")
tree = dino.snapshot(viewport_only=True)
print(tree)

dino.click("e2")
```

---

## In-App Copilot (`⌘⇧A`)

Press `⌘⇧A` to toggle the in-browser assistant:

- **Floating Docked Card**: Sits in the bottom-right corner without pushing or obscuring the primary web view.
- **Model Support**: Toggle between Google Gemini, Anthropic Claude, OpenAI, and local Ollama.
- **Safety Rails**: Automatic Human-In-The-Loop (HITL) gates pause execution for destructive actions (e.g., checkout buttons, credential deletion) and Cloudflare/Turnstile challenges.
- **Private Key Storage**: API keys are saved to `~/Library/Application Support/dino/agent_vault.json` with user-only permissions (`0600`), encrypted at rest via FileVault. Environment variables (`GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) are respected automatically.

---

## Driver Endpoints

When running, Dino exposes local control interfaces for external tools:

| Interface | Address | Protocol | Purpose |
|---|---|---|---|
| **HTTP API** | `http://127.0.0.1:9222` | REST / CDP | DevTools protocol (`/json/list`, `/json/version`) and REST automation (`/agent/snapshot`, `/agent/action`, `/agent/eval`) |
| **UNIX Socket** | `~/.dino/dino.sock` | JSON-RPC | Ultra-low-latency local IPC for CLI and native tools |
| **MCP** | `stdio` | MCP | Direct integration with Claude Desktop, Cursor, Antigravity, and Codex |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘T` | New tab |
| `⌘W` | Close active tab |
| `⌘L` / `⌘K` | Focus URL bar / Command Palette |
| `⌘⇧A` | Toggle In-App Copilot |
| `⌘⇧R` | Toggle Reader View |
| `⌘S` | Toggle sidebar collapse |
| `⌥⌘S` | Split tab side-by-side |
| `⌘1` .. `⌘9` | Switch to space / tab |
| `⌃Tab` | Quick tab switcher |

---

## Development

```bash
# Run strict build verification (0 errors, 0 warnings enforced)
./scripts/test.sh

# Build & package release distribution
./scripts/release.sh <patch|minor|major>
```

---

## License

MIT © [Tarun](https://github.com/tarunbtw)

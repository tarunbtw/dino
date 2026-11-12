# Dino Python SDK (`dino-browser`)

Official Python client for [Dino](https://github.com/tarunbtw/dino), the ultra-light native macOS agentic browser engine.

## Installation

```bash
pip install dino-browser
```

*(Requires Dino installed on macOS: `/Applications/Dino.app`)*

## Quick Start

```python
from dino_browser import dino

# 1. Navigate
dino.goto("https://html.duckduckgo.com/html/")

# 2. Token-Optimized Viewport Perception (~400 tokens)
tree = dino.snapshot(viewport_only=True)
print(tree)

# 3. Native & Dynamic Interactions
dino.type("e2", "Apple Silicon M4 Max", submit=True)
dino.wait()

# 4. Differential Perception (Sub-50 tokens for sequential turns!)
diff = dino.diff()
print("DOM Mutations:", diff.get("addedCount"), "Tokens:", diff.get("tokenEstimate"))

# 5. Parameterized Playbooks (0 LLM tokens!)
dino.playbook.run("search_flow", {"query": "Apple Silicon"})

# 6. Network Interception
dino.route.block("*://*.doubleclick.net/**")
dino.route.mock("*/api/user", {"name": "Alice", "tier": "pro"})
```


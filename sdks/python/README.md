# Nomad Python SDK (`nomad-browser`)

Official Python client for [Nomad](https://github.com/nomad-browser/nomad), the ultra-light native macOS agentic browser engine.

## Installation

```bash
pip install nomad-browser
```

*(Requires Nomad installed on macOS: `/Applications/Nomad.app`)*

## Quick Start

```python
from nomad_browser import Nomad

nomad = Nomad()

# 1. Navigate
nomad.goto("https://html.duckduckgo.com/html/")

# 2. Token-Optimized Viewport Perception (~400 tokens)
tree = nomad.snapshot(viewport_only=True)
print(tree)

# 3. Native & Dynamic Interactions
nomad.type("e2", "Apple Silicon M4 Max", submit=True)
nomad.wait()

# 4. Differential Perception (Sub-50 tokens for sequential turns!)
diff = nomad.diff()
print("DOM Mutations:", diff.get("addedCount"), "Tokens:", diff.get("tokenEstimate"))

# 5. Parameterized Playbooks (0 LLM tokens!)
nomad.playbook.run("search_flow", {"query": "Apple Silicon"})

# 6. Network Interception
nomad.route.block("*://*.doubleclick.net/**")
nomad.route.mock("*/api/user", {"name": "Alice", "tier": "pro"})
```


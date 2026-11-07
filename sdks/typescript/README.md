# Nomad TypeScript SDK (`nomad-browser`)

Official TypeScript/JavaScript client for [Nomad](https://github.com/nomad-browser/nomad), the ultra-light native macOS agentic browser engine.

## Installation

```bash
npm install nomad-browser
```

*(Requires Nomad installed on macOS: `/Applications/Nomad.app`)*

## Quick Start

```typescript
import { nomad } from 'nomad-browser';

// 1. Navigate
await nomad.goto('https://html.duckduckgo.com/html/');

// 2. Token-Optimized Viewport Perception (~400 tokens)
const tree = await nomad.snapshot({ viewportOnly: true });
console.log(tree);

// 3. Native & Dynamic Interactions
await nomad.type('e2', 'Apple Silicon M4 Max', { submit: true });
await nomad.wait();

// 4. Differential Perception (Sub-50 tokens for sequential turns!)
const diff = await nomad.diff();
console.log(`DOM Mutations: +${diff.addedCount}, Tokens: ${diff.tokenEstimate}`);

// 5. Parameterized Playbooks (0 LLM tokens!)
await nomad.playbook.run('search_flow', { query: 'Apple Silicon' });

// 6. Network Interception
await nomad.route.block('*://*.doubleclick.net/**');
await nomad.route.mock('*/api/user', { name: 'Alice', tier: 'pro' });
```


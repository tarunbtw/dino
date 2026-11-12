# Dino TypeScript SDK (`dino-browser`)

Official TypeScript/JavaScript client for [Dino](https://github.com/tarunbtw/dino), the ultra-light native macOS agentic browser engine.

## Installation

```bash
npm install dino-browser
```

*(Requires Dino installed on macOS: `/Applications/Dino.app`)*

## Quick Start

```typescript
import { dino } from 'dino-browser';

// 1. Navigate
await dino.goto('https://html.duckduckgo.com/html/');

// 2. Token-Optimized Viewport Perception (~400 tokens)
const tree = await dino.snapshot({ viewportOnly: true });
console.log(tree);

// 3. Native & Dynamic Interactions
await dino.type('e2', 'Apple Silicon M4 Max', { submit: true });
await dino.wait();

// 4. Differential Perception (Sub-50 tokens for sequential turns!)
const diff = await dino.diff();
console.log(`DOM Mutations: +${diff.addedCount}, Tokens: ${diff.tokenEstimate}`);

// 5. Parameterized Playbooks (0 LLM tokens!)
await dino.playbook.run('search_flow', { query: 'Apple Silicon' });

// 6. Network Interception
await dino.route.block('*://*.doubleclick.net/**');
await dino.route.mock('*/api/user', { name: 'Alice', tier: 'pro' });
```


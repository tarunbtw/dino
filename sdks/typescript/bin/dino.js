#!/usr/bin/env node

/**
 * Dino Browser CLI Wrapper
 * Resolves local Dino.app installation, global binary, or ~/.dino/bin/dino.
 */

const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

function resolveBinary() {
  // 1. Check custom environment variable
  if (process.env.DINO_BIN && fs.existsSync(process.env.DINO_BIN)) {
    return process.env.DINO_BIN;
  }

  // 2. Check /Applications/Dino.app
  const appPath = '/Applications/Dino.app/Contents/MacOS/dino';
  if (fs.existsSync(appPath)) {
    return appPath;
  }

  // 3. Check ~/.dino/bin/dino
  const userBin = path.join(os.homedir(), '.dino', 'bin', 'dino');
  if (fs.existsSync(userBin)) {
    return userBin;
  }

  // 4. Check PATH via 'which dino'
  try {
    const p = execSync('which dino 2>/dev/null', { encoding: 'utf8' }).trim();
    if (p && fs.existsSync(p)) {
      return p;
    }
  } catch {}

  return null;
}

const binary = resolveBinary();

if (!binary) {
  console.error('\x1b[31m[dino]\x1b[0m Dino native browser executable not found.');
  console.error('Please install Dino via Homebrew (brew install dino) or install /Applications/Dino.app.');
  process.exit(1);
}

const child = spawn(binary, process.argv.slice(2), {
  stdio: 'inherit',
  env: process.env
});

child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
  } else {
    process.exit(code ?? 0);
  }
});


#!/bin/bash
# ==============================================================================
# Dino Data & Cache Reset Script
#
# Stops running Dino processes and removes local caches, WebKit storage,
# preferences, and runtime state for clean test runs.
#
# Usage:
#   ./scripts/clean.sh
# ==============================================================================

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

echo "==> Stopping any running Dino instances..."
if command -v dino >/dev/null 2>&1; then
  dino stop --all >/dev/null 2>&1 || true
fi
pkill -f "/Applications/Dino.app/Contents/MacOS/Dino" >/dev/null 2>&1 || true
pkill -f "\.dino/workers/" >/dev/null 2>&1 || true

echo "==> Clearing preferences (tarun.dino)..."
defaults delete tarun.dino >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true

echo "==> Removing app data, caches, and WebKit stores..."
rm -rf \
  "$HOME/Library/Preferences/tarun.dino.plist" \
  "$HOME/Library/Application Support/Dino" \
  "$HOME/Library/Caches/tarun.dino" \
  "$HOME/Library/WebKit/tarun.dino" \
  "$HOME/Library/HTTPStorages/tarun.dino" \
  "$HOME/Library/Saved Application State/tarun.dino.savedState" \
  "$HOME/.dino"

echo "==> Cleaning temporary Xcode build directories..."
rm -rf "$PROJECT_ROOT/build" "$HOME/Library/Developer/Xcode/DerivedData"/dino-*

echo "✅ Dino data and caches cleared."

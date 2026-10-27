#!/bin/bash
# Builds a high-performance, fully optimized Release build of Nomad.
# Strips debug symbols, enables Whole Module Optimization (-O), and signs with entitlements.
#
# Usage:
#   ./scripts/build-release.sh [--install]
#
# Options:
#   --install    Copies the built Nomad.app to /Applications/Nomad.app

set -euo pipefail

cd "$(dirname "$0")/.."

INSTALL_TO_APPS=false
if [ "${1:-}" = "--install" ]; then
  INSTALL_TO_APPS=true
fi

OUT="build/Release"
APP_NAME="nomad"

echo "=========================================================="
echo "  Building Nomad in Release Configuration..."
echo "  - Whole Module Optimization (-O)"
echo "  - Zero debug assertion overhead"
echo "  - Dead-code stripping & minimized binary RSS footprint"
echo "=========================================================="

rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild -project nomad.xcodeproj \
  -scheme nomad \
  -configuration Release \
  -derivedDataPath "$OUT/derived" \
  build

BUILT_APP="$OUT/derived/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$BUILT_APP" ]; then
  echo "❌ Error: Built application not found at $BUILT_APP" >&2
  exit 1
fi

echo "==> Signing application bundle with entitlements..."
codesign --force --deep --sign - --entitlements nomad/nomad.entitlements "$BUILT_APP"

FINAL_APP="$OUT/Nomad.app"
rm -rf "$FINAL_APP"
cp -R "$BUILT_APP" "$FINAL_APP"

SIZE="$(du -sh "$FINAL_APP" | cut -f1)"

echo ""
echo "=========================================================="
echo "✅ Nomad Release Build Succeeded!"
echo "   Location: $FINAL_APP"
echo "   Bundle Size: $SIZE"
echo "=========================================================="

if [ "$INSTALL_TO_APPS" = true ]; then
  echo "==> Installing to /Applications/Nomad.app..."
  rm -rf /Applications/Nomad.app
  cp -R "$FINAL_APP" /Applications/Nomad.app
  echo "✅ Installed to /Applications/Nomad.app successfully."
fi

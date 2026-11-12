#!/bin/bash
# ==============================================================================
# Dino Build Verification & Cleanliness Test Suite
#
# Compiles Release build with strict zero-warnings/zero-errors enforcement,
# isolates DerivedData, unregisters any temporary build artifacts from macOS
# LaunchServices, and completely purges $PROJECT_ROOT/build and DerivedData.
#
# Usage:
#   ./scripts/test.sh
# ==============================================================================

set -euo pipefail

# Ensure script runs from project root
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR="$PROJECT_ROOT/build/DerivedData"
LOG_FILE=""

echo "=========================================================="
echo "  Dino Build Verification & Cleanliness Suite"
echo "=========================================================="

cleanup_artifacts() {
  echo "==> Cleaning build artifacts and LaunchServices registrations..."
  if [ -x "$LSREGISTER" ]; then
    for target_dir in "$PROJECT_ROOT/build" "$HOME/Library/Developer/Xcode/DerivedData"/dino-*; do
      if [ -d "$target_dir" ]; then
        find "$target_dir" -name "*.app" -type d -prune 2>/dev/null | while read -r app_path; do
          if [ -n "$app_path" ]; then
            "$LSREGISTER" -u "$app_path" 2>/dev/null || true
          fi
        done
      fi
    done
    "$LSREGISTER" -gc 2>/dev/null || true
  fi

  rm -rf "$PROJECT_ROOT/build"
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/dino-*
  if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
  fi
}

# Always ensure cleanup on script exit, abort, or error
trap cleanup_artifacts EXIT INT TERM

# 1. Pre-build cleanup of any leftover build artifacts
cleanup_artifacts

# 2. Compile Release binary with strict zero-warnings and zero-errors flags
echo "==> Compiling Release binary (strict: 0 warnings, 0 errors)..."
mkdir -p "$BUILD_DIR"
LOG_FILE=$(mktemp -t dino_build_verify.XXXXXX.log)

set +e
xcodebuild -project dino.xcodeproj \
  -scheme dino \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  build > "$LOG_FILE" 2>&1
BUILD_STATUS=$?
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
  echo "❌ Error: Build failed with exit code ${BUILD_STATUS}." >&2
  grep -E "(:[0-9]+:[0-9]+: error:)" "$LOG_FILE" >&2 || tail -n 25 "$LOG_FILE" >&2
  exit 1
fi

CODE_WARNINGS=$(grep -E "(:[0-9]+:[0-9]+: warning:)" "$LOG_FILE" || true)
if [ -n "$CODE_WARNINGS" ]; then
  echo "❌ Error: Release build produced compiler warnings." >&2
  echo "$CODE_WARNINGS" >&2
  exit 1
fi

echo "==> Build passed cleanly with 0 errors and 0 warnings."

BUILT_APP="$BUILD_DIR/Build/Products/Release/Dino.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "❌ Error: Expected build output not found at $BUILT_APP" >&2
  exit 1
fi
echo "==> Successfully verified built artifact at $BUILT_APP."

echo "=========================================================="
echo "  ✅ VERIFICATION PASSED: 0 errors, 0 warnings"
echo "  ✅ Purging build/ & DerivedData, ensuring 0 LaunchServices duplicates"
echo "=========================================================="


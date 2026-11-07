#!/bin/bash
# ==============================================================================
# Nomad Build Verification & Environment Cleanliness Test Script
#
# Compiles Release build with strict zero-warnings/zero-errors enforcement,
# unregisters any temporary build artifacts from macOS LaunchServices,
# and cleans DerivedData to prevent duplicate app registrations.
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

echo "=========================================================="
echo "  Nomad Build Verification & Cleanliness Suite"
echo "=========================================================="

# 1. Compile Release binary with strict zero-warnings and zero-errors flags
echo "==> Compiling Release binary (strict: 0 warnings, 0 errors)..."
LOG_FILE=$(mktemp -t nomad_build_verify.XXXXXX.log)

set +e
xcodebuild -project nomad.xcodeproj \
  -scheme nomad \
  -configuration Release \
  -destination "generic/platform=macOS" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  build > "$LOG_FILE" 2>&1
BUILD_STATUS=$?
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
  echo "❌ Error: Build failed with exit code ${BUILD_STATUS}." >&2
  grep -E "(:[0-9]+:[0-9]+: error:)" "$LOG_FILE" >&2 || tail -n 25 "$LOG_FILE" >&2
  rm -f "$LOG_FILE"
  exit 1
fi

CODE_WARNINGS=$(grep -E "(:[0-9]+:[0-9]+: warning:)" "$LOG_FILE" || true)
if [ -n "$CODE_WARNINGS" ]; then
  echo "❌ Error: Release build produced compiler warnings." >&2
  echo "$CODE_WARNINGS" >&2
  rm -f "$LOG_FILE"
  exit 1
fi
rm -f "$LOG_FILE"

echo "==> Build passed cleanly with 0 errors and 0 warnings."

# 2. Unregister any built nomad.app instances from LaunchServices
echo "==> Unregistering DerivedData and local builds from LaunchServices..."
if [ -x "$LSREGISTER" ]; then
  for app in ~/Library/Developer/Xcode/DerivedData/nomad-*/Build/Products/*/*.app "$PROJECT_ROOT"/build*/*/*.app; do
    if [ -d "$app" ]; then
      "$LSREGISTER" -u "$app" 2>/dev/null || true
    fi
  done
fi

# 3. Clean DerivedData artifacts to prevent Spotlight/Dock duplicates
echo "==> Purging DerivedData cache: ~/Library/Developer/Xcode/DerivedData/nomad-*"
rm -rf ~/Library/Developer/Xcode/DerivedData/nomad-*

echo "=========================================================="
echo "  ✅ VERIFICATION PASSED: 0 errors, 0 warnings"
echo "  ✅ LaunchServices & DerivedData pristine and cleaned"
echo "=========================================================="


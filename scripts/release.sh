#!/bin/bash
# ==============================================================================
# Nomad Automated Release & Homebrew Distribution Script
#
# Usage:
#   ./scripts/release.sh [version]
#
# Examples:
#   ./scripts/release.sh 0.2
#   ./scripts/release.sh 0.1.1
# ==============================================================================

set -euo pipefail

# Ensure script is run from project root
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
TAP_DIR="/Users/tarun/projects/homebrew-tap"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# 1. Version Detection & Determination
CURRENT_VERSION=$(grep 'version "' packaging/homebrew/nomad.rb | head -n1 | sed -E 's/.*version "([^"]+)".*/\1/')

if [ -n "${1:-}" ]; then
  NEW_VERSION="$1"
else
  # Auto-bump minor version (e.g. 0.1 -> 0.2)
  MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
  MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
  NEW_MINOR=$((MINOR + 1))
  NEW_VERSION="${MAJOR}.${NEW_MINOR}"
  echo "==> No version specified. Auto-bumping from ${CURRENT_VERSION} to ${NEW_VERSION}"
fi

echo "=========================================================="
echo "  Nomad Release Pipeline: v${NEW_VERSION}"
echo "  Previous Version:       v${CURRENT_VERSION}"
echo "=========================================================="

# 2. Pre-flight Validation
if [ ! -d "$TAP_DIR/Casks" ]; then
  echo "❌ Error: Homebrew tap directory not found at $TAP_DIR" >&2
  exit 1
fi

if [ ! -f "$TAP_DIR/Casks/nomad.rb" ]; then
  echo "❌ Error: $TAP_DIR/Casks/nomad.rb not found" >&2
  exit 1
fi

# Ensure tap repo is clean
if [ -n "$(cd "$TAP_DIR" && git status --porcelain)" ]; then
  echo "❌ Error: $TAP_DIR has uncommitted changes. Please clean or commit them first." >&2
  exit 1
fi

# 3. Version Update in project.pbxproj, NomadVersion.swift, local packaging, and tap
echo "==> Updating version numbers to ${NEW_VERSION}..."
sed -i '' -E "s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = ${NEW_VERSION};/g" nomad.xcodeproj/project.pbxproj
sed -i '' -E "s/static let version = \"[0-9.]+\"/static let version = \"${NEW_VERSION}\"/g" nomad/Services/NomadVersion.swift
sed -i '' -E "s/version \"[0-9.]+\"/version \"${NEW_VERSION}\"/g" packaging/homebrew/nomad.rb
sed -i '' -E "s/version \"[0-9.]+\"/version \"${NEW_VERSION}\"/g" "$TAP_DIR/Casks/nomad.rb"

# 4. Clean & Build Release via Xcode
echo "==> Compiling Release binary with Xcode..."
BUILD_DIR="$PROJECT_ROOT/build/DerivedData"
rm -rf "$BUILD_DIR"

xcodebuild -project nomad.xcodeproj \
  -scheme nomad \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  MARKETING_VERSION="${NEW_VERSION}" \
  -quiet \
  build

BUILT_APP="$BUILD_DIR/Build/Products/Release/nomad.app"

if [ ! -d "$BUILT_APP" ]; then
  echo "❌ Error: Compilation succeeded but build artifact not found at $BUILT_APP" >&2
  exit 1
fi

# 5. Staging, Metadata Cleanup, and Codesigning
echo "==> Staging and signing application bundle..."
STAGING_DIR="$PROJECT_ROOT/dist/staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$BUILT_APP" "$STAGING_DIR/Nomad.app"

# Strip quarantine and AppleDouble metadata
xattr -cr "$STAGING_DIR/Nomad.app" 2>/dev/null || true

# Codesign bundle with entitlements
codesign --force --deep --sign - --entitlements nomad/nomad.entitlements "$STAGING_DIR/Nomad.app" >/dev/null 2>&1

# 6. Archive Creation with ditto (immune to AppleDouble resource forks)
echo "==> Packaging archive with ditto..."
mkdir -p "$PROJECT_ROOT/dist"
ZIP_PATH="$PROJECT_ROOT/dist/Nomad-${NEW_VERSION}.zip"
rm -f "$ZIP_PATH"

ditto -c -k --keepParent --norsrc "$STAGING_DIR/Nomad.app" "$ZIP_PATH"

# 7. Compute SHA-256 Digest
SHA256=$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)
echo "==> Computed SHA-256: ${SHA256}"

# 8. Unregister and delete uncompressed build artifacts
# Prevents macOS LaunchServices and Spotlight from indexing duplicate Nomad.app instances
echo "==> Unregistering intermediate build artifacts from LaunchServices..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [ -f "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$STAGING_DIR/Nomad.app" 2>/dev/null || true
  "$LSREGISTER" -u "$BUILT_APP" 2>/dev/null || true
  # Also unregister any stray DerivedData builds
  for stray in ~/Library/Developer/Xcode/DerivedData/nomad-*/Build/Products/*/nomad.app; do
    if [ -d "$stray" ]; then
      "$LSREGISTER" -u "$stray" 2>/dev/null || true
    fi
  done
fi
rm -rf "$STAGING_DIR"
rm -rf "$PROJECT_ROOT/build"
rm -rf ~/Library/Developer/Xcode/DerivedData/nomad-*

# 9. Update Checksums in Casks
echo "==> Updating checksum in packaging/homebrew/nomad.rb and tap..."
sed -i '' -E "s/sha256 \"[a-f0-9]{64}\"/sha256 \"${SHA256}\"/g" packaging/homebrew/nomad.rb
sed -i '' -E "s/sha256 \"[a-f0-9]{64}\"/sha256 \"${SHA256}\"/g" "$TAP_DIR/Casks/nomad.rb"

# 10. Commit & Tag in Nomad repository
echo "==> Committing release changes in nomad repository..."
git add .
if git diff --cached --quiet; then
  echo "==> Working directory clean, no new changes to commit in nomad."
else
  git commit -m "release: v${NEW_VERSION}"
fi

if git rev-parse "v${NEW_VERSION}" >/dev/null 2>&1; then
  echo "==> Git tag v${NEW_VERSION} already exists."
else
  git tag -a "v${NEW_VERSION}" -m "Nomad ${NEW_VERSION}"
fi

echo "==> Pushing commits and tags to origin main..."
git push origin main --tags

# 11. Create GitHub Release & Upload Asset via gh CLI
echo "==> Publishing release to GitHub via gh..."
if gh release view "v${NEW_VERSION}" >/dev/null 2>&1; then
  echo "==> Release v${NEW_VERSION} already exists on GitHub. Uploading archive..."
  gh release upload "v${NEW_VERSION}" "$ZIP_PATH" --clobber
else
  echo "==> Creating GitHub release v${NEW_VERSION}..."
  gh release create "v${NEW_VERSION}" "$ZIP_PATH" \
    --title "Nomad ${NEW_VERSION}" \
    --generate-notes
fi

# 12. Commit & Push Homebrew Tap
echo "==> Committing and pushing Homebrew tap update..."
cd "$TAP_DIR"
git add Casks/nomad.rb
git commit -m "nomad: bump to ${NEW_VERSION}"
git push origin main
cd "$PROJECT_ROOT"

# 13. Final Summary
echo ""
echo "=========================================================="
echo "🎉 Nomad v${NEW_VERSION} successfully published and distributed!"
echo "=========================================================="
echo "  Archive:   ${ZIP_PATH}"
echo "  SHA-256:   ${SHA256}"
echo "  Release:   https://github.com/tarunbtw/nomad/releases/tag/v${NEW_VERSION}"
echo "  Homebrew:  Pushed to tarunbtw/homebrew-tap (brew update && brew upgrade nomad)"
echo "=========================================================="
echo ""

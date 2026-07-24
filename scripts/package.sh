#!/usr/bin/env bash
#
# Build a distributable release zip of ClaudeUsageBar.app plus its SHA-256,
# ready to attach to a GitHub Release. Users download it, remove the quarantine
# flag, and run — no build toolchain required on their side.
#
# Usage: scripts/package.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="ClaudeUsageBar"
VERSION="$(cat VERSION 2>/dev/null || echo "1.0.0")"
DIST="$ROOT/dist"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

# Ensure the app bundle is fresh.
"$ROOT/scripts/build-app.sh"

echo "==> Zipping $APP_NAME.app…"
rm -f "$ZIP"
# `ditto` produces a macOS-correct archive that preserves the bundle.
ditto -c -k --sequesterRsrc --keepParent "$DIST/$APP_NAME.app" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
SIZE="$(du -h "$ZIP" | awk '{print $1}')"

echo
echo "==> Release artifact ready:"
echo "    file:   dist/$APP_NAME-$VERSION.zip  ($SIZE)"
echo "    sha256: $SHA"
echo
echo "Attach it to a GitHub Release (tag v$VERSION). Include the SHA-256 above"
echo "so users can verify the download."

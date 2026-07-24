#!/usr/bin/env bash
#
# Build ClaudeUsageBar.app — a self-contained macOS menu bar app bundle.
#
# Compiles the SwiftPM executable in release mode and wraps it in a proper
# .app bundle with an Info.plist marking it as a menu-bar-only accessory
# (LSUIElement), so it shows in the menu bar with no Dock icon.
#
# Usage: scripts/build-app.sh [--open]
#   --open   Launch the app after building.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="ClaudeUsageBar"
BUNDLE_ID="com.claudeusagebar.app"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"

echo "==> Building $APP_NAME (release)…"
swift build -c release --product "$APP_NAME"

echo "==> Assembling $APP_NAME.app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# App icon (generate with: swift scripts/make-icon.swift)
ICON_SRC="$ROOT/Resources/AppIcon.icns"
HAS_ICON=false
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
    HAS_ICON=true
fi

# Read the marketing version from VERSION if present, else default.
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "1.0.0")"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- Accessory app: lives in the menu bar only, no Dock icon. -->
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc code signature so Gatekeeper lets the local build run.
if command -v codesign >/dev/null 2>&1; then
    echo "==> Ad-hoc code signing…"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
        echo "   (codesign skipped — app still runs locally)"
fi

echo "==> Built: $APP_DIR"

if [[ "${1:-}" == "--open" ]]; then
    echo "==> Launching…"
    open "$APP_DIR"
fi

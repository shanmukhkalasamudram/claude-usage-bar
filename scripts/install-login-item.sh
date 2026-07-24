#!/usr/bin/env bash
#
# Register ClaudeUsageBar.app as a macOS Login Item so it starts automatically
# when you log in. Prefers /Applications/ClaudeUsageBar.app, falling back to
# the dist/ build.
#
# Usage:
#   scripts/install-login-item.sh            # add to login items
#   scripts/install-login-item.sh --remove   # remove it

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudeUsageBar"

if [[ -d "/Applications/$APP_NAME.app" ]]; then
    APP_PATH="/Applications/$APP_NAME.app"
elif [[ -d "$ROOT/dist/$APP_NAME.app" ]]; then
    APP_PATH="$ROOT/dist/$APP_NAME.app"
else
    echo "error: $APP_NAME.app not found. Run scripts/build-app.sh first." >&2
    exit 1
fi

if [[ "${1:-}" == "--remove" ]]; then
    osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" 2>/dev/null || true
    echo "==> Removed $APP_NAME from Login Items."
    exit 0
fi

# Remove any stale entry first so we don't create duplicates.
osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" 2>/dev/null || true
osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_PATH\", hidden:true, name:\"$APP_NAME\"}" >/dev/null

echo "==> Added to Login Items: $APP_PATH"
echo "    It will start automatically at your next login."

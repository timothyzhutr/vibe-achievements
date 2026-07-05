#!/bin/bash
# Packages dist/VibeAchievements.app into a distributable disk image at
# dist/VibeAchievements-<version>.dmg (builds the app first).
#
# Usage: Scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="VibeAchievements"
VERSION="0.2.0"
APP_DIR="dist/$APP_NAME.app"
DMG_PATH="dist/$APP_NAME-$VERSION.dmg"

Scripts/make-app.sh

echo "==> Staging dmg contents"
STAGING="$(mktemp -d)"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Vibe Achievements" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null
rm -rf "$STAGING"

echo "==> Done: $DMG_PATH"
echo
echo "Note: the app is ad-hoc signed (no Developer ID / notarization)."
echo "On another Mac, right-click the app and choose Open to pass Gatekeeper."

#!/bin/bash
# Builds the release binary and assembles a double-clickable macOS .app bundle
# at dist/VibeAchievements.app, ad-hoc signed for local use.
#
# Usage: Scripts/make-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="VibeAchievements"
BUNDLE_ID="com.timothyzhutr.vibe-achievements"
VERSION="0.2.0"
PRODUCT="vibe-achievements-app"

echo "==> Building release binary"
swift build -c release --product "$PRODUCT"

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="dist/$APP_NAME.app"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$PRODUCT" "$APP_DIR/Contents/MacOS/$APP_NAME"

# SwiftPM resource bundles (achievement contracts, app logo). Bundle.module
# resolves them via Bundle.main.resourceURL at runtime.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

# Best-effort app icon from the bundled SVG logo (safe to fail: the app is a
# menu bar accessory, so the icon only shows in Finder).
ICON_SRC="Sources/vibe-achievements-app/Resources/VibeAchievementsLogo.svg"
if [ -f "$ICON_SRC" ]; then
    ICON_TMP="$(mktemp -d)"
    if qlmanage -t -s 1024 -o "$ICON_TMP" "$ICON_SRC" >/dev/null 2>&1 \
        && [ -f "$ICON_TMP/$(basename "$ICON_SRC").png" ]; then
        ICONSET="$ICON_TMP/AppIcon.iconset"
        mkdir -p "$ICONSET"
        BASE_PNG="$ICON_TMP/$(basename "$ICON_SRC").png"
        for size in 16 32 128 256 512; do
            sips -z $size $size "$BASE_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
            sips -z $((size * 2)) $((size * 2)) "$BASE_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
        done
        if iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null; then
            ICON_PLIST_ENTRY="<key>CFBundleIconFile</key><string>AppIcon</string>"
        fi
    fi
    rm -rf "$ICON_TMP"
fi

echo "==> Writing Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Vibe Achievements</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    ${ICON_PLIST_ENTRY:-}
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "==> Done: $APP_DIR"

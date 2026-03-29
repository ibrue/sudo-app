#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Sudo"
BUNDLE_ID="supply.sudo.app"
VERSION="1.0.0"

echo "[sudo] Building $APP_NAME v$VERSION..."
cd "$SCRIPT_DIR/Sudo"

swift build -c release 2>&1

BINARY=".build/release/Sudo"

if [ ! -f "$BINARY" ]; then
    echo "[sudo] Build failed."
    exit 1
fi

echo "[sudo] Creating app bundle..."

APP_DIR="$SCRIPT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BINARY" "$MACOS/$APP_NAME"

# Generate app icon (.icns) from SVG
echo "[sudo] Generating app icon..."
ICON_SVG="$SCRIPT_DIR/Sudo/AppIcon.svg"
ICON_TMP="$SCRIPT_DIR/Sudo/.build/icon_tmp"
ICONSET="$ICON_TMP/AppIcon.iconset"
rm -rf "$ICON_TMP"
mkdir -p "$ICONSET"

# Render SVG to 1024x1024 PNG (sips can convert from SVG on macOS)
sips -s format png -z 1024 1024 "$ICON_SVG" --out "$ICON_TMP/icon_1024.png" >/dev/null 2>&1

# Generate all required icon sizes
for SIZE in 16 32 128 256 512; do
    sips -z $SIZE $SIZE "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null 2>&1
    DOUBLE=$((SIZE * 2))
    sips -z $DOUBLE $DOUBLE "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null 2>&1
done

# Create .icns and copy to Resources
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
rm -rf "$ICON_TMP"
echo "[sudo] App icon created."

# Create Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>[sudo]</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo ""
echo "[sudo] Build successful: $APP_DIR"
echo "[sudo] To install: cp -r '$APP_DIR' /Applications/"
echo "[sudo] To create DMG: ./create-dmg.sh"

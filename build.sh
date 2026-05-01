#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Sudo"
BUNDLE_ID="supply.sudo.app"
# Read version from Swift source of truth
VERSION=$(grep 'static let currentVersion' "$SCRIPT_DIR/Sudo/Sources/Sudo/Services/OTAUpdater.swift" | sed 's/.*"\(.*\)".*/\1/')
if [ -z "$VERSION" ]; then VERSION="1.0.0"; fi

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

# Generate and copy app icon
cd "$SCRIPT_DIR/Sudo"
bash generate-icon.sh
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$RESOURCES/AppIcon.icns"
    echo "[sudo] App icon copied"
fi
cd "$SCRIPT_DIR"

# ----------------------------------------------------------------------------
# Optional: bundle the CircuitPython UF2 to skip the runtime download.
#
# `code.py` is embedded as a Swift string constant inside the app — no
# bundling needed for it, the source of truth lives in
# Sudo/Sources/Sudo/Services/FirmwareFlasher.swift (kept in sync with
# sudo-supply/hardware/firmware/code.py).
#
# `circuitpython-pico.uf2` — optional override. If missing, the app
# downloads it from downloads.circuitpython.org on first flash and caches it.
# ----------------------------------------------------------------------------
echo ""
CP_UF2="${SUDO_CIRCUITPYTHON_UF2:-}"
if [ -n "$CP_UF2" ] && [ -f "$CP_UF2" ]; then
    cp "$CP_UF2" "$RESOURCES/circuitpython-pico.uf2"
    echo "[sudo] Bundled CircuitPython ($(du -h "$RESOURCES/circuitpython-pico.uf2" | cut -f1))"
else
    echo "[sudo] CircuitPython UF2 not bundled — app will download on first flash"
fi

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
    <key>NSAppleEventsUsageDescription</key>
    <string>Sudo needs Automation permission to send keyboard shortcuts (like Cmd+R) to apps when using simple mode presets.</string>
</dict>
</plist>
PLIST

echo ""
echo "[sudo] Code signing..."
codesign --force --deep --sign - "$APP_DIR"
echo "[sudo] Signed (ad-hoc)"

# Reset TCC entries so macOS re-trusts the new binary
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null || true
echo "[sudo] Reset accessibility + automation trust (re-grant in settings)"

echo ""
echo "[sudo] Build successful: $APP_DIR"
echo "[sudo] To install: rm -rf /Applications/Sudo.app && cp -r '$APP_DIR' /Applications/"
echo "[sudo] To create DMG: ./create-dmg.sh"

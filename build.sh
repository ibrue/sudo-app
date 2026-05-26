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
# Bundle pad firmware and the pinned CircuitPython UF2.
#
# `Sudo/Resources/Firmware/pad` is the source of truth for files written
# to CIRCUITPY. Keep those files visible in the bundle so the app never
# flashes stale Swift-embedded firmware.
#
# `circuitpython-pico-9.2.1.uf2` is bundled for offline first-time flash.
# If it is missing locally, build.sh downloads the pinned file.
# ----------------------------------------------------------------------------
echo ""
FIRMWARE_SRC="$SCRIPT_DIR/Sudo/Resources/Firmware"
FIRMWARE_DST="$RESOURCES/Firmware"
mkdir -p "$FIRMWARE_DST"
if [ -d "$FIRMWARE_SRC/pad" ]; then
    cp -R "$FIRMWARE_SRC/pad" "$FIRMWARE_DST/pad"
    echo "[sudo] Bundled pad firmware"
else
    echo "[sudo] ERROR: missing $FIRMWARE_SRC/pad"
    exit 1
fi

CP_VERSION="9.2.1"
CP_UF2="${SUDO_CIRCUITPYTHON_UF2:-$FIRMWARE_SRC/circuitpython-pico-$CP_VERSION.uf2}"
if [ ! -f "$CP_UF2" ]; then
    mkdir -p "$FIRMWARE_SRC"
    CP_UF2="$FIRMWARE_SRC/circuitpython-pico-$CP_VERSION.uf2"
    echo "[sudo] Downloading CircuitPython $CP_VERSION for offline flashing..."
    curl -L --fail \
        "https://downloads.circuitpython.org/bin/raspberry_pi_pico/en_US/adafruit-circuitpython-raspberry_pi_pico-en_US-$CP_VERSION.uf2" \
        -o "$CP_UF2"
fi
cp "$CP_UF2" "$FIRMWARE_DST/circuitpython-pico-$CP_VERSION.uf2"
echo "[sudo] Bundled CircuitPython ($(du -h "$FIRMWARE_DST/circuitpython-pico-$CP_VERSION.uf2" | cut -f1))"

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
SIGN_IDENTITY="${SUDO_CODESIGN_IDENTITY:--}"
SIGN_REQUIREMENT="=designated => identifier \"$BUNDLE_ID\""
codesign --force --deep --sign "$SIGN_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --requirements "$SIGN_REQUIREMENT" \
    "$APP_DIR"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "[sudo] Signed (stable ad-hoc requirement for $BUNDLE_ID)"
else
    echo "[sudo] Signed ($SIGN_IDENTITY)"
fi

# Do not reset TCC by default. Sudo is signed with a stable designated
# requirement so iterative rebuilds can keep matching the user's existing
# Accessibility grant. Set SUDO_RESET_TCC=1 when you intentionally need a
# clean permission prompt.
if [ "${SUDO_RESET_TCC:-0}" = "1" ]; then
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset ListenEvent   "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset PostEvent     "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset AppleEvents   "$BUNDLE_ID" 2>/dev/null || true
    echo "[sudo] Reset accessibility + input-monitoring + automation trust (re-grant in settings)"
fi

echo ""
echo "[sudo] Build successful: $APP_DIR"
echo "[sudo] To install: rm -rf /Applications/Sudo.app && cp -r '$APP_DIR' /Applications/"
echo "[sudo] To create DMG: ./create-dmg.sh"

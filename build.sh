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
# Bundle the RP2040 firmware UF2 so the app can flash a blank board with one
# click. We look in three places, in order:
#   1. $SUDO_FIRMWARE_UF2  — explicit override
#   2. ../sudo-supply/hardware/firmware/build/sudo_firmware.uf2  — already built
#   3. ../sudo-supply/hardware/firmware/  — try to build it via cmake (needs
#      $PICO_SDK_PATH set; we fail soft and continue without firmware if not)
#
# If we end up with no firmware UF2, the app still builds — it just shows a
# clear "drop sudo-firmware.uf2 into ~/Library/Application Support/Sudo/Firmware/"
# error if the user clicks flash. This keeps the build working on machines
# that don't have the embedded toolchain installed.
# ----------------------------------------------------------------------------
echo ""
echo "[sudo] Locating firmware UF2..."
FIRMWARE_UF2=""
if [ -n "${SUDO_FIRMWARE_UF2:-}" ] && [ -f "$SUDO_FIRMWARE_UF2" ]; then
    FIRMWARE_UF2="$SUDO_FIRMWARE_UF2"
    echo "[sudo] Using firmware from \$SUDO_FIRMWARE_UF2: $FIRMWARE_UF2"
else
    SUPPLY_FW_DIR="$SCRIPT_DIR/../sudo-supply/hardware/firmware"
    PREBUILT="$SUPPLY_FW_DIR/build/sudo_firmware.uf2"
    if [ -f "$PREBUILT" ]; then
        FIRMWARE_UF2="$PREBUILT"
        echo "[sudo] Using prebuilt firmware: $FIRMWARE_UF2"
    elif [ -d "$SUPPLY_FW_DIR" ] && [ -n "${PICO_SDK_PATH:-}" ] && command -v cmake >/dev/null 2>&1; then
        echo "[sudo] Building firmware via cmake (PICO_SDK_PATH=$PICO_SDK_PATH)..."
        (
            cd "$SUPPLY_FW_DIR"
            mkdir -p build
            cd build
            cmake .. >/dev/null 2>&1
            make -j sudo_firmware >/dev/null 2>&1
        ) && [ -f "$PREBUILT" ] && FIRMWARE_UF2="$PREBUILT"
        if [ -n "$FIRMWARE_UF2" ]; then
            echo "[sudo] Firmware built: $FIRMWARE_UF2"
        else
            echo "[sudo] WARN: firmware build failed — bundling without UF2"
        fi
    fi
fi

if [ -n "$FIRMWARE_UF2" ]; then
    cp "$FIRMWARE_UF2" "$RESOURCES/sudo-firmware.uf2"
    echo "[sudo] Firmware bundled: $(du -h "$RESOURCES/sudo-firmware.uf2" | cut -f1)"
else
    echo "[sudo] WARN: no firmware UF2 bundled. Flash button will show a clear error."
    echo "[sudo]       To bundle one, either:"
    echo "[sudo]         - clone ibrue/sudo-supply as a sibling and set PICO_SDK_PATH"
    echo "[sudo]         - export SUDO_FIRMWARE_UF2=/path/to/sudo-firmware.uf2"
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

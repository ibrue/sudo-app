#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Sudo"
VERSION="1.0.0"
DMG_NAME="Sudo-${VERSION}-macOS"
APP_PATH="$SCRIPT_DIR/dist/$APP_NAME.app"
DMG_DIR="$SCRIPT_DIR/dist/dmg"
DMG_OUTPUT="$SCRIPT_DIR/dist/$DMG_NAME.dmg"

if [ ! -d "$APP_PATH" ]; then
    echo "[sudo] App bundle not found. Run ./build.sh first."
    exit 1
fi

echo "[sudo] Creating DMG installer..."

# Clean up
rm -rf "$DMG_DIR" "$DMG_OUTPUT"
mkdir -p "$DMG_DIR"

# Copy app to DMG staging
cp -R "$APP_PATH" "$DMG_DIR/"

# Create symlink to /Applications for drag-and-drop install
ln -s /Applications "$DMG_DIR/Applications"

# Create a background readme
cat > "$DMG_DIR/.background_readme" << 'EOF'
Drag [sudo] to Applications to install.
EOF

# Create the DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUTPUT"

# Clean up staging
rm -rf "$DMG_DIR"

echo ""
echo "[sudo] DMG created: $DMG_OUTPUT"
echo "[sudo] Size: $(du -h "$DMG_OUTPUT" | cut -f1)"
echo ""
echo "[sudo] To distribute:"
echo "  1. Upload to GitHub Releases as v$VERSION"
echo "  2. The OTA updater will find it automatically"

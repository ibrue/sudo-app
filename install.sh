#!/bin/bash
set -euo pipefail

APP_NAME="Sudo"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  ┌─────────────────────────────────┐"
echo "  │  [sudo] installer               │"
echo "  │  macro pad companion app        │"
echo "  └─────────────────────────────────┘"
echo ""

# Check if app bundle exists, if not build it
if [ ! -d "$SCRIPT_DIR/dist/$APP_NAME.app" ]; then
    echo "[sudo] App not built yet. Building..."
    "$SCRIPT_DIR/build.sh"
fi

APP_PATH="$SCRIPT_DIR/dist/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

# Check if already installed
if [ -d "$INSTALL_PATH" ]; then
    echo "[sudo] Existing installation found. Replacing..."
    # Kill running instance
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_PATH"
fi

echo "[sudo] Installing to /Applications..."
cp -R "$APP_PATH" "$INSTALL_PATH"

echo "[sudo] Setting permissions..."
chmod -R 755 "$INSTALL_PATH"
xattr -cr "$INSTALL_PATH" 2>/dev/null || true

echo ""
echo "[sudo] Installation complete!"
echo ""
echo "[sudo] Next steps:"
echo "  1. Open $APP_NAME from /Applications or Spotlight"
echo "  2. Grant Accessibility permission when prompted"
echo "     System Settings → Privacy & Security → Accessibility"
echo "  3. Plug in your sudo macro pad"
echo "  4. Open Claude, ChatGPT, or Grok"
echo "  5. Press a button on the macro pad"
echo ""

# Offer to launch
read -p "[sudo] Launch now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "[sudo] Launching..."
    open "$INSTALL_PATH"
fi

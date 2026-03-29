#!/usr/bin/env bash
#
# [sudo] Macro Pad Companion - Linux Installation Script
#
# Installs system dependencies, Python packages, desktop entry,
# and optionally creates a systemd user service for autostart.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="sudo-app"
CONFIG_DIR="$HOME/.config/sudo"
DESKTOP_DIR="$HOME/.local/share/applications"
SYSTEMD_DIR="$HOME/.config/systemd/user"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[sudo]${NC} $*"; }
warn()  { echo -e "${YELLOW}[sudo]${NC} $*"; }
error() { echo -e "${RED}[sudo]${NC} $*"; }

# ---------- System dependencies ----------

info "Checking system dependencies..."

PACKAGES=(
    python3
    python3-pip
    python3-gi
    python3-gi-cairo
    gir1.2-appindicator3-0.1
    gir1.2-atspi-2.0
    tesseract-ocr
    xdotool
)

MISSING=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    info "Installing missing packages: ${MISSING[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${MISSING[@]}"
else
    info "All system packages are installed."
fi

# ---------- Python dependencies ----------

info "Installing Python packages..."
pip3 install --user -q -r "$SCRIPT_DIR/requirements.txt" 2>/dev/null || {
    warn "pip install with --user failed, trying without..."
    pip3 install -q -r "$SCRIPT_DIR/requirements.txt"
}

# ---------- Config directory ----------

info "Creating config directory at $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

# ---------- Desktop entry ----------

info "Installing desktop entry..."
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/sudo.desktop" << EOF
[Desktop Entry]
Name=[sudo]
Comment=Macro pad companion for AI agents
Exec=python3 $SCRIPT_DIR/sudo_app.py
Icon=$SCRIPT_DIR/views/icon.py
Type=Application
Categories=Utility;
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF

chmod +x "$DESKTOP_DIR/sudo.desktop"
info "Desktop entry installed at $DESKTOP_DIR/sudo.desktop"

# ---------- Systemd user service (optional) ----------

echo ""
read -rp "$(echo -e "${GREEN}[sudo]${NC} Create systemd user service for autostart? [y/N]: ")" CREATE_SERVICE

if [[ "$CREATE_SERVICE" =~ ^[Yy]$ ]]; then
    mkdir -p "$SYSTEMD_DIR"

    cat > "$SYSTEMD_DIR/sudo-app.service" << EOF
[Unit]
Description=[sudo] Macro Pad Companion
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $SCRIPT_DIR/sudo_app.py
Restart=on-failure
RestartSec=5
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable sudo-app.service
    info "Systemd user service created and enabled."
    info "Start now with: systemctl --user start sudo-app.service"
    info "View logs with: journalctl --user -u sudo-app.service -f"
else
    info "Skipping systemd service creation."
fi

# ---------- Done ----------

echo ""
info "Installation complete!"
info ""
info "To run manually:  python3 $SCRIPT_DIR/sudo_app.py"
info "To run at login:  Copy $DESKTOP_DIR/sudo.desktop to ~/.config/autostart/"
info "Config stored at: $CONFIG_DIR/config.json"
echo ""

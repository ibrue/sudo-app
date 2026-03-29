# [sudo] — Cross-Platform Macro Pad Companion

Companion app for the [sudo macro pad](https://sudo.supply). Translates physical button presses into AI agent actions across **macOS**, **Windows**, and **Linux**.

## Install

### macOS
```bash
./install.sh
# or build manually:
./build.sh              # builds Sudo.app in dist/
./create-dmg.sh         # creates Sudo-1.0.0-macOS.dmg
```
Or download from [sudo.supply/download](https://sudo.supply/download) or [GitHub Releases](https://github.com/ibrue/sudo-app/releases).

### Windows
```bash
cd SudoWindows
build.bat               # builds publish/SudoWindows.exe
```
Requires [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0). Output is a self-contained single-file exe.

### Linux
```bash
cd SudoLinux
./install.sh            # installs deps, desktop entry, optional systemd autostart
python3 sudo_app.py     # run manually
```
Installs via apt: `python3-gi`, `gir1.2-appindicator3-0.1`, `gir1.2-atspi-2.0`, `tesseract-ocr`, `xdotool`.

## How it works

1. **Listen** — Intercepts configurable hotkeys (default `Ctrl+Shift+F13–F16`) from the macro pad
2. **Detect** — Identifies frontmost AI app (Claude, ChatGPT, Grok) via native app detection or browser tab matching
3. **Find** — Locates buttons via accessibility tree (primary) + OCR (fallback)
4. **Act** — Presses button via platform accessibility API — no synthetic input, anti-cheat safe

| Step | macOS | Windows | Linux |
|------|-------|---------|-------|
| Hotkeys | CGEvent tap | RegisterHotKey | pynput |
| Detection | Bundle ID + browser title | Process name + window title | xdotool + /proc |
| Button finding | AXUIElement tree | UI Automation tree | AT-SPI2 tree |
| OCR fallback | Apple Vision | Windows.Media.Ocr | Tesseract |
| Execution | AXPress | InvokePattern | AT-SPI Action / xdotool |

## Button mapping

| Button | Default Hotkey | Action |
|--------|----------------|--------|
| 1 | `Ctrl+Shift+F13` | Approve / Yes |
| 2 | `Ctrl+Shift+F14` | Reject / No |
| 3 | `Ctrl+Shift+F15` | Action 3 |
| 4 | `Ctrl+Shift+F16` | Action 4 |

All hotkeys are fully configurable in the app settings.

## Customizable key bindings

Each button can operate in two modes:

- **Simple mode** — Triggers a preset system shortcut (screenshot, copy, paste, undo, save, lock screen, etc.)
- **Complex mode** — Searches for UI buttons by text (the original AI agent approve/reject flow)

Both the trigger hotkeys and the button actions are fully configurable through the settings UI.

## QMK / VIA / Vial firmware

The `firmware/` directory contains everything needed to build and flash the RP2040 macro pad:

```bash
# Stock QMK
qmk compile -kb sudo_pad -km default    # hardcoded Ctrl+Shift+F13-F16
qmk compile -kb sudo_pad -km via        # VIA-enabled (live reconfiguration)

# Vial QMK fork
qmk compile -kb sudo_pad -km vial       # Vial-enabled (auto-detection)
```

| Feature | VIA | Vial |
|---------|-----|------|
| Draft definition needed | Yes (`firmware/via/sudo_pad.json`) | No (embedded in firmware) |
| Auto-detection | No | Yes |
| QMK fork required | No | Yes (vial-qmk) |
| Web app | [usevia.app](https://usevia.app) | [vial.rocks](https://vial.rocks) |

See [`firmware/README.md`](firmware/README.md) for detailed build, flash, and setup instructions.

## Supported AI apps

- **Native**: Claude for Desktop, ChatGPT
- **Web** (via browser detection): claude.ai, chatgpt.com, grok.com
- **Browsers**: Safari (macOS), Chrome, Firefox, Brave, Edge, Opera, Chromium

## Requirements

### macOS
- macOS 13 Ventura or later
- Accessibility permission (System Settings → Privacy & Security → Accessibility)
- Screen Recording permission (for OCR fallback)

### Windows
- Windows 10 1809+ (for OCR)
- .NET 8 runtime (bundled in self-contained build)

### Linux
- Python 3.9+
- GTK 3, AppIndicator3, AT-SPI2
- Tesseract OCR, xdotool

## OTA Updates (macOS)

The macOS app checks GitHub Releases every 4 hours. When an update is found, click "Install Update" in the menu bar popover.

## Project structure

```
sudo-app/
├── Sudo/                    # macOS app (Swift, SwiftUI)
│   ├── Sources/Sudo/
│   │   ├── Models/          # PadAction, SimpleAction, ButtonMode, HotkeyConfig
│   │   ├── Services/        # Engine, HotkeyListener, AXButtonFinder, OCR, Config
│   │   └── Views/           # MenuBarView, ButtonConfigView
│   └── AppIcon.svg
├── SudoWindows/             # Windows app (C#, .NET 8, WinForms)
│   ├── Models/              # PadAction, SimpleAction, ButtonMode, HotkeyConfig
│   ├── Services/            # Engine, HotkeyListener, UIAutomation, OCR, Config
│   └── Views/               # TrayApp, ConfigForm
├── SudoLinux/               # Linux app (Python 3, GTK3)
│   ├── models/              # pad_action, simple_action, button_mode, hotkey_config
│   ├── services/            # engine, hotkey_listener, atspi, ocr, config
│   └── views/               # tray_app, config_window, icon
├── firmware/                # QMK/VIA/Vial firmware for RP2040
│   ├── qmk/keyboards/sudo_pad/
│   └── via/sudo_pad.json
├── build.sh                 # macOS build script
├── install.sh               # macOS install script
└── create-dmg.sh            # macOS DMG creator
```

## Anti-cheat compatibility

All platforms use official accessibility APIs — the same interfaces used by screen readers and OS automation tools. No HID injection, no memory patching, no kernel extensions.

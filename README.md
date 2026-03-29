# [sudo] — macOS Companion App

Menu bar daemon for the [sudo macro pad](https://sudo.supply). Translates physical button presses into AI agent actions.

## Install

**Quick install (from source):**
```bash
cd sudopad-app
./install.sh
```

**Or build manually:**
```bash
cd sudopad-app
./build.sh              # builds Sudo.app in dist/
./create-dmg.sh         # creates Sudo-1.0.0-macOS.dmg
```

**Or download** from [sudo.supply/download](https://sudo.supply/download) or [GitHub Releases](https://github.com/ibrue/sudo-app/releases).

## How it works

1. **Listen** — Intercepts `Ctrl+Shift+F13–F16` from the RP2040 macro pad
2. **Detect** — Identifies frontmost AI app (Claude, ChatGPT, Grok) via bundle ID or browser tab
3. **Find** — Locates approve/reject buttons via AX accessibility tree (primary) + Vision OCR (fallback)
4. **Act** — Presses button via `AXUIElement.performAction` — no synthetic input, anti-cheat safe

## Button mapping

| Button | Hotkey | Action |
|--------|--------|--------|
| 1 | `Ctrl+Shift+F13` | Approve / Yes |
| 2 | `Ctrl+Shift+F14` | Reject / No |
| 3 | `Ctrl+Shift+F15` | Action 3 |
| 4 | `Ctrl+Shift+F16` | Action 4 |

## Requirements

- macOS 13 Ventura or later
- Accessibility permission (System Settings → Privacy & Security → Accessibility)
- Screen Recording permission (for OCR fallback)

## OTA Updates

The app checks GitHub Releases every 4 hours for new versions. When an update is found, it shows a banner in the menu bar popover. Click "Install Update" to download and install automatically.

To push an update:
1. Bump the version in `OTAUpdater.swift` and `build.sh`
2. Run `./build.sh && ./create-dmg.sh`
3. Create a GitHub Release tagged `v1.x.x` with the DMG attached

## Anti-cheat compatibility

Uses the official macOS Accessibility API — same interface as VoiceOver and Shortcuts.app. No HID injection, no memory patching, no kernel extensions.

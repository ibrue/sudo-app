# [sudo] — macOS Companion App

Menu bar daemon for the [sudo macro pad](https://sudo.supply). Translates physical button presses into AI agent actions.

## Button Layout

Physical device, bottom to top:

| # | Color | Hotkey | Default Action |
|---|-------|--------|----------------|
| 1 (bottom) | Green | `Ctrl+Shift+F13` | Approve / Yes |
| 2 | Yellow | `Ctrl+Shift+F15` | Make it better |
| 3 | Red | `Ctrl+Shift+F14` | Reject / No |
| 4 (top) | Black | `Ctrl+Shift+F16` | YOLO (allow all) |

All buttons are fully remappable with custom search terms, keyboard shortcuts, or macro sequences.

## Install

**Quick install (from source):**
```bash
cd sudo-app
./install.sh
```

**Or build manually:**
```bash
cd sudo-app
./build.sh              # builds Sudo.app in dist/
./create-dmg.sh         # creates Sudo-1.0.0-macOS.dmg
```

**Or download** from [sudo.supply/download](https://sudo.supply/download) or [GitHub Releases](https://github.com/ibrue/sudo-app/releases).

## How it works

1. **Listen** — Intercepts `Ctrl+Shift+F13–F16` from the RP2040 macro pad
2. **Detect** — Identifies frontmost AI app via bundle ID or browser tab
3. **Find** — Locates buttons via 3-strategy pipeline: AX accessibility tree → Vision OCR → keyboard fallback
4. **Act** — Presses button via `AXUIElement.performAction` — no synthetic input, anti-cheat safe

## Supported Apps

| Category | Apps |
|----------|------|
| Native AI | Claude for Desktop, ChatGPT |
| Editors | VS Code, VS Code Insiders, Cursor, VSCodium, Windsurf |
| Terminals | Terminal.app, iTerm2, Warp, Ghostty, Kitty, Alacritty |
| Web (via browser) | claude.ai, chatgpt.com, grok.com |
| Browsers | Safari, Chrome, Firefox, Brave, Edge, Arc, Opera |

Editors and terminals are detected as AI apps when running agents like Claude Code, Cline, or GitHub Copilot.

## Quick Presets

| Preset | Description |
|--------|-------------|
| AI Agent | Approve / reject / make it better / YOLO for AI permission prompts |
| Plan Mode | Plan-oriented actions for AI coding agents |
| Claude Code | Optimized for Claude Code terminal workflows |
| System Shortcuts | Screenshot, copy, paste, undo, save, lock screen |
| Media Controls | Play/pause, next, previous, volume |
| Web Browsing | Tab navigation, back, forward, refresh |
| Discord Soundboard | Trigger soundboard clips |

## Features

### Menu Bar Daemon
- `[sudo]` label with animated loading `[····]`, success `[okay]`, failure `[fail]`
- Launch at login via SMAppService
- Sound feedback (configurable)
- Bug reporting from menu bar

### AI Detection & Button Finding
- 3-strategy pipeline: AX accessibility tree → Vision OCR → keyboard fallback
- Per-app profiles with auto-switching
- Button remapping with custom search terms
- Context preview (shows what the AI wants to do)
- Debounce at 100ms (spammable)

### Action Modes
- AI search (default) — find and press buttons in AI apps
- Keyboard shortcuts — send arbitrary key combos
- Media keys — play/pause, next, previous, volume
- Macro sequences — chain multiple actions with configurable delays

### Automation
- Auto-approve rules engine with safety exclusions
- Action history log (last 50 actions)
- Auto-retry permission checker (re-checks every 3s, no restart needed)

### Developer API
Local HTTP API on port 7483:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/status` | GET | App status and current configuration |
| `/press/:button` | POST | Simulate a button press (1–4) |
| `/config` | GET | Current button mappings |
| `/config` | PUT | Update button mappings |
| `/webhooks` | POST | Register a webhook URL |
| `/webhooks` | DELETE | Remove a webhook |
| `/history` | GET | Last 50 actions |

Webhooks notify on every button press with JSON payload.

### MCP Server Mode
POST `/mcp/request-approval` blocks until a physical button is pressed. Integrates with any MCP-compatible AI agent to gate tool use behind hardware approval.

### Plugin System
Drop `.json` plugin files in `~/Library/Application Support/Sudo/Plugins/` to extend functionality. Plugins can define custom button actions, search terms, and automation rules.

### Hardware Integration
- Visual device layout in settings matching physical button colors (green, yellow, red, black)
- LED feedback protocol for RP2040 USB serial

### Gamification & Telemetry
- Usage streaks (approves/rejects/day streak)
- Anonymous telemetry (opt-in) with public analytics dashboard
- OTA updates from GitHub Releases

### Developer Workflow
- Pull & Rebuild button + embedded terminal for dev workflow

## Testing without hardware

The app includes a built-in test panel (click `> test panel` in the menu bar popover):

- **F13–F16 buttons** — simulate macro pad key presses
- **Test window** — opens a fake AI permission prompt with Allow/Deny buttons for testing the accessibility tree detection

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

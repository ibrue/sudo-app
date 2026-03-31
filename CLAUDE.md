# sudo-app — development context

## Style Guide

### Text & Typography
- **All UI text is lowercase** — menu bar labels, status text, section headers, button labels
- Menu bar states: `[sudo]`, `[ ok ]`, `[fail]`, `[·___]`
- Section headers use `> ` prefix: `> button map`, `> settings`, `> history`
- Toggles use bracket checkboxes: `[x]` / `[ ]`
- Terminal aesthetic: monospace everywhere, no serif/sans-serif
- No emojis except `✓` (success) and `✗` (failure) in the action log

### Colors (from design tokens)
- Background: `#0a0a0a`
- Accent (green): `#00ff41`
- Text: `#f0f0f0`
- Muted text: `#666666`
- Border: `#1e1e1e`
- Error (red): `#ff3333`
- Surface: `#333333`

### Layout
- Menu bar popover: fixed 320pt width
- Sharp corners everywhere (borderRadius = 0)
- 1px borders
- Consistent padding: 16px horizontal, 10px vertical per section
- Sections separated by 1px divider lines

### Code Conventions
- Swift, SwiftUI, macOS 13+
- `SudoTheme.*` for all colors, fonts, spacing
- `SudoSettings.shared` singleton for persisted preferences
- All user preferences stored in UserDefaults
- Background work on `DispatchQueue.global(qos: .userInitiated)`
- UI updates always on `DispatchQueue.main`

## Architecture
- `SudoEngine` — central orchestrator, owns detection → execution pipeline
- `AppDetector` — identifies frontmost app via bundle ID or browser tab
- `AXButtonFinder` — walks accessibility tree to find buttons (primary)
- `OCRButtonFinder` — Vision framework screenshot OCR (fallback)
- `ActionExecutor` — presses buttons via AXPress or CGEvent click
- `HotkeyListener` — CGEvent tap for Ctrl+Shift+F13–F16
- `LocalAPIServer` — HTTP API on port 7483
- `SudoTelemetry` — anonymous usage tracking
- `SudoSettings` — persisted preferences singleton
- `PadAction` — enum mapping buttons to actions, uses settings for display names / search terms
- `ButtonPreset` — quick-apply configurations

## Build
```bash
./build.sh                    # builds to dist/Sudo.app
cp -r dist/Sudo.app /Applications/
```
Version is read from `OTAUpdater.currentVersion` (single source of truth).

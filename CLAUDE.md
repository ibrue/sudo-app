# sudo-app — development context

## Style Guide

### Text & Typography
- **All UI text is lowercase** — menu bar labels, status text, section headers, button labels, footer buttons
- Menu bar states: `[sudo]`, `[ ok ]`, `[fail]`, `[·___]` — always 6 chars total
- Section headers use `> ` prefix: `> button map`, `> settings`, `> history`
- Toggles use bracket checkboxes: `[x]` / `[ ]`
- Terminal aesthetic: monospace everywhere, no serif/sans-serif
- No emojis except `✓` (success) and `✗` (failure) in the action log
- Button display names are stored lowercase: "approve / yes", "reject / no"
- Never use `action.displayName` directly in UI — it's already lowercase from settings

### Button Identity
- Physical buttons are numbered 1-4 (bottom to top): green, yellow, red, black
- Users see button numbers (1-4), NOT F-key numbers (F13-F16)
- F-keys are internal hotkey details — only shown in settings > hotkey bindings
- Color stripes (3px on left) represent physical button colors in all UI

### Colors (from design tokens, must match website)
- Background: `#0a0a0a` (SudoTheme.bg)
- Background secondary: `#111111` (SudoTheme.bgSecondary)
- Accent (green): `#00ff41` (SudoTheme.accent)
- Text: `#f0f0f0` (SudoTheme.text)
- Muted text: `#666666` (SudoTheme.textMuted)
- Border: `#1e1e1e` (SudoTheme.border)
- Error (red): `#ff3333` (SudoTheme.error)
- Surface: `#333333` (SudoTheme.surface)
- Button colors: green `#6abf73`, yellow `#d4b85c`, red `#c85c5c`, black `#2a2a2a`

### Layout
- Menu bar popover: fixed 320pt width
- Sharp corners everywhere (borderRadius = 0)
- 1px borders, no rounded corners
- Consistent padding: 16px horizontal, 10px vertical per section
- Sections separated by 1px divider lines
- No heavy colored backgrounds — use thin color stripes instead
- Developer features (terminal, pull & rebuild) hidden when not in dev mode

### Code Conventions
- Swift, SwiftUI, macOS 13+
- `SudoTheme.*` for all colors, fonts, spacing — never hardcode hex in views
- `SudoSettings.shared` singleton for persisted preferences
- All user preferences stored in UserDefaults
- Background work on `DispatchQueue.global(qos: .userInitiated)`
- UI updates always on `DispatchQueue.main`
- Hotkey listener dispatches to background queue, never main
- Use `as?` not `as!` for AX element casts (can crash)
- `Color(hex:)` extension lives in Theme.swift

## Architecture
- `SudoEngine` — central orchestrator, owns detection → execution pipeline
- `AppDetector` — identifies frontmost app via bundle ID or browser tab
- `AXButtonFinder` — walks accessibility tree to find buttons (primary, 30-level depth)
- `OCRButtonFinder` — Vision framework screenshot OCR (fallback)
- `ActionExecutor` — presses buttons via AXPress or CGEvent click (with center-click fallback)
- `HotkeyListener` — configurable CGEvent tap (default: Ctrl+Shift+F13–F16)
- `LocalAPIServer` — HTTP API on port 7483 + MCP server endpoints
- `WebhookManager` — fires POST to user-configured URL on each action
- `SudoTelemetry` — anonymous usage tracking (button number + mode, no action names)
- `BugReporter` — collects diagnostics and POSTs to sudo.supply/api/bugs
- `SudoSettings` — persisted preferences singleton (UserDefaults)
- `PadAction` — enum mapping 4 buttons to actions, delegates to settings for display names / search terms
- `ButtonPreset` — quick-apply configurations with 3 modes: aiSearch, keyCombo, mediaKey
- `MacroSequence` — chained actions with delays, assignable to buttons
- `AutoApproveRule` — rules engine for automatic approval with safety exclusions
- `RulesEngine` — evaluates auto-approve rules against app + context
- `PadCommunicator` — USB serial to RP2040 for LED feedback
- `PluginManager` — loads .json plugin files from ~/Library/Application Support/Sudo/Plugins/
- `DevRebuilder` — git fetch + rebuild + reinstall from menu bar (dev mode only)
- `TestWindowManager` — AppKit NSWindow for the test prompt (bypasses MenuBarExtra limitation)

## Action Pipeline
1. HotkeyListener receives keypress → dispatches to background queue
2. Debounce check (100ms)
3. Macro check (if button has assigned macro, execute sequence)
4. Mode check:
   - `keyCombo` → send keyboard shortcut directly, done
   - `mediaKey` → send media key event, done
   - `aiSearch` → continue to detection pipeline
5. App detection (frontmost app, or all apps if search-all enabled)
6. AX tree search (3s timeout) → OCR fallback (3s timeout) → keyboard fallback (editors only)
7. Execute action (AXPress → center click fallback)
8. Finish: update UI, sound, webhook, telemetry, LED, notification

## Permissions
- Accessibility required for hotkey listener + AX tree reading
- Permission check runs every 3s until connected, auto-retries event tap
- `isConnected` = hotkey event tap successfully created (no AX test needed)
- Screen Recording permission needed for OCR fallback only

## Build
```bash
./build.sh                    # builds to dist/Sudo.app
rm -rf /Applications/Sudo.app
cp -r dist/Sudo.app /Applications/
```
Version is read from `OTAUpdater.currentVersion` (single source of truth).
Build script reads version from Swift source via grep.

## Common Issues
- `CGEventFlags` requires `import CoreGraphics` in any file using it
- `NSWorkspace` requires `import Cocoa` (not just Foundation)
- `Color(hex:)` extension is in Theme.swift — don't duplicate
- `as! AXUIElement` forced casts can crash — always use `as?`
- `git pull` fails with divergent branches — use `git fetch + git reset --hard`
- MenuBarExtra `.onAppear` fires every time popover opens, not just once
- `@Environment(\.openWindow)` crashes in MenuBarExtra — use TestWindowManager instead

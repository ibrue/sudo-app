# sudo-app — development context

## Style Guide

### Text & Typography
- **All UI text is lowercase** — menu bar labels, status text, section headers, button labels, footer buttons
- Menu bar states: `[sudo]`, `[ ok ]`, `[fail]`, `[·___]` — always 6 chars total
- **SF Pro (`SudoTheme.label`)** for UI chrome: labels, buttons, descriptions, status text
- **Monospace (`SudoTheme.mono`)** for data values: display names, bundle IDs, key combos, version numbers, API keys
- Toggles use bracket checkboxes: `[x]` / `[ ]` (monospace)
- No emojis except `✓` (success) and `✗` (failure) in the action log
- Button display names are stored lowercase: "approve / yes", "reject / no"
- Never use `action.displayName` directly in UI — it's already lowercase from settings

### Button Identity
- Physical buttons are numbered 1-4 (bottom to top): green, yellow, red, black
- Users see button numbers (1-4), NOT F-key numbers (F13-F16)
- F-keys are internal hotkey details — only shown in settings > hotkey bindings
- Buttons are floating pills with color-tinted glass backgrounds (no stripe)

### Colors & Materials
- **Liquid glass aesthetic** — `.ultraThinMaterial` root, `.thinMaterial` for cards/buttons
- Accent (green): `#34C759` (Apple system green, `SudoTheme.accent`)
- Text: `.primary` / `.secondary` (system semantic colors)
- Border: `.separatorColor` at 0.3 opacity, 0.5px width
- Error: `.systemRed`, Warning: `.systemYellow`
- Button colors: green `#6abf73`, yellow `#d4b85c`, red `#c85c5c`, black `#2a2a2a`
- Button tint: assigned color at 4% opacity (8% hover, 12% press)

### Layout
- Menu bar popover: fixed 320pt width
- Rounded corners: 10pt for cards, 14pt for pill buttons, 6pt for hover states
- 0.5px borders with low opacity (glass-friendly)
- Consistent padding: 16px horizontal, 10px vertical per section
- Sections separated by 0.5px subtle divider lines
- Buttons are floating pills with 6px spacing between them
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
- `AppDetector` — identifies frontmost app via bundle ID or browser tab, returns AppCategory
- `AppCategory` — enum: ai, terminal, browser, media, cad, videoEditing, writing, communication, design, unknown
- `AXButtonFinder` — walks accessibility tree to find buttons (primary, 30-level depth), tracks SearchStats
- `AXInspector` — debug tool: tree dumps, search dry-runs, pipeline tests (exposed via /debug/ endpoints)
- `AutomationButtonFinder` — AppleScript via System Events for hard-to-reach buttons (sheets, alerts, nested dialogs)
- `OCRButtonFinder` — Vision framework screenshot OCR (fallback)
- `ActionExecutor` — presses buttons via AXPress or CGEvent click (with center-click fallback)
- `FirmwareFlasher` — detects RP2040 bootloader, copies UF2 firmware for simple mode presets
- `HotkeyListener` — configurable CGEvent tap (default: Ctrl+Shift+F13–F16)
- `LocalAPIServer` — HTTP API on port 7483 + MCP server endpoints
- `WebhookManager` — fires POST to user-configured URL on each action
- `SudoTelemetry` — anonymous usage tracking (button number + mode, no action names)
- `BugReporter` — collects diagnostics and POSTs to sudo.supply/api/bugs
- `SudoSettings` — persisted preferences singleton (UserDefaults)
- `PadAction` — enum mapping 4 buttons to actions, delegates to settings for display names / search terms
- `ButtonPreset` — quick-apply configs (12 presets: ai-agent, plan-mode, claude-code, shortcuts, media, browsing, discord, cad, video-editing, writing, communication, design)
- `MacroSequence` — chained actions with delays, assignable to buttons
- `AutoApproveRule` — rules engine for automatic approval with safety exclusions
- `RulesEngine` — evaluates auto-approve rules against app + context
- `PadCommunicator` — USB serial to RP2040 for LED feedback
- `PluginManager` — loads .json plugin files from ~/Library/Application Support/Sudo/Plugins/
- `DevRebuilder` — git fetch + rebuild + reinstall from menu bar (dev mode only)
- `TestWindowManager` — AppKit NSWindow for the test prompt (bypasses MenuBarExtra limitation)

## Action Pipeline
1. HotkeyListener receives keypress → dispatches to background queue
2. Debounce check (configurable, default 20ms)
3. Macro check (if button has assigned macro, execute sequence)
4. Mode check:
   - `keyCombo` → send keyboard shortcut directly, done
   - `mediaKey` → send media key event, done
   - `aiSearch` → continue to detection pipeline
5. App detection (frontmost app, or all apps if search-all enabled)
6. AX tree search (3s timeout) → Automation/AppleScript (3s timeout) → OCR fallback (3s timeout) → keyboard fallback (editors only)
7. Execute action (AXPress → center click fallback)
8. Finish: update UI, sound, webhook, telemetry, LED, notification

## Permissions
- Accessibility required for hotkey listener + AX tree reading
- Automation (System Events) required for AutomationButtonFinder — reaches sheets, alerts, nested dialogs
- Permission check runs every 3s until connected, auto-retries event tap
- `isConnected` = hotkey event tap successfully created (no AX test needed)
- Screen Recording permission needed for OCR fallback only

## Auto-Profile Switching
- `SudoSettings.autoSwitchEnabled` (default: true) — auto-applies preset when frontmost app changes category
- `SudoSettings.categoryPresets: [String: String]` — maps category.rawValue → preset ID
- `AppCategory.from(bundleID:appName:)` — detects category from bundle ID, falls back to name substring matching
- `SudoEngine.handleAutoSwitch()` — called from `updateDetectedApp()`, applies preset if category changed
- `SudoEngine.autoSwitchStatus` — transient UI notification ("→ media controls"), clears after 3s
- Won't re-apply same preset (tracked via `lastAppliedPresetID`)

## Debug API Endpoints (requires X-API-Key header)
- `GET /debug/ax-tree` — dump AX tree of frontmost app as JSON (depth 8)
- `GET /debug/ax-tree?pid=N` — dump AX tree of specific PID
- `GET /debug/ax-search?terms=Allow,Approve` — dry-run search for terms in frontmost app
- `GET /debug/pipeline-test?action=approve` — run full detection pipeline, return detailed report with timings

## Simple Mode & Firmware Flashing
- Simple mode = all 4 buttons use keyCombo or mediaKey (no aiSearch)
- `SudoSettings.isSimpleMode` computed property checks all button modes
- When simple mode is active, pad can be flashed to work natively without companion app
- `FirmwareFlasher` detects RP2040 bootloader (RPI-RP2 USB volume) and copies UF2 files
- Pre-built firmware profiles for each preset (default, shortcuts, media, browsing, discord, custom)
- UF2 files looked up in: bundle resources → ~/Library/Application Support/Sudo/Firmware/

## Build
```bash
./build.sh                    # builds to dist/Sudo.app
rm -rf /Applications/Sudo.app
cp -r dist/Sudo.app /Applications/
```
Version is read from `OTAUpdater.currentVersion` (single source of truth).
Build script reads version from Swift source via grep.

## UI Audit (completed 2026-04-02)

All 17 audit issues resolved across MainView, MenuBarHelpers, TestPromptView, SudoSettings, and ConfigView.

## Common Issues
- `CGEventFlags` requires `import CoreGraphics` in any file using it
- `NSWorkspace` requires `import Cocoa` (not just Foundation)
- `Color(hex:)` extension is in Theme.swift — don't duplicate
- `as! AXUIElement` forced casts can crash — always use `as?`
- `git pull` fails with divergent branches — use `git fetch + git reset --hard`
- MenuBarExtra `.onAppear` fires every time popover opens, not just once
- `@Environment(\.openWindow)` crashes in MenuBarExtra — use TestWindowManager instead

# sudo-app — development context

## Style Guide

### Text & Typography
- **All UI text is lowercase** — menu bar labels, status text, section headers, button labels, footer buttons
- Menu bar states: `[sudo]`, `[ ok ]`, `[fail]`, `[·___]` — always 6 chars total
- **Hybrid type system** as of v1.6:
  - **System fonts** for body / labels / sections / panel headings — use the `SudoTheme.title` / `.heading` / `.body` / `.bodyEmphasized` / `.caption` ramp.
  - **Mono lane** (`SudoTheme.code(size:)` and `SudoTheme.brand`) only for: the `[sudo]` brand mark, version strings, hotkey bindings, debug log entries + timestamps, API key display, terminal output, action-log timestamps, code-like callouts in the test prompt.
  - The legacy `SudoTheme.mono(size:)` helper still exists for in-flight migrations; new code should reach for the semantic ramp first.
- Toggles use SF Symbols (`checkmark.square.fill` / `square`) via `SettingToggle` — the legacy `[x]/[ ]` mono glyphs were retired with the macOS pivot.
- Brackets stay part of the brand: `[sudo]`, `[<]`, `[ ok ]`, `[fail]` — keep them mono.
- No emojis except `✓` (success) and `✗` (failure) in the action log.
- Button display names are stored lowercase: "approve / yes", "reject / no".
- Never use `action.displayName` directly in UI — it's already lowercase from settings.

### Button Identity
- Physical buttons are numbered 1-4 (bottom to top): green, yellow, red, black
- Users see button numbers (1-4), NOT F-key numbers (F13-F16)
- F-keys are internal hotkey details — only shown in settings > hotkey bindings
- Buttons are floating pills with color-tinted glass backgrounds (no stripe)

### Colors & Materials
- **Liquid glass aesthetic** — `.ultraThinMaterial` root, `.thinMaterial` for cards/buttons.
- Accent (green): `#34C759` (Apple system green, `SudoTheme.accent`).
- Text: `.primary` / `.secondary` (system semantic colors).
- Border: `.separatorColor` at 0.3 opacity, 0.5px width.
- Error: `.systemRed`, Warning: `.systemYellow`.
- **Button colors are dark-mode-aware** via `PadAction.buttonColor`:
  | button | light | dark |
  |--------|-------|------|
  | green (1) | `#6abf73` | `#6FC97D` |
  | yellow (2) | `#d4b85c` | `#E0C76B` |
  | red (3) | `#c85c5c` | `#D66B6B` |
  | dark (4) | `#2a2a2a` | `#9A9A9A` |
  Button 4 specifically lifts in dark mode so it doesn't disappear on the translucent dark popover.
- Button card tint ramp on the popover: icon disc fill at ~35%, ring at 0.5 opacity always-on (1.2 when last-touched), shadow 0.20 when last-touched.
- Card surfaces use the `SudoTheme.cardSurface` (4%) / `cardSurfaceHover` (7%) / `cardSurfaceActive` (10%) tokens — they layer over `.thinMaterial` more cleanly than ad-hoc opacities.
- Code/log/terminal backgrounds use `SudoTheme.codeBackground` (system text-background color) so log surfaces match the system editor surface.

### Layout
- Menu bar popover: `SudoTheme.popoverWidth` (360pt). Used by `MainView`, `ConfigView`, `OnboardingView`.
- Card corners: `SudoTheme.cardCornerRadius` (14pt). Pill radius: 14pt. Hover states: 6pt.
- Button card height: `SudoTheme.buttonCardHeight` (52pt minimum) with a 28pt tinted icon disc and ringed border.
- 0.5px borders with low opacity (glass-friendly).
- Section padding: 16px horizontal, 12px vertical per popover section.
- Sections separated by 0.5px subtle divider lines.
- Settings window: 760×560 default, 680×460 minimum, NavigationSplitView with sidebar.
- Developer features (terminal, pull & rebuild) hidden when not in dev mode.

### Code Conventions
- Swift, SwiftUI, macOS 13+.
- `SudoTheme.*` for all colors, fonts, spacing — never hardcode hex in views.
- `SudoSettings.shared` singleton for persisted preferences.
- All user preferences stored in UserDefaults.
- Background work on `DispatchQueue.global(qos: .userInitiated)`.
- UI updates always on `DispatchQueue.main`.
- Hotkey listener dispatches to background queue, never main.
- Use `as?` not `as!` for AX element casts (can crash).
- `Color(hex:)` and `NSColor(hex:)` extensions live in Theme.swift.
- **Platform shim** at `Services/Platform/`: views call `Clipboard.setString(_:)`, `URLOpener.open(_:)` / `URLOpener.openAccessibilitySettings()`, and `AppLifecycle.terminate()` instead of reaching into `NSPasteboard` / `NSWorkspace` / `NSApplication` directly. Window managers (`SettingsWindowManager`, `EditPresetWindowManager`, `TestWindowManager`, `ToastWindowManager`) keep their AppKit imports — they're the platform-specific edge by design and would be replaced with sheets / `NavigationStack` push when iOS lands.

## Architecture
- `SudoEngine` — central orchestrator, owns detection → execution pipeline
- `AppDetector` — identifies frontmost app via bundle ID or browser tab, returns AppCategory
- `AppCategory` — enum: ai, terminal, browser, media, cad, videoEditing, writing, communication, design, unknown
- `AXButtonFinder` — walks accessibility tree to find buttons (primary, 30-level depth), tracks SearchStats
- `AXInspector` — debug tool: tree dumps, search dry-runs, pipeline tests (exposed via /debug/ endpoints)
- `AutomationButtonFinder` — AppleScript via System Events for hard-to-reach buttons (sheets, alerts, nested dialogs)
- `OCRButtonFinder` — Vision framework screenshot OCR (fallback)
- `ActionExecutor` — presses buttons via AXPress or CGEvent click (with center-click fallback)
- `FirmwareFlasher` — detects RP2040 bootloader, copies UF2 firmware. Also owns the IOKit HID watcher (matches Adafruit VID `0x239A`) that drives the popover's "device: connected (running)" indicator when CIRCUITPY is hidden in normal mode.
- `HotkeyListener` — configurable CGEvent tap (default: Ctrl+Shift+F13–F16). Has its own IOKit HID watcher that rebuilds the tap on any keyboard hot-plug (50 ms debounce, was 250 ms — too long for single-pad plug-in).
- `LocalAPIServer` — HTTP API on port 7483 + MCP server endpoints
- `WebhookManager` — fires POST to user-configured URL on each action
- `SudoTelemetry` — anonymous usage tracking (button number + mode, no action names)
- `BugReporter` — collects diagnostics and POSTs to sudo.supply/api/bugs
- `SudoSettings` — persisted preferences singleton (UserDefaults)
- `PadAction` — enum mapping 4 buttons to actions, delegates to settings for display names / search terms
- `ButtonPreset` — quick-apply configs (12 presets: ai-agent, plan-mode, claude-code, shortcuts, media, browsing, discord, cad, video-editing, writing, communication, design)
- `MacroSequence` — chained steps, assignable to a button. Steps are kinds: `.action` (fires a PadAction), `.switchToApp(bundleID, displayName, waitMs)` (activates / launches an app), `.switchBack(waitMs)` (restores the app that was frontmost when the macro fired), `.keystroke(keyCode, modifiers, delayAfter)` (sends a raw key combo without binding it to a PadAction). Backwards-compatible Codable: legacy macros default `kind` to `.action`.
- `AutoApproveRule` — rules engine for automatic approval with safety exclusions
- `RulesEngine` — evaluates auto-approve rules against app + context
- `PadCommunicator` — USB serial to RP2040 for LED feedback
- `PadConsoleReader` — tails the firmware's CDC console at `/dev/cu.usbmodem*`. Surfaces every press / boot line as a published `lines` array; surfaces in Settings → Developer → "pad console" so users can copy boot logs for debugging without `screen`. Cancels its DispatchSource synchronously on EOF (a TTY at EOF stays "readable" until cancelled, which used to cause a disconnect-spam loop).
- `PluginManager` — loads .json plugin files from ~/Library/Application Support/Sudo/Plugins/
- `DevRebuilder` — git fetch + rebuild + reinstall from menu bar (dev mode only)
- `TestWindowManager` — AppKit NSWindow for the test prompt (bypasses MenuBarExtra limitation)

## Action Pipeline
1. HotkeyListener receives keypress → logs `pad input: button N (...)` → dispatches to background queue
2. Debounce check (configurable, default 20ms)
3. `handleAction` logs `trigger: button N (name) in <app>` so the Debug console shows the full chain (input → trigger → result)
4. Macro check (if button has assigned macro, execute sequence — including scoped switch / keystroke steps)
5. Mode check:
   - `keyCombo` → send keyboard shortcut directly, done
   - `mediaKey` → send media key event, done
   - `aiSearch` → continue to detection pipeline
6. App detection (frontmost app, or all apps if search-all enabled)
7. AX tree search (3s timeout) → Automation/AppleScript (3s timeout) → OCR fallback (3s timeout) → keyboard fallback (editors only)
8. Execute action (AXPress → center click fallback)
9. Finish: update UI, sound, webhook, telemetry, LED, notification

## Permissions
- Accessibility required for hotkey listener + AX tree reading
- Automation (System Events) required for AutomationButtonFinder — reaches sheets, alerts, nested dialogs
- Permission check runs every 3s until connected, auto-retries event tap
- `isConnected` = hotkey event tap successfully created (no AX test needed)
- Screen Recording permission needed for OCR fallback only

## Macros

`MacroSequence` is a chain of `MacroStep`s with a `Kind` discriminator.
Currently four kinds, all executed by `SudoEngine.executeMacro`:

| kind | fields | what it does |
|------|--------|--------------|
| `.action` | `action` (PadAction rawValue), `delayAfter` | Fires one of the four pad actions through the normal pipeline (debounce + app detection + AX search + execute). Per-step `delayAfter` is post-action. |
| `.switchToApp` | `targetBundleID`, `targetDisplayName`, `waitMs` | Activates (or launches via NSWorkspace) an app and waits `waitMs` for it to become frontmost so the next keystroke lands. Default 150 ms; bump for heavier apps (Logic, Final Cut). |
| `.switchBack` | `waitMs` | Activates whatever app was frontmost when the macro started. The original bundle ID is captured once at the top of `executeMacro`, so multiple intermediate switches don't lose it. |
| `.keystroke` | `keyCode`, `modifiers`, `delayAfter` | Sends a CGEvent down + up at `.cghidEventTap`. Lets a macro fire app-specific shortcuts (Spotify's like-song, screenshot, etc.) without binding them to a PadAction first. |

**Codable note:** `MacroStep` is a struct (not an enum-with-associated-values)
so existing user data — saved before `kind` existed — keeps decoding.
The custom `init(from:)` defaults `kind` to `.action` and reads
`action`/`delayAfter` like before; new fields are all optional.

**Recursion guard:** synthesized keystrokes go through `cghidEventTap`,
which means our own event tap could intercept them. We get away with
it today because the default macros (Cmd+Shift+4 screenshot,
Option+Shift+B Spotify like) don't collide with the F13–F18 + ctrl-shift
hotkey bindings. If someone adds a `.keystroke` step that DOES match
a binding, suspend / resume `HotkeyListener` around the post — see
`HotkeyListener.suspend()` / `.resume()`.

**Default macros** (`SudoSettings.defaultMacros`):
- `double approve` / `approve all` — legacy `.action`-only chains.
- `screenshot` — single `.keystroke(Cmd+Shift+4)` step.
- `like song in spotify` — `.switchToApp(com.spotify.client)` →
  `.keystroke(Option+Shift+B)` → `.switchBack()`. The canonical
  scoped-macro reference.

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

## Build + test workflow

The user tests changes by pulling main and rebuilding locally — this
project doesn't have a CI pipeline that ships pre-built artifacts.
The standard loop after pushing a change:

```bash
git pull origin main
./build.sh                                    # builds to dist/Sudo.app
killall Sudo 2>/dev/null || true              # otherwise the running copy holds the binary
rm -rf /Applications/Sudo.app
cp -r dist/Sudo.app /Applications/
open /Applications/Sudo.app
```

**Accessibility permission gets revoked on every build.** `build.sh`
runs `tccutil reset Accessibility supply.sudo.app` on line 109 so
macOS treats the new binary as a fresh app, which is the right
default for unsigned local builds — but the user has to re-grant
Accessibility in System Settings → Privacy & Security → Accessibility
each time. The popover shows a red banner with an "open settings"
button when permission is missing. After granting, the in-app
permission timer (every 3 s) picks it up; if it doesn't, click
"re-check" in the banner.

**Don't use `AXIsProcessTrusted()` or `AXIsProcessTrustedWithOptions()`
to gate the connect-to-pad flow.** Both APIs cache at the per-process
level and only refresh on relaunch — they'll return a stale "false"
for the rest of the process lifetime even after the user has just
re-granted Accessibility in System Settings. This isn't a bug in
the API per se, but it makes them useless as a polling check.

Use `CGEvent.tapCreate()` as the source of truth instead. It
consults TCC at call time and reflects current state, so polling
it every 3 seconds (which the permission timer already does) picks
up a fresh grant without needing a relaunch. See
`SudoEngine.checkAndConnect` — the AX trust APIs are gone from
that path entirely; success is "did the tap get created."

Version is read from `OTAUpdater.currentVersion` (single source of truth).
Build script reads version from Swift source via grep.

### Firmware test loop (on the macropad itself)

The pad runs CircuitPython firmware in `sudo-supply/hardware/firmware/`.
Re-flashing requires the user to:

1. Hold button 1 + plug in the pad → CIRCUITPY drive mounts.
2. Open the popover → Settings → Device → Flash.
3. Unplug + replug (no button held) → new code.py runs.

Diagnostic console: dev mode → Settings → Developer → "pad console"
section tails `/dev/cu.usbmodem*`. Click connect, replug pad, copy
the boot log out. Useful for "pad takes ages to connect" reports.

## UI Audits

- **2026-04-02:** 17 issues across MainView, MenuBarHelpers, TestPromptView, SudoSettings, ConfigView.
- **v1.6.0-beta:** macOS-native pivot. Hybrid type system (system fonts + a mono lane for code/brand). Adaptive button colors via `PadAction.buttonColor`. Larger button cards (52pt min height, 28pt tinted disc). Popover widened to 360pt. Platform shim at `Services/Platform/` so panel views no longer touch AppKit directly.
- **v1.7.0-beta:** Scoped macros (switch-to-app / switch-back / raw keystroke step kinds; `screenshot` and `like song in spotify` defaults). Pad console reader in the Developer panel (tails `/dev/cu.usbmodem*`, copy-to-clipboard). Accessibility detection switched from `AXIsProcessTrusted` (cached per-process, returned stale false for the lifetime of the process) to `CGEvent.tapCreate` (real-time TCC check — picks up a fresh grant on the next 3 s timer tick, no relaunch needed). Press / release CDC logging in the firmware paired with `trigger: ...` lines in the Debug console so the full chain is visible. Hot-plug debounce 250 ms → 50 ms. `.metadata_never_index` written first during flash so Spotlight stops thrashing CIRCUITPY.

## Settings surface

The settings UI splits in two:
- **`ConfigView`** — slim popover at `SudoTheme.popoverWidth` (360pt). Device flash status, four
  quick toggles, automation on/off, and a CTA that opens the full window.
- **`SettingsWindow`** — separate NSWindow (760×560 default, 680×460 minimum, resizable) hosting
  `NavigationSplitView` with sidebar sections for `general`, `buttons`,
  `macros`, `auto-switch`, `auto-approve`, `developer` (dev-only),
  `history`, and `about`. Each panel lives in
  `Views/Settings/*Panel.swift` and uses only SwiftUI primitives + the
  `Services/Platform/` shim, so they port cleanly to iOS / iPadOS later.
  The only macOS-specific piece is `SettingsWindowManager` (NSWindow lifecycle).

Open the window from the popover via the "open full settings…" card or
the macros / history quick-link chips. `SettingsWindowManager.shared.open(
engine:updater:rebuilder:apiServer:initialSection:)` accepts an
`initialSection` to deep-link a specific panel.

The developer panel has three log surfaces — name overlap caused
real confusion, so they're documented here:

| section | what it shows | source |
|---------|---------------|--------|
| **pad console** | every press / release the firmware sees + boot log | `/dev/cu.usbmodem*` CDC stream via `PadConsoleReader` |
| **debug console** | every press the event tap catches + every action sudo triggers + pipeline results | `DebugLogger.shared` |
| **build & rebuild terminal** | `./build.sh` and the in-app rebuild button output | `DevRebuilder.buildLog` |

The first two should both light up when a macropad button is pressed.
The third is unrelated to macropad input — it's the pull-and-rebuild
log. Each section has a one-line subtitle in the panel itself for the
same reason.

## Common Issues
- `CGEventFlags` requires `import CoreGraphics` in any file using it
- View files should not import `AppKit`/`Cocoa` directly — use `Services/Platform/` instead. Window managers + Theme.swift are exceptions (they own the platform edge).
- `Color(hex:)` and `NSColor(hex:)` extensions are in Theme.swift — don't duplicate
- `as! AXUIElement` forced casts can crash — always use `as?`
- `git pull` fails with divergent branches — use `git fetch + git reset --hard`
- MenuBarExtra `.onAppear` fires every time popover opens, not just once
- `@Environment(\.openWindow)` crashes in MenuBarExtra — use TestWindowManager instead

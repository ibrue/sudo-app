# [sudo] — macOS Companion App

Menu bar daemon for the [sudo macro pad](https://sudo.supply). Translates physical button presses into per-app actions: AI permission approvals, media controls, YouTube playback, custom keystrokes.

Current version: **1.5.1-beta**.

## Button Layout

Physical device, bottom to top:

| # | Color | Hotkey | Default Action |
|---|-------|--------|----------------|
| 1 (bottom) | Green | `Ctrl+Shift+F13` | Approve / Yes |
| 2 | Yellow | `Ctrl+Shift+F18` | Make it better |
| 3 | Red | `Ctrl+Shift+F17` | Reject / No |
| 4 (top) | Black | `Ctrl+Shift+F16` | YOLO (allow all) |

`F14` and `F15` are deliberately skipped — macOS treats them as display-brightness keys even with modifiers. F17/F18 are unclaimed by the system.

All bindings are remappable in the **edit preset** wizard (settings → edit preset → walk through all 4 buttons).

## Install

```bash
cd sudo-app
./build.sh                                   # builds dist/Sudo.app
rm -rf /Applications/Sudo.app
cp -r dist/Sudo.app /Applications/
open /Applications/Sudo.app
```

Or download from [sudo.supply/download](https://sudo.supply/download) / [GitHub Releases](https://github.com/ibrue/sudo-app/releases).

After install, click **flash device** in settings to push the latest CircuitPython firmware + your config to the macropad.

## How it works

1. **Listen** — global CGEvent tap catches `Ctrl+Shift+F13/F17/F18/F16` from the macropad. Subscribed to `tapDisabledByTimeout` / `tapDisabledByUserInput` so macOS auto-disabling the tap is recovered instantly.
2. **Detect** — identifies the frontmost app via bundle ID, name hints, or browser-tab URL/title.
3. **Dispatch** — based on the button's mode:
   - **aiSearch** → 4-strategy match pipeline: AX accessibility tree → Automation (System Events) → Vision OCR → keyboard fallback for editors
   - **keyCombo** → genuine HID hold (key-down on press, key-up on release — YouTube's hold-spacebar-for-2x works)
   - **mediaKey** → consumer-control HID code (play/pause, next, prev, mute)
4. **Act** — `AXUIElement.performAction` (anti-cheat-safe), with mouse-click + AppleScript click as fallbacks.

## Two modes

| Mode | Behaviour |
|------|-----------|
| **dynamic** | Auto-switches preset by frontmost app category. The app dispatches per-app actions in real time. Default. |
| **simple** | One fixed preset; the firmware sends keystrokes natively, so the pad works standalone without the app running. |

The legacy "custom" mode collapsed into **simple → edit preset** in v1.4.

## Auto-detected app categories

| Category | Default Preset | Triggers on |
|---|---|---|
| AI apps | AI Agent | Claude.app, ChatGPT.app, claude.ai / chatgpt.com / grok.com tabs |
| Editors / IDEs | Claude Code | VS Code, Cursor, Windsurf, Warp, iTerm2, Ghostty, Kitty, Alacritty, Terminal.app |
| Browsers | YouTube | Any tab in Safari / Chrome / Firefox / Brave / Edge / Arc / Opera |
| YouTube | YouTube | youtube.com / music.youtube.com tabs (in any browser) |
| Media | Media Controls | Spotify, Apple Music, VLC, IINA, Tidal, Plex |
| CAD | CAD | Fusion 360, AutoCAD, Rhino, FreeCAD, SketchUp, SOLIDWORKS, Inventor |
| Video editing | Video Editing | Final Cut, DaVinci Resolve, Premiere, After Effects, iMovie, CapCut |
| Writing | Writing | Notion, Obsidian, Bear, Pages, Word, Typora |
| Communication | Communication | Slack, Teams, Discord, Zoom, Webex |
| Design | Design | Figma, Sketch, Affinity, Photoshop, Illustrator |

## Built-in presets

| Preset | Bindings |
|--------|----------|
| **AI Agent** | approve / make-it-better / reject / yolo (AI permission prompts) |
| **YouTube** | space (play/pause) / j (-10s) / l (+10s) / f (fullscreen) — bottom to top |
| **Media** | play-pause / next / previous / `Opt+Shift+B` (Spotify "save to liked") |
| **Plan Mode**, **Claude Code**, **Web Browsing**, **Discord Soundboard**, **CAD**, **Video Editing**, **Writing**, **Communication**, **Design**, **System Shortcuts** | preset-specific |

Apply via settings → edit preset → quick presets.

## App-specific quirks handled

- **Fusion 360** — after a successful "save" press, the app posts `Return` 1s later to dismiss the Save Version dialog.
- **YouTube hold-for-2x** — keyCombo dispatch holds the HID report until you release the physical button. Hold the bottom button on a YouTube tab → 2x speed kicks in.
- **F14/F15 brightness** — defaults skip these; existing user bindings are auto-migrated to F17/F18 on first launch.

## Menu bar label

Stays out of the way:

| Display | When |
|---------|------|
| `[sudo]` | idle |
| `[····]` (animated) | dispatch in progress |
| `[✓ approve]` | success — holds 2.5 s, then idle |
| `[✗ reject]` | failure — holds 4 s, then idle |

## In-app feedback

- **Failure toast** — borderless floating panel under the menu bar with `couldn't <action> in <app>` whenever an AI-search press doesn't find a target. Auto-dismisses in 3 s.
- **Action history** — last 50 actions with timestamps and per-method status, browsable in settings.
- **Debug console** — every dispatch step logged with a copy button for sharing reports.
- **Device LED** — both under-glow LEDs (GP24 + GP25) flash 120 ms on every press. Each pin is claimed independently inside try/except so if CircuitPython has already grabbed GP25 for its status indicator we just keep GP24 going without crashing.

## Firmware

The macropad runs CircuitPython 9.x. Source lives in `sudo-supply/hardware/firmware/code.py`; the app bundles a verbatim copy and writes it to the CIRCUITPY drive on flash. Pure HID transport — no boot.py, no serial protocol, no `pwmio`.

Pin order: `(GP3, GP2, GP1, GP0)` so `buttons[0]` is the bottom switch (matching the app's physical-order indexing).

## Permissions

| Permission | What for | Required? |
|---|---|---|
| Accessibility | hotkey listener + AX tree reading | yes |
| Automation (System Events) | AppleScript fallback for sheets / dialogs | recommended |
| Screen Recording | OCR fallback (Vision framework) | optional |

The app prompts on first launch and shows a red banner with **open settings** until accessibility is granted.

## OTA Updates

Checks GitHub Releases every 4 h. When a newer beta is found, the **install** banner appears in the popover.

To cut a release:
1. Bump `OTAUpdater.currentVersion` (single source of truth — `build.sh` reads it via grep).
2. `./build.sh && ./create-dmg.sh` on macOS.
3. Tag + GitHub Release with the `.dmg` attached.

## Anti-cheat compatibility

Uses the macOS Accessibility API — same interface as VoiceOver and Shortcuts.app. No HID injection, no memory patching, no kernel extensions.

## Recent changelog (highlights)

- **1.5.1** — both under-glow LEDs flash on press (was GP24-only)
- **1.5.0** — firmware press-and-hold (key-down on press, key-up on release)
- **1.4.9** — browser default switched to YouTube preset
- **1.4.8** — auto-switch to YouTube preset on Chrome / Safari / etc. tabs
- **1.4.7** — `AutomationButtonFinder` no longer activates apps it's just probing
- **1.4.6** — keep CGEvent tap alive across macOS auto-disables (fixes "doesn't work for a few minutes")
- **1.4.5** — copy button on debug console
- **1.4.4** — LED feedback on press, Fusion save → Enter, Spotify Opt+Shift+B Like
- **1.4.3** — build fixes
- **1.4.2** — auto-detect device on USB mount/unmount; failure toast
- **1.4.1** — edit-preset 4-button wizard, redesigned onboarding, fix button order
- **1.4.0** — popover redesign (~260pt tall, native macOS feel, glass cards)
- **1.3.x** — pure-HID firmware path; `supervisor.ticks_diff` fix that resolved the long-running "buttons don't do anything" bug

# [sudo] macOS companion app

Menu bar companion for the [sudo macro pad](https://sudo.supply). It turns the
four physical buttons into context-aware actions for AI permission prompts,
editors, browsers, media apps, CAD tools, and custom workflows.

Current version: **1.7.3-beta**.

## What it does

- Listens for the pad's global hotkeys with a macOS event tap.
- Detects the frontmost app by bundle ID and app name; for supported browsers,
  it also inspects the active tab URL/title when macOS exposes it.
- Runs per-app button actions such as approve/reject prompts, YouTube controls,
  media keys, CAD shortcuts, and custom keystrokes.
- Auto-switches presets by app category in dynamic mode.
- Flashes and configures the RP2040 pad from inside the app.
- Controls the pad's two bottom LEDs live over CircuitPython's second CDC
  serial channel.
- Shows pad connection, firmware, progress, and console diagnostics in Settings.

## Button layout

Physical device, bottom to top:

| # | Color | Default hotkey | Default action |
|---|---|---|---|
| 1 | Green | `Ctrl+Shift+F13` | Approve / Yes |
| 2 | Yellow | `Ctrl+Shift+F18` | Make it better |
| 3 | Red | `Ctrl+Shift+F17` | Reject / No |
| 4 | Black | `Ctrl+Shift+F16` | YOLO / allow all |

`F14` and `F15` are skipped because macOS treats them as display-brightness keys
on Apple-style keyboards, even with modifiers.

## Install from source

```bash
./build.sh
rm -rf /Applications/Sudo.app
cp -r dist/Sudo.app /Applications/
open /Applications/Sudo.app
```

`build.sh` creates `dist/Sudo.app`, bundles pad firmware, bundles the pinned
CircuitPython UF2 for offline first-time flashing, and signs the app with a
stable ad-hoc requirement.

## Flash the pad

Open **Settings -> Device**.

The Device panel handles the supported sudo RP2040/CircuitPython pad flow:

- **Running pad**: normal production firmware hides `CIRCUITPY`. To flash,
  unplug the pad, hold button 1, and plug it back in.
- **CIRCUITPY mounted**: the app writes `boot.py`, `code.py`, `sudo_leds.py`,
  generated `config.json`, and `.metadata_never_index`.
- **RPI-RP2 mounted**: the app copies bundled CircuitPython `9.2.1`, waits for
  `CIRCUITPY`, then writes the pad firmware and config.

Bundled firmware lives in:

```text
Sudo/Resources/Firmware/pad/
Sudo/Resources/Firmware/circuitpython-pico-9.2.1.uf2
```

The app uses those bundled files as the flashing source of truth. If a
development build omits the UF2, the flasher falls back to downloading and
caching the pinned CircuitPython build.

The current firmware enables:

- HID keyboard + consumer-control output for button presses.
- CDC console output for diagnostics.
- A second CDC data channel for host-to-pad LED commands.
- PWM underglow on GP24 and GP25 with `feedback`, `breathe`, `solid`, and
  `status-dim` modes.

## App modes

| Mode | Behavior |
|---|---|
| **dynamic** | Firmware emits passthrough F-key hotkeys; Sudo dispatches context-aware actions in real time. Default. |
| **simple** | Pad emits the configured keystrokes directly, so it can work without the app running. |

Settings also include button editing, macros, auto-switch presets,
auto-approve rules, action history, developer diagnostics, and the Device panel.

## Built-in presets

| Preset | Typical bindings |
|---|---|
| AI Agent | approve / make better / reject / yolo |
| Plan Mode | approve plan / reject plan / revise plan / exit |
| Claude Code | prompt-aware AI actions and keyboard fallbacks |
| System Shortcuts | copy / paste / undo / screenshot |
| YouTube | play-pause / rewind / forward / fullscreen |
| Media | play-pause / next / previous / Spotify like |
| Web Browsing | back / forward / refresh / close tab |
| Discord Soundboard | soundboard shortcuts and mute/deafen |
| CAD | app-specific CAD shortcuts |
| Bambu Studio | slice / arrange / save / print |
| Video Editing | common timeline/editing actions |
| Writing | document and note-taking shortcuts |
| Communication | Slack, Teams, Discord, Zoom-oriented actions |
| Design | Figma, Sketch, Adobe/Affinity-oriented actions |

Dynamic mode maps app categories to presets automatically. Browser apps default
to the YouTube preset, and Bambu Studio is seeded as a per-app override. Other
per-app overrides are available in Settings.

## How dispatch works

1. **Listen**: a global `CGEvent` tap catches the pad hotkeys and recovers when
   macOS disables the tap.
2. **Detect**: Sudo identifies the active app and, for browsers, the active tab
   URL/title where available.
3. **Choose action**: dynamic mode selects the preset for the detected app;
   simple mode uses the fixed configured button mapping.
4. **Act**: AI-search actions try Accessibility, Automation/System Events,
   Vision OCR, then keyboard fallback. Key-combo and media-key actions dispatch
   directly.

## Feedback and diagnostics

- Menu bar status shows idle, processing, success, and failure states.
- The popover shows current target app, app mode, last action, and pad status.
- Failure to find a UI target shows a transient toast.
- The pad underglow can show press identity, busy/result state, ambient
  breathing, solid light, or dim event-only status.
- Settings -> History records recent actions and detection results.
- Settings -> Device shows pad connection state, flash progress, recovery
  guidance, and the pad CDC console.
- Settings -> Developer includes debug logs, local API controls, plugin state,
  and build/rebuild output.

## Permissions

| Permission | Used for | Required |
|---|---|---|
| Accessibility | Global hotkey listener and Accessibility tree actions | Yes |
| Automation | System Events / AppleScript fallback clicks and keystrokes | Recommended |
| Screen Recording | Vision OCR fallback | Optional |

If Accessibility is missing, Sudo shows a banner with actions to open System
Settings, relaunch, reset permissions, or re-check.

## Development

Useful commands:

```bash
swift test --package-path Sudo
./build.sh
./create-dmg.sh
```

Version source of truth:

```text
Sudo/Sources/Sudo/Services/OTAUpdater.swift
```

`build.sh` reads `OTAUpdater.currentVersion` and writes it into the app bundle.

## Release checklist

1. Update `OTAUpdater.currentVersion`.
2. Run `swift test --package-path Sudo`.
3. Run `./build.sh`.
4. Run `./create-dmg.sh`.
5. Tag the release and attach the DMG in GitHub Releases.

## Anti-cheat compatibility

Sudo uses macOS Accessibility and standard event APIs. It does not patch memory,
install kernel extensions, or use game-process injection.

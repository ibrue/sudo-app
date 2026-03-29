# Claude Code Prompt: Update sudo.supply Website

Use this prompt with Claude Code to update the sudo.supply website with the latest app features.

---

## Prompt

```
Update the sudo.supply website to reflect that the [sudo] companion app is now cross-platform (macOS, Windows, Linux) with customizable key bindings, VIA/Vial/QMK firmware support, and simple/complex button modes.

Here's what changed and needs to be reflected on the site:

### 1. Cross-Platform Support (NEW)
The app now runs on all three desktop platforms:
- **macOS**: Swift/SwiftUI menu bar app (original)
- **Windows**: C#/.NET 8 WinForms system tray app (NEW)
- **Linux**: Python/GTK3 AppIndicator tray app (NEW)

Add download/install sections for each platform. The macOS version has a DMG, Windows builds to a single .exe, Linux installs via a shell script.

### 2. Customizable Key Bindings (NEW)
Users can now fully customize what each button does:
- **Simple mode**: Assign preset system shortcuts (screenshot, copy, paste, undo, save, lock screen, etc.)
- **Complex mode**: The original AI agent button-finding approach with customizable search terms
- **Configurable hotkeys**: Change which key combos trigger each action (not just the default Ctrl+Shift+F13-F16)

Add a "Customization" or "Configuration" section showing the simple/complex toggle and the settings UI.

### 3. QMK / VIA / Vial Firmware (NEW)
The repo now includes complete QMK firmware for the RP2040 macro pad:
- Default keymap (Ctrl+Shift+F13-F16)
- VIA-enabled keymap (live reconfiguration via usevia.app)
- Vial-enabled keymap (auto-detection, no draft definition needed)
- VIA JSON definition file

Add a "Firmware" section explaining the three keymap options and linking to VIA/Vial setup instructions.

### 4. Detection Stack Per Platform
Show the technology used on each platform:

| Feature | macOS | Windows | Linux |
|---------|-------|---------|-------|
| System tray | MenuBarExtra | NotifyIcon | AppIndicator3 |
| Hotkeys | CGEvent tap | RegisterHotKey | pynput |
| Button finding | AXUIElement | UI Automation | AT-SPI2 |
| OCR fallback | Apple Vision | Windows.Media.Ocr | Tesseract |
| Execution | AXPress | InvokePattern | AT-SPI/xdotool |

### 5. Updated Icon
The app icon is now a minimal black-and-white "[]" (square brackets) design — white brackets on a black rounded-rect background. Use this as the favicon and app icon throughout the site.

### 6. Supported AI Apps
- Native: Claude for Desktop, ChatGPT
- Web: claude.ai, chatgpt.com, grok.com
- Browsers: Safari (macOS), Chrome, Firefox, Brave, Edge, Opera, Chromium

### Design Notes
- Keep the existing Matrix-style dark theme (#0A0A0A background, #00FF41 green accent, monospaced fonts)
- The app's visual identity uses: dark bg, green terminal text, white brackets icon
- Show platform tabs or toggles for macOS/Windows/Linux install instructions
- Add the VIA vs Vial comparison table from the firmware README

### Key Pages to Update
- Homepage hero: "Cross-platform companion app for macOS, Windows & Linux"
- Download page: Add Windows .exe and Linux install options
- Features page: Add customizable bindings, simple/complex modes, VIA/Vial support
- Documentation: Link to firmware/README.md for QMK/VIA/Vial setup
```

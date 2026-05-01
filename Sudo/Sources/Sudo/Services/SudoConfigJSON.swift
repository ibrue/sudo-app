import Foundation
import CoreGraphics

/// Generates the `config.json` file the CircuitPython firmware reads on boot.
///
/// Schema mirrors `code.py`:
/// ```json
/// {
///   "version": 1,
///   "mode": "dynamic" | "simple" | "custom",
///   "buttons": [
///     {"mode": "keycombo"|"mediakey"|"passthrough",
///      "keycode": <hid usage>, "modifiers": <hid mod mask>,
///      "name": "<display>"},
///     ...4 entries, physical order bottom→top
///   ]
/// }
/// ```
///
/// Once the device is running CircuitPython, the app updates behaviour by
/// writing this file directly to the CIRCUITPY mass-storage volume.
/// CircuitPython auto-reloads on save, so changes take effect in <1 s.
enum SudoConfigJSON {

    static let version = 1

    /// Build the JSON payload for the current settings snapshot.
    static func generate(from settings: SudoSettings) throws -> Data {
        var buttons: [[String: Any]] = []
        for action in PadAction.physicalOrder {
            buttons.append(buttonRecord(action: action, settings: settings))
        }
        let payload: [String: Any] = [
            "version": version,
            "mode": settings.appMode.rawValue,
            "buttons": buttons,
        ]
        return try JSONSerialization.data(withJSONObject: payload,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    /// Convenience: write the JSON to a temp file. Returns the URL.
    static func writeTemp(from settings: SudoSettings) throws -> URL {
        let data = try generate(from: settings)
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("sudo-config-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url)
        return url
    }

    // MARK: - Internal

    static func buttonRecord(action: PadAction, settings: SudoSettings) -> [String: Any] {
        // In dynamic mode the firmware is intentionally dumb: it always
        // sends F13–F16 + ctrl+shift, regardless of what auto-switch has
        // momentarily set the per-button modes to. The app's HotkeyListener
        // catches those F-keys and dispatches per-app via the currently
        // auto-switched preset.
        //
        // This is the architectural difference between the modes:
        //   dynamic — firmware passthrough; app does per-app dispatch
        //   simple  — firmware sends one fixed preset's keystrokes natively
        //   custom  — firmware sends user-defined per-button keystrokes
        //
        // Without this override, clicking [ flash device ] while a media
        // preset was momentarily auto-applied would write `mediaKey` into
        // the device for ever, bypassing the app — i.e. buttons would no
        // longer track what the menu bar shows.
        let effectiveMode: ActionMode
        if settings.appMode == .dynamic {
            effectiveMode = .aiSearch
        } else {
            effectiveMode = settings.actionMode(for: action)
        }

        let combo = settings.keyCombo(for: action)
        let (keycode, modifiers) = hidMapping(for: action, mode: effectiveMode, combo: combo)
        return [
            "mode": pythonModeName(for: effectiveMode),
            "keycode": Int(keycode),
            "modifiers": Int(modifiers),
            "name": settings.displayName(for: action),
        ]
    }

    private static func pythonModeName(for mode: ActionMode) -> String {
        switch mode {
        case .keyCombo: return "keycombo"
        case .mediaKey: return "mediakey"
        case .aiSearch: return "passthrough"
        }
    }

    private static func hidMapping(for action: PadAction, mode: ActionMode, combo: ButtonPreset.KeyCombo?) -> (UInt8, UInt8) {
        switch mode {
        case .aiSearch:
            // Firmware sends the original F-key + ctrl+shift so the macOS
            // app can hear the hotkey and run its AI search pipeline.
            return (fKeyHID(action: action), hidModCtrlShift)
        case .keyCombo:
            guard let kc = combo else { return (0, 0) }
            return (macOSKeyCodeToHID(kc.keyCode), hidModifiers(from: kc.modifiers))
        case .mediaKey:
            guard let kc = combo else { return (0, 0) }
            // We pass macOS NX_KEYTYPE values through; the firmware maps to
            // HID consumer-control usage codes.
            return (UInt8(truncatingIfNeeded: kc.keyCode), 0)
        }
    }

    /// HID usage codes for the four passthrough F-keys. We deliberately skip
    /// 0x69 (F14) and 0x6A (F15) — macOS treats those as display-brightness
    /// keys on Apple-style keyboards even with modifiers, so the keystrokes
    /// would be swallowed before HotkeyListener saw them. F17/F18 (0x6C/0x6D)
    /// are unclaimed by the OS.
    private static func fKeyHID(action: PadAction) -> UInt8 {
        switch action {
        case .approve: return 0x68  // F13
        case .reject:  return 0x6C  // F17
        case .action3: return 0x6D  // F18
        case .action4: return 0x6B  // F16
        }
    }

    private static let hidModCtrlShift: UInt8 = 0x01 | 0x02

    static func hidModifiers(from flags: CGEventFlags) -> UInt8 {
        var mods: UInt8 = 0
        if flags.contains(.maskControl)   { mods |= 0x01 }
        if flags.contains(.maskShift)     { mods |= 0x02 }
        if flags.contains(.maskAlternate) { mods |= 0x04 }
        if flags.contains(.maskCommand)   { mods |= 0x08 }  // GUI / cmd
        return mods
    }

    /// Map macOS virtual keycode → USB HID usage code (keyboard page).
    static func macOSKeyCodeToHID(_ kc: UInt16) -> UInt8 {
        switch kc {
        case 0:   return 0x04  // a
        case 1:   return 0x16  // s
        case 2:   return 0x07  // d
        case 3:   return 0x09  // f
        case 4:   return 0x0B  // h
        case 5:   return 0x0A  // g
        case 6:   return 0x1D  // z
        case 7:   return 0x1B  // x
        case 8:   return 0x06  // c
        case 9:   return 0x19  // v
        case 11:  return 0x05  // b
        case 12:  return 0x14  // q
        case 13:  return 0x1A  // w
        case 14:  return 0x08  // e
        case 15:  return 0x15  // r
        case 16:  return 0x1C  // y
        case 17:  return 0x17  // t
        case 18:  return 0x1E  // 1
        case 19:  return 0x1F  // 2
        case 20:  return 0x20  // 3
        case 21:  return 0x21  // 4
        case 22:  return 0x23  // 6
        case 23:  return 0x22  // 5
        case 24:  return 0x2E  // =
        case 25:  return 0x26  // 9
        case 26:  return 0x24  // 7
        case 27:  return 0x2D  // -
        case 28:  return 0x25  // 8
        case 29:  return 0x27  // 0
        case 30:  return 0x30  // ]
        case 31:  return 0x12  // o
        case 32:  return 0x18  // u
        case 33:  return 0x2F  // [
        case 34:  return 0x0C  // i
        case 35:  return 0x13  // p
        case 36:  return 0x28  // return
        case 37:  return 0x0F  // l
        case 38:  return 0x0D  // j
        case 40:  return 0x0E  // k
        case 41:  return 0x33  // ;
        case 42:  return 0x31  // \
        case 43:  return 0x36  // ,
        case 44:  return 0x38  // /
        case 46:  return 0x10  // m
        case 47:  return 0x37  // .
        case 49:  return 0x2C  // space
        case 51:  return 0x2A  // delete (backspace)
        case 53:  return 0x29  // escape
        case 105: return 0x68  // F13
        case 106: return 0x6B  // F16
        case 107: return 0x69  // F14
        case 113: return 0x6A  // F15
        case 64:  return 0x6C  // F17
        case 79:  return 0x6D  // F18
        case 80:  return 0x6E  // F19
        case 90:  return 0x6F  // F20
        case 122: return 0x3A  // F1
        case 97:  return 0x3F  // F6
        default:  return 0
        }
    }
}

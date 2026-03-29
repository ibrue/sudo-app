import Foundation
import Carbon

/// Defines a configurable hotkey binding (key code + modifier flags).
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt32  // CGEventFlags raw value

    /// Human-readable display string, e.g. "⌃⇧F13".
    var displayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(modifiers))

        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }

        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    /// Returns the default hotkey config for a given pad action (Ctrl+Shift+F13-F16).
    static func defaultFor(_ action: PadAction) -> HotkeyConfig {
        let flags: UInt32 = UInt32(CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
        return HotkeyConfig(keyCode: action.keyCode, modifiers: flags)
    }

    /// Maps a macOS virtual key code to a human-readable key name.
    static func keyName(for keyCode: UInt16) -> String {
        let knownKeys: [UInt16: String] = [
            // F-keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16",
            64: "F17", 79: "F18", 80: "F19", 90: "F20",

            // Common keys
            36: "Return", 76: "Enter", 49: "Space", 51: "Delete",
            117: "Fwd Del", 53: "Esc", 48: "Tab",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",

            // Alphanumeric
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F",
            5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
            46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
            1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",

            // Numbers
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
            23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        ]

        return knownKeys[keyCode] ?? "Key\(keyCode)"
    }

    /// Extracts modifier flags relevant for hotkey matching, stripping device-specific bits.
    static func normalizedModifiers(from flags: CGEventFlags) -> UInt32 {
        let mask: UInt64 = CGEventFlags.maskControl.rawValue
            | CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskCommand.rawValue
        return UInt32(flags.rawValue & mask)
    }
}

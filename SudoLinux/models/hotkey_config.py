"""Defines a configurable hotkey binding (X11 keysym + modifier mask)."""

from dataclasses import dataclass

# X11 modifier masks
MOD_SHIFT = 1 << 0     # ShiftMask
MOD_CONTROL = 1 << 2   # ControlMask
MOD_ALT = 1 << 3       # Mod1Mask (Alt)
MOD_SUPER = 1 << 6     # Mod4Mask (Super)

# X11 keysym name map (common keys)
_KEYSYM_NAMES = {
    # F-keys
    0xFFBE: "F1",  0xFFBF: "F2",  0xFFC0: "F3",  0xFFC1: "F4",
    0xFFC2: "F5",  0xFFC3: "F6",  0xFFC4: "F7",  0xFFC5: "F8",
    0xFFC6: "F9",  0xFFC7: "F10", 0xFFC8: "F11", 0xFFC9: "F12",
    0xFFCA: "F13", 0xFFCB: "F14", 0xFFCC: "F15", 0xFFCD: "F16",
    0xFFCE: "F17", 0xFFCF: "F18", 0xFFD0: "F19", 0xFFD1: "F20",

    # Common keys
    0xFF0D: "Return", 0xFF1B: "Escape", 0xFF09: "Tab", 0x0020: "Space",
    0xFF08: "BackSpace", 0xFFFF: "Delete",
    0xFF51: "Left", 0xFF52: "Up", 0xFF53: "Right", 0xFF54: "Down",
    0xFF50: "Home", 0xFF57: "End", 0xFF55: "Page_Up", 0xFF56: "Page_Down",
    0xFF61: "Print",

    # Letters (lowercase keysyms)
    0x0061: "A", 0x0062: "B", 0x0063: "C", 0x0064: "D", 0x0065: "E",
    0x0066: "F", 0x0067: "G", 0x0068: "H", 0x0069: "I", 0x006A: "J",
    0x006B: "K", 0x006C: "L", 0x006D: "M", 0x006E: "N", 0x006F: "O",
    0x0070: "P", 0x0071: "Q", 0x0072: "R", 0x0073: "S", 0x0074: "T",
    0x0075: "U", 0x0076: "V", 0x0077: "W", 0x0078: "X", 0x0079: "Y",
    0x007A: "Z",

    # Numbers
    0x0030: "0", 0x0031: "1", 0x0032: "2", 0x0033: "3", 0x0034: "4",
    0x0035: "5", 0x0036: "6", 0x0037: "7", 0x0038: "8", 0x0039: "9",
}


@dataclass
class HotkeyConfig:
    """A configurable hotkey binding with X11 keysym and modifier mask."""

    keysym: int
    modifiers: int  # X11 modifier mask (bitmask of MOD_* constants)

    @property
    def display_string(self):
        """Human-readable display string, e.g. 'Ctrl+Shift+F13'."""
        parts = []
        if self.modifiers & MOD_CONTROL:
            parts.append("Ctrl")
        if self.modifiers & MOD_ALT:
            parts.append("Alt")
        if self.modifiers & MOD_SHIFT:
            parts.append("Shift")
        if self.modifiers & MOD_SUPER:
            parts.append("Super")
        parts.append(self.key_name(self.keysym))
        return "+".join(parts)

    @classmethod
    def default_for(cls, action):
        """Returns the default hotkey config for a given pad action (Ctrl+Shift+F13-F16)."""
        mods = MOD_CONTROL | MOD_SHIFT
        return cls(keysym=action.key_code, modifiers=mods)

    @staticmethod
    def key_name(keysym):
        """Maps an X11 keysym to a human-readable key name."""
        return _KEYSYM_NAMES.get(keysym, f"Key{hex(keysym)}")

    @staticmethod
    def normalized_modifiers(modifiers):
        """Extracts relevant modifier flags, stripping device-specific bits."""
        mask = MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_SUPER
        return modifiers & mask

    def to_dict(self):
        """Serialize to a JSON-compatible dict."""
        return {"keysym": self.keysym, "modifiers": self.modifiers}

    @classmethod
    def from_dict(cls, data):
        """Deserialize from a dict."""
        return cls(keysym=data["keysym"], modifiers=data["modifiers"])

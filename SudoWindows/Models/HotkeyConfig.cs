using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace SudoWindows.Models;

/// <summary>
/// Defines a configurable hotkey binding (virtual key code + modifier flags).
/// </summary>
public class HotkeyConfig
{
    // Win32 modifier constants
    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT = 0x0004;
    public const uint MOD_WIN = 0x0008;

    [JsonPropertyName("keyCode")]
    public uint KeyCode { get; set; }

    [JsonPropertyName("modifiers")]
    public uint Modifiers { get; set; }  // MOD_CONTROL, MOD_SHIFT, MOD_ALT, MOD_WIN

    /// <summary>
    /// Human-readable display string, e.g. "Ctrl+Shift+F13".
    /// </summary>
    [JsonIgnore]
    public string DisplayString
    {
        get
        {
            var parts = new List<string>();

            if ((Modifiers & MOD_CONTROL) != 0) parts.Add("Ctrl");
            if ((Modifiers & MOD_ALT) != 0) parts.Add("Alt");
            if ((Modifiers & MOD_SHIFT) != 0) parts.Add("Shift");
            if ((Modifiers & MOD_WIN) != 0) parts.Add("Win");

            parts.Add(KeyName(KeyCode));
            return string.Join("+", parts);
        }
    }

    public HotkeyConfig() { }

    public HotkeyConfig(uint keyCode, uint modifiers)
    {
        KeyCode = keyCode;
        Modifiers = modifiers;
    }

    /// <summary>
    /// Returns the default hotkey config for a given pad action (Ctrl+Shift+F13-F16).
    /// </summary>
    public static HotkeyConfig DefaultFor(PadActionType action)
    {
        uint vk = (uint)PadAction.KeyCodes[action];
        return new HotkeyConfig(vk, MOD_CONTROL | MOD_SHIFT);
    }

    /// <summary>
    /// Maps a Windows virtual key code to a human-readable key name.
    /// </summary>
    public static string KeyName(uint vk)
    {
        var knownKeys = new Dictionary<uint, string>
        {
            // F-keys
            { 0x70, "F1" }, { 0x71, "F2" }, { 0x72, "F3" }, { 0x73, "F4" },
            { 0x74, "F5" }, { 0x75, "F6" }, { 0x76, "F7" }, { 0x77, "F8" },
            { 0x78, "F9" }, { 0x79, "F10" }, { 0x7A, "F11" }, { 0x7B, "F12" },
            { 0x7C, "F13" }, { 0x7D, "F14" }, { 0x7E, "F15" }, { 0x7F, "F16" },
            { 0x80, "F17" }, { 0x81, "F18" }, { 0x82, "F19" }, { 0x83, "F20" },
            { 0x84, "F21" }, { 0x85, "F22" }, { 0x86, "F23" }, { 0x87, "F24" },

            // Common keys
            { 0x0D, "Enter" }, { 0x20, "Space" }, { 0x08, "Backspace" },
            { 0x2E, "Delete" }, { 0x1B, "Esc" }, { 0x09, "Tab" },
            { 0x25, "Left" }, { 0x26, "Up" }, { 0x27, "Right" }, { 0x28, "Down" },
            { 0x24, "Home" }, { 0x23, "End" }, { 0x21, "PgUp" }, { 0x22, "PgDn" },
            { 0x2C, "PrtSc" }, { 0x91, "ScrLk" }, { 0x13, "Pause" },
            { 0x2D, "Insert" }, { 0x90, "NumLock" },

            // Alphanumeric (A-Z are 0x41-0x5A)
        };

        if (knownKeys.TryGetValue(vk, out var name))
            return name;

        // A-Z
        if (vk >= 0x41 && vk <= 0x5A)
            return ((char)vk).ToString();

        // 0-9
        if (vk >= 0x30 && vk <= 0x39)
            return ((char)vk).ToString();

        // Numpad 0-9
        if (vk >= 0x60 && vk <= 0x69)
            return $"Num{vk - 0x60}";

        return $"VK{vk:X2}";
    }
}

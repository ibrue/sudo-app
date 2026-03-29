using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using SudoWindows.Models;

namespace SudoWindows.Services;

/// <summary>
/// Executes simple preset actions by simulating keystrokes using Win32 SendInput API.
/// </summary>
public class SimpleActionExecutor
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public INPUTUNION union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;

    // Virtual key codes
    private const ushort VK_LWIN = 0x5B;
    private const ushort VK_SHIFT = 0x10;
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_MENU = 0x12; // Alt

    public bool Execute(SimpleActionType actionType)
    {
        if (!SimpleAction.Actions.TryGetValue(actionType, out var info))
        {
            Console.WriteLine($"[sudo] Unknown simple action: {actionType}");
            return false;
        }

        bool needsWin = SimpleAction.RequiresWinKey(actionType);
        var inputs = new List<INPUT>();

        // Press modifiers
        if (needsWin)
            inputs.Add(MakeKeyInput(VK_LWIN, false));
        if (info.Modifiers.HasFlag(Keys.Control))
            inputs.Add(MakeKeyInput(VK_CONTROL, false));
        if (info.Modifiers.HasFlag(Keys.Shift))
            inputs.Add(MakeKeyInput(VK_SHIFT, false));
        if (info.Modifiers.HasFlag(Keys.Alt))
            inputs.Add(MakeKeyInput(VK_MENU, false));

        // Press main key
        ushort mainVk = (ushort)info.Key;
        inputs.Add(MakeKeyInput(mainVk, false));

        // Release main key
        inputs.Add(MakeKeyInput(mainVk, true));

        // Release modifiers (reverse order)
        if (info.Modifiers.HasFlag(Keys.Alt))
            inputs.Add(MakeKeyInput(VK_MENU, true));
        if (info.Modifiers.HasFlag(Keys.Shift))
            inputs.Add(MakeKeyInput(VK_SHIFT, true));
        if (info.Modifiers.HasFlag(Keys.Control))
            inputs.Add(MakeKeyInput(VK_CONTROL, true));
        if (needsWin)
            inputs.Add(MakeKeyInput(VK_LWIN, true));

        var inputArray = inputs.ToArray();
        uint sent = SendInput((uint)inputArray.Length, inputArray, Marshal.SizeOf<INPUT>());

        if (sent == inputArray.Length)
        {
            Console.WriteLine($"[sudo] Executed simple action: {info.DisplayName}");
            return true;
        }

        Console.WriteLine($"[sudo] SendInput failed for: {info.DisplayName} (sent {sent}/{inputArray.Length})");
        return false;
    }

    private static INPUT MakeKeyInput(ushort vk, bool keyUp)
    {
        uint flags = keyUp ? KEYEVENTF_KEYUP : 0;
        // Extended key flag for special keys
        if (vk == VK_LWIN || vk == VK_MENU)
            flags |= KEYEVENTF_EXTENDEDKEY;

        return new INPUT
        {
            type = INPUT_KEYBOARD,
            union = new INPUTUNION
            {
                ki = new KEYBDINPUT
                {
                    wVk = vk,
                    wScan = 0,
                    dwFlags = flags,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero
                }
            }
        };
    }
}

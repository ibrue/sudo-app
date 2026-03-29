using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using SudoWindows.Models;

namespace SudoWindows.Services;

/// <summary>
/// Listens for global Ctrl+Shift+F13-F16 hotkey events from the macro pad.
/// Uses RegisterHotKey Win32 API.
/// </summary>
public class HotkeyListener : IDisposable
{
    public event Action<PadActionType>? HotkeyPressed;

    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;

    // Hotkey IDs (arbitrary unique ints)
    private const int HOTKEY_ID_BASE = 0x5D00;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private readonly Dictionary<int, PadActionType> _hotkeyMap = new();
    private HotkeyWindow? _window;
    private bool _disposed;

    public bool Start()
    {
        if (_window != null) return true;

        _window = new HotkeyWindow();
        _window.HotkeyReceived += OnHotkeyReceived;

        bool allRegistered = true;
        int index = 0;
        foreach (var action in PadAction.AllActions)
        {
            int hotkeyId = HOTKEY_ID_BASE + index;
            uint vk = (uint)action.GetKeyCode();

            if (RegisterHotKey(_window.Handle, hotkeyId, MOD_CONTROL | MOD_SHIFT, vk))
            {
                _hotkeyMap[hotkeyId] = action;
                Console.WriteLine($"[sudo] Registered hotkey: Ctrl+Shift+F{action.GetFKeyNumber()} (id={hotkeyId})");
            }
            else
            {
                int error = Marshal.GetLastWin32Error();
                Console.WriteLine($"[sudo] ERROR: Failed to register Ctrl+Shift+F{action.GetFKeyNumber()} (error={error})");
                allRegistered = false;
            }
            index++;
        }

        Console.WriteLine("[sudo] Hotkey listener active - waiting for macro pad input");
        return allRegistered;
    }

    public void Stop()
    {
        if (_window == null) return;

        foreach (var hotkeyId in _hotkeyMap.Keys)
        {
            UnregisterHotKey(_window.Handle, hotkeyId);
        }
        _hotkeyMap.Clear();

        _window.HotkeyReceived -= OnHotkeyReceived;
        _window.DestroyHandle();
        _window = null;
    }

    private void OnHotkeyReceived(int hotkeyId)
    {
        if (_hotkeyMap.TryGetValue(hotkeyId, out var action))
        {
            Console.WriteLine($"[sudo] Received: {action.GetDisplayName()} (F{action.GetFKeyNumber()})");
            HotkeyPressed?.Invoke(action);
        }
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            Stop();
            _disposed = true;
        }
        GC.SuppressFinalize(this);
    }

    /// <summary>
    /// Hidden NativeWindow that receives WM_HOTKEY messages.
    /// </summary>
    private class HotkeyWindow : NativeWindow
    {
        public event Action<int>? HotkeyReceived;

        public HotkeyWindow()
        {
            CreateHandle(new CreateParams
            {
                Caption = "SudoHotkeyWindow",
                Style = 0,
                ExStyle = 0,
                Parent = IntPtr.Zero
            });
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                int hotkeyId = m.WParam.ToInt32();
                HotkeyReceived?.Invoke(hotkeyId);
            }
            base.WndProc(ref m);
        }
    }
}

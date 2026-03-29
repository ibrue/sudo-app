using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using SudoWindows.Models;

namespace SudoWindows.Services;

/// <summary>
/// Listens for global hotkey events from the macro pad.
/// Uses RegisterHotKey Win32 API. Hotkey combos are configurable via ButtonConfigStore
/// (defaults to Ctrl+Shift+F13-F16).
/// </summary>
public class HotkeyListener : IDisposable
{
    public event Action<PadActionType>? HotkeyPressed;

    private const int WM_HOTKEY = 0x0312;

    // Hotkey IDs (arbitrary unique ints)
    private const int HOTKEY_ID_BASE = 0x5D00;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private readonly Dictionary<int, PadActionType> _hotkeyMap = new();
    private HotkeyWindow? _window;
    private bool _disposed;
    private bool _started;

    public bool Start()
    {
        if (_window != null) return true;

        _window = new HotkeyWindow();
        _window.HotkeyReceived += OnHotkeyReceived;

        bool allRegistered = RegisterAllHotkeys();

        // Listen for hotkey config changes
        ButtonConfigStore.Shared.HotkeyConfigChanged += OnHotkeyConfigChanged;

        _started = true;
        Console.WriteLine("[sudo] Hotkey listener active - waiting for macro pad input");
        return allRegistered;
    }

    /// <summary>
    /// Unregisters all current hotkeys and re-registers with current config.
    /// Call when hotkey configuration changes.
    /// </summary>
    public void Restart()
    {
        if (_window == null) return;

        UnregisterAllHotkeys();
        RegisterAllHotkeys();
        Console.WriteLine("[sudo] Hotkey listener restarted with updated config");
    }

    public void Stop()
    {
        if (_window == null) return;

        if (_started)
        {
            ButtonConfigStore.Shared.HotkeyConfigChanged -= OnHotkeyConfigChanged;
            _started = false;
        }

        UnregisterAllHotkeys();

        _window.HotkeyReceived -= OnHotkeyReceived;
        _window.DestroyHandle();
        _window = null;
    }

    private bool RegisterAllHotkeys()
    {
        var configStore = ButtonConfigStore.Shared;
        bool allRegistered = true;
        int index = 0;

        foreach (var action in PadAction.AllActions)
        {
            int hotkeyId = HOTKEY_ID_BASE + index;
            var config = configStore.GetHotkeyConfig(action);

            if (RegisterHotKey(_window!.Handle, hotkeyId, config.Modifiers, config.KeyCode))
            {
                _hotkeyMap[hotkeyId] = action;
                Console.WriteLine($"[sudo] Registered hotkey: {config.DisplayString} (id={hotkeyId})");
            }
            else
            {
                int error = Marshal.GetLastWin32Error();
                Console.WriteLine($"[sudo] ERROR: Failed to register {config.DisplayString} (error={error})");
                allRegistered = false;
            }
            index++;
        }

        return allRegistered;
    }

    private void UnregisterAllHotkeys()
    {
        if (_window == null) return;

        foreach (var hotkeyId in _hotkeyMap.Keys)
        {
            UnregisterHotKey(_window.Handle, hotkeyId);
        }
        _hotkeyMap.Clear();
    }

    private void OnHotkeyConfigChanged()
    {
        Restart();
    }

    private void OnHotkeyReceived(int hotkeyId)
    {
        if (_hotkeyMap.TryGetValue(hotkeyId, out var action))
        {
            var config = ButtonConfigStore.Shared.GetHotkeyConfig(action);
            Console.WriteLine($"[sudo] Received: {action.GetDisplayName()} ({config.DisplayString})");
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

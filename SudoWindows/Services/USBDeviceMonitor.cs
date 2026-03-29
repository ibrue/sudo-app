using System;
using System.Management;

namespace SudoWindows.Services;

/// <summary>
/// Monitors USB device connections/disconnections for the Sudo Pad device.
/// VID: 0x5D00, PID: 0x5D01
/// </summary>
public class USBDeviceMonitor : IDisposable
{
    private const string DeviceIdPattern = "%VID_5D00&PID_5D01%";

    private ManagementEventWatcher? _connectWatcher;
    private ManagementEventWatcher? _disconnectWatcher;
    private bool _disposed;

    public bool IsDeviceConnected { get; private set; }

    public event Action? DeviceConnected;
    public event Action? DeviceDisconnected;

    /// <summary>
    /// Checks if the device is currently connected and starts monitoring for changes.
    /// </summary>
    public void Start()
    {
        // Check if device is already connected on startup
        CheckDevicePresent();

        // Watch for device arrival
        try
        {
            var connectQuery = new WqlEventQuery(
                "SELECT * FROM __InstanceCreationEvent WITHIN 2 " +
                "WHERE TargetInstance ISA 'Win32_PnPEntity'");
            _connectWatcher = new ManagementEventWatcher(connectQuery);
            _connectWatcher.EventArrived += OnDeviceEvent;
            _connectWatcher.Start();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] USB connect watcher failed to start: {ex.Message}");
        }

        // Watch for device removal
        try
        {
            var disconnectQuery = new WqlEventQuery(
                "SELECT * FROM __InstanceDeletionEvent WITHIN 2 " +
                "WHERE TargetInstance ISA 'Win32_PnPEntity'");
            _disconnectWatcher = new ManagementEventWatcher(disconnectQuery);
            _disconnectWatcher.EventArrived += OnDeviceEvent;
            _disconnectWatcher.Start();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] USB disconnect watcher failed to start: {ex.Message}");
        }
    }

    private void OnDeviceEvent(object sender, EventArrivedEventArgs e)
    {
        // When any PnP event fires, re-check whether our device is present.
        // This is simpler and more reliable than parsing the event target.
        bool wasConnected = IsDeviceConnected;
        CheckDevicePresent();

        if (IsDeviceConnected && !wasConnected)
        {
            Console.WriteLine("[sudo] USB device connected (VID_5D00&PID_5D01)");
            DeviceConnected?.Invoke();
        }
        else if (!IsDeviceConnected && wasConnected)
        {
            Console.WriteLine("[sudo] USB device disconnected (VID_5D00&PID_5D01)");
            DeviceDisconnected?.Invoke();
        }
    }

    private void CheckDevicePresent()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                $"SELECT * FROM Win32_PnPEntity WHERE DeviceID LIKE '{DeviceIdPattern}'");
            using var results = searcher.Get();
            IsDeviceConnected = results.Count > 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] USB device query failed: {ex.Message}");
            IsDeviceConnected = false;
        }
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            _connectWatcher?.Stop();
            _connectWatcher?.Dispose();
            _disconnectWatcher?.Stop();
            _disconnectWatcher?.Dispose();
            _disposed = true;
        }
        GC.SuppressFinalize(this);
    }
}

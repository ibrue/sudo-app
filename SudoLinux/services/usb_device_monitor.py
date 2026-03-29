"""Monitor USB device connections for the Sudo Pad (VID:0x5D00, PID:0x5D01)."""

import subprocess
import threading

try:
    import pyudev
    HAS_PYUDEV = True
except ImportError:
    HAS_PYUDEV = False

# Sudo Pad USB identifiers
SUDO_VID = "5d00"
SUDO_PID = "5d01"


def check_device_connected():
    """Check if Sudo Pad is connected via lsusb."""
    try:
        result = subprocess.run(
            ["lsusb", "-d", f"{SUDO_VID}:{SUDO_PID}"],
            capture_output=True, text=True, timeout=5,
        )
        return result.returncode == 0 and result.stdout.strip() != ""
    except Exception:
        return False


class USBDeviceMonitor:
    """Monitors USB events for the Sudo Pad device.

    Uses pyudev for live monitoring when available, otherwise falls back
    to polling lsusb every 2 seconds via GLib.timeout_add.
    """

    def __init__(self):
        self._connected = False
        self._on_connected_cb = None
        self._on_disconnected_cb = None
        self._udev_thread = None
        self._poll_timer_id = None
        self._running = False

    @property
    def is_device_connected(self):
        """Whether the Sudo Pad is currently connected."""
        return self._connected

    def on_device_connected(self, callback):
        """Register callback for device connection events."""
        self._on_connected_cb = callback

    def on_device_disconnected(self, callback):
        """Register callback for device disconnection events."""
        self._on_disconnected_cb = callback

    def start(self):
        """Start monitoring. Checks current state then watches for changes."""
        self._running = True

        # Check initial state
        self._connected = check_device_connected()
        if self._connected:
            self._fire_connected()

        if HAS_PYUDEV:
            self._start_udev_monitor()
        else:
            print("[sudo] pyudev not available; falling back to polling lsusb")
            self._start_polling()

    def stop(self):
        """Stop monitoring."""
        self._running = False
        if self._poll_timer_id is not None:
            from gi.repository import GLib
            GLib.source_remove(self._poll_timer_id)
            self._poll_timer_id = None

    # -- pyudev live monitoring ------------------------------------------

    def _start_udev_monitor(self):
        """Start a background thread watching udev for USB events."""
        self._udev_thread = threading.Thread(
            target=self._udev_loop, daemon=True
        )
        self._udev_thread.start()
        print("[sudo] USB monitoring via pyudev")

    def _udev_loop(self):
        """Background loop reading udev events."""
        try:
            context = pyudev.Context()
            monitor = pyudev.Monitor.from_netlink(context)
            monitor.filter_by(subsystem="usb")
            for device in iter(monitor.poll, None):
                if not self._running:
                    break
                if device.action in ("add", "remove"):
                    vid = (device.get("ID_VENDOR_ID") or "").lower()
                    pid = (device.get("ID_MODEL_ID") or "").lower()
                    if vid == SUDO_VID and pid == SUDO_PID:
                        from gi.repository import GLib
                        if device.action == "add":
                            GLib.idle_add(self._handle_connected)
                        else:
                            GLib.idle_add(self._handle_disconnected)
        except Exception as e:
            print(f"[sudo] udev monitor error: {e}; falling back to polling")
            if self._running:
                from gi.repository import GLib
                GLib.idle_add(self._start_polling)

    # -- polling fallback ------------------------------------------------

    def _start_polling(self):
        """Poll lsusb every 2 seconds using GLib."""
        from gi.repository import GLib
        self._poll_timer_id = GLib.timeout_add(2000, self._poll_tick)

    def _poll_tick(self):
        """Single poll tick."""
        if not self._running:
            return False  # stop the timer

        connected = check_device_connected()
        if connected and not self._connected:
            self._handle_connected()
        elif not connected and self._connected:
            self._handle_disconnected()
        return True  # keep polling

    # -- state transitions -----------------------------------------------

    def _handle_connected(self):
        self._connected = True
        print("[sudo] Sudo Pad USB device connected")
        self._fire_connected()

    def _handle_disconnected(self):
        self._connected = False
        print("[sudo] Sudo Pad USB device disconnected")
        self._fire_disconnected()

    def _fire_connected(self):
        if self._on_connected_cb:
            try:
                self._on_connected_cb()
            except Exception:
                pass

    def _fire_disconnected(self):
        if self._on_disconnected_cb:
            try:
                self._on_disconnected_cb()
            except Exception:
                pass

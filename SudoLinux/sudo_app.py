#!/usr/bin/env python3
"""[sudo] - Macro pad companion app for Linux.

Main entry point: single-instance check, GTK initialization, tray app startup.
"""

import os
import sys
import fcntl
import signal

LOCK_FILE = "/tmp/sudo-app.lock"


def acquire_lock():
    """Ensure only one instance of the app is running via a lock file."""
    try:
        lock_fd = open(LOCK_FILE, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock_fd.write(str(os.getpid()))
        lock_fd.flush()
        return lock_fd
    except (IOError, OSError):
        print("[sudo] Another instance is already running.")
        sys.exit(1)


def main():
    """Main entry point."""
    # Add the app directory to the Python path so imports work
    app_dir = os.path.dirname(os.path.abspath(__file__))
    if app_dir not in sys.path:
        sys.path.insert(0, app_dir)

    # Single-instance check
    lock_fd = acquire_lock()

    # Handle SIGINT/SIGTERM gracefully
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)

    # Initialize GTK
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk, GLib

    # Set the application name
    GLib.set_application_name("[sudo]")
    GLib.set_prgname("sudo-app")

    print("[sudo] Starting macro pad companion app...")

    # Create and start the tray app
    from views.tray_app import TrayApp
    tray = TrayApp()

    print("[sudo] Running GTK main loop")
    try:
        Gtk.main()
    except KeyboardInterrupt:
        pass
    finally:
        # Clean up lock file
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            lock_fd.close()
            os.unlink(LOCK_FILE)
        except OSError:
            pass

    print("[sudo] Exiting")


if __name__ == "__main__":
    main()

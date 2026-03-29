"""System tray application using AppIndicator3."""

import os
import sys

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

try:
    gi.require_version("AppIndicator3", "0.1")
    from gi.repository import AppIndicator3
    HAS_APPINDICATOR = True
except (ImportError, ValueError):
    HAS_APPINDICATOR = False
    print("[sudo] AppIndicator3 not available. Install: apt install gir1.2-appindicator3-0.1")

from models.pad_action import PadAction
from services.sudo_engine import SudoEngine
from services.button_config_store import ButtonConfigStore
from views.icon import create_tray_icon


class TrayApp:
    """System tray application with context menu.

    Equivalent to MenuBarView on macOS and TrayApp on Windows.
    """

    def __init__(self):
        self._engine = SudoEngine()
        self._config_store = ButtonConfigStore.shared()
        self._config_window = None
        self._test_pad_window = None
        self._menu_items = {}

        # Create tray icon
        icon_path = create_tray_icon()
        if icon_path and HAS_APPINDICATOR:
            # AppIndicator3 needs the icon directory and icon name (without extension)
            icon_dir = os.path.dirname(icon_path)
            icon_name = os.path.splitext(os.path.basename(icon_path))[0]
            self._indicator = AppIndicator3.Indicator.new(
                "sudo-app",
                icon_name,
                AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
            )
            self._indicator.set_icon_theme_path(icon_dir)
            self._indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
            self._indicator.set_title("[sudo]")

            # Build and set the menu
            menu = self._build_menu()
            self._indicator.set_menu(menu)
        elif not HAS_APPINDICATOR:
            print("[sudo] WARNING: No system tray support. Running headless.")

        # Listen for status changes
        self._engine.on_status_change(self._on_status_changed)
        self._config_store.on_change(self._on_config_changed)

        # Start the engine
        self._engine.start()

    def _build_menu(self):
        """Build the GTK context menu."""
        menu = Gtk.Menu()

        # Header
        header = Gtk.MenuItem(label="[sudo]")
        header.set_sensitive(False)
        menu.append(header)

        menu.append(Gtk.SeparatorMenuItem())

        # Status section
        self._menu_items["status"] = Gtk.MenuItem(label="Status: Checking...")
        self._menu_items["status"].set_sensitive(False)
        menu.append(self._menu_items["status"])

        self._menu_items["device"] = Gtk.MenuItem(label="Device: Checking...")
        self._menu_items["device"].set_sensitive(False)
        menu.append(self._menu_items["device"])

        self._menu_items["app"] = Gtk.MenuItem(label="app: No AI app detected")
        self._menu_items["app"].set_sensitive(False)
        menu.append(self._menu_items["app"])

        self._menu_items["last"] = Gtk.MenuItem(label="last: Waiting for input...")
        self._menu_items["last"].set_sensitive(False)
        menu.append(self._menu_items["last"])

        self._menu_items["via"] = Gtk.MenuItem(label="via: -")
        self._menu_items["via"].set_sensitive(False)
        menu.append(self._menu_items["via"])

        menu.append(Gtk.SeparatorMenuItem())

        # Button map header
        btn_header = Gtk.MenuItem(label="> button map")
        btn_header.set_sensitive(False)
        menu.append(btn_header)

        # Button map entries
        for action in PadAction:
            config = self._config_store.hotkey_config(action)
            label = f"{config.display_string}  {action.display_name}"
            if self._config_store.is_customized(action):
                label += " *"
            item = Gtk.MenuItem(label=label)
            item.set_sensitive(False)
            self._menu_items[f"btn_{action.value}"] = item
            menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        # Test Mode
        self._menu_items["test_mode"] = Gtk.MenuItem(label="Test Mode (Virtual Pad)...")
        self._menu_items["test_mode"].connect("activate", self._on_test_mode)
        menu.append(self._menu_items["test_mode"])

        # Configure Buttons
        config_item = Gtk.MenuItem(label="Configure Buttons...")
        config_item.connect("activate", self._on_configure)
        menu.append(config_item)

        menu.append(Gtk.SeparatorMenuItem())

        # Quit
        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", self._on_quit)
        menu.append(quit_item)

        menu.show_all()
        return menu

    def _on_status_changed(self):
        """Update menu items when engine status changes."""
        GLib.idle_add(self._update_menu_items)

    def _on_config_changed(self):
        """Update button map when config changes."""
        GLib.idle_add(self._update_button_map)

    def _update_menu_items(self):
        """Update the status display in the menu."""
        status_text = "Status: Connected" if self._engine.is_connected else "Status: Disconnected"
        self._menu_items["status"].set_label(status_text)

        # Device connection state
        if self._engine.is_device_connected:
            self._menu_items["device"].set_label("Device: Sudo Pad connected")
        else:
            self._menu_items["device"].set_label("Device: Not connected (use Test Mode)")

        # Make Test Mode label more prominent when device is disconnected
        if not self._engine.is_device_connected:
            self._menu_items["test_mode"].set_label(">>> Test Mode (Virtual Pad) <<<")
        else:
            self._menu_items["test_mode"].set_label("Test Mode (Virtual Pad)...")

        self._menu_items["app"].set_label(f"app: {self._engine.detected_app}")
        self._menu_items["last"].set_label(f"last: {self._engine.last_action}")

        via_text = f"via: {self._engine.last_method}" if self._engine.last_method else "via: -"
        self._menu_items["via"].set_label(via_text)

    def _update_button_map(self):
        """Update the button map entries in the menu."""
        for action in PadAction:
            key = f"btn_{action.value}"
            if key in self._menu_items:
                config = self._config_store.hotkey_config(action)
                label = f"{config.display_string}  {action.display_name}"
                if self._config_store.is_customized(action):
                    label += " *"
                self._menu_items[key].set_label(label)

    def _on_test_mode(self, _widget):
        """Open the virtual macro pad test window."""
        if self._test_pad_window is not None:
            self._test_pad_window.present()
            return

        from views.test_pad_window import TestPadWindow
        self._test_pad_window = TestPadWindow(self._engine)
        self._test_pad_window.connect("destroy", self._on_test_pad_closed)
        self._test_pad_window.show_all()

    def _on_test_pad_closed(self, _widget):
        """Handle test pad window being closed."""
        self._test_pad_window = None

    def _on_configure(self, _widget):
        """Open the configuration window."""
        if self._config_window is not None:
            self._config_window.present()
            return

        from views.config_window import ConfigWindow
        self._config_window = ConfigWindow()
        self._config_window.connect("destroy", self._on_config_closed)
        self._config_window.show_all()

    def _on_config_closed(self, _widget):
        """Handle config window being closed."""
        self._config_window = None

    def _on_quit(self, _widget):
        """Clean up and quit the application."""
        self._engine.stop()
        Gtk.main_quit()

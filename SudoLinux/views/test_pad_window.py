"""Virtual macro pad window for testing without the physical device."""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk

from models.pad_action import PadAction
from services.button_config_store import ButtonConfigStore


# CSS styling for the keycap buttons and window
TEST_PAD_CSS = """
#test-pad-window {
    background-color: #0A0A0A;
}

.keycap-button {
    background-image: none;
    background-color: #2A2A2A;
    border-top: 2px solid #444444;
    border-left: 2px solid #3A3A3A;
    border-right: 2px solid #1A1A1A;
    border-bottom: 3px solid #111111;
    border-radius: 4px;
    padding: 6px 12px;
    min-width: 160px;
    min-height: 56px;
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.06);
}

.keycap-button:hover {
    background-color: #353535;
    border-top-color: #505050;
}

.keycap-button:active {
    background-color: #1E1E1E;
    border-top: 1px solid #222222;
    border-bottom: 2px solid #222222;
    padding-top: 8px;
}

.keycap-label {
    color: #FFFFFF;
    font-size: 13px;
    font-weight: bold;
}

.keycap-hotkey {
    color: #777777;
    font-size: 10px;
}
"""


class TestPadWindow(Gtk.Window):
    """A virtual macro pad window that simulates button presses."""

    def __init__(self, engine):
        super().__init__(title="[sudo] Test Mode")
        self._engine = engine
        self._config_store = ButtonConfigStore.shared()

        self.set_default_size(200, 300)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_name("test-pad-window")

        # Apply CSS
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(TEST_PAD_CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # Main vertical box
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        vbox.set_margin_top(8)
        vbox.set_margin_bottom(8)
        vbox.set_margin_start(16)
        vbox.set_margin_end(16)

        for action in PadAction:
            btn = self._make_keycap_button(action)
            vbox.pack_start(btn, False, False, 0)

        self.add(vbox)

    def _make_keycap_button(self, action):
        """Create a keycap-styled button for the given action."""
        config = self._config_store.hotkey_config(action)

        # Vertical box inside the button for two-line label
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)

        label = Gtk.Label(label=action.display_name)
        label.get_style_context().add_class("keycap-label")
        inner.pack_start(label, False, False, 0)

        hotkey_label = Gtk.Label(label=config.display_string)
        hotkey_label.get_style_context().add_class("keycap-hotkey")
        inner.pack_start(hotkey_label, False, False, 0)

        button = Gtk.Button()
        button.add(inner)
        button.get_style_context().add_class("keycap-button")
        button.connect("clicked", self._on_keycap_clicked, action)

        return button

    def _on_keycap_clicked(self, _widget, action):
        """Handle a keycap button click by simulating the action."""
        print(f"[sudo] Test mode: simulating {action.display_name}")
        self._engine.simulate_action(action)

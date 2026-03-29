"""GTK3 configuration window with dark Matrix theme."""

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, GLib

from models.pad_action import PadAction
from models.button_mode import ButtonMode
from models.simple_action import SimpleAction
from models.hotkey_config import HotkeyConfig, MOD_CONTROL, MOD_ALT, MOD_SHIFT, MOD_SUPER
from services.button_config_store import ButtonConfigStore

# Dark Matrix theme colors
BG_COLOR = "#0A0A0A"
PANEL_BG = "#1A1A1A"
BORDER_COLOR = "#1E1E1E"
GREEN_ACCENT = "#00FF41"
DIM_TEXT = "#666666"
WHITE_TEXT = "#FFFFFF"
RED_ACCENT = "#FF3333"
BLUE_ACCENT = "#00BFFF"

# CSS for the dark theme
_CSS = f"""
window.sudo-config {{
    background-color: {BG_COLOR};
}}

.sudo-header {{
    color: {GREEN_ACCENT};
    font-family: monospace;
    font-size: 14px;
    font-weight: bold;
}}

.sudo-label {{
    color: {WHITE_TEXT};
    font-family: monospace;
    font-size: 11px;
}}

.sudo-dim {{
    color: {DIM_TEXT};
    font-family: monospace;
    font-size: 10px;
}}

.sudo-green {{
    color: {GREEN_ACCENT};
    font-family: monospace;
    font-weight: bold;
}}

.sudo-blue {{
    color: {BLUE_ACCENT};
    font-family: monospace;
    font-weight: bold;
}}

notebook {{
    background-color: {BG_COLOR};
}}

notebook header {{
    background-color: {BG_COLOR};
}}

notebook header tab {{
    background-color: {BG_COLOR};
    color: {DIM_TEXT};
    font-family: monospace;
    font-weight: bold;
    padding: 6px 12px;
    border: 1px solid {BORDER_COLOR};
}}

notebook header tab:checked {{
    background-color: {PANEL_BG};
    color: {GREEN_ACCENT};
}}

notebook > stack {{
    background-color: {BG_COLOR};
}}

.sudo-entry {{
    background-color: {PANEL_BG};
    color: {WHITE_TEXT};
    font-family: monospace;
    font-size: 11px;
    border: 1px solid {BORDER_COLOR};
    padding: 4px;
}}

.sudo-textview {{
    background-color: {PANEL_BG};
    color: {WHITE_TEXT};
    font-family: monospace;
    font-size: 11px;
}}

.sudo-textview text {{
    background-color: {PANEL_BG};
    color: {WHITE_TEXT};
}}

.sudo-combo {{
    background-color: {PANEL_BG};
    color: {WHITE_TEXT};
    font-family: monospace;
    font-size: 11px;
    border: 1px solid {BORDER_COLOR};
}}

.sudo-button-green {{
    background-color: {BG_COLOR};
    color: {GREEN_ACCENT};
    font-family: monospace;
    border: 1px solid {GREEN_ACCENT};
    padding: 4px 10px;
}}

.sudo-button-green:hover {{
    background-color: {BORDER_COLOR};
}}

.sudo-button-red {{
    background-color: {BG_COLOR};
    color: {RED_ACCENT};
    font-family: monospace;
    border: 1px solid {RED_ACCENT};
    padding: 4px 10px;
}}

.sudo-button-red:hover {{
    background-color: {BORDER_COLOR};
}}

.sudo-button-dim {{
    background-color: {BG_COLOR};
    color: {DIM_TEXT};
    font-family: monospace;
    border: 1px solid {DIM_TEXT};
    padding: 4px 10px;
}}

.sudo-button-dim:hover {{
    background-color: {BORDER_COLOR};
}}

radiobutton {{
    color: {WHITE_TEXT};
    font-family: monospace;
}}

radiobutton label {{
    color: {WHITE_TEXT};
    font-family: monospace;
    font-size: 11px;
}}
"""


class ConfigWindow(Gtk.Window):
    """GTK3 settings window with dark Matrix-style theme.

    Equivalent to ButtonConfigView on macOS and ConfigForm on Windows.
    """

    def __init__(self):
        super().__init__(title="[sudo] Key Bindings")
        self.set_default_size(460, 520)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.get_style_context().add_class("sudo-config")

        # Apply CSS
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(_CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        self._config_store = ButtonConfigStore.shared()
        self._tab_widgets = {}   # action -> {widget_name: widget}
        self._recording_action = None

        # Enable key event capture for hotkey recording
        self.connect("key-press-event", self._on_key_press)

        # Main layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        vbox.set_margin_start(12)
        vbox.set_margin_end(12)
        vbox.set_margin_top(8)
        vbox.set_margin_bottom(8)
        self.add(vbox)

        # Header
        header = Gtk.Label(label="> key bindings")
        header.set_halign(Gtk.Align.START)
        header.get_style_context().add_class("sudo-header")
        vbox.pack_start(header, False, False, 4)

        # Notebook (tabs)
        notebook = Gtk.Notebook()
        vbox.pack_start(notebook, True, True, 0)

        for action in PadAction:
            tab_content = self._create_action_tab(action)
            tab_label = Gtk.Label(label=f"F{action.f_key_number}")
            notebook.append_page(tab_content, tab_label)

        # Bottom buttons
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        vbox.pack_start(button_box, False, False, 4)

        reset_all_btn = Gtk.Button(label="[ RESET ALL TO DEFAULTS ]")
        reset_all_btn.get_style_context().add_class("sudo-button-red")
        reset_all_btn.connect("clicked", self._on_reset_all)
        button_box.pack_start(reset_all_btn, False, False, 0)

        # Spacer
        button_box.pack_start(Gtk.Box(), True, True, 0)

        save_btn = Gtk.Button(label="[ SAVE ]")
        save_btn.get_style_context().add_class("sudo-button-green")
        save_btn.connect("clicked", self._on_save)
        button_box.pack_start(save_btn, False, False, 0)

        cancel_btn = Gtk.Button(label="[ CANCEL ]")
        cancel_btn.get_style_context().add_class("sudo-button-dim")
        cancel_btn.connect("clicked", self._on_cancel)
        button_box.pack_start(cancel_btn, False, False, 0)

    def _create_action_tab(self, action):
        """Create the configuration tab for one pad action."""
        widgets = {}
        self._tab_widgets[action] = widgets

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        vbox.set_margin_start(10)
        vbox.set_margin_end(10)
        vbox.set_margin_top(10)
        vbox.set_margin_bottom(10)

        # Action name header
        name_label = Gtk.Label(label=f"F{action.f_key_number} - {action.display_name}")
        name_label.set_halign(Gtk.Align.START)
        name_label.get_style_context().add_class("sudo-green")
        vbox.pack_start(name_label, False, False, 0)

        # Hotkey binding section
        hotkey_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        vbox.pack_start(hotkey_box, False, False, 0)

        hotkey_label = Gtk.Label(label="Hotkey:")
        hotkey_label.get_style_context().add_class("sudo-dim")
        hotkey_box.pack_start(hotkey_label, False, False, 0)

        config = self._config_store.hotkey_config(action)
        hotkey_display = Gtk.Label(label=config.display_string)
        if self._config_store.has_custom_hotkey(action):
            hotkey_display.get_style_context().add_class("sudo-blue")
        else:
            hotkey_display.get_style_context().add_class("sudo-label")
        widgets["hotkey_display"] = hotkey_display
        hotkey_box.pack_start(hotkey_display, False, False, 0)

        record_btn = Gtk.Button(label="[ RECORD ]")
        record_btn.get_style_context().add_class("sudo-button-green")
        record_btn.connect("clicked", lambda _w, a=action: self._start_recording(a))
        widgets["record_btn"] = record_btn
        hotkey_box.pack_start(record_btn, False, False, 0)

        hotkey_reset_btn = Gtk.Button(label="[ RESET ]")
        hotkey_reset_btn.get_style_context().add_class("sudo-button-red")
        hotkey_reset_btn.connect("clicked", lambda _w, a=action: self._reset_hotkey(a))
        if not self._config_store.has_custom_hotkey(action):
            hotkey_reset_btn.set_visible(False)
            hotkey_reset_btn.set_no_show_all(True)
        widgets["hotkey_reset_btn"] = hotkey_reset_btn
        hotkey_box.pack_start(hotkey_reset_btn, False, False, 0)

        # Mode selection
        mode_label = Gtk.Label(label="Mode:")
        mode_label.set_halign(Gtk.Align.START)
        mode_label.get_style_context().add_class("sudo-dim")
        vbox.pack_start(mode_label, False, False, 0)

        simple_radio = Gtk.RadioButton.new_with_label(None, "Simple (preset action)")
        simple_radio.connect("toggled", lambda _w, a=action: self._on_mode_toggled(a))
        vbox.pack_start(simple_radio, False, False, 0)
        widgets["simple_radio"] = simple_radio

        complex_radio = Gtk.RadioButton.new_with_label_from_widget(
            simple_radio, "Complex (search UI for button)"
        )
        vbox.pack_start(complex_radio, False, False, 0)
        widgets["complex_radio"] = complex_radio

        # Simple mode: ComboBox grouped by category
        preset_label = Gtk.Label(label="Preset Action:")
        preset_label.set_halign(Gtk.Align.START)
        preset_label.get_style_context().add_class("sudo-dim")
        vbox.pack_start(preset_label, False, False, 0)

        combo_store = Gtk.ListStore(str, str)  # display_name, action_value
        for category, actions in SimpleAction.grouped_by_category():
            combo_store.append([f"--- {category} ---", ""])
            for sa in actions:
                combo_store.append([sa.display_name, sa.value])

        combo = Gtk.ComboBox.new_with_model(combo_store)
        combo.get_style_context().add_class("sudo-combo")
        renderer = Gtk.CellRendererText()
        combo.pack_start(renderer, True)
        combo.add_attribute(renderer, "text", 0)
        combo.set_row_separator_func(lambda model, iter_: model[iter_][1] == "" and "---" in model[iter_][0])
        widgets["combo"] = combo
        vbox.pack_start(combo, False, False, 0)

        # Complex mode: TextView for search terms
        terms_label = Gtk.Label(label="Search Terms (comma-separated):")
        terms_label.set_halign(Gtk.Align.START)
        terms_label.get_style_context().add_class("sudo-dim")
        vbox.pack_start(terms_label, False, False, 0)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_min_content_height(80)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        text_view = Gtk.TextView()
        text_view.set_wrap_mode(Gtk.WrapMode.WORD)
        text_view.get_style_context().add_class("sudo-textview")
        widgets["text_view"] = text_view
        scrolled.add(text_view)
        vbox.pack_start(scrolled, False, False, 0)

        # Reset this button
        reset_btn = Gtk.Button(label="[ RESET ]")
        reset_btn.set_halign(Gtk.Align.START)
        reset_btn.get_style_context().add_class("sudo-button-red")
        reset_btn.connect("clicked", lambda _w, a=action: self._reset_action(a))
        vbox.pack_start(reset_btn, False, False, 0)

        # Load current config
        self._refresh_tab(action)

        return vbox

    def _refresh_tab(self, action):
        """Refresh a tab with current configuration."""
        widgets = self._tab_widgets[action]
        mode = self._config_store.button_mode(action)

        if mode.is_simple:
            widgets["simple_radio"].set_active(True)
        else:
            widgets["complex_radio"].set_active(True)

        # Set combo selection
        if mode.is_simple and mode.simple_action is not None:
            combo = widgets["combo"]
            model = combo.get_model()
            for i, row in enumerate(model):
                if row[1] == mode.simple_action.value:
                    combo.set_active(i)
                    break

        # Set search terms
        terms = self._config_store.search_terms(action)
        text_buf = widgets["text_view"].get_buffer()
        text_buf.set_text(", ".join(terms))

        # Update hotkey display
        config = self._config_store.hotkey_config(action)
        widgets["hotkey_display"].set_text(config.display_string)

        self._update_mode_ui(action)

    def _on_mode_toggled(self, action):
        """Handle mode radio button toggle."""
        self._update_mode_ui(action)

    def _update_mode_ui(self, action):
        """Enable/disable widgets based on current mode selection."""
        widgets = self._tab_widgets[action]
        is_simple = widgets["simple_radio"].get_active()
        widgets["combo"].set_sensitive(is_simple)
        widgets["text_view"].set_sensitive(not is_simple)

    def _start_recording(self, action):
        """Begin recording a new hotkey."""
        self._recording_action = action
        widgets = self._tab_widgets[action]
        widgets["hotkey_display"].set_text("Press keys...")
        widgets["hotkey_display"].get_style_context().remove_class("sudo-label")
        widgets["hotkey_display"].get_style_context().remove_class("sudo-blue")
        widgets["hotkey_display"].get_style_context().add_class("sudo-green")
        widgets["record_btn"].set_label("[ CANCEL ]")
        widgets["record_btn"].get_style_context().remove_class("sudo-button-green")
        widgets["record_btn"].get_style_context().add_class("sudo-button-dim")

    def _stop_recording(self):
        """Cancel or finish hotkey recording."""
        if self._recording_action is not None:
            action = self._recording_action
            self._recording_action = None
            self._refresh_hotkey_display(action)

    def _refresh_hotkey_display(self, action):
        """Update the hotkey display for an action."""
        widgets = self._tab_widgets[action]
        config = self._config_store.hotkey_config(action)
        widgets["hotkey_display"].set_text(config.display_string)

        # Update style
        widgets["hotkey_display"].get_style_context().remove_class("sudo-green")
        widgets["hotkey_display"].get_style_context().remove_class("sudo-blue")
        widgets["hotkey_display"].get_style_context().remove_class("sudo-label")
        if self._config_store.has_custom_hotkey(action):
            widgets["hotkey_display"].get_style_context().add_class("sudo-blue")
        else:
            widgets["hotkey_display"].get_style_context().add_class("sudo-label")

        widgets["record_btn"].set_label("[ RECORD ]")
        widgets["record_btn"].get_style_context().remove_class("sudo-button-dim")
        widgets["record_btn"].get_style_context().add_class("sudo-button-green")

        widgets["hotkey_reset_btn"].set_visible(self._config_store.has_custom_hotkey(action))
        widgets["hotkey_reset_btn"].set_no_show_all(not self._config_store.has_custom_hotkey(action))

    def _reset_hotkey(self, action):
        """Reset the hotkey for an action to default."""
        self._config_store.reset_hotkey_config(action)
        self._refresh_hotkey_display(action)

    def _reset_action(self, action):
        """Reset a single action to defaults."""
        self._config_store.reset_to_defaults(action)
        self._refresh_tab(action)

    def _on_key_press(self, _widget, event):
        """Handle key press events for hotkey recording."""
        if self._recording_action is None:
            return False

        action = self._recording_action
        keyval = event.keyval
        state = event.state

        # Escape cancels recording
        if keyval == Gdk.KEY_Escape:
            self._stop_recording()
            return True

        # Ignore bare modifier presses
        modifier_keys = {
            Gdk.KEY_Control_L, Gdk.KEY_Control_R,
            Gdk.KEY_Shift_L, Gdk.KEY_Shift_R,
            Gdk.KEY_Alt_L, Gdk.KEY_Alt_R,
            Gdk.KEY_Super_L, Gdk.KEY_Super_R,
            Gdk.KEY_Meta_L, Gdk.KEY_Meta_R,
        }
        if keyval in modifier_keys:
            # Show modifier preview
            widgets = self._tab_widgets[action]
            parts = []
            if state & Gdk.ModifierType.CONTROL_MASK:
                parts.append("Ctrl")
            if state & Gdk.ModifierType.MOD1_MASK:
                parts.append("Alt")
            if state & Gdk.ModifierType.SHIFT_MASK:
                parts.append("Shift")
            if state & Gdk.ModifierType.SUPER_MASK or state & Gdk.ModifierType.MOD4_MASK:
                parts.append("Super")
            preview = "+".join(parts) + "..." if parts else "Press keys..."
            widgets["hotkey_display"].set_text(preview)
            return True

        # Build modifier flags
        modifiers = 0
        if state & Gdk.ModifierType.CONTROL_MASK:
            modifiers |= MOD_CONTROL
        if state & Gdk.ModifierType.MOD1_MASK:
            modifiers |= MOD_ALT
        if state & Gdk.ModifierType.SHIFT_MASK:
            modifiers |= MOD_SHIFT
        if state & (Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.MOD4_MASK):
            modifiers |= MOD_SUPER

        config = HotkeyConfig(keysym=keyval, modifiers=modifiers)
        self._config_store.set_hotkey_config(config, action)

        self._recording_action = None
        self._refresh_hotkey_display(action)
        return True

    def _on_reset_all(self, _widget):
        """Reset all buttons to defaults."""
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=Gtk.DialogFlags.MODAL,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Reset all buttons to defaults?",
        )
        response = dialog.run()
        dialog.destroy()
        if response == Gtk.ResponseType.YES:
            self._config_store.reset_all_to_defaults()
            for action in PadAction:
                self._refresh_tab(action)

    def _on_save(self, _widget):
        """Save all configuration and close."""
        for action in PadAction:
            widgets = self._tab_widgets[action]
            is_simple = widgets["simple_radio"].get_active()

            simple_action = None
            if is_simple:
                combo = widgets["combo"]
                active = combo.get_active()
                if active >= 0:
                    model = combo.get_model()
                    action_value = model[active][1]
                    if action_value:
                        try:
                            simple_action = SimpleAction(action_value)
                        except ValueError:
                            pass

            if is_simple and simple_action is not None:
                mode = ButtonMode.simple(simple_action)
            else:
                mode = ButtonMode.complex()

            self._config_store.set_button_mode(mode, action)

            # Save search terms
            text_buf = widgets["text_view"].get_buffer()
            start, end = text_buf.get_bounds()
            terms_text = text_buf.get_text(start, end, True)
            terms = [t.strip() for t in terms_text.split(",") if t.strip()]
            if terms:
                self._config_store.set_search_terms(terms, action)

        self.destroy()

    def _on_cancel(self, _widget):
        """Close without saving."""
        self.destroy()

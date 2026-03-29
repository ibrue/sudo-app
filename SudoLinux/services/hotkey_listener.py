"""Global hotkey listener using pynput."""

import threading

from models.pad_action import PadAction
from models.hotkey_config import HotkeyConfig, MOD_CONTROL, MOD_ALT, MOD_SHIFT, MOD_SUPER
from services.button_config_store import ButtonConfigStore


class HotkeyListener:
    """Listens for global hotkey events from the macro pad.

    Uses pynput.keyboard.Listener for global key monitoring.
    Hotkey combos are configurable via ButtonConfigStore
    (defaults to Ctrl+Shift+F13-F16).
    """

    def __init__(self):
        self._listener = None
        self._handler = None
        self._key_map = {}      # (keysym, modifiers) -> PadAction
        self._current_modifiers = 0
        self._lock = threading.Lock()

    def start(self, handler):
        """Start listening for hotkeys.

        Args:
            handler: Callable that takes a PadAction when a hotkey fires.
        """
        self._handler = handler
        self._build_key_map()

        # Listen for config changes to rebuild the map
        ButtonConfigStore.shared().on_hotkey_change(self.rebuild_key_map)

        try:
            from pynput.keyboard import Listener, Key
            self._listener = Listener(
                on_press=self._on_press,
                on_release=self._on_release,
            )
            self._listener.daemon = True
            self._listener.start()
            print("[sudo] Hotkey listener active -- waiting for macro pad input")
        except ImportError:
            print("[sudo] ERROR: pynput not installed. Run: pip install pynput")
        except Exception as e:
            print(f"[sudo] ERROR: Failed to start hotkey listener: {e}")

    def stop(self):
        """Stop listening for hotkeys."""
        if self._listener is not None:
            self._listener.stop()
            self._listener = None
        self._handler = None

    def rebuild_key_map(self):
        """Rebuild the key map when hotkey configuration changes."""
        self._build_key_map()
        print("[sudo] Hotkey map rebuilt with updated config")

    def _build_key_map(self):
        """Build the mapping from (keysym, modifiers) to PadAction."""
        key_map = {}
        store = ButtonConfigStore.shared()
        for action in PadAction:
            config = store.hotkey_config(action)
            normalized = HotkeyConfig.normalized_modifiers(config.modifiers)
            key_map[(config.keysym, normalized)] = action
        with self._lock:
            self._key_map = key_map

    def _modifier_from_key(self, key):
        """Convert a pynput key to our modifier mask."""
        from pynput.keyboard import Key
        mod_map = {
            Key.ctrl_l: MOD_CONTROL, Key.ctrl_r: MOD_CONTROL,
            Key.alt_l: MOD_ALT, Key.alt_r: MOD_ALT,
            Key.shift_l: MOD_SHIFT, Key.shift_r: MOD_SHIFT,
            Key.cmd_l: MOD_SUPER, Key.cmd_r: MOD_SUPER,
        }
        # Handle Key enum comparison
        try:
            return mod_map.get(key, 0)
        except (TypeError, AttributeError):
            return 0

    def _keysym_from_key(self, key):
        """Convert a pynput key to an X11 keysym."""
        from pynput.keyboard import Key, KeyCode

        # Special keys mapping
        special_map = {
            Key.f1: 0xFFBE, Key.f2: 0xFFBF, Key.f3: 0xFFC0, Key.f4: 0xFFC1,
            Key.f5: 0xFFC2, Key.f6: 0xFFC3, Key.f7: 0xFFC4, Key.f8: 0xFFC5,
            Key.f9: 0xFFC6, Key.f10: 0xFFC7, Key.f11: 0xFFC8, Key.f12: 0xFFC9,
            Key.f13: 0xFFCA, Key.f14: 0xFFCB, Key.f15: 0xFFCC, Key.f16: 0xFFCD,
            Key.f17: 0xFFCE, Key.f18: 0xFFCF, Key.f19: 0xFFD0, Key.f20: 0xFFD1,
            Key.enter: 0xFF0D, Key.esc: 0xFF1B, Key.tab: 0xFF09,
            Key.space: 0x0020, Key.backspace: 0xFF08, Key.delete: 0xFFFF,
            Key.left: 0xFF51, Key.up: 0xFF52, Key.right: 0xFF53, Key.down: 0xFF54,
            Key.home: 0xFF50, Key.end: 0xFF57, Key.page_up: 0xFF55,
            Key.page_down: 0xFF56, Key.print_screen: 0xFF61,
        }

        try:
            if key in special_map:
                return special_map[key]
        except TypeError:
            pass

        # Regular character keys
        if isinstance(key, KeyCode):
            if key.vk is not None:
                # Map virtual key codes to keysyms
                vk = key.vk
                # Letters (vk 65-90 on Linux via X11)
                if 65 <= vk <= 90:
                    return 0x0061 + (vk - 65)  # lowercase keysym
                # Numbers (vk 48-57)
                if 48 <= vk <= 57:
                    return 0x0030 + (vk - 48)
                # F-keys (vk 269025043+ varies by platform)
                return vk
            if key.char is not None:
                return ord(key.char.lower())

        return 0

    def _on_press(self, key):
        """Handle key press events."""
        # Update modifier state
        mod = self._modifier_from_key(key)
        if mod:
            self._current_modifiers |= mod
            return

        # Check for matching hotkey
        keysym = self._keysym_from_key(key)
        if keysym == 0:
            return

        normalized_mods = HotkeyConfig.normalized_modifiers(self._current_modifiers)

        with self._lock:
            action = self._key_map.get((keysym, normalized_mods))

        if action is not None and self._handler is not None:
            config = ButtonConfigStore.shared().hotkey_config(action)
            print(f"[sudo] Received: {action.display_name} ({config.display_string})")
            # Fire handler on a separate thread to avoid blocking the listener
            handler = self._handler
            threading.Thread(target=handler, args=(action,), daemon=True).start()

    def _on_release(self, key):
        """Handle key release events."""
        mod = self._modifier_from_key(key)
        if mod:
            self._current_modifiers &= ~mod

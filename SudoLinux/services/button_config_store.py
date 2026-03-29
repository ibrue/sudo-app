"""Persists per-button configuration to ~/.config/sudo/config.json."""

import json
import os
from pathlib import Path

from models.pad_action import PadAction
from models.button_mode import ButtonMode
from models.hotkey_config import HotkeyConfig


class ButtonConfigStore:
    """Singleton store for button configuration including search terms,
    button modes, and hotkey bindings."""

    _instance = None

    CONFIG_DIR = os.path.join(str(Path.home()), ".config", "sudo")
    CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")

    @classmethod
    def shared(cls):
        """Return the singleton instance."""
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self._custom_terms = {}      # {action_value: [str]}
        self._button_modes = {}      # {action_value: ButtonMode}
        self._hotkey_configs = {}    # {action_value: HotkeyConfig}
        self._change_callbacks = []  # list of callables
        self._hotkey_callbacks = []  # list of callables for hotkey config changes
        self._load()

    def on_change(self, callback):
        """Register a callback to be called when configuration changes."""
        self._change_callbacks.append(callback)

    def on_hotkey_change(self, callback):
        """Register a callback to be called when hotkey configuration changes."""
        self._hotkey_callbacks.append(callback)

    def _notify_change(self):
        for cb in self._change_callbacks:
            try:
                cb()
            except Exception:
                pass

    def _notify_hotkey_change(self):
        for cb in self._hotkey_callbacks:
            try:
                cb()
            except Exception:
                pass

    # -- Button Mode --

    def button_mode(self, action):
        """Returns the mode for a given action -- defaults to complex."""
        return self._button_modes.get(action.value, ButtonMode.complex())

    def set_button_mode(self, mode, action):
        """Sets the mode for a given action."""
        self._button_modes[action.value] = mode
        self._save()
        self._notify_change()

    # -- Search Terms --

    def search_terms(self, action):
        """Returns active search terms -- custom if set, otherwise defaults."""
        custom = self._custom_terms.get(action.value)
        if custom:
            return custom
        return action.default_search_terms

    def set_search_terms(self, terms, action):
        """Updates search terms for an action. Pass None or empty to reset."""
        if terms:
            self._custom_terms[action.value] = terms
        else:
            self._custom_terms.pop(action.value, None)
        self._save()
        self._notify_change()

    def is_customized(self, action):
        """Whether the user has customized the terms for this action."""
        custom = self._custom_terms.get(action.value)
        return custom is not None and len(custom) > 0

    def reset_to_defaults(self, action):
        """Reset a single action back to defaults."""
        self._custom_terms.pop(action.value, None)
        self._button_modes.pop(action.value, None)
        self._save()
        self._notify_change()

    def reset_all_to_defaults(self):
        """Reset all actions back to defaults."""
        self._custom_terms.clear()
        self._button_modes.clear()
        self._hotkey_configs.clear()
        self._save()
        self._notify_change()
        self._notify_hotkey_change()

    # -- Hotkey Config --

    def hotkey_config(self, action):
        """Returns the hotkey config for an action -- custom or default."""
        return self._hotkey_configs.get(action.value, HotkeyConfig.default_for(action))

    def set_hotkey_config(self, config, action):
        """Sets a custom hotkey config for an action."""
        self._hotkey_configs[action.value] = config
        self._save()
        self._notify_hotkey_change()

    def has_custom_hotkey(self, action):
        """Whether the user has a custom hotkey for this action."""
        return action.value in self._hotkey_configs

    def reset_hotkey_config(self, action):
        """Reset the hotkey config for an action back to default."""
        self._hotkey_configs.pop(action.value, None)
        self._save()
        self._notify_hotkey_change()

    # -- Persistence --

    def _load(self):
        """Load configuration from disk."""
        if not os.path.exists(self.CONFIG_FILE):
            return
        try:
            with open(self.CONFIG_FILE, "r") as f:
                data = json.load(f)
            self._custom_terms = data.get("custom_terms", {})
            modes_data = data.get("button_modes", {})
            self._button_modes = {
                k: ButtonMode.from_dict(v) for k, v in modes_data.items()
            }
            hotkeys_data = data.get("hotkey_configs", {})
            self._hotkey_configs = {
                k: HotkeyConfig.from_dict(v) for k, v in hotkeys_data.items()
            }
        except (json.JSONDecodeError, KeyError, TypeError):
            pass

    def _save(self):
        """Save configuration to disk."""
        os.makedirs(self.CONFIG_DIR, exist_ok=True)
        data = {
            "custom_terms": self._custom_terms,
            "button_modes": {
                k: v.to_dict() for k, v in self._button_modes.items()
            },
            "hotkey_configs": {
                k: v.to_dict() for k, v in self._hotkey_configs.items()
            },
        }
        try:
            with open(self.CONFIG_FILE, "w") as f:
                json.dump(data, f, indent=2)
        except OSError as e:
            print(f"[sudo] Failed to save config: {e}")

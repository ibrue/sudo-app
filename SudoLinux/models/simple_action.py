"""Preset system shortcuts that can be assigned to macro pad buttons in simple mode."""

from enum import Enum


class SimpleAction(Enum):
    """Linux system shortcuts mapped to macro pad buttons."""

    TAKE_SCREENSHOT = "take_screenshot"
    TAKE_SCREENSHOT_AREA = "take_screenshot_area"
    COPY = "copy"
    PASTE = "paste"
    UNDO = "undo"
    REDO = "redo"
    SAVE = "save"
    SELECT_ALL = "select_all"
    NEW_TAB = "new_tab"
    CLOSE_TAB = "close_tab"
    SWITCH_APP = "switch_app"
    SEARCH = "search"
    WORKSPACES = "workspaces"
    SHOW_DESKTOP = "show_desktop"
    LOCK_SCREEN = "lock_screen"

    @property
    def display_name(self):
        """Human-readable name for display."""
        return {
            SimpleAction.TAKE_SCREENSHOT:      "Screenshot",
            SimpleAction.TAKE_SCREENSHOT_AREA: "Screenshot Area",
            SimpleAction.COPY:                 "Copy",
            SimpleAction.PASTE:                "Paste",
            SimpleAction.UNDO:                 "Undo",
            SimpleAction.REDO:                 "Redo",
            SimpleAction.SAVE:                 "Save",
            SimpleAction.SELECT_ALL:           "Select All",
            SimpleAction.NEW_TAB:              "New Tab",
            SimpleAction.CLOSE_TAB:            "Close Tab",
            SimpleAction.SWITCH_APP:           "Switch App",
            SimpleAction.SEARCH:               "Search",
            SimpleAction.WORKSPACES:           "Workspaces",
            SimpleAction.SHOW_DESKTOP:         "Show Desktop",
            SimpleAction.LOCK_SCREEN:          "Lock Screen",
        }[self]

    @property
    def category(self):
        """Category grouping for display."""
        system = {
            SimpleAction.TAKE_SCREENSHOT, SimpleAction.TAKE_SCREENSHOT_AREA,
            SimpleAction.SEARCH, SimpleAction.WORKSPACES,
            SimpleAction.SHOW_DESKTOP, SimpleAction.LOCK_SCREEN,
            SimpleAction.SWITCH_APP,
        }
        editing = {
            SimpleAction.COPY, SimpleAction.PASTE,
            SimpleAction.UNDO, SimpleAction.REDO,
            SimpleAction.SAVE, SimpleAction.SELECT_ALL,
        }
        if self in system:
            return "System"
        if self in editing:
            return "Editing"
        return "Navigation"

    @property
    def key_combo(self):
        """xdotool key string for this shortcut.

        Returns a string suitable for `xdotool key <combo>`.
        """
        return {
            SimpleAction.TAKE_SCREENSHOT:      "Print",
            SimpleAction.TAKE_SCREENSHOT_AREA: "shift+Print",
            SimpleAction.COPY:                 "ctrl+c",
            SimpleAction.PASTE:                "ctrl+v",
            SimpleAction.UNDO:                 "ctrl+z",
            SimpleAction.REDO:                 "ctrl+shift+z",
            SimpleAction.SAVE:                 "ctrl+s",
            SimpleAction.SELECT_ALL:           "ctrl+a",
            SimpleAction.NEW_TAB:              "ctrl+t",
            SimpleAction.CLOSE_TAB:            "ctrl+w",
            SimpleAction.SWITCH_APP:           "alt+Tab",
            SimpleAction.SEARCH:               "super",
            SimpleAction.WORKSPACES:           "super+Tab",
            SimpleAction.SHOW_DESKTOP:         "super+d",
            SimpleAction.LOCK_SCREEN:          "super+l",
        }[self]

    @staticmethod
    def categories():
        """All categories in display order."""
        return ["System", "Editing", "Navigation"]

    @classmethod
    def actions_in_category(cls, category):
        """Return actions filtered by category."""
        return [a for a in cls if a.category == category]

    @classmethod
    def grouped_by_category(cls):
        """Return actions grouped by category as list of (category, [actions])."""
        return [(cat, cls.actions_in_category(cat)) for cat in cls.categories()]

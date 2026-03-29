"""Primary button detection using AT-SPI2 (Linux accessibility tree)."""

try:
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi
    HAS_ATSPI = True
except (ImportError, ValueError):
    HAS_ATSPI = False
    print("[sudo] AT-SPI2 not available. Install: apt install gir1.2-atspi-2.0")


class ATSPIResult:
    """Result of an AT-SPI button search."""

    def __init__(self, found=False, accessible=None, name="", reason=""):
        self.found = found
        self.accessible = accessible
        self.name = name
        self.reason = reason


class ATSPIButtonFinder:
    """Walks the accessibility tree to find buttons matching the action.

    Uses AT-SPI2 -- the Linux equivalent of macOS Accessibility API.
    Same code path as Orca screen reader.
    """

    # Roles that are typically clickable
    CLICKABLE_ROLES = {
        "push button", "link", "menu item", "toggle button",
        "check box", "radio button", "label", "panel",
        "table cell", "filler",
    }

    def find_button(self, action, pid):
        """Search the accessibility tree for a button matching the action.

        Args:
            action: PadAction to search for
            pid: Process ID of the target application

        Returns:
            ATSPIResult with the found element or failure reason
        """
        if not HAS_ATSPI:
            return ATSPIResult(reason="AT-SPI2 not available")

        search_terms = [t.lower() for t in action.search_terms]

        try:
            desktop = Atspi.get_desktop(0)
            app_count = desktop.get_child_count()

            # Find the application matching the PID
            target_app = None
            for i in range(app_count):
                app = desktop.get_child_at_index(i)
                if app is None:
                    continue
                try:
                    app_pid = app.get_process_id()
                    if app_pid == pid:
                        target_app = app
                        break
                except Exception:
                    continue

            if target_app is None:
                return ATSPIResult(reason="Could not find app in AT-SPI tree")

            # Search through the app's windows
            window_count = target_app.get_child_count()
            for i in range(window_count):
                window = target_app.get_child_at_index(i)
                if window is None:
                    continue
                result = self._search_tree(window, search_terms, depth=0)
                if result is not None:
                    return ATSPIResult(found=True, accessible=result[0], name=result[1])

            return ATSPIResult(reason="No matching button found in AT-SPI tree")

        except Exception as e:
            return ATSPIResult(reason=f"AT-SPI error: {e}")

    def _search_tree(self, element, search_terms, depth):
        """Recursively search the accessibility tree.

        Args:
            element: Atspi.Accessible to search from
            search_terms: List of lowercase search terms
            depth: Current recursion depth (max 15)

        Returns:
            Tuple of (accessible, matched_name) or None
        """
        if depth > 15 or element is None:
            return None

        try:
            role = element.get_role_name()
        except Exception:
            role = ""

        # Check if this element is a clickable type
        if role in self.CLICKABLE_ROLES or self._has_action(element):
            text = self._get_element_text(element)
            if text and self._matches_search_terms(text, search_terms):
                if self._is_actionable(element):
                    return (element, text)

        # For container roles, check combined child text
        if role in ("panel", "filler", "table cell", "section"):
            combined = self._get_combined_child_text(element, max_depth=2)
            if combined and self._matches_search_terms(combined, search_terms):
                if self._has_action(element) and self._is_actionable(element):
                    return (element, combined)

        # Recurse into children
        try:
            child_count = element.get_child_count()
        except Exception:
            return None

        for i in range(child_count):
            try:
                child = element.get_child_at_index(i)
                result = self._search_tree(child, search_terms, depth + 1)
                if result is not None:
                    return result
            except Exception:
                continue

        return None

    def _get_element_text(self, element):
        """Get text from an accessible element (name, description)."""
        parts = []
        try:
            name = element.get_name()
            if name:
                parts.append(name)
        except Exception:
            pass
        try:
            desc = element.get_description()
            if desc:
                parts.append(desc)
        except Exception:
            pass
        return " ".join(parts) if parts else None

    def _get_combined_child_text(self, element, max_depth):
        """Get combined text from an element and its children."""
        if max_depth <= 0:
            return self._get_element_text(element)

        parts = []
        text = self._get_element_text(element)
        if text:
            parts.append(text)

        try:
            child_count = min(element.get_child_count(), 10)
            for i in range(child_count):
                child = element.get_child_at_index(i)
                child_text = self._get_combined_child_text(child, max_depth - 1)
                if child_text:
                    parts.append(child_text)
        except Exception:
            pass

        return " ".join(parts) if parts else None

    def _matches_search_terms(self, text, terms):
        """Check if text matches any search term."""
        lower = text.lower().strip()
        return any(lower == t or t in lower for t in terms)

    def _has_action(self, element):
        """Check if the element supports click/activate actions."""
        try:
            action_iface = element.get_action_iface()
            if action_iface is None:
                return False
            n_actions = action_iface.get_n_actions()
            for i in range(n_actions):
                name = action_iface.get_action_name(i)
                if name in ("click", "activate", "press", "jump"):
                    return True
        except Exception:
            pass
        return False

    def _is_actionable(self, element):
        """Check if the element is enabled and visible."""
        try:
            state_set = element.get_state_set()
            if state_set is None:
                return True
            # Check that the element is enabled and visible
            is_enabled = state_set.contains(Atspi.StateType.ENABLED) if HAS_ATSPI else True
            is_showing = state_set.contains(Atspi.StateType.SHOWING) if HAS_ATSPI else True
            return is_enabled and is_showing
        except Exception:
            return True

"""Executes found buttons via AT-SPI action or xdotool click fallback."""

import subprocess

try:
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi
    HAS_ATSPI = True
except (ImportError, ValueError):
    HAS_ATSPI = False


class ExecutionResult:
    """Result of executing an action."""

    def __init__(self, success, detail):
        self.success = success
        self.detail = detail

    @classmethod
    def ok(cls, detail):
        return cls(True, detail)

    @classmethod
    def fail(cls, reason):
        return cls(False, reason)


class ActionExecutor:
    """Executes found buttons via AT-SPI action (preferred) or xdotool click (fallback).

    AT-SPI action execution is the gold standard for Linux accessibility --
    same code path as Orca screen reader.
    """

    def execute_atspi(self, atspi_result):
        """Execute via AT-SPI action interface.

        Args:
            atspi_result: ATSPIResult with a found accessible element

        Returns:
            ExecutionResult
        """
        if not atspi_result.found or atspi_result.accessible is None:
            return ExecutionResult.fail(atspi_result.reason)

        return self._perform_atspi_action(atspi_result.accessible)

    def execute_click(self, ocr_result):
        """Execute via xdotool mouse click at coordinates.

        Args:
            ocr_result: OCRResult with screen coordinates

        Returns:
            ExecutionResult
        """
        if not ocr_result.found:
            return ExecutionResult.fail(ocr_result.reason)

        return self._perform_click(ocr_result.x, ocr_result.y)

    def _perform_atspi_action(self, accessible):
        """Perform an AT-SPI action on the accessible element."""
        if not HAS_ATSPI:
            return ExecutionResult.fail("AT-SPI not available")

        try:
            action_iface = accessible.get_action_iface()
            if action_iface is None:
                # Fallback: try to get position and click
                return self._click_accessible(accessible)

            # Try common action names in order of preference
            n_actions = action_iface.get_n_actions()
            for action_name in ("click", "activate", "press", "jump"):
                for i in range(n_actions):
                    if action_iface.get_action_name(i) == action_name:
                        if action_iface.do_action(i):
                            return ExecutionResult.ok(f"AT-SPI {action_name}")

            # Try the first available action as last resort
            if n_actions > 0:
                name = action_iface.get_action_name(0)
                if action_iface.do_action(0):
                    return ExecutionResult.ok(f"AT-SPI {name}")

            # Fallback: click at element position
            return self._click_accessible(accessible)

        except Exception as e:
            return ExecutionResult.fail(f"AT-SPI action failed: {e}")

    def _click_accessible(self, accessible):
        """Click at the position of an accessible element using xdotool."""
        try:
            component = accessible.get_component_iface()
            if component is None:
                return ExecutionResult.fail("Element has no position")

            # Get position in screen coordinates
            rect = component.get_extents(Atspi.CoordType.SCREEN)
            x = rect.x + rect.width // 2
            y = rect.y + rect.height // 2

            return self._perform_click(x, y)
        except Exception as e:
            return ExecutionResult.fail(f"Could not get element position: {e}")

    def _perform_click(self, x, y):
        """Simulate a mouse click at the given screen coordinates using xdotool."""
        try:
            result = subprocess.run(
                ["xdotool", "mousemove", "--sync", str(x), str(y),
                 "click", "1"],
                capture_output=True, text=True, timeout=3
            )
            if result.returncode == 0:
                return ExecutionResult.ok(f"xdotool click ({x}, {y})")
            return ExecutionResult.fail(f"xdotool error: {result.stderr.strip()}")
        except FileNotFoundError:
            return ExecutionResult.fail("xdotool not installed")
        except subprocess.TimeoutExpired:
            return ExecutionResult.fail("xdotool timed out")

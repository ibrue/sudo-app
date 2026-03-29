"""Executes simple actions by simulating keystrokes via xdotool."""

import subprocess


class SimpleActionResult:
    """Result of a simple action execution."""

    def __init__(self, success, detail):
        self.success = success
        self.detail = detail

    @classmethod
    def ok(cls, detail):
        return cls(True, detail)

    @classmethod
    def fail(cls, reason):
        return cls(False, reason)


class SimpleActionExecutor:
    """Executes a SimpleAction by simulating its keyboard shortcut via xdotool.

    Uses `xdotool key` to send key combinations.
    """

    def execute(self, action):
        """Execute a simple action.

        Args:
            action: SimpleAction to execute

        Returns:
            SimpleActionResult
        """
        combo = action.key_combo

        try:
            result = subprocess.run(
                ["xdotool", "key", combo],
                capture_output=True, text=True, timeout=3
            )
            if result.returncode == 0:
                return SimpleActionResult.ok(f"Simulated {action.display_name}")
            return SimpleActionResult.fail(
                f"xdotool error: {result.stderr.strip()}"
            )
        except FileNotFoundError:
            return SimpleActionResult.fail(
                "xdotool not installed. Run: apt install xdotool"
            )
        except subprocess.TimeoutExpired:
            return SimpleActionResult.fail("xdotool timed out")

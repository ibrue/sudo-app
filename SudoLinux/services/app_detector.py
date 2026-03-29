"""Detects whether the foreground window belongs to a supported AI application."""

import subprocess
import os


class DetectedApp:
    """Represents a detected AI application."""

    def __init__(self, process_name, window_title, pid, is_browser=False, matched_domain=None):
        self.process_name = process_name
        self.window_title = window_title
        self.pid = pid
        self.is_browser = is_browser
        self.matched_domain = matched_domain

    @property
    def name(self):
        """Display name for the detected app."""
        if self.matched_domain:
            domain_names = {
                "claude.ai": "Claude",
                "chatgpt.com": "ChatGPT",
                "chat.openai.com": "ChatGPT",
                "grok.com": "Grok",
            }
            return domain_names.get(self.matched_domain, self.matched_domain)

        name_lower = self.process_name.lower()
        native_names = {
            "claude": "Claude",
            "chatgpt": "ChatGPT",
        }
        return native_names.get(name_lower, self.process_name)


# Native desktop app process names (case-insensitive match)
_NATIVE_APP_NAMES = {"claude", "chatgpt"}

# Browser process names
_BROWSER_NAMES = {
    "firefox", "chrome", "chromium", "chromium-browser",
    "google-chrome", "google-chrome-stable",
    "brave", "brave-browser",
    "msedge", "microsoft-edge", "microsoft-edge-stable",
    "opera", "vivaldi",
}

# Web domains for AI apps
_WEB_DOMAINS = [
    "claude.ai",
    "chatgpt.com",
    "grok.com",
    "chat.openai.com",
]


class AppDetector:
    """Detects the frontmost AI application on Linux."""

    def detect_frontmost_app(self):
        """Detect the foreground AI app, if any.

        Returns:
            DetectedApp or None
        """
        try:
            return self._detect_via_xdotool()
        except Exception:
            return None

    def _detect_via_xdotool(self):
        """Use xdotool to get the active window info."""
        try:
            # Get active window ID
            result = subprocess.run(
                ["xdotool", "getactivewindow"],
                capture_output=True, text=True, timeout=2
            )
            if result.returncode != 0:
                return None
            window_id = result.stdout.strip()
            if not window_id:
                return None

            # Get window title
            result = subprocess.run(
                ["xdotool", "getwindowname", window_id],
                capture_output=True, text=True, timeout=2
            )
            window_title = result.stdout.strip() if result.returncode == 0 else ""

            # Get window PID
            result = subprocess.run(
                ["xdotool", "getwindowpid", window_id],
                capture_output=True, text=True, timeout=2
            )
            pid = int(result.stdout.strip()) if result.returncode == 0 else 0

            # Get process name from PID
            process_name = self._get_process_name(pid) if pid else ""
            process_lower = process_name.lower()

            # Check native AI desktop apps
            if process_lower in _NATIVE_APP_NAMES:
                return DetectedApp(
                    process_name=process_name,
                    window_title=window_title,
                    pid=pid,
                    is_browser=False,
                )

            # Check browsers for AI web apps
            if process_lower in _BROWSER_NAMES:
                matched_domain = self._detect_ai_domain(window_title)
                if matched_domain:
                    return DetectedApp(
                        process_name=process_name,
                        window_title=window_title,
                        pid=pid,
                        is_browser=True,
                        matched_domain=matched_domain,
                    )

            return None

        except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
            return None

    def _get_process_name(self, pid):
        """Get process name from PID via /proc."""
        try:
            comm_path = f"/proc/{pid}/comm"
            if os.path.exists(comm_path):
                with open(comm_path, "r") as f:
                    return f.read().strip()
        except (IOError, PermissionError):
            pass
        return ""

    def _detect_ai_domain(self, window_title):
        """Check if a browser window title matches a known AI domain."""
        title_lower = window_title.lower()

        # Check exact domain matches
        for domain in _WEB_DOMAINS:
            if domain in title_lower:
                return domain

        # Check common patterns in browser title bars
        # e.g. "Claude - Google Chrome", "ChatGPT - Mozilla Firefox"
        if "claude" in title_lower:
            return "claude.ai"
        if "chatgpt" in title_lower:
            return "chatgpt.com"
        if "grok" in title_lower:
            return "grok.com"

        return None

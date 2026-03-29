"""Central orchestrator: receives pad actions and coordinates detection -> execution."""

import threading

from models.pad_action import PadAction
from services.app_detector import AppDetector
from services.atspi_button_finder import ATSPIButtonFinder
from services.ocr_button_finder import OCRButtonFinder
from services.action_executor import ActionExecutor
from services.simple_action_executor import SimpleActionExecutor
from services.hotkey_listener import HotkeyListener
from services.button_config_store import ButtonConfigStore


class SudoEngine:
    """Central orchestrator that receives pad actions and coordinates
    detection and execution."""

    def __init__(self):
        self.last_action = "Waiting for input..."
        self.last_method = ""
        self.detected_app = "No AI app detected"
        self.is_connected = False

        self._app_detector = AppDetector()
        self._atspi_finder = ATSPIButtonFinder()
        self._ocr_finder = OCRButtonFinder()
        self._executor = ActionExecutor()
        self._simple_executor = SimpleActionExecutor()
        self._hotkey_listener = HotkeyListener()
        self._config_store = ButtonConfigStore.shared()
        self._status_callbacks = []
        self._app_poll_timer = None
        self._running = False

    def on_status_change(self, callback):
        """Register a callback to be called when status changes."""
        self._status_callbacks.append(callback)

    def _notify_status(self):
        """Notify all status callbacks."""
        for cb in self._status_callbacks:
            try:
                cb()
            except Exception:
                pass

    def start(self):
        """Start the engine: begin listening for hotkeys and polling for apps."""
        self._hotkey_listener.start(self._handle_action)
        self.is_connected = True
        self._running = True
        self._notify_status()

        # Start app detection polling
        self._poll_app()

    def stop(self):
        """Stop the engine."""
        self._running = False
        self._hotkey_listener.stop()
        self.is_connected = False
        if self._app_poll_timer is not None:
            self._app_poll_timer.cancel()
        self._notify_status()

    def _poll_app(self):
        """Poll for the active AI app every second."""
        if not self._running:
            return
        self._update_detected_app()
        self._app_poll_timer = threading.Timer(1.0, self._poll_app)
        self._app_poll_timer.daemon = True
        self._app_poll_timer.start()

    def _update_detected_app(self):
        """Update the detected app display."""
        app = self._app_detector.detect_frontmost_app()
        if app is not None:
            label = f"{app.name} ({app.matched_domain})" if app.is_browser else app.name
            self.detected_app = label
        else:
            self.detected_app = "No AI app detected"

    def _handle_action(self, action):
        """Handle a pad action triggered by a hotkey.

        Args:
            action: PadAction that was triggered
        """
        mode = self._config_store.button_mode(action)

        # Simple mode: simulate a keyboard shortcut directly
        if mode.is_simple and mode.simple_action is not None:
            self.last_action = f"Processing: {mode.simple_action.display_name}..."
            self._notify_status()
            print(f"[sudo] Simple action: {mode.simple_action.display_name}")

            result = self._simple_executor.execute(mode.simple_action)
            if result.success:
                self.last_action = mode.simple_action.display_name
                self.last_method = f"Shortcut -> {result.detail}"
                print(f"[sudo] OK: {mode.simple_action.display_name} via shortcut")
            else:
                self.last_action = f"{mode.simple_action.display_name} -- failed"
                self.last_method = f"Shortcut: {result.detail}"
            self._notify_status()
            return

        # Complex mode: AT-SPI tree + OCR flow
        self.last_action = f"Processing: {action.display_name}..."
        self._notify_status()

        app = self._app_detector.detect_frontmost_app()
        if app is None:
            self.last_action = f"{action.display_name} -- no AI app in focus"
            self.last_method = ""
            self._notify_status()
            return

        print(f"[sudo] Target: {app.name} (PID {app.pid}), action: {action.display_name}")

        # Strategy 1: AT-SPI tree (preferred)
        atspi_result = self._atspi_finder.find_button(action, app.pid)
        if atspi_result.found:
            exec_result = self._executor.execute_atspi(atspi_result)
            self._update_status(action, exec_result, "AT-SPI")
            return

        print("[sudo] AT-SPI miss -- falling back to OCR")

        # Strategy 2: Tesseract OCR fallback
        ocr_result = self._ocr_finder.find_button(action, app.pid)
        if ocr_result.found:
            exec_result = self._executor.execute_click(ocr_result)
            self._update_status(action, exec_result, "OCR")
            return

        self.last_action = f"{action.display_name} -- button not found"
        self.last_method = "Searched AT-SPI + OCR"
        self._notify_status()

    def _update_status(self, action, exec_result, method):
        """Update status display after an action execution."""
        if exec_result.success:
            self.last_action = action.display_name
            self.last_method = f"{method} -> {exec_result.detail}"
            print(f"[sudo] OK: {action.display_name} via {method} -> {exec_result.detail}")
        else:
            self.last_action = f"{action.display_name} -- failed"
            self.last_method = f"{method}: {exec_result.detail}"
        self._notify_status()

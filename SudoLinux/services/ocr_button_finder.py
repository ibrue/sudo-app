"""Fallback button detection using Tesseract OCR."""

import subprocess
import tempfile
import os

try:
    import pytesseract
    from PIL import Image
    HAS_OCR = True
except ImportError:
    HAS_OCR = False
    print("[sudo] OCR not available. Install: pip install pytesseract Pillow && apt install tesseract-ocr")


class OCRResult:
    """Result of an OCR button search."""

    def __init__(self, found=False, x=0, y=0, text="", reason=""):
        self.found = found
        self.x = x
        self.y = y
        self.text = text
        self.reason = reason


class OCRButtonFinder:
    """Captures a window screenshot and uses Tesseract OCR to find buttons.

    Runs entirely on-device -- no data leaves the machine.
    """

    def find_button(self, action, pid):
        """Search for a button matching the action using OCR.

        Args:
            action: PadAction to search for
            pid: Process ID of the target application

        Returns:
            OCRResult with coordinates or failure reason
        """
        if not HAS_OCR:
            return OCRResult(reason="OCR dependencies not available")

        screenshot_path = self._capture_window(pid)
        if screenshot_path is None:
            return OCRResult(reason="Could not capture window screenshot")

        try:
            search_terms = [t.lower() for t in action.search_terms]
            image = Image.open(screenshot_path)

            # Get window position for coordinate mapping
            window_x, window_y = self._get_window_position(pid)

            # Use pytesseract to extract text with bounding boxes
            data = pytesseract.image_to_data(image, output_type=pytesseract.Output.DICT)

            n_boxes = len(data["text"])
            for i in range(n_boxes):
                text = data["text"][i].strip()
                if not text:
                    continue

                text_lower = text.lower()
                for term in search_terms:
                    if text_lower == term or term in text_lower:
                        # Calculate center of the bounding box in screen coordinates
                        box_x = data["left"][i]
                        box_y = data["top"][i]
                        box_w = data["width"][i]
                        box_h = data["height"][i]

                        center_x = window_x + box_x + box_w // 2
                        center_y = window_y + box_y + box_h // 2

                        print(f"[sudo] OCR found '{text}' at ({center_x}, {center_y})")
                        return OCRResult(
                            found=True,
                            x=center_x,
                            y=center_y,
                            text=text,
                        )

            return OCRResult(reason="OCR found no matching text")

        except Exception as e:
            return OCRResult(reason=f"OCR error: {e}")
        finally:
            # Clean up temporary screenshot
            try:
                os.unlink(screenshot_path)
            except OSError:
                pass

    def _capture_window(self, pid):
        """Capture a screenshot of the window belonging to the given PID.

        Returns:
            Path to the temporary screenshot file, or None on failure.
        """
        try:
            # Get window ID from PID using xdotool
            result = subprocess.run(
                ["xdotool", "search", "--pid", str(pid)],
                capture_output=True, text=True, timeout=2
            )
            if result.returncode != 0 or not result.stdout.strip():
                return None

            # Use the first window ID found
            window_id = result.stdout.strip().split("\n")[0]

            # Create a temporary file for the screenshot
            tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
            tmp_path = tmp.name
            tmp.close()

            # Try import (ImageMagick) first, then scrot
            capture_result = subprocess.run(
                ["import", "-window", window_id, tmp_path],
                capture_output=True, text=True, timeout=5
            )
            if capture_result.returncode != 0:
                # Fallback: use xdotool to activate and scrot
                capture_result = subprocess.run(
                    ["scrot", "-u", tmp_path],
                    capture_output=True, text=True, timeout=5
                )
                if capture_result.returncode != 0:
                    os.unlink(tmp_path)
                    return None

            return tmp_path

        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            return None

    def _get_window_position(self, pid):
        """Get the screen position of the window for coordinate mapping."""
        try:
            result = subprocess.run(
                ["xdotool", "search", "--pid", str(pid)],
                capture_output=True, text=True, timeout=2
            )
            if result.returncode != 0 or not result.stdout.strip():
                return (0, 0)

            window_id = result.stdout.strip().split("\n")[0]

            result = subprocess.run(
                ["xdotool", "getwindowgeometry", "--shell", window_id],
                capture_output=True, text=True, timeout=2
            )
            if result.returncode != 0:
                return (0, 0)

            # Parse output: X=...\nY=...\nWIDTH=...\nHEIGHT=...
            x, y = 0, 0
            for line in result.stdout.strip().split("\n"):
                if line.startswith("X="):
                    x = int(line.split("=")[1])
                elif line.startswith("Y="):
                    y = int(line.split("=")[1])
            return (x, y)

        except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
            return (0, 0)

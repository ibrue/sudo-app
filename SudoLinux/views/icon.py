"""Generate the [sudo] tray icon programmatically using cairo."""

import os
import tempfile

try:
    import cairo
    HAS_CAIRO = True
except ImportError:
    try:
        import gi
        gi.require_version("cairo", "1.0")
        from gi.repository import cairo
        HAS_CAIRO = True
    except (ImportError, ValueError):
        HAS_CAIRO = False


def create_tray_icon():
    """Create a 48x48 PNG icon with white [] brackets on black background.

    Returns:
        Path to the generated icon file.
    """
    icon_dir = os.path.join(tempfile.gettempdir(), "sudo-app")
    os.makedirs(icon_dir, exist_ok=True)
    icon_path = os.path.join(icon_dir, "sudo-icon.png")

    # Return cached icon if it exists
    if os.path.exists(icon_path):
        return icon_path

    if not HAS_CAIRO:
        # Fallback: create a minimal icon using PIL if available
        return _create_icon_pil(icon_path)

    try:
        size = 48
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
        ctx = cairo.Context(surface)

        # Black background
        ctx.set_source_rgb(0, 0, 0)
        ctx.rectangle(0, 0, size, size)
        ctx.fill()

        # White brackets
        ctx.set_source_rgb(1, 1, 1)
        ctx.set_line_width(3)

        # Left bracket "["
        bracket_top = 10
        bracket_bottom = 38
        left_x = 10
        serif_len = 8

        ctx.move_to(left_x + serif_len, bracket_top)
        ctx.line_to(left_x, bracket_top)
        ctx.line_to(left_x, bracket_bottom)
        ctx.line_to(left_x + serif_len, bracket_bottom)
        ctx.stroke()

        # Right bracket "]"
        right_x = 38

        ctx.move_to(right_x - serif_len, bracket_top)
        ctx.line_to(right_x, bracket_top)
        ctx.line_to(right_x, bracket_bottom)
        ctx.line_to(right_x - serif_len, bracket_bottom)
        ctx.stroke()

        surface.write_to_png(icon_path)
        return icon_path

    except Exception:
        return _create_icon_pil(icon_path)


def _create_icon_pil(icon_path):
    """Fallback icon creation using PIL."""
    try:
        from PIL import Image, ImageDraw

        size = 48
        img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
        draw = ImageDraw.Draw(img)

        # Left bracket "["
        draw.rectangle([8, 9, 11, 39], fill=(255, 255, 255))     # vertical
        draw.rectangle([8, 9, 18, 12], fill=(255, 255, 255))     # top serif
        draw.rectangle([8, 36, 18, 39], fill=(255, 255, 255))    # bottom serif

        # Right bracket "]"
        draw.rectangle([36, 9, 39, 39], fill=(255, 255, 255))    # vertical
        draw.rectangle([29, 9, 39, 12], fill=(255, 255, 255))    # top serif
        draw.rectangle([29, 36, 39, 39], fill=(255, 255, 255))   # bottom serif

        img.save(icon_path, "PNG")
        return icon_path

    except ImportError:
        return None

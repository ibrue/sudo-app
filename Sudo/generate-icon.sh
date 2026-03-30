#!/bin/bash
# Generates AppIcon.icns from the SVG favicon design
# Requires: macOS with sips and iconutil (built-in)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICONSET="$SCRIPT_DIR/AppIcon.iconset"
ICNS="$SCRIPT_DIR/AppIcon.icns"

# Skip if icns already exists and is newer than this script
if [ -f "$ICNS" ]; then
    echo "[icon] AppIcon.icns already exists, skipping generation"
    exit 0
fi

echo "[icon] Generating AppIcon.icns..."

# Create a 1024x1024 PNG from scratch using Python (no external deps)
python3 -c "
import struct, zlib

def create_png(width, height, pixels):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\\x89PNG\\r\\n\\x1a\\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw = b''
    for y in range(height):
        raw += b'\\x00'  # filter byte
        for x in range(width):
            raw += bytes(pixels[y * width + x])

    idat = chunk(b'IDAT', zlib.compress(raw))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend

size = 1024
pixels = []
bg = (10, 10, 10, 255)       # #0a0a0a
fg = (0, 255, 65, 255)       # #00ff41

# Scale: each 'unit' in the 32x32 grid = 32 pixels at 1024x1024
s = size // 32

for y in range(size):
    for x in range(size):
        gx, gy = x // s, y // s
        pixel = bg

        # Left bracket [
        if 4 <= gx < 7 and 4 <= gy < 28: pixel = fg      # vertical bar
        if 7 <= gx < 12 and 4 <= gy < 7: pixel = fg       # top horizontal
        if 7 <= gx < 12 and 25 <= gy < 28: pixel = fg     # bottom horizontal

        # Right bracket ]
        if 25 <= gx < 28 and 4 <= gy < 28: pixel = fg     # vertical bar
        if 20 <= gx < 25 and 4 <= gy < 7: pixel = fg      # top horizontal
        if 20 <= gx < 25 and 25 <= gy < 28: pixel = fg    # bottom horizontal

        pixels.append(pixel)

png_data = create_png(size, size, pixels)
with open('$SCRIPT_DIR/icon_1024.png', 'wb') as f:
    f.write(png_data)
print('[icon] Created 1024x1024 PNG')
"

# Create iconset with all required sizes
mkdir -p "$ICONSET"
sizes=(16 32 64 128 256 512 1024)
for s in "${sizes[@]}"; do
    sips -z $s $s "$SCRIPT_DIR/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" > /dev/null 2>&1
done

# Create @2x variants
sips -z 32 32 "$SCRIPT_DIR/icon_1024.png" --out "$ICONSET/icon_16x16@2x.png" > /dev/null 2>&1
sips -z 64 64 "$SCRIPT_DIR/icon_1024.png" --out "$ICONSET/icon_32x32@2x.png" > /dev/null 2>&1
sips -z 256 256 "$SCRIPT_DIR/icon_1024.png" --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 512 512 "$SCRIPT_DIR/icon_1024.png" --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 1024 1024 "$SCRIPT_DIR/icon_1024.png" --out "$ICONSET/icon_512x512@2x.png" > /dev/null 2>&1

# Generate .icns
iconutil -c icns "$ICONSET" -o "$ICNS"

# Cleanup
rm -rf "$ICONSET" "$SCRIPT_DIR/icon_1024.png"

echo "[icon] Generated: $ICNS"

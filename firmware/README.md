# Sudo Pad Firmware

QMK firmware and VIA configuration for the Sudo Pad, an RP2040-based 4-key macro pad.

## Default Key Mapping

| Position    | Key              |
|-------------|------------------|
| Top Left    | Ctrl+Shift+F13   |
| Top Right   | Ctrl+Shift+F14   |
| Bottom Left | Ctrl+Shift+F15   |
| Bottom Right| Ctrl+Shift+F16   |

## Building

Copy the `qmk/keyboards/sudo_pad` directory into your QMK firmware tree at `keyboards/sudo_pad`, then compile:

```bash
# Default keymap
qmk compile -kb sudo_pad -km default

# VIA-enabled keymap
qmk compile -kb sudo_pad -km via
```

## Flashing

1. Hold the **BOOTSEL** button on the RP2040 board.
2. While holding BOOTSEL, plug in the USB cable.
3. Release BOOTSEL. A drive named **RPI-RP2** will appear.
4. Drag the compiled `.uf2` file onto the RPI-RP2 drive.
5. The board will flash and reboot automatically.

## VIA Configuration

VIA allows live key reconfiguration without reflashing.

1. Flash the `via` keymap (see above).
2. Open [VIA](https://usevia.app/) in a WebHID-compatible browser.
3. Go to **Settings** and enable **Show Design Tab**.
4. Open the **Design** tab and click **Load Draft Definition**.
5. Select `firmware/via/sudo_pad.json`.
6. Your Sudo Pad should now appear and be fully configurable.

## Default Keymap: Reset to Bootloader

In the default keymap, press all 4 keys simultaneously to activate the function layer, then the top-left key triggers bootloader mode for reflashing.

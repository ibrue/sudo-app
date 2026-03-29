# Sudo Pad Firmware

QMK firmware with VIA and Vial support for the Sudo Pad, an RP2040-based 4-key macro pad.

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

# Vial-enabled keymap (requires Vial QMK fork)
qmk compile -kb sudo_pad -km vial
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

## Vial Configuration

[Vial](https://get.vial.today/) is an alternative to VIA with auto-detection (no draft definition needed).

1. Clone the [Vial QMK fork](https://github.com/vial-kb/vial-qmk) instead of stock QMK.
2. Copy `qmk/keyboards/sudo_pad` into the Vial fork at `keyboards/sudo_pad`.
3. Compile with: `qmk compile -kb sudo_pad -km vial`
4. Flash the `.uf2` file (see Flashing above).
5. Open [Vial](https://get.vial.today/) — the Sudo Pad will be auto-detected.
6. Remap keys live. Changes are saved to the board instantly.

The Vial keymap includes:
- **Unlock combo**: Press top-left + bottom-right keys simultaneously to unlock Vial security.
- **4 layers**: Layer 0 has defaults, layers 1-3 are configurable via Vial.
- **`vial.json`**: Embedded in the firmware, so Vial auto-detects the layout.

## VIA vs Vial

| Feature | VIA | Vial |
|---------|-----|------|
| Draft definition required | Yes (`via/sudo_pad.json`) | No (embedded in firmware) |
| Auto-detection | No | Yes |
| QMK fork required | No (stock QMK) | Yes (vial-qmk) |
| Web app | [usevia.app](https://usevia.app) | [vial.rocks](https://vial.rocks) |
| Desktop app | No | [get.vial.today](https://get.vial.today) |
| Security unlock | N/A | Top-left + bottom-right combo |

## Default Keymap: Reset to Bootloader

In the default keymap, press all 4 keys simultaneously to activate the function layer, then the top-left key triggers bootloader mode for reflashing.

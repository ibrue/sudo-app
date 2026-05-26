# pad firmware — bottom-LED control

Companion firmware for the host-controlled underglow feature. Pairs with
`PadCommunicator` on the Mac side.

## files

- **`boot.py`** — enables the second CircuitPython CDC interface
  (`usb_cdc.data`) so host writes don't collide with REPL/print traffic
  on the console interface. **Also explicitly re-enables HID** with the
  same descriptor — touching `usb_cdc.enable` silently resets the USB
  descriptor on CircuitPython 9.x, and forgetting to re-enable HID
  puts the pad in a reset loop (the v3 incident).
- **`code.py`** — production v3. Same reliability machinery as v2
  (watchdog, USB reconnect, send-fail tracking) with the GP24/GP25
  LEDs migrated from `digitalio` on/off to PWM via `sudo_leds`.
- **`sudo_leds.py`** — PWM driver + line-protocol parser + pattern
  engine for the four LED modes (`feedback` / `breathe` / `solid` /
  `status-dim`).

## pin mapping

| GPIO | role (v2)       | role (v3)                                  |
|------|-----------------|--------------------------------------------|
| GP24 | press flash     | left bottom LED  (PWM, host-controlled)   |
| GP25 | ready indicator | right bottom LED (PWM, host-controlled)   |

The "alive" signal is now the dim idle-floor of the default `feedback`
mode; the per-press flash is now an `evt:press` fired from
`dispatch_press` into the controller.

## installing

1. Hold button 1 + plug in the pad so CIRCUITPY mounts.
2. Drag all three files (`boot.py`, `code.py`, `sudo_leds.py`) to the
   root of CIRCUITPY, overwriting the existing copies.
3. Unplug and replug the pad (no button held). Two `/dev/cu.usbmodem*`
   devices will now appear instead of one — that's expected: console
   on the first, host commands on the second.

## what the Mac app sends

| line | meaning |
|------|---------|
| `cfg:on=0` / `cfg:on=1` | master enable |
| `cfg:bri=N` | brightness 0–100 |
| `cfg:mode=feedback\|breathe\|solid\|status-dim` | pattern mode |
| `evt:idle\|press\|busy\|ok\|fail\|wait\|reboot` | momentary event |

Unknown lines / fields are ignored — forward-compatible with future Mac
versions.

## the pad keeps no persistent state

Settings (`cfg:*`) are re-sent by the Mac app every time the pad
reconnects. A freshly-plugged pad always reflects current Mac settings,
without any NVM / config-file dance on the pad side.

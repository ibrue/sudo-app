# sudo macropad — boot.py (v4, adds usb_cdc.data for host-driven LEDs)
#
# Two non-obvious things in here, both load-bearing:
#
# 1. Flash-mode button check (from v2).
#    Holding button 1 (GP3) at plug-in keeps the CIRCUITPY drive
#    visible so the user can edit code.py / boot.py. Normal plug-in
#    hides the drive so Spotlight doesn't churn it.
#
# 2. usb_cdc.enable + usb_hid.enable must BOTH be called, in this
#    order. v3 of this file called only usb_cdc.enable() to add the
#    data CDC interface — and that silently resets the USB descriptor,
#    dropping HID. The result was a 10-second hard-reset loop on
#    CircuitPython 9.2.1 (no HID -> no enumeration -> usb_connected
#    stays False past USB_GONE_RESET_MS in code.py -> microcontroller
#    .reset() -> repeat). Re-enabling HID explicitly with the same
#    device tuple keeps the descriptor intact.

import board
import digitalio
import storage
import usb_cdc
import usb_hid

# Flash-mode check first — if the user is iterating, we want the
# drive up no matter what comes after.
_btn = digitalio.DigitalInOut(board.GP3)
_btn.direction = digitalio.Direction.INPUT
_btn.pull = digitalio.Pull.UP
_flash_mode = not _btn.value  # active-low
if not _flash_mode:
    storage.disable_usb_drive()
_btn.deinit()

# Enable the second CDC interface so the Mac app (PadCommunicator) has
# a dedicated write channel for LED commands. console=True keeps the
# existing print/REPL stream that PadConsoleReader tails.
usb_cdc.enable(console=True, data=True)

# Re-enable HID with the same descriptor we've always used. This is
# the line v3 was missing — without it the descriptor resets and the
# pad stops enumerating.
usb_hid.enable(
    (usb_hid.Device.KEYBOARD, usb_hid.Device.CONSUMER_CONTROL),
)

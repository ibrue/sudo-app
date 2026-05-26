# sudo macropad firmware — CircuitPython (production v3)
#
# Reliability-first base from v2, with bottom LEDs (GP24 + GP25)
# converted from digitalio on/off to PWM under host control via the
# usb_cdc.data channel. The Sudo Mac app's PadCommunicator writes
# cfg:* / evt:* lines; the firmware also fires evt:press locally so
# the LEDs respond before the host has connected.
#
# Failure modes addressed (carried from v2 — unchanged):
#
#   - "Pad powers on but macOS doesn't see USB": hardware watchdog
#     (8s) hard-resets the chip if the main loop hangs. Secondary
#     `usb_connected` check soft-fails after 10s of "powered but not
#     enumerated" by calling microcontroller.reset().
#
#   - "Buttons silently don't register": send_report() exceptions
#     tracked per-press; 3 consecutive fails -> microcontroller.reset().
#
#   - "No visible 'I'm alive' signal": GP24/GP25 are now PWM-driven by
#     sudo_leds.UnderglowController. The 'feedback' mode (default)
#     keeps both LEDs at idle_floor when nothing is happening, which
#     is the same "firmware is alive" signal the old `set_ready_led`
#     provided. Per-press flash is fired from dispatch_press via
#     leds.on_event("press").
#
#   - "Auto-reload kicked in mid-press": autoreload stays False.
#
#   - "Loop spammed error logs": throttled to one log per unique
#     error with backoff.
#
# To iterate: hold button 1 + plug to mount CIRCUITPY, edit this file,
# then `screen /dev/cu.usbmodem* 115200` (or Sudo's pad console) for
# CDC. Autoreload is OFF — Ctrl-D over REPL or replug to apply.

import supervisor
print("## sudo-code.py-start t={}ms".format(supervisor.ticks_ms()))

# --- Reliability: hardware watchdog ----------------------------------
try:
    import microcontroller
    import watchdog
    microcontroller.watchdog.timeout = 8
    microcontroller.watchdog.mode = watchdog.WatchDogMode.RESET
    _wdt = microcontroller.watchdog
    print("## sudo-wdt-armed timeout=8s")
except Exception as _e:  # noqa: BLE001
    _wdt = None
    print("## sudo-wdt-failed {}".format(_e))

supervisor.runtime.autoreload = False

import board
import digitalio
import json
import time
import usb_hid

print("## sudo-imports-done t={}ms".format(supervisor.ticks_ms()))


# --- Wrap-safe ticks_diff (CircuitPython 9 ticks_ms wraps at 2**29) ---
_TICKS_PERIOD = 1 << 29
_TICKS_HALFPERIOD = _TICKS_PERIOD // 2

def ticks_diff(t1, t2):
    diff = (t1 - t2) & (_TICKS_PERIOD - 1)
    if diff >= _TICKS_HALFPERIOD:
        diff -= _TICKS_PERIOD
    return diff


# --- HID device lookup -----------------------------------------------
keyboard = None
consumer = None
try:
    keyboard = usb_hid.devices[0]
    if not (keyboard.usage_page == 0x01 and keyboard.usage == 0x06):
        keyboard = None
        for d in usb_hid.devices:
            if d.usage_page == 0x01 and d.usage == 0x06:
                keyboard = d
                break
except (IndexError, AttributeError):
    keyboard = None

for d in usb_hid.devices:
    if d.usage_page == 0x0C and d.usage == 0x01:
        consumer = d
        break

print("## sudo-hid-enumerated t={}ms kbd={} cons={}".format(
    supervisor.ticks_ms(),
    "ok" if keyboard else "none",
    "ok" if consumer else "none",
))


# --- Buttons (GP3=btn1 bottom .. GP0=btn4 top) -----------------------
PINS = (board.GP3, board.GP2, board.GP1, board.GP0)
buttons = []
for pin in PINS:
    p = digitalio.DigitalInOut(pin)
    p.direction = digitalio.Direction.INPUT
    p.pull = digitalio.Pull.UP
    buttons.append(p)

print("## sudo-gpio-ready t={}ms".format(supervisor.ticks_ms()))


# --- Bottom LEDs (host-controlled PWM, GP24 + GP25) ------------------
#
# These are the two green LEDs on the bottom of the pad. v2 drove
# them with digitalio (on/off) where GP25 was the "alive" indicator
# and GP24 flashed per press. Both roles are now subsumed into the
# sudo_leds pattern engine — the 'feedback' mode (default) provides
# a dim idle-floor as the alive signal plus an event-driven pulse
# on press, and the host can change behaviour live over CDC.
#
# Pin mapping (matches v2): GP24 = left underglow, GP25 = right
# underglow. The controller drives both with the same pattern; if
# we ever want independent left/right effects, that becomes a mode.
try:
    import sudo_leds
    leds = sudo_leds.UnderglowController(
        left_pin=board.GP24,
        right_pin=board.GP25,
    )
    print("## sudo-leds-ready t={}ms pwm=ok".format(supervisor.ticks_ms()))
except Exception as _e:  # noqa: BLE001
    leds = None
    print("## sudo-leds-ready t={}ms err:{}".format(supervisor.ticks_ms(), _e))


def leds_tick():
    if leds is not None:
        try: leds.tick()
        except Exception: pass


def leds_event(tag):
    if leds is not None:
        try: leds.on_event(tag)
        except Exception: pass


# --- Config ----------------------------------------------------------
DEFAULT_BUTTONS = [
    {"mode": "keycombo", "keycode": 0x68, "modifiers": 0x03},  # F13
    {"mode": "keycombo", "keycode": 0x6D, "modifiers": 0x03},  # F18
    {"mode": "keycombo", "keycode": 0x6C, "modifiers": 0x03},  # F17
    {"mode": "keycombo", "keycode": 0x6B, "modifiers": 0x03},  # F16
]


def load_config():
    try:
        with open("/config.json") as f:
            cfg = json.load(f).get("buttons", DEFAULT_BUTTONS)
        if len(cfg) != 4:
            return DEFAULT_BUTTONS
        return cfg
    except (OSError, ValueError):
        return DEFAULT_BUTTONS


config = load_config()
print("## sudo-config-loaded t={}ms".format(supervisor.ticks_ms()))


# --- HID send with failure tracking ----------------------------------
MAX_SEND_FAILS = 3
_consecutive_send_fails = 0


def _note_send_ok():
    global _consecutive_send_fails
    _consecutive_send_fails = 0


def _note_send_fail(why):
    global _consecutive_send_fails
    _consecutive_send_fails += 1
    print("## sudo-send-fail n={} why={}".format(_consecutive_send_fails, why))
    if _consecutive_send_fails >= MAX_SEND_FAILS:
        print("## sudo-hard-reset reason=hid-stalled")
        try: time.sleep(0.05)
        except Exception: pass
        try: microcontroller.reset()
        except Exception: pass


def send_key_down(modifiers, keycode):
    if keyboard is None:
        _note_send_fail("no-keyboard")
        return
    try:
        rpt = bytearray(8)
        rpt[0] = modifiers & 0xFF
        rpt[2] = keycode & 0xFF
        keyboard.send_report(rpt)
        _note_send_ok()
    except Exception as e:  # noqa: BLE001
        _note_send_fail("kd:{}".format(e))


def send_key_up():
    if keyboard is None:
        return
    try:
        keyboard.send_report(bytearray(8))
    except Exception as e:  # noqa: BLE001
        _note_send_fail("ku:{}".format(e))


def send_consumer(usage):
    if consumer is None:
        return
    try:
        rpt = bytearray(2)
        rpt[0] = usage & 0xFF
        rpt[1] = (usage >> 8) & 0xFF
        consumer.send_report(rpt)
        time.sleep(0.01)
        consumer.send_report(bytearray(2))
        _note_send_ok()
    except Exception as e:  # noqa: BLE001
        _note_send_fail("cons:{}".format(e))


_CONSUMER = {16: 0xCD, 17: 0xB5, 18: 0xB6, 19: 0xB7, 20: 0xE2}
key_held = [False] * 4


def dispatch_press(i):
    b = config[i]
    mode = b.get("mode", "keycombo")
    if mode == "mediakey":
        usage = _CONSUMER.get(b.get("keycode", 0), 0)
        if usage:
            send_consumer(usage)
    else:
        send_key_down(b.get("modifiers", 0), b.get("keycode", 0))
        key_held[i] = True


def dispatch_release(i):
    send_key_up()
    key_held[i] = False


# --- Main loop -------------------------------------------------------
DEBOUNCE_MS = 20
last_state = [True] * 4
_now0 = supervisor.ticks_ms()
debounce_until = [_now0] * 4

print("## sudo-ready t={}ms".format(supervisor.ticks_ms()))
try:
    print("## sudo-buttons-state t={}ms states={}".format(
        supervisor.ticks_ms(),
        "".join(["1" if b.value else "0" for b in buttons]),
    ))
except Exception as _e:  # noqa: BLE001
    print("## sudo-buttons-state t={}ms err:{}".format(supervisor.ticks_ms(), _e))

USB_GONE_RESET_MS = 10_000
_usb_last_seen = supervisor.ticks_ms()

HEARTBEAT_MS = 30000
_BOOT_BURST_MS = (200, 1000, 3000, 10000)
_boot_t = supervisor.ticks_ms()
_burst_index = 0
_last_heartbeat = _boot_t

_last_err_text = None
_last_err_logged_at = 0
ERR_LOG_THROTTLE_MS = 5000


def log_error(text):
    global _last_err_text, _last_err_logged_at
    now = supervisor.ticks_ms()
    if text == _last_err_text and ticks_diff(now, _last_err_logged_at) < ERR_LOG_THROTTLE_MS:
        return
    _last_err_text = text
    _last_err_logged_at = now
    try:
        print("## sudo-loop-error {}".format(text))
    except Exception:  # noqa: BLE001
        pass


while True:
    try:
        now = supervisor.ticks_ms()

        if _wdt is not None:
            try: _wdt.feed()
            except Exception: pass

        try:
            usb_ok = supervisor.runtime.usb_connected
        except Exception:  # noqa: BLE001
            usb_ok = True
        if usb_ok:
            _usb_last_seen = now
        elif ticks_diff(now, _usb_last_seen) > USB_GONE_RESET_MS:
            print("## sudo-hard-reset reason=usb-gone-{}ms".format(
                ticks_diff(now, _usb_last_seen)))
            try: time.sleep(0.05)
            except Exception: pass
            try: microcontroller.reset()
            except Exception: pass

        leds_tick()

        for i in range(4):
            if ticks_diff(now, debounce_until[i]) < 0:
                continue
            state = buttons[i].value
            if state != last_state[i]:
                last_state[i] = state
                debounce_until[i] = now + DEBOUNCE_MS
                if not state:
                    dispatch_press(i)
                    leds_event("press")
                    print("## sudo-press btn={} t={}ms".format(i + 1, now))
                else:
                    dispatch_release(i)

        if _burst_index < len(_BOOT_BURST_MS) and \
                ticks_diff(now, _boot_t) >= _BOOT_BURST_MS[_burst_index]:
            _burst_index += 1
            _last_heartbeat = now
            print("## sudo-alive t={}ms".format(now))
        elif ticks_diff(now, _last_heartbeat) >= HEARTBEAT_MS:
            _last_heartbeat = now
            print("## sudo-alive t={}ms".format(now))

        time.sleep(0.005)

    except Exception as e:  # noqa: BLE001
        log_error(str(e))
        try: time.sleep(0.1)
        except Exception: pass

# sudo_leds.py — host-controlled underglow for the two bottom green LEDs.
#
# Drop this file onto CIRCUITPY alongside code.py and integrate from
# your main loop:
#
#     import sudo_leds
#     leds = sudo_leds.UnderglowController(left_pin=board.GP24,
#                                          right_pin=board.GP25)
#     while True:
#         # ... your existing button + HID work ...
#         leds.tick()  # call as often as practical; ~200 Hz is plenty
#
# The Sudo Mac app writes line-based ASCII commands to usb_cdc.data:
#   cfg:on=0|1                  master enable
#   cfg:bri=0..100              brightness percent
#   cfg:mode=feedback|breathe|solid|status-dim
#   evt:idle|press|busy|ok|fail|wait|reboot
#   evt:press n=N               press of physical button N (1..4)
#
# Pattern engine returns (left, right) levels so future stereo
# patterns drop in without changing the call sites. Today only the
# `feedback` mode uses asymmetry — it fires a per-button identity
# signature so the user can tell buttons apart from the LEDs alone.

import time
import usb_cdc
import pwmio

_PWM_MAX = 65535


def _scale(pct, level=1.0):
    """pct: 0..100 user setting. level: 0..1 pattern modulation.
    Gamma-squared so the slider feels linear to the eye."""
    if pct <= 0 or level <= 0:
        return 0
    p = max(0.0, min(1.0, pct / 100.0)) * max(0.0, min(1.0, level))
    return int((p * p) * _PWM_MAX)


# --- Per-button identity signature -----------------------------------
#
# Each of the four physical buttons gets a distinct (left, right)
# decay pattern in feedback mode. Buttons 1+3 ("approve" + "reject")
# are both "both bright" but differ in which side decays first —
# subtle but learnable. Buttons 2+4 ("action3" + "action4") use
# asymmetric amplitude as the signature.

_IDENTITY_PEAK_DUR = 0.10   # seconds at peak brightness
_IDENTITY_TOTAL_DUR = 0.20  # full signature length (peak + decay)


def _identity(btn, dt):
    """Return (L, R) levels during the press signature, or None when
    the signature is complete (caller falls back to idle)."""
    if dt >= _IDENTITY_TOTAL_DUR:
        return None
    decay_len = _IDENTITY_TOTAL_DUR - _IDENTITY_PEAK_DUR
    # Peak phase: hold the target levels.
    if dt < _IDENTITY_PEAK_DUR:
        if btn == 1: return (1.0, 1.0)
        if btn == 2: return (0.3, 1.0)
        if btn == 3: return (1.0, 1.0)
        if btn == 4: return (1.0, 0.3)
        return None
    # Decay phase: 0..1 progress over decay_len.
    p = (dt - _IDENTITY_PEAK_DUR) / decay_len
    if btn == 1:
        # L decays first; R lags by ~half the decay window.
        return (1.0 * (1.0 - p), 1.0 * (1.0 - 0.5 * p))
    if btn == 3:
        # Mirror of btn 1: R decays first.
        return (1.0 * (1.0 - 0.5 * p), 1.0 * (1.0 - p))
    if btn == 2:
        # Asymmetric amplitude held; both fade together.
        return (0.3 * (1.0 - p), 1.0 * (1.0 - p))
    if btn == 4:
        return (1.0 * (1.0 - p), 0.3 * (1.0 - p))
    return None


class UnderglowController:
    def __init__(self, left_pin, right_pin, frequency=20000):
        self._left = pwmio.PWMOut(left_pin, frequency=frequency, duty_cycle=0)
        self._right = pwmio.PWMOut(right_pin, frequency=frequency, duty_cycle=0)

        self.enabled = True
        self.brightness = 60
        self.mode = "feedback"

        # Last event tag + when it happened (monotonic seconds).
        self._event = "idle"
        self._event_t = time.monotonic()
        # Button number associated with the last press (1..4 or None).
        self._event_btn = None

        # CDC line buffer.
        self._buf = b""

    # ---- Public ----

    def tick(self):
        self._drain_cdc()
        now = time.monotonic()
        left_lvl, right_lvl = self._levels_for_mode(now)
        if self.enabled:
            self._left.duty_cycle = _scale(self.brightness, left_lvl)
            self._right.duty_cycle = _scale(self.brightness, right_lvl)
        else:
            self._left.duty_cycle = 0
            self._right.duty_cycle = 0

    def on_event(self, tag, n=None):
        """Fire an event from firmware-side code (e.g. a local button
        press). The host also sends evt:* over CDC for the same things,
        but local firing means the LEDs respond even before the host
        has connected. Latest event wins."""
        self._event = tag
        self._event_t = time.monotonic()
        self._event_btn = n

    # ---- CDC line reader ----

    def _drain_cdc(self):
        data = usb_cdc.data
        if data is None:
            return
        n = data.in_waiting
        if n <= 0:
            return
        try:
            chunk = data.read(n)
        except Exception:
            return
        if not chunk:
            return
        self._buf += chunk
        while b"\n" in self._buf:
            line, _, self._buf = self._buf.partition(b"\n")
            try:
                self._handle(line.decode("ascii").strip())
            except Exception:
                pass  # malformed line — ignore

    def _handle(self, line):
        if not line:
            return
        if line.startswith("cfg:"):
            key, _, value = line[4:].partition("=")
            if key == "on":
                self.enabled = (value == "1")
            elif key == "bri":
                try:
                    self.brightness = max(0, min(100, int(value)))
                except ValueError:
                    pass
            elif key == "mode":
                self.mode = value
        elif line.startswith("evt:"):
            payload = line[4:]
            # `evt:press n=2` -> tag="press", n=2. Bare `evt:idle` -> n=None.
            parts = payload.split(None)
            tag = parts[0] if parts else ""
            btn = None
            for tok in parts[1:]:
                k, _, v = tok.partition("=")
                if k == "n":
                    try: btn = int(v)
                    except ValueError: btn = None
            self.on_event(tag, btn)

    # ---- Pattern engine ----
    #
    # Each branch returns a (left, right) tuple of 0..1 levels that
    # scale the brightness setting. Symmetric modes return (x, x).

    def _levels_for_mode(self, now):
        m = self.mode
        if m == "solid":
            return (1.0, 1.0)
        if m == "breathe":
            x = self._breathe(now, period=4.0)
            return (x, x)
        if m == "status-dim":
            x = self._status_dim(now)
            return (x, x)
        # default + unknown → feedback
        return self._feedback(now)

    def _breathe(self, now, period=4.0):
        # Triangle wave 0→1→0. Period in seconds.
        phase = (now % period) / period
        return 1.0 - abs(2.0 * phase - 1.0)

    def _status_dim(self, now):
        dt = now - self._event_t
        ev = self._event
        if ev == "press":
            return 1.0 if dt < 0.12 else 0.0
        if ev == "busy":
            return self._breathe(now, period=1.6)
        if ev == "ok":
            return 1.0 if dt < 0.35 else 0.0
        if ev == "fail":
            if dt > 0.45:
                return 0.0
            return 1.0 if int(dt * 20) % 2 == 0 else 0.0
        if ev == "wait":
            return self._breathe(now, period=3.0) * 0.5
        return 0.0

    def _feedback(self, now):
        idle_floor = 0.18
        dt = now - self._event_t
        ev = self._event
        # Per-button identity signature on press — only when host
        # supplied a button number. Bare `evt:press` (no n=) keeps
        # the original symmetric pulse so older firmware/host combos
        # still get visible feedback.
        if ev == "press":
            if self._event_btn is not None:
                sig = _identity(self._event_btn, dt)
                if sig is not None:
                    L, R = sig
                    # Floor the signature so the LEDs land back on
                    # idle smoothly rather than blink to zero.
                    return (max(L, idle_floor), max(R, idle_floor))
                return (idle_floor, idle_floor)
            # Legacy bare press: original symmetric pulse.
            x = 1.0 if dt < 0.12 else idle_floor
            return (x, x)
        if ev == "busy":
            x = max(idle_floor, self._breathe(now, period=1.6))
            return (x, x)
        if ev == "ok":
            # Double blink: on / off / on / settle.
            if dt < 0.10: x = 1.0
            elif dt < 0.18: x = idle_floor
            elif dt < 0.30: x = 1.0
            else: x = idle_floor
            return (x, x)
        if ev == "fail":
            if dt > 0.45:
                x = idle_floor
            else:
                x = 1.0 if int(dt * 20) % 2 == 0 else 0.0
            return (x, x)
        if ev == "wait":
            x = max(idle_floor, self._breathe(now, period=3.0) * 0.6)
            return (x, x)
        # idle
        return (idle_floor, idle_floor)

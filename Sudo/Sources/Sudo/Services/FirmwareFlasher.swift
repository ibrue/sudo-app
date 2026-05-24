import Foundation
import IOKit
import IOKit.hid

/// Detects the sudo macropad and writes its firmware/config.
///
/// The pad runs CircuitPython. The flash flow has two paths:
///
/// 1. **`CIRCUITPY` is mounted** — the device is already running our firmware.
///    We just write `code.py` and `config.json` directly to the volume.
///    CircuitPython auto-reloads on save, so changes are live in <1 s. No
///    BOOTSEL, no UF2, no reboot. Most common path after the very first
///    flash.
///
/// 2. **`RPI-RP2` is mounted** — the device is in BOOTSEL (blank board, or
///    user just held the BOOTSEL switch). We flash the CircuitPython UF2
///    onto it, wait for it to reboot and re-enumerate as `CIRCUITPY`, then
///    fall through to path 1.
///
/// 3. **Neither is mounted** — we ask the user to plug in the pad while
///    holding BOOTSEL.
///
/// The CircuitPython UF2 is downloaded once from the Adafruit CDN and cached
/// in `~/Library/Application Support/Sudo/Firmware/` — same place the old C
/// firmware path used.
final class FirmwareFlasher: ObservableObject {
    static let shared = FirmwareFlasher()

    enum FlashState: Equatable {
        case idle
        case detectingDevice
        case readyForConfig(circuitpyPath: String)   // device is running CP, just write config
        case readyForFirmware(rpiPath: String)       // device is in BOOTSEL, needs CP UF2 first
        case flashing
        case success
        case error(message: String)
    }

    /// Coarse lifecycle phase used by the UI's 3-step indicator.
    /// `.reboot` covers BOOTSEL detection + UF2 copy. `.write` is the
    /// `code.py` / `config.json` write to CIRCUITPY. `.verify` is the brief
    /// settle period after the write before we report success.
    enum FlashStep: Int { case reboot = 0, write = 1, verify = 2 }

    @Published var state: FlashState = .idle
    @Published var phase: String = ""
    @Published var progress: Double = 0
    @Published var step: FlashStep = .reboot

    /// True when an Adafruit USB HID device is currently attached. Set
    /// by an IOKit matching subscription, so it tracks plug/unplug
    /// without needing the CIRCUITPY mass-storage volume — which boot.py
    /// hides in normal use, leaving `state == .idle` even though the
    /// pad is fully functional. Used to drive the device label so the
    /// popover shows "connected" instead of a misleading "idle" once
    /// the pad is plugged in.
    @Published var hidConnected: Bool = false

    /// Fired on the main queue whenever IOKit reports an Adafruit-VID
    /// HID device match. SudoEngine subscribes to this to short-circuit
    /// the 3-second permission-timer wait — the moment the pad
    /// enumerates we want to re-check the event tap.
    var onPadDetected: (() -> Void)?

    private var hidWatcher: IOHIDManager?

    /// Pinned CircuitPython release for the Raspberry Pi Pico (RP2040). We
    /// don't track latest because Adafruit releases occasionally rename
    /// modules; pinning means the `code.py` we ship is always known-good.
    static let circuitPythonURL = URL(string:
        "https://downloads.circuitpython.org/bin/raspberry_pi_pico/en_US/adafruit-circuitpython-raspberry_pi_pico-en_US-9.2.1.uf2"
    )!
    static let circuitPythonVersion = "9.2.1"

    private let unmountTimeoutSeconds: Double = 30
    private let pollIntervalSeconds: Double = 0.25

    // MARK: - Detection

    /// Look for the device. Tries CIRCUITPY first (no BOOTSEL needed), then
    /// RPI-RP2. Falls back to asking the user.
    func detectDevice() {
        DispatchQueue.main.async {
            self.state = .detectingDevice
            self.phase = "looking for sudo macropad…"
            self.progress = 0
            self.step = .reboot
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let cp = self.findCircuitPyVolume() {
                DispatchQueue.main.async {
                    self.state = .readyForConfig(circuitpyPath: cp)
                    self.phase = "device running CircuitPython — ready for config"
                }
                return
            }

            if let rpi = self.findBootloaderVolume() {
                DispatchQueue.main.async {
                    self.state = .readyForFirmware(rpiPath: rpi)
                    self.phase = "device in BOOTSEL — ready to install CircuitPython"
                }
                return
            }

            DispatchQueue.main.async {
                self.state = .idle
                self.phase = "no device — plug in the macropad (hold BOOTSEL on first install)"
            }
        }
    }

    /// Backwards-compatible alias for the previous bootloader-only API.
    func detectBootloader() { detectDevice() }

    /// Like `detectDevice` but silent — no phase / progress churn. Called on
    /// app launch and on every USB mount/unmount so `state` always reflects
    /// what's actually plugged in. Skips the update if we're mid-flash so we
    /// don't clobber an active operation.
    func refreshDeviceState() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let cp = self.findCircuitPyVolume()
            let rpi = self.findBootloaderVolume()
            DispatchQueue.main.async {
                switch self.state {
                case .flashing, .detectingDevice, .success, .error:
                    return
                default:
                    break
                }
                if let cp = cp {
                    self.state = .readyForConfig(circuitpyPath: cp)
                } else if let rpi = rpi {
                    self.state = .readyForFirmware(rpiPath: rpi)
                } else {
                    self.state = .idle
                }
            }
        }
    }

    // MARK: - Public flash entry points

    /// Always-correct one-button flash. Picks the right path based on
    /// current device state.
    func flashFirmwareAndConfig(settings: SudoSettings = .shared) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runFlash(settings: settings)
        }
    }

    /// Legacy alias; same behaviour as flashFirmwareAndConfig now.
    func flashCurrentConfig(settings: SudoSettings = .shared) {
        flashFirmwareAndConfig(settings: settings)
    }

    func reset() {
        DispatchQueue.main.async {
            self.state = .idle
            self.phase = ""
            self.progress = 0
            self.step = .reboot
        }
    }

    // MARK: - HID hot-plug detection
    //
    // Subscribes to IOKit for any USB device with the Adafruit vendor
    // ID (0x239A — covers every CircuitPython-based board, which on a
    // user's Mac is the sudo pad). When one shows up or disappears we
    // flip `hidConnected`; the device label reads that to show
    // "connected (running)" while the CIRCUITPY drive is hidden.
    //
    // Why we don't piggyback on `HotkeyListener`'s existing watcher:
    // that one matches *any* keyboard so it can rebuild the event tap
    // when the user adds a new keyboard of any kind. We need a stricter
    // filter for "is the sudo pad here", so it lives separately.

    private static let adafruitVendorID: Int = 0x239A

    func startHIDDetection() {
        guard hidWatcher == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: Self.adafruitVendorID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            guard let ctx = ctx else { return }
            let me = Unmanaged<FirmwareFlasher>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                me.hidConnected = true
                me.onPadDetected?()
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            guard let ctx = ctx else { return }
            let me = Unmanaged<FirmwareFlasher>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.refreshHIDState() }
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[sudo] FirmwareFlasher.startHIDDetection: IOHIDManagerOpen returned \(result)")
        }
        // The matching callback fires synchronously for any already-
        // attached devices, so `hidConnected` is correct after Open
        // returns. No initial scan needed.
        self.hidWatcher = manager
    }

    /// Re-walks the matched device set after a removal to decide whether
    /// any sudo-pad-shaped device is still attached. The removal callback
    /// fires for the device that left; we have to poll the manager to
    /// know whether anything matching the same filter remains.
    private func refreshHIDState() {
        guard let manager = hidWatcher else { return }
        let attached = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        hidConnected = !attached.isEmpty
    }

    // MARK: - Implementation

    private func runFlash(settings: SudoSettings) {
        // Re-detect each time so we don't act on stale state.
        if let cp = findCircuitPyVolume() {
            writeConfigToCircuitPy(path: cp, settings: settings)
            return
        }
        if let rpi = findBootloaderVolume() {
            installCircuitPythonThenConfig(rpiPath: rpi, settings: settings)
            return
        }
        setError("no device — plug in the macropad with BOOTSEL held (first time only)")
    }

    /// Path 1: CIRCUITPY is mounted, write boot.py + code.py + config.json.
    ///
    /// boot.py is what makes the firmware hot-pluggable: it hides
    /// CIRCUITPY in normal use (no more "eject before unplug" warning),
    /// only re-exposes the drive when the user holds button 1 while
    /// plugging in. Pure HID otherwise.
    private func writeConfigToCircuitPy(path: String, settings: SudoSettings) {
        beginFlashing(label: "writing firmware…", at: .write)
        do {
            let metaDst = URL(fileURLWithPath: path).appendingPathComponent(".metadata_never_index")
            let bootDst = URL(fileURLWithPath: path).appendingPathComponent("boot.py")
            let codeDst = URL(fileURLWithPath: path).appendingPathComponent("code.py")
            let configDst = URL(fileURLWithPath: path).appendingPathComponent("config.json")
            let configData = try SudoConfigJSON.generate(from: settings)

            // Spotlight indexing CIRCUITPY was the culprit behind the
            // "pad takes minutes to connect" reports: macOS would
            // write `.Spotlight-V100/`, `.fseventsd/`, `.Trashes/`
            // metadata, every write would trigger CircuitPython's
            // auto-reload, and the pad would ping-pong through boot.py
            // for 1–2 minutes before settling. Dropping a
            // `.metadata_never_index` file (zero-byte, recognised by
            // Spotlight) tells macOS to skip this volume entirely.
            // Write it FIRST so it's in place before macOS has a
            // chance to start scanning the volume metadata we add.
            updateProgress(0.05, phase: "tagging volume to skip Spotlight…")
            try Data().write(to: metaDst, options: .atomic)

            updateProgress(0.20, phase: "writing boot.py (hot-plug guard)…")
            try Self.embeddedBootPy.write(to: bootDst, atomically: true, encoding: .utf8)
            updateProgress(0.50, phase: "writing code.py…")
            try Self.embeddedCodePy.write(to: codeDst, atomically: true, encoding: .utf8)
            updateProgress(0.80, phase: "writing config.json (\(settings.appMode.rawValue) mode)…")
            try writeOverwriting(data: configData, to: configDst)

            DispatchQueue.main.async { self.step = .verify }
            // The new boot.py disables auto-reload, so we don't wait
            // for CircuitPython to pick the files up — the user
            // unplugs/replugs and the new firmware runs cleanly from
            // a fresh boot. Quick settle to let the FAT writes flush.
            updateProgress(0.95, phase: "settling…")
            Thread.sleep(forTimeInterval: 0.3)

            finishSuccess(label: "flashed — unplug + replug to start (hold button 1 again to re-flash)")
        } catch {
            setError("config write failed: \(error.localizedDescription)")
        }
    }

    /// Path 2: RPI-RP2 is mounted. Flash CircuitPython UF2 to it, wait for
    /// CIRCUITPY to enumerate, then write config.
    private func installCircuitPythonThenConfig(rpiPath: String, settings: SudoSettings) {
        beginFlashing(label: "preparing CircuitPython…", at: .reboot)
        do {
            let cpURL = try locateOrDownloadCircuitPython()
            updatePhase("flashing CircuitPython \(Self.circuitPythonVersion) to RPI-RP2…")
            let cpDst = URL(fileURLWithPath: rpiPath).appendingPathComponent("circuitpython.uf2")
            try copyToBootloader(src: cpURL, dst: cpDst, label: "writing CircuitPython")

            DispatchQueue.main.async { self.step = .write }
            updatePhase("waiting for CIRCUITPY to mount…")
            guard let cpPath = waitForCircuitPyMount(timeout: 20) else {
                throw NSError(domain: "FirmwareFlasher", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "CIRCUITPY didn't mount within 20s — try unplugging and replugging"
                ])
            }
            // Recurse into the config-write path.
            writeConfigToCircuitPy(path: cpPath, settings: settings)
        } catch {
            setError("install failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CircuitPython UF2 sourcing

    private func locateOrDownloadCircuitPython() throws -> URL {
        // Bundled (most reliable, but ships ~1 MB extra in .app)
        if let bundleURL = Bundle.main.url(forResource: "circuitpython-pico", withExtension: "uf2") {
            return bundleURL
        }
        // Cached locally
        let cache = circuitPythonCacheURL
        if FileManager.default.fileExists(atPath: cache.path) {
            return cache
        }
        // Download from Adafruit
        return try downloadCircuitPython(to: cache)
    }

    private var circuitPythonCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sudo/Firmware/circuitpython-pico-\(Self.circuitPythonVersion).uf2")
    }

    private func downloadCircuitPython(to dest: URL) throws -> URL {
        updateProgress(0, phase: "downloading CircuitPython \(Self.circuitPythonVersion)…")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<URL, Error>!

        let delegate = FirmwareDownloadDelegate { [weak self] received, expected in
            guard let self = self, expected > 0 else { return }
            let p = min(Double(received) / Double(expected), 1.0)
            self.updateProgress(p, phase: "downloading CircuitPython… \(Int(p * 100))%")
        }
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: Self.circuitPythonURL) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error = error { result = .failure(error); return }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(NSError(domain: "FirmwareFlasher", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "CircuitPython download HTTP \(http.statusCode)"
                ]))
                return
            }
            guard let tempURL = tempURL else {
                result = .failure(NSError(domain: "FirmwareFlasher", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "no file downloaded"
                ]))
                return
            }
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                result = .success(dest)
            } catch {
                result = .failure(error)
            }
        }
        task.resume()
        semaphore.wait()
        session.invalidateAndCancel()

        return try result.get()
    }

    // MARK: - Embedded firmware
    //
    // KEEP IN SYNC with sudo-supply/hardware/firmware/{boot,code}.py.

    /// boot.py runs once at every cold boot, before code.py. Three jobs:
    ///
    /// 1. Hide the CIRCUITPY mass-storage volume unless button 1 (GP3) is
    ///    held during plug-in. macOS volume mount + Spotlight + Finder
    ///    activity on every replug is real perceived lag.
    /// 2. Leave LED ownership to code.py. CircuitPython pin objects
    ///    should be kept alive by the program that needs the pin, so
    ///    the visible ready LED is claimed once the main loop is ready.
    /// 3. Stay silent over CDC. boot.py's stdout is captured to
    ///    boot_out.txt, not the live CDC console — printing here just
    ///    wastes startup time.
    private static let embeddedBootPy: String = #"""
# sudo macropad — boot.py (production v2, KNOWN-GOOD)
#
# Reverted from v3 — v3's usb_cdc.enable/usb_hid.enable calls broke the
# HID descriptor on this CircuitPython 9.2.1 build, putting the pad in
# a 10-second reset loop. This is the v2 boot.py that we verified works.

import board
import digitalio
import storage

_btn = digitalio.DigitalInOut(board.GP3)
_btn.direction = digitalio.Direction.INPUT
_btn.pull = digitalio.Pull.UP
# Active-low: button held -> False -> flash mode (drive stays visible).
_flash_mode = not _btn.value
if not _flash_mode:
    storage.disable_usb_drive()
_btn.deinit()
"""#

    private static let embeddedCodePy: String = #"""
# sudo macropad firmware — CircuitPython (production v2)
#
# Reliability-first rewrite. Targets the failure modes seen in testing:
#
#   - "Pad powers on but macOS doesn't see USB": CircuitPython's USB
#     stack got wedged. Now: hardware watchdog (5s) hard-resets the
#     chip if the main loop hangs, AND a secondary `usb_connected`
#     check soft-fails after 10s of "powered but not enumerated" by
#     calling microcontroller.reset() to force a fresh USB stack.
#
#   - "Buttons silently don't register": send_report() exceptions used
#     to be swallowed. Now: tracked per-press, and after 3 consecutive
#     failures we microcontroller.reset() since that's the only way
#     to recover a stalled HID endpoint.
#
#   - "No visible 'I'm alive' signal": GP25 is now owned by code.py
#     for the whole run and turns on after the firmware reaches the
#     main loop. GP24 remains a short per-press flash so physical
#     button detection is visible independently of the Mac app.
#
#   - "Auto-reload kicked in mid-press": autoreload was True for
#     iteration. Production must be False so Spotlight / random FS
#     events can't soft-reload us at runtime.
#
#   - "Loop spammed error logs": persistent exceptions in the main
#     loop spammed CDC. Now: throttled to one log per unique error
#     message, with backoff.
#
# To iterate: hold button 1 + plug to mount CIRCUITPY, edit this file,
# then run `screen /dev/cu.usbmodem* 115200` (or use Sudo's pad
# console viewer) to watch CDC. Autoreload stays OFF — you need a
# Ctrl-D over REPL or a replug to apply changes.

import supervisor
print("## sudo-code.py-start t={}ms".format(supervisor.ticks_ms()))

# --- Reliability: hardware watchdog ----------------------------------
#
# RP2040 ships with an 8.3s-max hardware watchdog. We arm it at 8s
# (well below the limit, well above any legit main-loop latency) and
# feed it every iteration. If the main loop ever hangs (CircuitPython
# USB-stack lockup, infinite loop in a callback, you name it), the
# chip hard-resets within 8s and USB re-enumerates from scratch.
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

# Autoreload OFF in production. Spotlight / Finder file events can't
# trigger a soft-reload mid-press now.
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
#
# Direct-index first (always usb_hid.devices[0] in our config), with a
# scan fallback in case the order ever surprises us.
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


# --- LEDs ------------------------------------------------------------
#
# GP25 is the visible ready LED. It stays on once the firmware reaches
# the main loop. GP24 is a short per-press flash. Keep both objects
# alive for the whole run; relying on boot.py ownership across code.py
# is not reliable.
READY_LED_PIN = board.GP25
PRESS_LED_PIN = board.GP24
PRESS_LED_FLASH_MS = 160
_ready_led = None
_press_led = None
_press_led_off_at = 0
try:
    _ready_led = digitalio.DigitalInOut(READY_LED_PIN)
    _ready_led.direction = digitalio.Direction.OUTPUT
    _ready_led.value = False
    print("## sudo-leds-ready t={}ms gp25=ok".format(supervisor.ticks_ms()))
except Exception as _e:  # noqa: BLE001
    print("## sudo-leds-ready t={}ms gp25=err:{}".format(supervisor.ticks_ms(), _e))

try:
    _press_led = digitalio.DigitalInOut(PRESS_LED_PIN)
    _press_led.direction = digitalio.Direction.OUTPUT
    _press_led.value = False
    print("## sudo-leds-press t={}ms gp24=ok".format(supervisor.ticks_ms()))
except Exception as _e:  # noqa: BLE001
    print("## sudo-leds-press t={}ms gp24=err:{}".format(supervisor.ticks_ms(), _e))


def set_ready_led(on):
    if _ready_led is None:
        return
    try:
        _ready_led.value = on
    except Exception:  # noqa: BLE001
        pass


def flash_press_led():
    global _press_led_off_at
    if _press_led is None:
        return
    try:
        _press_led.value = True
        _press_led_off_at = supervisor.ticks_ms() + PRESS_LED_FLASH_MS
    except Exception:  # noqa: BLE001
        pass


def update_press_led():
    global _press_led_off_at
    if _press_led is None or _press_led_off_at == 0:
        return
    try:
        if ticks_diff(supervisor.ticks_ms(), _press_led_off_at) >= 0:
            _press_led.value = False
            _press_led_off_at = 0
    except Exception:  # noqa: BLE001
        _press_led_off_at = 0


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
#
# Every send_report() call can fail if USB endpoint is stalled. We
# track consecutive failures; after MAX_SEND_FAILS in a row, hard-reset
# the chip since a wedged HID endpoint can't be unwedged without a USB
# stack reinit. This is the second line of defence after the watchdog
# (which only fires if the loop itself hangs).
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
        # Brief sleep so the print actually goes out the wire.
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
        return  # release path doesn't trigger reset on its own
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
#
# debounce_until is seeded from the current ticks_ms() rather than 0.
# Reason: ticks_diff is wrap-safe across the 2**29 ms period, which
# means ticks_diff(now, 0) returns NEGATIVE whenever ticks_ms() is in
# the upper half of the wrap window (anything past ~3.1 days of
# uptime). The button loop below skips when ticks_diff < 0, so a
# seed of 0 silently disables button detection for up to ~3 days
# until ticks_ms() wraps back through zero. Seeding from the current
# tick makes ticks_diff start at 0 (not negative) and the debounce
# math stays correct for the actual button-press case.
DEBOUNCE_MS = 20
last_state = [True] * 4
_now0 = supervisor.ticks_ms()
debounce_until = [_now0] * 4

print("## sudo-ready t={}ms".format(supervisor.ticks_ms()))
set_ready_led(True)
try:
    print("## sudo-buttons-state t={}ms states={}".format(
        supervisor.ticks_ms(),
        "".join(["1" if b.value else "0" for b in buttons]),
    ))
except Exception as _e:  # noqa: BLE001
    print("## sudo-buttons-state t={}ms err:{}".format(supervisor.ticks_ms(), _e))

# USB connectivity watchdog. supervisor.runtime.usb_connected goes
# False when the host stops responding (cable yank, host USB stack
# crash). If we see it False for USB_GONE_RESET_MS and we're still
# running (so power is good), force a hard reset to give CircuitPython
# a fresh USB stack.
USB_GONE_RESET_MS = 10_000
_usb_last_seen = supervisor.ticks_ms()

# Heartbeat — every 30s in steady state, with an early-boot burst so
# the host gets a "I'm alive" line within ~200ms of plug-in.
#
# Why the burst exists: CircuitPython's USB CDC TX FIFO is small and not
# buffered before the host opens the tty. Every boot print before the
# host attaches gets discarded. The Mac side's `PadConsoleReader` opens
# /dev/cu.usbmodem* 50ms-1.5s after HID enumeration, which is often
# AFTER the boot prints have rolled out of the FIFO. Without the burst,
# the first "## sudo-" line the host sees is the steady-state heartbeat
# at t=30s — and the Mac-side event-tap refresh on `padReady` doesn't
# fire until then, so buttons silently don't work for the first 30s
# after plug-in. The burst at 200ms / 1s / 3s / 10s defeats that race
# regardless of which side wins the open/print order.
HEARTBEAT_MS = 30000
_BOOT_BURST_MS = (200, 1000, 3000, 10000)
_boot_t = supervisor.ticks_ms()
_burst_index = 0
_last_heartbeat = _boot_t

# Error-log throttle: don't spam "loop-error" 10x/s if something is
# persistently broken. Track last-logged message + min interval.
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

        # Feed the hardware watchdog every loop. Skipping a feed
        # means the loop is hung; the chip resets within timeout.
        if _wdt is not None:
            try:
                _wdt.feed()
            except Exception:  # noqa: BLE001
                pass

        # USB-stack health check. If host says "connected" we update
        # the timestamp. If it's been gone too long while we're still
        # running, hard reset to re-init USB.
        try:
            usb_ok = supervisor.runtime.usb_connected
        except Exception:  # noqa: BLE001
            usb_ok = True  # API missing -> don't reset on a false negative
        if usb_ok:
            _usb_last_seen = now
        elif ticks_diff(now, _usb_last_seen) > USB_GONE_RESET_MS:
            print("## sudo-hard-reset reason=usb-gone-{}ms".format(
                ticks_diff(now, _usb_last_seen)))
            try: time.sleep(0.05)
            except Exception: pass
            try: microcontroller.reset()
            except Exception: pass

        update_press_led()

        for i in range(4):
            if ticks_diff(now, debounce_until[i]) < 0:
                continue
            state = buttons[i].value
            if state != last_state[i]:
                last_state[i] = state
                debounce_until[i] = now + DEBOUNCE_MS
                if not state:
                    dispatch_press(i)
                    flash_press_led()
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
"""#

    // MARK: - Copy helpers

    /// Spawn `cp`, then poll for the bootloader volume to unmount. The
    /// RP2040 bootloader unmounts after it processes a UF2 — that's our
    /// completion signal. `cp` itself usually hangs on close() until the
    /// volume reappears or we kill it.
    func copyToBootloader(src: URL, dst: URL, label: String) throws {
        updatePhase("\(label) — \(formatBytes(fileSize(at: src)))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = [src.path, dst.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let start = Date()
        var lastSeenMounted = true
        while true {
            let mounted = findBootloaderVolume() != nil
            let elapsed = Date().timeIntervalSince(start)
            // Model progress as elapsed/expected window during the write.
            let modelled = min(elapsed / 4.0, 0.95)
            updateProgress(modelled, phase: "\(label)… \(Int(modelled * 100))%")

            if !mounted && lastSeenMounted {
                Thread.sleep(forTimeInterval: 0.4)
                process.terminate()
                updateProgress(1.0, phase: "device rebooting")
                return
            }
            lastSeenMounted = mounted

            if elapsed > unmountTimeoutSeconds {
                process.terminate()
                throw NSError(domain: "FirmwareFlasher", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "device didn't unmount after \(Int(unmountTimeoutSeconds)) s — try unplugging and re-entering BOOTSEL"
                ])
            }
            Thread.sleep(forTimeInterval: pollIntervalSeconds)
        }
    }

    private func copyOverwriting(src: URL, dst: URL) throws {
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
    }

    private func writeOverwriting(data: Data, to dst: URL) throws {
        try data.write(to: dst, options: [.atomic])
    }

    // MARK: - Volume discovery

    private func findBootloaderVolume() -> String? {
        findVolume(named: "RPI-RP2", marker: "INFO_UF2.TXT")
    }

    private func findCircuitPyVolume() -> String? {
        findVolume(named: "CIRCUITPY", marker: "boot_out.txt")
    }

    private func findVolume(named name: String, marker: String) -> String? {
        let volumesPath = "/Volumes"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: volumesPath) else {
            return nil
        }
        for volume in contents where volume == name {
            let path = "\(volumesPath)/\(volume)"
            let markerPath = "\(path)/\(marker)"
            if FileManager.default.fileExists(atPath: markerPath) {
                return path
            }
        }
        return nil
    }

    private func waitForCircuitPyMount(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let path = findCircuitPyVolume() {
                return path
            }
            // Also model progress while we wait
            let elapsed = timeout - deadline.timeIntervalSinceNow
            updateProgress(min(elapsed / timeout, 0.95),
                           phase: "waiting for CIRCUITPY to mount…")
            Thread.sleep(forTimeInterval: pollIntervalSeconds)
        }
        return nil
    }

    // MARK: - State helpers

    private func beginFlashing(label: String, at step: FlashStep) {
        DispatchQueue.main.async {
            self.state = .flashing
            self.phase = label
            self.progress = 0
            self.step = step
        }
    }

    private func updatePhase(_ label: String) {
        DispatchQueue.main.async { self.phase = label }
    }

    private func updateProgress(_ value: Double, phase: String) {
        DispatchQueue.main.async {
            self.progress = value
            self.phase = phase
        }
    }

    private func finishSuccess(label: String) {
        DispatchQueue.main.async {
            self.state = .success
            self.phase = label
            self.progress = 1.0
            self.step = .verify
            print("[sudo] \(label)")
        }
    }

    private func setError(_ message: String) {
        DispatchQueue.main.async {
            self.state = .error(message: message)
            self.phase = message
            self.progress = 0
            print("[sudo] flash error: \(message)")
        }
    }

    // MARK: - Misc helpers

    private func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }
}

/// URLSession delegate that forwards download progress to a closure.
private final class FirmwareDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Int64, Int64) -> Void
    init(onProgress: @escaping (Int64, Int64) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

// MARK: - Connection-status label

import SwiftUI

extension FirmwareFlasher {
    struct ConnectionLabel {
        let label: String
        let colour: Color
    }

    /// Human-readable status used by the settings device panel and the
    /// onboarding flow. Reads `state` so the same source of truth drives
    /// every "is the pad plugged in?" UI.
    var deviceConnectionLabel: ConnectionLabel {
        switch state {
        case .readyForConfig:
            return .init(label: "device: connected (CircuitPython)", colour: SudoTheme.accent)
        case .readyForFirmware:
            return .init(label: "device: in BOOTSEL — needs install", colour: Color(nsColor: .systemYellow))
        case .detectingDevice:
            return .init(label: "device: scanning…", colour: Color(nsColor: .systemYellow))
        case .flashing:
            return .init(label: "device: flashing", colour: SudoTheme.accent)
        case .success:
            return .init(label: "device: just flashed", colour: SudoTheme.accent)
        case .error(let msg):
            return .init(label: "device: error — \(msg)", colour: Color(nsColor: .systemRed))
        case .idle:
            // After v1.5.3 boot.py hides the CIRCUITPY drive in normal
            // use, so the volume-mount notification never fires when the
            // pad is just running. The IOKit HID watcher gives us a
            // reliable "is the pad here" signal that doesn't depend on
            // the mass-storage drive being visible.
            if hidConnected {
                return .init(label: "device: connected (running)",
                             colour: SudoTheme.accent)
            }
            return .init(label: "device: not detected (hold button 1 + replug to flash)",
                         colour: Color(nsColor: .separatorColor))
        }
    }
}

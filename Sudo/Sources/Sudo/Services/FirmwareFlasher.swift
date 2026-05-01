import Foundation

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

    /// Path 1: CIRCUITPY is mounted, write code.py + config.json.
    ///
    /// Pure-HID firmware: pad sends ctrl+shift+F-keys, the macOS app's
    /// HotkeyListener catches them. No serial protocol, no boot.py.
    private func writeConfigToCircuitPy(path: String, settings: SudoSettings) {
        beginFlashing(label: "writing code.py and config.json…", at: .write)
        do {
            let bootDst = URL(fileURLWithPath: path).appendingPathComponent("boot.py")
            let codeDst = URL(fileURLWithPath: path).appendingPathComponent("code.py")
            let configDst = URL(fileURLWithPath: path).appendingPathComponent("config.json")
            let configData = try SudoConfigJSON.generate(from: settings)

            // Old serial-protocol installs left a boot.py behind that enabled
            // usb_cdc.data. Remove it so the device only exposes one tty.
            try? FileManager.default.removeItem(at: bootDst)

            updateProgress(0.2, phase: "writing code.py…")
            try Self.embeddedCodePy.write(to: codeDst, atomically: true, encoding: .utf8)
            updateProgress(0.6, phase: "writing config.json (\(settings.appMode.rawValue) mode)…")
            try writeOverwriting(data: configData, to: configDst)

            DispatchQueue.main.async { self.step = .verify }
            updateProgress(0.9, phase: "waiting for CircuitPython auto-reload…")
            Thread.sleep(forTimeInterval: 0.6)

            finishSuccess(label: "config live (\(settings.appMode.rawValue) mode)")
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
    // KEEP IN SYNC with sudo-supply/hardware/firmware/code.py.

    private static let embeddedCodePy: String = #"""
# sudo macropad firmware — CircuitPython
#
# Buttons on GP0-GP3 (active-low, internal pull-up). Sends HID keystrokes;
# the macOS app's HotkeyListener catches them and dispatches per-app actions.
#
# Defaults: ctrl+shift + F13/F18/F17/F16. F14/F15 are skipped because macOS
# treats those as display-brightness keys even with modifiers held.

import board
import digitalio
import json
import supervisor
import time
import usb_hid


# CircuitPython 9.x exposes ticks_ms() but NOT ticks_diff() — that's a
# MicroPython-ism. Roll our own wrap-safe version (counter wraps at 2**29).
_TICKS_PERIOD = 1 << 29
_TICKS_HALFPERIOD = _TICKS_PERIOD // 2


def ticks_diff(t1, t2):
    diff = (t1 - t2) & (_TICKS_PERIOD - 1)
    if diff >= _TICKS_HALFPERIOD:
        diff -= _TICKS_PERIOD
    return diff


keyboard = None
consumer = None
for d in usb_hid.devices:
    if d.usage_page == 0x01 and d.usage == 0x06:
        keyboard = d
    elif d.usage_page == 0x0C and d.usage == 0x01:
        consumer = d


# Pin order = physical bottom → top (matches PadAction.physicalOrder on
# the app side). The hardware wires GP3 to the bottom switch, so going
# numeric here would flip the indexes from what the app shows.
PINS = (board.GP3, board.GP2, board.GP1, board.GP0)
buttons = []
for pin in PINS:
    p = digitalio.DigitalInOut(pin)
    p.direction = digitalio.Direction.INPUT
    p.pull = digitalio.Pull.UP
    buttons.append(p)


# LED feedback on GP24 only — GP25 is the Pico's onboard LED and
# CircuitPython uses it for boot / error patterns. try/except so a board
# without LED2 wired up still runs.
LED_PIN = board.GP24
LED_FLASH_MS = 120
_led_off_at = 0
try:
    _led = digitalio.DigitalInOut(LED_PIN)
    _led.direction = digitalio.Direction.OUTPUT
    _led.value = False
    _led_ok = True
except Exception:  # noqa: BLE001
    _led_ok = False


def flash_led():
    global _led_off_at
    if not _led_ok:
        return
    try:
        _led.value = True
        _led_off_at = supervisor.ticks_ms() + LED_FLASH_MS
    except Exception:  # noqa: BLE001
        pass


def update_led():
    global _led_off_at
    if not _led_ok or _led_off_at == 0:
        return
    try:
        if ticks_diff(supervisor.ticks_ms(), _led_off_at) >= 0:
            _led.value = False
            _led_off_at = 0
    except Exception:  # noqa: BLE001
        _led_off_at = 0


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


def send_key_down(modifiers, keycode):
    if keyboard is None:
        return
    try:
        rpt = bytearray(8)
        rpt[0] = modifiers & 0xFF
        rpt[2] = keycode & 0xFF
        keyboard.send_report(rpt)
    except Exception:  # noqa: BLE001
        pass


def send_key_up():
    if keyboard is None:
        return
    try:
        keyboard.send_report(bytearray(8))
    except Exception:  # noqa: BLE001
        pass


def send_key(modifiers, keycode):
    send_key_down(modifiers, keycode)
    time.sleep(0.015)
    send_key_up()


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
    except Exception:  # noqa: BLE001
        pass


_CONSUMER = {16: 0xCD, 17: 0xB5, 18: 0xB6, 19: 0xB7, 20: 0xE2}

# Per-button "currently held" tracker so we can release the key the
# moment the user lets go (enables YouTube's hold-spacebar-for-2x).
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
    if key_held[i]:
        send_key_up()
        key_held[i] = False


DEBOUNCE_MS = 20
last_state = [True] * 4
debounce_until = [0] * 4

while True:
    try:
        now = supervisor.ticks_ms()
        update_led()
        for i in range(4):
            if ticks_diff(now, debounce_until[i]) < 0:
                continue
            state = buttons[i].value
            if state != last_state[i]:
                last_state[i] = state
                debounce_until[i] = now + DEBOUNCE_MS
                if not state:
                    flash_led()
                    dispatch_press(i)
                else:
                    dispatch_release(i)
        time.sleep(0.005)
    except Exception:  # noqa: BLE001
        try:
            time.sleep(0.1)
        except Exception:  # noqa: BLE001
            pass
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
            return .init(label: "device: not detected", colour: Color(nsColor: .separatorColor))
        }
    }
}

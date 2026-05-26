import Foundation
import Darwin

/// LED state commands sent to the RP2040 pad over USB serial.
/// Maps 1:1 to the `evt:*` lines the firmware listens for.
enum PadLEDState: UInt8 {
    case idle            = 0x01
    case processing      = 0x02
    case success         = 0x03
    case failure         = 0x04
    case waitingForInput = 0x05
    case buttonPressed   = 0x06
    case rebootBootsel   = 0x07

    /// Tag used in `evt:<tag>` on the wire. Pad firmware owns the
    /// pattern that runs for each tag — keep these short and ASCII.
    var wireTag: String {
        switch self {
        case .idle:            return "idle"
        case .processing:      return "busy"
        case .success:         return "ok"
        case .failure:         return "fail"
        case .waitingForInput: return "wait"
        case .buttonPressed:   return "press"
        case .rebootBootsel:   return "reboot"
        }
    }
}

/// Host → pad write channel over the second CDC interface
/// (`usb_cdc.data`). Pairs with `PadConsoleReader`, which owns the
/// console interface (reads firmware prints). The two never share a
/// file descriptor: console reader holds the first sorted
/// `cu.usbmodem*`, this class holds the second.
///
/// Wire protocol — line-based, `\n`-terminated, ASCII:
///   `cfg:on=0|1`              master enable
///   `cfg:bri=N`               brightness 0–100 (pad maps to PWM 0–65535)
///   `cfg:mode=feedback|breathe|solid|status-dim`
///   `evt:idle|press|busy|ok|fail|wait|reboot`
///
/// Pad keeps no persistent state. On every (re)connect we push the
/// full `cfg:*` triple followed by `evt:idle` so a freshly-plugged
/// pad always reflects current settings. Writes silently drop when
/// disconnected — pad absent isn't an error.
final class PadCommunicator {
    static let shared = PadCommunicator()

    private let queue = DispatchQueue(label: "sudo.pad.write", qos: .userInitiated)
    private var fd: Int32 = -1
    private var portPath: String?
    private var reconnectObserver: NSObjectProtocol?

    private init() {
        // Re-push settings the moment the firmware shows it's alive
        // on the console channel. `padReady` fires after any `## sudo-`
        // line, which means the main loop is running and is therefore
        // also draining `usb_cdc.data.in_waiting`.
        reconnectObserver = NotificationCenter.default.addObserver(
            forName: .padReady, object: nil, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.openIfNeeded(); self?.pushAllSettingsLocked() }
        }
    }

    // MARK: - Lifecycle

    /// Idempotent. Tries once to open the data port; no-ops if absent.
    /// Safe to call before the pad is plugged in — reconnect happens
    /// automatically on `.padReady`.
    func connect() {
        queue.async { [weak self] in
            self?.openIfNeeded()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.closeLocked()
        }
    }

    // MARK: - Sending

    /// Send an event tag. Most callers (`SudoEngine`) already invoke
    /// this at the right pipeline moments; the only behaviour change is
    /// that the write now actually reaches the pad.
    func sendState(_ state: PadLEDState) {
        write(line: "evt:\(state.wireTag)")
    }

    /// Press event with the physical button number (1..4). The pad
    /// firmware uses N to fire a per-button identity signature in
    /// feedback mode so the user can tell buttons apart from the LEDs
    /// alone. Older firmware ignores the trailing token.
    func sendPress(button: Int) {
        write(line: "evt:press n=\(button)")
    }

    /// Push all three settings + an `evt:idle`. Call from settings
    /// `didSet` and after `connect()` so the pad never lags the host.
    func pushAllSettings() {
        queue.async { [weak self] in
            self?.pushAllSettingsLocked()
        }
    }

    // MARK: - Internals

    private func pushAllSettingsLocked() {
        guard fd >= 0 else { return }
        let s = SudoSettings.shared
        writeLineLocked("cfg:on=\(s.ledsEnabled ? 1 : 0)")
        writeLineLocked("cfg:bri=\(s.ledBrightness)")
        writeLineLocked("cfg:mode=\(s.ledMode)")
        writeLineLocked("evt:idle")
    }

    private func write(line: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.openIfNeeded()
            self.writeLineLocked(line)
        }
    }

    private func writeLineLocked(_ line: String) {
        guard fd >= 0 else { return }
        let payload = line + "\n"
        guard let data = payload.data(using: .ascii) else { return }
        data.withUnsafeBytes { raw -> Void in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = Darwin.write(fd, base.advanced(by: sent), data.count - sent)
                if n > 0 {
                    sent += n
                    continue
                }
                if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    // CDC TX FIFO full — rare; drop the line rather than
                    // block the queue. Next setting change re-pushes.
                    return
                }
                // EIO / ENXIO etc. — pad went away mid-write.
                closeLocked()
                return
            }
        }
    }

    private func openIfNeeded() {
        if fd >= 0 { return }
        guard let path = PadConsoleReader.findDataPort() else { return }
        let opened = Darwin.open(path, O_WRONLY | O_NONBLOCK | O_NOCTTY)
        if opened < 0 { return }
        // Raw + 115200 to mirror PadConsoleReader. CDC ACM ignores baud
        // but cfmakeraw disables canonical-mode line buffering, which
        // matters once we're writing instead of reading.
        var t = termios()
        if tcgetattr(opened, &t) == 0 {
            cfmakeraw(&t)
            cfsetspeed(&t, speed_t(B115200))
            _ = tcsetattr(opened, TCSANOW, &t)
        }
        fd = opened
        portPath = path
    }

    private func closeLocked() {
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        portPath = nil
    }
}

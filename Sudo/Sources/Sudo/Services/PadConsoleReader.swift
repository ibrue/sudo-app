import Foundation
import Darwin

/// Tails the macropad's CDC console (`/dev/cu.usbmodem*`) and surfaces
/// each line as a published entry. Lets us copy boot/runtime logs out
/// of the firmware without making users wrangle `screen` from a
/// terminal — the typical debugging audience for "the pad takes a
/// minute to connect" reports.
///
/// Why we don't use ORSSerialPort or similar: the pad's CDC interface
/// runs through CircuitPython's USB stack and ignores baud rate (USB
/// CDC ACM is byte-streamed, not actually serial), so all we need is
/// to open the tty in raw mode and read whatever shows up. POSIX
/// `open(2)` + a `DispatchSourceRead` covers it in ~80 lines.
final class PadConsoleReader: ObservableObject {
    static let shared = PadConsoleReader()

    @Published private(set) var lines: [String] = []
    @Published private(set) var portPath: String?
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var lastError: String?

    /// Flips true the moment we see ANY firmware print on CDC — the signal
    /// that the main loop is running and the pad is ready to accept presses.
    /// The Sudo engine subscribes to this to refresh the event tap so the
    /// freshly-enumerated HID keyboard's events route through.
    ///
    /// Why "any" instead of just `## sudo-ready`: the CircuitPython USB CDC
    /// TX FIFO is small and unbuffered before the host opens the tty. The
    /// boot prints (`## sudo-code.py-start` through `## sudo-ready`) can
    /// roll out of the FIFO before `PadConsoleReader` connects — common
    /// because the CDC tty appears 50 ms–1.5 s after HID enumeration. If
    /// we only matched `## sudo-ready`, missing it meant waiting 30 s for
    /// the first `## sudo-alive` heartbeat with no tap refresh in between,
    /// which is exactly the "30 s before any button works" symptom we saw.
    /// Any `## sudo-` line proves the firmware is alive, so it's a valid
    /// trigger.
    @Published private(set) var padReady: Bool = false

    private static let maxLines = 2000

    /// Prefix that every firmware diagnostic line carries. Seeing any line
    /// with this prefix means the main loop is running, which is what
    /// `padReady` represents.
    private static let runningPrefix = "## sudo-"

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "sudo.pad.console", qos: .userInitiated)
    private var lineBuffer: String = ""

    // MARK: - Public

    /// Try to open the first available `/dev/cu.usbmodem*` device and
    /// start tailing it. Idempotent — calling twice while connected
    /// is a no-op. Silent if no device is present (vs. `start()` which
    /// records a "plug in the pad" error). Use this from app launch so
    /// we're tailing CDC the moment the pad enumerates, without making
    /// noise when the pad isn't there.
    func startIfPossible() {
        guard fd < 0 else { return }
        guard Self.findPort() != nil else { return }
        start()
    }

    /// Try to open the first available `/dev/cu.usbmodem*` device and
    /// start tailing it. Idempotent — calling twice while connected
    /// is a no-op.
    func start() {
        guard fd < 0 else { return }
        guard let path = Self.findPort() else {
            DispatchQueue.main.async {
                self.lastError = "no /dev/cu.usbmodem* device — is the pad plugged in?"
            }
            return
        }
        let opened = open(path, O_RDONLY | O_NONBLOCK | O_NOCTTY)
        if opened < 0 {
            let msg = String(cString: strerror(errno))
            DispatchQueue.main.async {
                self.lastError = "open(\(path)) failed: \(msg)"
            }
            return
        }
        fd = opened

        // Best-effort raw-mode config so the OS doesn't munge bytes
        // line-by-line. CDC ACM ignores baud rate but cfmakeraw
        // disables canonical mode + signal handling, which is what
        // we want for a free-form log stream.
        var t = termios()
        if tcgetattr(fd, &t) == 0 {
            cfmakeraw(&t)
            cfsetspeed(&t, speed_t(B115200))
            _ = tcsetattr(fd, TCSANOW, &t)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
        }
        source.resume()
        readSource = source

        DispatchQueue.main.async {
            self.portPath = path
            self.isConnected = true
            self.lastError = nil
            self.append(line: "── connected to \(path) ──")
            Self.diagLog("[mac] tty-opened path=\(path)")
        }
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        DispatchQueue.main.async { [weak self] in
            self?.handleDisconnect(reason: nil)
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.lines.removeAll()
            self.lineBuffer = ""
        }
    }

    /// Disconnect + reconnect — the typical "I want fresh output"
    /// gesture after replugging the pad.
    func reconnect() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.start() }
    }

    /// Raw text dump for clipboard copy.
    var transcript: String {
        lines.joined(separator: "\n")
    }

    // MARK: - Internals

    private static func findPort() -> String? {
        let dev = "/dev"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dev) else {
            return nil
        }
        // `cu.usbmodem*` is the macOS naming for USB CDC devices.
        // Sorted so a stable choice across calls when more than one
        // is present (rare).
        let candidates = entries
            .filter { $0.hasPrefix("cu.usbmodem") }
            .sorted()
        return candidates.first.map { "\(dev)/\($0)" }
    }

    private func readAvailable() {
        // Pulled off the read source's queue, so blocking calls are
        // fine here. The fd is non-blocking anyway.
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = buf.withUnsafeMutableBufferPointer { ptr -> Int in
            return read(fd, ptr.baseAddress, ptr.count)
        }
        if n <= 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            // Cancel the source synchronously on the read queue so the
            // dispatch source stops firing immediately. If we instead
            // dispatched the cancel to main and waited for it, the
            // source can fire its read handler hundreds of times in
            // the meantime — a TTY at EOF is perpetually "readable"
            // until the source is cancelled — and each firing would
            // schedule another disconnect notification. That's how
            // the popover ended up with thousands of "── disconnected
            // ──" lines on a single unplug.
            if let src = readSource {
                src.cancel()
                readSource = nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.handleDisconnect(reason: "pad disconnected")
            }
            return
        }
        guard let chunk = String(bytes: buf[0..<n], encoding: .utf8) else { return }
        lineBuffer += chunk
        // Split on newlines, keep any trailing partial line for the
        // next chunk.
        var parts = lineBuffer.components(separatedBy: "\n")
        lineBuffer = parts.removeLast()
        let newLines = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        DispatchQueue.main.async {
            for line in newLines { self.append(line: line) }
        }
    }

    /// Always called on main. Appends + caps line count. Detects the
    /// firmware READY sentinel and posts a notification so the engine
    /// can react without polling.
    private func append(line: String) {
        lines.append(line)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
        Self.diagLog(line)
        if !padReady, line.contains(Self.runningPrefix) {
            padReady = true
            NotificationCenter.default.post(name: .padReady, object: nil)
        }
    }

    /// Mirror every CDC line to /tmp/sudo-pad-console.log with a
    /// millisecond wall-clock prefix. Used during connect-time
    /// debugging — gives us a single timeline of "## sudo-..." pad
    /// boot markers plus Mac-side observations of "tty-appeared",
    /// "padReady fired", etc., so we can see exactly where the time
    /// goes between plug-in and first-press-works. Cheap (~80 bytes
    /// per line); leave on in production.
    static func diagLog(_ line: String) {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let entry = "\(ms) \(line)\n"
        guard let data = entry.data(using: .utf8) else { return }
        let path = "/tmp/sudo-pad-console.log"
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            if let fh = try? FileHandle(forWritingTo: url) {
                _ = try? fh.seekToEnd()
                _ = try? fh.write(contentsOf: data)
                _ = try? fh.close()
            }
        } else {
            try? data.write(to: url)
        }
    }

    /// Idempotent shutdown — both the user-driven `stop()` path and the
    /// EOF path in `readAvailable` route through here. The `isConnected`
    /// guard means a second call (e.g. duplicate disconnect events from
    /// a source that fired once before its cancel took effect) is a
    /// no-op rather than appending another marker.
    private func handleDisconnect(reason: String?) {
        guard isConnected else { return }
        isConnected = false
        portPath = nil
        padReady = false
        if let reason = reason { lastError = reason }
        // fd is closed by the dispatch source's cancel handler — it
        // runs on the source's queue, so closing it from main here
        // would race against background reads. Leave it to the cancel
        // path (the cancel was already issued before this main-queue
        // hop, in either stop() or readAvailable's EOF branch).
        append(line: "── disconnected ──")
    }
}

extension Notification.Name {
    /// Posted by PadConsoleReader the first time any `## sudo-` firmware
    /// line is seen after (re)connect — proof the main loop is running.
    /// The Sudo engine listens for it to refresh the event tap and flip
    /// the popover's connected state immediately, no polling required.
    static let padReady = Notification.Name("sudo.pad.ready")
}

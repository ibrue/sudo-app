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

    private static let maxLines = 2000

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "sudo.pad.console", qos: .userInitiated)
    private var lineBuffer: String = ""

    // MARK: - Public

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
        }
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.portPath = nil
            self.append(line: "── disconnected ──")
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
            // Pad probably disconnected. Tear down so the user can
            // hit reconnect once they replug.
            DispatchQueue.main.async {
                self.lastError = "pad disconnected"
                self.stop()
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

    /// Always called on main. Appends + caps line count.
    private func append(line: String) {
        lines.append(line)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }
}

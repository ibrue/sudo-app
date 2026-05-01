import Foundation
import Darwin

/// LED state commands sent to the RP2040 pad over USB serial.
/// Kept for future use — current CircuitPython firmware does not read these.
enum PadLEDState: UInt8 {
    case idle           = 0x01
    case processing     = 0x02
    case success        = 0x03
    case failure        = 0x04
    case waitingForInput = 0x05
    case buttonPressed  = 0x06
    case rebootBootsel  = 0x07
}

/// USB serial bridge to the sudo macropad.
///
/// CircuitPython exposes two `tty.usbmodem*` devices when `usb_cdc.data`
/// is enabled (REPL on one, our protocol on the other). We open every
/// candidate, read line-buffered, and only act on lines we understand —
/// so we don't have to identify which port is which.
///
/// Protocol (firmware → app, line-buffered, UTF-8):
///   PRESS <1|2|3|4>\n   physical button (1 = bottom, 4 = top) was pressed
///
/// On `PRESS N`, looks up the matching `PadAction` via
/// `PadAction.physicalOrder` and invokes `onButtonPress`. The engine
/// wires that handler into the action pipeline so dynamic mode no longer
/// relies on intercepting HID F-keys system-wide.
final class PadCommunicator {
    static let shared = PadCommunicator()

    /// Invoked off the main queue when the firmware reports a button press.
    /// Wired by SudoEngine on startup.
    var onButtonPress: ((PadAction) -> Void)?

    private struct Port {
        let fd: Int32
        let path: String
        let source: DispatchSourceRead
        var buffer: Data
    }

    private let queue = DispatchQueue(label: "com.sudo.pad-communicator", qos: .userInitiated)
    private var ports: [Int32: Port] = [:]
    private var rescanTimer: DispatchSourceTimer?

    func connect() {
        queue.async { [weak self] in
            self?.rescan()
            self?.startRescanTimer()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.closeAll()
            self?.rescanTimer?.cancel()
            self?.rescanTimer = nil
        }
    }

    /// Send a single-byte LED state command. No-op if no device.
    /// (Current firmware doesn't consume these; kept for future LED protocol.)
    func sendState(_ state: PadLEDState) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.ports.isEmpty { self.rescan() }
            var byte = state.rawValue
            for fd in self.ports.keys {
                _ = write(fd, &byte, 1)
            }
        }
    }

    // MARK: - Rescan + open + close

    private func rescan() {
        let candidates = Set(
            findDevices(matching: "/dev/tty.usbmodem*")
            + findDevices(matching: "/dev/tty.usbserial*")
        )
        let openPaths = Set(ports.values.map { $0.path })

        // Close ports whose device path has vanished.
        for (fd, port) in ports where !candidates.contains(port.path) {
            print("[sudo-pad] device gone: \(port.path)")
            port.source.cancel()
            ports.removeValue(forKey: fd)
        }

        // Open new candidates.
        for path in candidates where !openPaths.contains(path) {
            openOne(path: path)
        }
    }

    private func openOne(path: String) {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            print("[sudo-pad] open \(path) failed: \(String(cString: strerror(errno)))")
            return
        }
        configureRaw(fd: fd)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable(fd: fd)
        }
        source.setCancelHandler { close(fd) }
        source.resume()

        ports[fd] = Port(fd: fd, path: path, source: source, buffer: Data())
        print("[sudo-pad] listening on \(path)")
    }

    private func closeAll() {
        for (_, port) in ports { port.source.cancel() }
        ports.removeAll()
    }

    private func startRescanTimer() {
        rescanTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in self?.rescan() }
        timer.resume()
        rescanTimer = timer
    }

    private func configureRaw(fd: Int32) {
        var t = termios()
        if tcgetattr(fd, &t) != 0 { return }
        cfmakeraw(&t)
        t.c_cflag |= UInt(CLOCAL | CREAD)
        // Non-blocking reads regardless of cfmakeraw's VMIN default.
        withUnsafeMutablePointer(to: &t.c_cc) { ptr in
            ptr.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)] = 0
                cc[Int(VTIME)] = 0
            }
        }
        _ = tcsetattr(fd, TCSANOW, &t)
    }

    // MARK: - Read + parse

    private func readAvailable(fd: Int32) {
        guard var port = ports[fd] else { return }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = read(fd, &buf, buf.count)
        if n <= 0 { return }
        port.buffer.append(buf, count: Int(n))

        while let nlIdx = port.buffer.firstIndex(of: 0x0A) {
            let lineData = port.buffer.subdata(in: 0..<nlIdx)
            port.buffer.removeSubrange(0...nlIdx)
            if let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                handleLine(line)
            }
        }
        ports[fd] = port
    }

    private func handleLine(_ line: String) {
        // Only one line type today. Anything else (REPL banner, debug
        // prints, errant bytes) is silently ignored.
        guard line.hasPrefix("PRESS ") else { return }
        let parts = line.split(separator: " ")
        guard parts.count == 2,
              let n = Int(parts[1]),
              (1...4).contains(n) else { return }

        let order = PadAction.physicalOrder
        guard n - 1 < order.count else { return }
        let action = order[n - 1]

        print("[sudo-pad] PRESS \(n) → \(action.rawValue)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.onButtonPress?(action)
        }
    }

    private func findDevices(matching pattern: String) -> [String] {
        var gt = glob_t()
        defer { globfree(&gt) }
        guard glob(pattern, 0, nil, &gt) == 0 else { return [] }
        var paths: [String] = []
        for i in 0..<Int(gt.gl_pathc) {
            if let cStr = gt.gl_pathv[i] {
                paths.append(String(cString: cStr))
            }
        }
        return paths
    }
}

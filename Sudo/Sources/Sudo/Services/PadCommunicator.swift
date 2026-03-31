import Foundation

/// LED state commands sent to the RP2040 pad over USB serial.
enum PadLEDState: UInt8 {
    case idle           = 0x01  // dim green
    case processing     = 0x02  // pulsing green
    case success        = 0x03  // flash green
    case failure        = 0x04  // flash red
    case waitingForInput = 0x05 // bright green
}

/// Communicates with the sudo pad hardware over USB serial to control LEDs.
///
/// Scans for `/dev/tty.usbmodem*` devices and sends single-byte state commands.
/// Degrades gracefully if no device is found.
final class PadCommunicator {
    static let shared = PadCommunicator()

    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.sudo.pad-communicator", qos: .userInitiated)

    /// Attempt to open the first matching USB serial device.
    func connect() {
        queue.async { [weak self] in
            self?.openDevice()
        }
    }

    /// Send an LED state command to the pad.
    /// If no device is connected, logs and returns silently.
    func sendState(_ state: PadLEDState) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Try to connect if not already open
            if self.fileDescriptor < 0 {
                self.openDevice()
            }

            guard self.fileDescriptor >= 0 else {
                // No device — degrade silently
                return
            }

            var byte = state.rawValue
            let written = write(self.fileDescriptor, &byte, 1)
            if written < 0 {
                print("[sudo-pad] Write failed, closing device")
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            } else {
                print("[sudo-pad] Sent state: \(state) (0x\(String(format: "%02x", state.rawValue)))")
            }
        }
    }

    /// Close the serial connection.
    func disconnect() {
        queue.async { [weak self] in
            guard let self = self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
            print("[sudo-pad] Disconnected")
        }
    }

    // MARK: - Private

    private func openDevice() {
        let patterns = ["/dev/tty.usbmodem*", "/dev/tty.usbserial*"]
        var devicePath: String?

        for pattern in patterns {
            let globResult = findDevices(matching: pattern)
            if let first = globResult.first {
                devicePath = first
                break
            }
        }

        guard let path = devicePath else {
            print("[sudo-pad] No USB serial device found — LED feedback disabled")
            return
        }

        let fd = open(path, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        if fd < 0 {
            print("[sudo-pad] Failed to open \(path): \(String(cString: strerror(errno)))")
            return
        }

        fileDescriptor = fd
        print("[sudo-pad] Connected to \(path)")
    }

    /// Glob for device paths matching a pattern.
    private func findDevices(matching pattern: String) -> [String] {
        var gt = glob_t()
        defer { globfree(&gt) }

        let result = glob(pattern, 0, nil, &gt)
        guard result == 0 else { return [] }

        var paths: [String] = []
        for i in 0..<Int(gt.gl_pathc) {
            if let cStr = gt.gl_pathv[i] {
                paths.append(String(cString: cStr))
            }
        }
        return paths
    }
}

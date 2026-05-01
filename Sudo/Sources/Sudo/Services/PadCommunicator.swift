import Foundation

/// LED state commands sent to the RP2040 pad over USB serial.
/// The current pure-HID firmware doesn't read these; kept as a stub so
/// callers (engine, status updates) keep compiling. Restoring real LED
/// feedback is a future change that pairs with a firmware-side reader.
enum PadLEDState: UInt8 {
    case idle           = 0x01
    case processing     = 0x02
    case success        = 0x03
    case failure        = 0x04
    case waitingForInput = 0x05
    case buttonPressed  = 0x06
    case rebootBootsel  = 0x07
}

/// No-op stub. Input now arrives via HID + HotkeyListener; this class is
/// reserved for future LED feedback over a CDC channel.
final class PadCommunicator {
    static let shared = PadCommunicator()

    func connect()    {}
    func disconnect() {}
    func sendState(_ state: PadLEDState) {}
}

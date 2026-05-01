import Foundation
import CoreGraphics

/// Generates a real RP2040 UF2 file containing the user's current button config.
///
/// The UF2 contains a single 256-byte block written to the last 4KB sector of
/// the W25Q16JV flash (0x101FF000 — 2 MB - 4 KB). The firmware reads this
/// region on boot and applies the per-button HID mappings.
///
/// Format reference:
/// - UF2 spec: <https://github.com/microsoft/uf2>
/// - RP2040 family ID: 0xe48bff56
///
/// Binary layout (must match `firmware/sudo_config.h`):
/// ```
/// offset  size  field
/// ------  ----  ---------------------------------
///   0      4    magic "SUDO" (little-endian 0x4F445553)
///   4      1    version (0x01)
///   5      1    mode (1=simple, 2=custom)
///   6      2    reserved
///   8    32×4   buttons[4] — physical order, bottom→top:
///                  0  uint8  actionMode (0=passthrough, 1=keyCombo, 2=mediaKey)
///                  1  uint8  reserved
///                  2  uint8  hidKeycode (USB HID usage)
///                  3  uint8  hidModifiers (bitmask: 1=ctrl 2=shift 4=alt 8=gui)
///                  4  28×u8  name (UTF-8, null-padded)
/// 136    120    padding (zero)
/// total: 256 bytes
/// ```
enum SudoConfigUF2 {

    static let configFlashAddress: UInt32 = 0x101F_F000
    static let rp2040FamilyID: UInt32 = 0xe48b_ff56
    static let configMagic: UInt32 = 0x4F44_5553  // "SUDO" little-endian
    static let configVersion: UInt8 = 0x01
    static let configPayloadSize = 256

    // MARK: - Public API

    /// Build a UF2 file from a SudoSettings snapshot.
    /// Returns the raw UF2 bytes (one 512-byte block).
    static func generate(from settings: SudoSettings) throws -> Data {
        let payload = buildConfigPayload(settings: settings)
        precondition(payload.count == configPayloadSize)
        return wrapUF2Block(payload: payload, targetAddress: configFlashAddress)
    }

    /// Convenience: write the generated UF2 to a temp file. Returns the URL.
    static func writeTemp(from settings: SudoSettings) throws -> URL {
        let data = try generate(from: settings)
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("sudo-config-\(Int(Date().timeIntervalSince1970)).uf2")
        try data.write(to: url)
        return url
    }

    // MARK: - Combined firmware + config

    /// Build a single UF2 file containing the base firmware followed by the
    /// user's current config block. Use this when flashing a blank RP2040 —
    /// a config-only UF2 leaves the chip with no executable code at
    /// 0x10000000 and the device boots into BOOTSEL forever.
    ///
    /// The base firmware UF2 is parsed block-by-block. Every block's
    /// `total_blocks` field is rewritten to (firmwareBlocks + 1) so the
    /// bootloader's progress accounting stays consistent.
    static func combineWithFirmware(firmwareData: Data, settings: SudoSettings) throws -> Data {
        guard firmwareData.count > 0, firmwareData.count % 512 == 0 else {
            throw FlashError.invalidFirmware("firmware UF2 must be a non-empty multiple of 512 bytes (got \(firmwareData.count))")
        }
        let firmwareBlocks = firmwareData.count / 512

        // Validate every block: magic + RP2040 family.
        for i in 0..<firmwareBlocks {
            let off = i * 512
            let m0 = readU32LE(firmwareData, offset: off)
            let m1 = readU32LE(firmwareData, offset: off + 4)
            let mEnd = readU32LE(firmwareData, offset: off + 508)
            let family = readU32LE(firmwareData, offset: off + 28)
            guard m0 == uf2MagicStart0, m1 == uf2MagicStart1, mEnd == uf2MagicEnd else {
                throw FlashError.invalidFirmware("block \(i): UF2 magic mismatch")
            }
            guard family == rp2040FamilyID else {
                throw FlashError.invalidFirmware("block \(i): not an RP2040 UF2 (family 0x\(String(family, radix: 16)))")
            }
        }

        let totalBlocks = UInt32(firmwareBlocks + 1)

        // Rewrite total_blocks (offset 24) in every firmware block. This is
        // informational for the bootloader but lying about it can confuse
        // some host-side tools.
        var combined = Data(firmwareData)
        for i in 0..<firmwareBlocks {
            let off = i * 512 + 24
            combined[off]     = UInt8(truncatingIfNeeded: totalBlocks)
            combined[off + 1] = UInt8(truncatingIfNeeded: totalBlocks >> 8)
            combined[off + 2] = UInt8(truncatingIfNeeded: totalBlocks >> 16)
            combined[off + 3] = UInt8(truncatingIfNeeded: totalBlocks >> 24)
        }

        // Append the config block as block #firmwareBlocks of totalBlocks.
        let configPayload = buildConfigPayload(settings: settings)
        let configBlock = wrapUF2Block(payload: configPayload,
                                       targetAddress: configFlashAddress,
                                       blockNumber: UInt32(firmwareBlocks),
                                       totalBlocks: totalBlocks)
        combined.append(configBlock)
        return combined
    }

    /// Locate the bundled base firmware UF2.
    /// Search order: app bundle resources → ~/Library/Application Support/Sudo/Firmware/sudo-firmware.uf2
    static func locateBaseFirmware() -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "sudo-firmware", withExtension: "uf2") {
            return bundleURL
        }
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sudo/Firmware")
        let candidate = supportDir.appendingPathComponent("sudo-firmware.uf2")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    enum FlashError: Error, LocalizedError {
        case invalidFirmware(String)
        case firmwareMissing

        var errorDescription: String? {
            switch self {
            case .invalidFirmware(let msg): return "invalid firmware: \(msg)"
            case .firmwareMissing: return "sudo-firmware.uf2 not bundled — drop it into ~/Library/Application Support/Sudo/Firmware/"
            }
        }
    }

    // MARK: - Config payload

    static func buildConfigPayload(settings: SudoSettings) -> Data {
        var data = Data(capacity: configPayloadSize)

        // magic (4)
        appendUInt32LE(&data, configMagic)

        // version (1) + mode (1) + reserved (2)
        data.append(configVersion)
        let modeByte: UInt8 = {
            switch settings.appMode {
            case .simple:  return 1
            case .custom:  return 2
            case .dynamic: return 2  // dynamic still flashes the current per-button config
            }
        }()
        data.append(modeByte)
        data.append(0)
        data.append(0)

        // buttons in physical order (bottom → top): approve, action3, reject, action4
        for action in PadAction.physicalOrder {
            data.append(buildButtonRecord(action: action, settings: settings))
        }

        // pad to 256
        let pad = configPayloadSize - data.count
        if pad > 0 {
            data.append(Data(repeating: 0, count: pad))
        }
        return data
    }

    private static func buildButtonRecord(action: PadAction, settings: SudoSettings) -> Data {
        var rec = Data(capacity: 32)

        let mode = settings.actionMode(for: action)
        let modeByte: UInt8 = {
            switch mode {
            case .keyCombo: return 1
            case .mediaKey: return 2
            case .aiSearch: return 0  // passthrough — firmware sends F-key so the app can handle it
            }
        }()
        rec.append(modeByte)
        rec.append(0)  // reserved

        let combo = settings.keyCombo(for: action)
        let (keycode, modifiers) = hidMapping(for: action, mode: mode, combo: combo)
        rec.append(keycode)
        rec.append(modifiers)

        // name: 28 bytes, null-padded UTF-8
        let name = settings.displayName(for: action)
        let nameBytes = Array(name.utf8.prefix(27))
        rec.append(contentsOf: nameBytes)
        rec.append(Data(repeating: 0, count: 28 - nameBytes.count))

        precondition(rec.count == 32)
        return rec
    }

    /// Resolve the HID keycode + modifier byte the firmware should send.
    private static func hidMapping(for action: PadAction, mode: ActionMode, combo: ButtonPreset.KeyCombo?) -> (UInt8, UInt8) {
        switch mode {
        case .aiSearch:
            // Firmware sends the original F-key so the macOS app can process it.
            return (fKeyHID(action: action), hidModCtrlShift)
        case .keyCombo:
            guard let kc = combo else { return (0, 0) }
            return (macOSKeyCodeToHID(kc.keyCode), hidModifiers(from: kc.modifiers))
        case .mediaKey:
            // Firmware looks up media key by keycode value (using consumer-control HID page).
            // We pass the macOS NX_KEYTYPE through and let firmware translate.
            guard let kc = combo else { return (0, 0) }
            return (UInt8(truncatingIfNeeded: kc.keyCode), 0)
        }
    }

    private static func fKeyHID(action: PadAction) -> UInt8 {
        switch action {
        case .approve: return 0x68  // F13
        case .reject:  return 0x69  // F14
        case .action3: return 0x6A  // F15
        case .action4: return 0x6B  // F16
        }
    }

    private static let hidModCtrlShift: UInt8 = 0x01 | 0x02  // ctrl+shift

    static func hidModifiers(from flags: CGEventFlags) -> UInt8 {
        var mods: UInt8 = 0
        if flags.contains(.maskControl)   { mods |= 0x01 }
        if flags.contains(.maskShift)     { mods |= 0x02 }
        if flags.contains(.maskAlternate) { mods |= 0x04 }
        if flags.contains(.maskCommand)   { mods |= 0x08 }  // GUI / cmd
        return mods
    }

    /// Map macOS virtual keycode → USB HID usage code (keyboard page).
    /// Covers the keys used in built-in presets; unknown codes return 0.
    static func macOSKeyCodeToHID(_ kc: UInt16) -> UInt8 {
        switch kc {
        case 0:   return 0x04  // a
        case 1:   return 0x16  // s
        case 2:   return 0x07  // d
        case 3:   return 0x09  // f
        case 4:   return 0x0B  // h
        case 5:   return 0x0A  // g
        case 6:   return 0x1D  // z
        case 7:   return 0x1B  // x
        case 8:   return 0x06  // c
        case 9:   return 0x19  // v
        case 11:  return 0x05  // b
        case 12:  return 0x14  // q
        case 13:  return 0x1A  // w
        case 14:  return 0x08  // e
        case 15:  return 0x15  // r
        case 16:  return 0x1C  // y
        case 17:  return 0x17  // t
        case 18:  return 0x1E  // 1
        case 19:  return 0x1F  // 2
        case 20:  return 0x20  // 3
        case 21:  return 0x21  // 4
        case 22:  return 0x23  // 6
        case 23:  return 0x22  // 5
        case 24:  return 0x2E  // =
        case 25:  return 0x26  // 9
        case 26:  return 0x24  // 7
        case 27:  return 0x2D  // -
        case 28:  return 0x25  // 8
        case 29:  return 0x27  // 0
        case 30:  return 0x30  // ]
        case 31:  return 0x12  // o
        case 32:  return 0x18  // u
        case 33:  return 0x2F  // [
        case 34:  return 0x0C  // i
        case 35:  return 0x13  // p
        case 37:  return 0x0F  // l
        case 38:  return 0x0D  // j
        case 40:  return 0x0E  // k
        case 41:  return 0x33  // ;
        case 42:  return 0x31  // \
        case 43:  return 0x36  // ,
        case 44:  return 0x38  // /
        case 46:  return 0x10  // m
        case 47:  return 0x37  // .
        case 49:  return 0x2C  // space
        case 53:  return 0x29  // escape
        case 36:  return 0x28  // return
        case 51:  return 0x2A  // delete (backspace)
        case 105: return 0x68  // F13
        case 106: return 0x6B  // F16
        case 107: return 0x69  // F14
        case 113: return 0x6A  // F15
        case 122: return 0x3A  // F1
        case 97:  return 0x3F  // F6
        default:  return 0
        }
    }

    // MARK: - UF2 wrapper

    /// UF2 magic / format constants.
    static let uf2MagicStart0: UInt32 = 0x0A32_4655
    static let uf2MagicStart1: UInt32 = 0x9E5D_5157
    static let uf2MagicEnd: UInt32    = 0x0AB1_6F30
    /// flag: familyID present (0x00002000)
    static let uf2FlagFamilyID: UInt32 = 0x0000_2000

    static func wrapUF2Block(payload: Data, targetAddress: UInt32, blockNumber: UInt32 = 0, totalBlocks: UInt32 = 1) -> Data {
        precondition(payload.count <= 476, "UF2 block payload max 476 bytes")
        var block = Data(capacity: 512)
        appendUInt32LE(&block, uf2MagicStart0)
        appendUInt32LE(&block, uf2MagicStart1)
        appendUInt32LE(&block, uf2FlagFamilyID)
        appendUInt32LE(&block, targetAddress)
        appendUInt32LE(&block, UInt32(payload.count))
        appendUInt32LE(&block, blockNumber)
        appendUInt32LE(&block, totalBlocks)
        appendUInt32LE(&block, rp2040FamilyID)
        block.append(payload)
        // pad data area to 476
        let dataPad = 476 - payload.count
        if dataPad > 0 {
            block.append(Data(repeating: 0, count: dataPad))
        }
        appendUInt32LE(&block, uf2MagicEnd)
        precondition(block.count == 512)
        return block
    }

    // MARK: - Byte helpers

    private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    static func readU32LE(_ data: Data, offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i])
            | (UInt32(data[i + 1]) << 8)
            | (UInt32(data[i + 2]) << 16)
            | (UInt32(data[i + 3]) << 24)
    }
}

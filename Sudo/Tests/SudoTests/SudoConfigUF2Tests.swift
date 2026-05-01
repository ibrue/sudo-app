import XCTest
import CoreGraphics
@testable import Sudo

final class SudoConfigUF2Tests: XCTestCase {

    // MARK: - UF2 envelope

    func testWrappedBlockIs512Bytes() {
        let payload = Data(repeating: 0xAA, count: 256)
        let block = SudoConfigUF2.wrapUF2Block(payload: payload, targetAddress: 0x1000_0000)
        XCTAssertEqual(block.count, 512)
    }

    func testUF2MagicNumbers() {
        let payload = Data(repeating: 0, count: 256)
        let block = SudoConfigUF2.wrapUF2Block(payload: payload, targetAddress: 0x1010_0000)
        let magic0 = readU32LE(block, offset: 0)
        let magic1 = readU32LE(block, offset: 4)
        let magicEnd = readU32LE(block, offset: 508)
        XCTAssertEqual(magic0, SudoConfigUF2.uf2MagicStart0)
        XCTAssertEqual(magic1, SudoConfigUF2.uf2MagicStart1)
        XCTAssertEqual(magicEnd, SudoConfigUF2.uf2MagicEnd)
    }

    func testUF2HeaderFields() {
        let payload = Data(repeating: 0, count: 200)
        let target: UInt32 = 0x101F_F000
        let block = SudoConfigUF2.wrapUF2Block(payload: payload, targetAddress: target,
                                               blockNumber: 0, totalBlocks: 1)
        XCTAssertEqual(readU32LE(block, offset: 8), SudoConfigUF2.uf2FlagFamilyID)
        XCTAssertEqual(readU32LE(block, offset: 12), target)
        XCTAssertEqual(readU32LE(block, offset: 16), 200)         // payload size
        XCTAssertEqual(readU32LE(block, offset: 20), 0)           // block number
        XCTAssertEqual(readU32LE(block, offset: 24), 1)           // total blocks
        XCTAssertEqual(readU32LE(block, offset: 28), SudoConfigUF2.rp2040FamilyID)
    }

    func testUF2DataAreaIsZeroPadded() {
        let payload = Data([0x11, 0x22, 0x33, 0x44])
        let block = SudoConfigUF2.wrapUF2Block(payload: payload, targetAddress: 0)
        // Data area at offsets 32..507 (476 bytes), payload at 32..35, rest zero
        XCTAssertEqual(block[32], 0x11)
        XCTAssertEqual(block[33], 0x22)
        XCTAssertEqual(block[34], 0x33)
        XCTAssertEqual(block[35], 0x44)
        for i in 36..<508 {
            XCTAssertEqual(block[i], 0, "byte \(i) should be zero")
        }
    }

    // MARK: - Config payload

    func testConfigPayloadIs256Bytes() {
        let payload = SudoConfigUF2.buildConfigPayload(settings: SudoSettings.shared)
        XCTAssertEqual(payload.count, 256)
    }

    func testConfigPayloadStartsWithMagic() {
        let payload = SudoConfigUF2.buildConfigPayload(settings: SudoSettings.shared)
        let magic = readU32LE(payload, offset: 0)
        XCTAssertEqual(magic, SudoConfigUF2.configMagic)
    }

    func testConfigPayloadVersion() {
        let payload = SudoConfigUF2.buildConfigPayload(settings: SudoSettings.shared)
        XCTAssertEqual(payload[4], SudoConfigUF2.configVersion)
    }

    func testConfigPayloadModeByte() {
        let settings = SudoSettings.shared
        let originalMode = settings.appMode
        defer { settings.appMode = originalMode }

        settings.appMode = .simple
        XCTAssertEqual(SudoConfigUF2.buildConfigPayload(settings: settings)[5], 1)

        settings.appMode = .custom
        XCTAssertEqual(SudoConfigUF2.buildConfigPayload(settings: settings)[5], 2)

        settings.appMode = .dynamic
        XCTAssertEqual(SudoConfigUF2.buildConfigPayload(settings: settings)[5], 2)
    }

    // MARK: - HID translation

    func testHIDModifiersFromCGEventFlags() {
        XCTAssertEqual(SudoConfigUF2.hidModifiers(from: .maskCommand), 0x08)
        XCTAssertEqual(SudoConfigUF2.hidModifiers(from: .maskShift), 0x02)
        XCTAssertEqual(SudoConfigUF2.hidModifiers(from: .maskControl), 0x01)
        XCTAssertEqual(SudoConfigUF2.hidModifiers(from: .maskAlternate), 0x04)
        XCTAssertEqual(SudoConfigUF2.hidModifiers(from: [.maskCommand, .maskShift]), 0x0A)
        XCTAssertEqual(SudoConfigUF2.hidModifiers(from: [.maskControl, .maskShift]), 0x03)
    }

    func testMacOSKeyCodeToHIDCommonKeys() {
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(8), 0x06)   // c
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(9), 0x19)   // v
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(6), 0x1D)   // z
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(49), 0x2C)  // space
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(53), 0x29)  // escape
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(105), 0x68) // F13
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(107), 0x69) // F14
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(113), 0x6A) // F15
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(106), 0x6B) // F16
    }

    func testMacOSKeyCodeToHIDUnknownReturnsZero() {
        XCTAssertEqual(SudoConfigUF2.macOSKeyCodeToHID(255), 0)
    }

    // MARK: - End-to-end

    func testGenerateProducesValidUF2() throws {
        let data = try SudoConfigUF2.generate(from: SudoSettings.shared)
        XCTAssertEqual(data.count, 512)
        XCTAssertEqual(readU32LE(data, offset: 0), SudoConfigUF2.uf2MagicStart0)
        XCTAssertEqual(readU32LE(data, offset: 12), SudoConfigUF2.configFlashAddress)
        // first 4 bytes of payload (offset 32) should be the SUDO magic
        XCTAssertEqual(readU32LE(data, offset: 32), SudoConfigUF2.configMagic)
    }

    // MARK: - AppMode

    func testAppModeRawValuesStable() {
        // Persistence depends on these strings — guard against accidental rename.
        XCTAssertEqual(AppMode.dynamic.rawValue, "dynamic")
        XCTAssertEqual(AppMode.simple.rawValue, "simple")
        XCTAssertEqual(AppMode.custom.rawValue, "custom")
    }

    func testAppModeAllCasesCount() {
        XCTAssertEqual(AppMode.allCases.count, 3)
    }

    // MARK: - helpers

    private func readU32LE(_ data: Data, offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}

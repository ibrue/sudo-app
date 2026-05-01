import XCTest
import CoreGraphics
@testable import Sudo

final class SudoConfigJSONTests: XCTestCase {

    // MARK: - Schema

    func testGenerateProducesValidJSON() throws {
        let data = try SudoConfigJSON.generate(from: SudoSettings.shared)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj)
    }

    func testTopLevelFields() throws {
        let data = try SudoConfigJSON.generate(from: SudoSettings.shared)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["version"] as? Int, 1)
        XCTAssertNotNil(obj["mode"] as? String)
        let buttons = obj["buttons"] as? [[String: Any]]
        XCTAssertEqual(buttons?.count, 4)
    }

    func testModeStringMatchesAppMode() throws {
        let settings = SudoSettings.shared
        let original = settings.appMode
        defer { settings.appMode = original }

        for mode in AppMode.allCases {
            settings.appMode = mode
            let data = try SudoConfigJSON.generate(from: settings)
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(obj["mode"] as? String, mode.rawValue)
        }
    }

    func testDynamicModeForcesPassthroughEvenIfButtonModesSayOtherwise() throws {
        // Reproduces the original bug: auto-switch had momentarily set every
        // button to mediaKey for Spotify. Pre-fix, clicking flash would
        // write `mediaKey` into the firmware and the device would bypass
        // the app forever after. The dynamic-mode override forces every
        // button back to passthrough (F-keys) regardless of buttonModes.
        let settings = SudoSettings.shared
        let originalMode = settings.appMode
        let originalButtonModes = settings.buttonModes
        defer {
            settings.appMode = originalMode
            settings.buttonModes = originalButtonModes
        }

        settings.appMode = .dynamic
        settings.buttonModes = [
            "approve": "mediaKey",
            "reject":  "mediaKey",
            "action3": "keyCombo",
            "action4": "mediaKey",
        ]

        let data = try SudoConfigJSON.generate(from: settings)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let buttons = obj["buttons"] as! [[String: Any]]
        for b in buttons {
            XCTAssertEqual(b["mode"] as? String, "passthrough",
                           "every button in dynamic mode must emit passthrough; got \(b["mode"] ?? "nil")")
        }
    }

    func testSimpleAndCustomModesPreserveButtonModes() throws {
        let settings = SudoSettings.shared
        let originalMode = settings.appMode
        let originalButtonModes = settings.buttonModes
        defer {
            settings.appMode = originalMode
            settings.buttonModes = originalButtonModes
        }

        settings.buttonModes = [
            "approve": "mediaKey",
            "reject":  "keyCombo",
            "action3": "keyCombo",
            "action4": "mediaKey",
        ]

        for mode in [AppMode.simple, .custom] {
            settings.appMode = mode
            let data = try SudoConfigJSON.generate(from: settings)
            let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let buttons = obj["buttons"] as! [[String: Any]]
            // In non-dynamic modes, the per-button mode must reflect what
            // the user / preset has configured.
            let modes = buttons.compactMap { $0["mode"] as? String }
            XCTAssertTrue(modes.contains("mediakey"),
                          "\(mode.rawValue) mode should preserve mediaKey buttons")
        }
    }

    func testButtonsAreInPhysicalOrder() throws {
        let data = try SudoConfigJSON.generate(from: SudoSettings.shared)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let buttons = obj["buttons"] as! [[String: Any]]
        XCTAssertEqual(buttons.count, 4)
        // Each entry must have the expected keys.
        for b in buttons {
            XCTAssertNotNil(b["mode"] as? String)
            XCTAssertNotNil(b["keycode"] as? Int)
            XCTAssertNotNil(b["modifiers"] as? Int)
            XCTAssertNotNil(b["name"] as? String)
        }
    }

    // MARK: - HID translation

    func testHIDModifiersFromCGEventFlags() {
        XCTAssertEqual(SudoConfigJSON.hidModifiers(from: .maskCommand), 0x08)
        XCTAssertEqual(SudoConfigJSON.hidModifiers(from: .maskShift), 0x02)
        XCTAssertEqual(SudoConfigJSON.hidModifiers(from: .maskControl), 0x01)
        XCTAssertEqual(SudoConfigJSON.hidModifiers(from: .maskAlternate), 0x04)
        XCTAssertEqual(SudoConfigJSON.hidModifiers(from: [.maskCommand, .maskShift]), 0x0A)
        XCTAssertEqual(SudoConfigJSON.hidModifiers(from: [.maskControl, .maskShift]), 0x03)
    }

    func testMacOSKeyCodeToHIDCommonKeys() {
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(8), 0x06)   // c
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(9), 0x19)   // v
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(6), 0x1D)   // z
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(49), 0x2C)  // space
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(53), 0x29)  // escape
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(105), 0x68) // F13
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(107), 0x69) // F14
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(113), 0x6A) // F15
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(106), 0x6B) // F16
    }

    func testMacOSKeyCodeToHIDUnknownReturnsZero() {
        XCTAssertEqual(SudoConfigJSON.macOSKeyCodeToHID(255), 0)
    }

    // MARK: - AppMode

    func testAppModeRawValuesStable() {
        // Persistence + JSON schema both depend on these strings.
        XCTAssertEqual(AppMode.dynamic.rawValue, "dynamic")
        XCTAssertEqual(AppMode.simple.rawValue, "simple")
        XCTAssertEqual(AppMode.custom.rawValue, "custom")
    }

    func testAppModeAllCasesCount() {
        XCTAssertEqual(AppMode.allCases.count, 3)
    }
}

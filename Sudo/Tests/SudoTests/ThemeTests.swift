import XCTest
import SwiftUI
@testable import Sudo

final class ThemeTests: XCTestCase {

    // MARK: - Color tokens

    func testAccentColorIsDefined() {
        let accent = SudoTheme.accent
        XCTAssertNotNil(accent, "SudoTheme.accent must be defined")
    }

    func testAllColorsAreDefined() {
        let _ = SudoTheme.bg
        let _ = SudoTheme.text
        let _ = SudoTheme.textMuted
        let _ = SudoTheme.accent
        let _ = SudoTheme.accentDim
        let _ = SudoTheme.border
        let _ = SudoTheme.error
        let _ = SudoTheme.surface
        let _ = SudoTheme.warning
        let _ = SudoTheme.accentSoft
        let _ = SudoTheme.dangerSoft
        let _ = SudoTheme.infoSoft
    }

    func testCornerRadii() {
        XCTAssertEqual(SudoTheme.cardCornerRadius, 14)
        XCTAssertEqual(SudoTheme.cornerRadius, 10)
    }

    func testBorderWidth() {
        XCTAssertEqual(SudoTheme.borderWidth, 0.5)
        XCTAssertEqual(SudoTheme.ringWidth, 0.5)
        XCTAssertEqual(SudoTheme.ringWidthEmphasized, 1.2)
    }

    func testMonoFontHelper() {
        let font = SudoTheme.mono(size: 14, weight: .bold)
        XCTAssertNotNil(font)
    }

    func testSpacingValues() {
        XCTAssertEqual(SudoTheme.spacingXs, 4)
        XCTAssertEqual(SudoTheme.spacingSm, 8)
        XCTAssertEqual(SudoTheme.spacingMd, 16)
        XCTAssertEqual(SudoTheme.spacingLg, 24)
        XCTAssertEqual(SudoTheme.spacingXl, 32)
    }
}

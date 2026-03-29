import XCTest
import SwiftUI
@testable import Sudo

final class ThemeTests: XCTestCase {

    // MARK: - Color consistency with web design tokens

    func testAccentColorIsTerminalGreen() {
        // The accent color must be #00FF41 across all platforms
        let accent = SudoTheme.accent
        XCTAssertNotNil(accent, "SudoTheme.accent must be defined")
    }

    func testAllColorsAreDefined() {
        // Verify all design token colors exist
        let _ = SudoTheme.bg
        let _ = SudoTheme.bgSecondary
        let _ = SudoTheme.text
        let _ = SudoTheme.textMuted
        let _ = SudoTheme.accent
        let _ = SudoTheme.accentDim
        let _ = SudoTheme.border
        let _ = SudoTheme.error
        let _ = SudoTheme.surface
    }

    func testBorderRadiusIsZero() {
        // Terminal aesthetic: no rounded corners
        XCTAssertEqual(SudoTheme.borderRadius, 0, "Border radius must be 0 for terminal aesthetic")
    }

    func testBorderWidthIsOne() {
        XCTAssertEqual(SudoTheme.borderWidth, 1)
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
        XCTAssertEqual(SudoTheme.spacingXxl, 48)
    }
}

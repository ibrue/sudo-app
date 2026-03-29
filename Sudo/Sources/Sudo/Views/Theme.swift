// AUTO-GENERATED from tokens.json — do not edit directly
import SwiftUI

enum SudoTheme {
    // MARK: - Colors
    static let bg = Color(hex: 0x0A0A0A)
    static let bgSecondary = Color(hex: 0x111111)
    static let text = Color(hex: 0xF0F0F0)
    static let textMuted = Color(hex: 0x666666)
    static let accent = Color(hex: 0x00FF41)
    static let accentDim = Color(red: 0/255.0, green: 255/255.0, blue: 65/255.0, opacity: 32/255.0)
    static let border = Color(hex: 0x1E1E1E)
    static let error = Color(hex: 0xFF3333)
    static let surface = Color(hex: 0x333333)

    // MARK: - Typography
    static let monoFont: Font = .system(.body, design: .monospaced)
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Borders
    static let borderRadius: CGFloat = 0
    static let borderWidth: CGFloat = 1

    // MARK: - Spacing
    static let spacingXs: CGFloat = 4
    static let spacingSm: CGFloat = 8
    static let spacingMd: CGFloat = 16
    static let spacingLg: CGFloat = 24
    static let spacingXl: CGFloat = 32
    static let spacingXxl: CGFloat = 48
}

import SwiftUI
import AppKit

enum SudoTheme {
    // MARK: - Colors (macOS native, glass-friendly)
    static let bg = Color.clear
    static let text = Color.primary
    static let textMuted = Color.secondary
    static let accent = Color(hex: 0x34C759)
    static let accentDim = Color(hex: 0x34C759).opacity(0.12)
    static let border = Color(nsColor: .separatorColor)
    static let error = Color(nsColor: .systemRed)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let warning = Color(nsColor: .systemYellow)

    // Glow variants
    static let accentGlow = Color(hex: 0x34C759).opacity(0.08)
    static let errorGlow = Color(nsColor: .systemRed).opacity(0.08)
    static let hoverBg = Color.white.opacity(0.06)

    // MARK: - Typography
    /// SF Pro for labels, headers, UI chrome
    static func label(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Monospace for values, code, data
    static let monoFont: Font = .system(.body, design: .monospaced)
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Layout
    static let cornerRadius: CGFloat = 10
    static let pillRadius: CGFloat = 14
    static let borderWidth: CGFloat = 0.5
    static let spacingXs: CGFloat = 4
    static let spacingSm: CGFloat = 8
    static let spacingMd: CGFloat = 16
    static let spacingLg: CGFloat = 24
    static let spacingXl: CGFloat = 32

    // MARK: - Animation
    static let flashDuration: Double = 0.15
    static let glowDuration: Double = 0.8
}

// MARK: - View helpers

extension View {
    /// Glass root background (.ultraThinMaterial)
    func sudoBackground() -> some View {
        self.background(.ultraThinMaterial)
    }
    /// Glass card surface (.thinMaterial with rounded corners)
    func glassCard(cornerRadius: CGFloat = SudoTheme.cornerRadius) -> some View {
        self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

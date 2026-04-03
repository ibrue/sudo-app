import SwiftUI
import AppKit

/// App theme selection
enum AppTheme: String, CaseIterable {
    case terminal   // dark hacker aesthetic
    case macos      // native glass + system colors
}

enum SudoTheme {
    // MARK: - Theme accessor
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "terminal") ?? .terminal
    }

    private static var isTerminal: Bool { current == .terminal }

    // MARK: - Colors
    static var bg: Color { isTerminal ? Color(hex: 0x0A0A0A) : .clear }
    static var bgSecondary: Color { isTerminal ? Color(hex: 0x111111) : Color(nsColor: .controlBackgroundColor) }
    static var text: Color { isTerminal ? Color(hex: 0xF0F0F0) : .primary }
    static var textMuted: Color { isTerminal ? Color(hex: 0x666666) : .secondary }
    static var accent: Color { isTerminal ? Color(hex: 0x00FF41) : Color(hex: 0x34C759) }
    static var accentDim: Color { isTerminal
        ? Color(red: 0/255.0, green: 255/255.0, blue: 65/255.0, opacity: 32/255.0)
        : Color(hex: 0x34C759).opacity(0.12)
    }
    static var border: Color { isTerminal ? Color(hex: 0x1E1E1E) : Color(nsColor: .separatorColor) }
    static var error: Color { isTerminal ? Color(hex: 0xFF3333) : Color(nsColor: .systemRed) }
    static var surface: Color { isTerminal ? Color(hex: 0x333333) : Color(nsColor: .controlBackgroundColor) }
    static var terminalBg: Color { isTerminal ? Color(hex: 0x050505) : Color(nsColor: .textBackgroundColor) }
    static var warning: Color { isTerminal ? Color(hex: 0xD4B85C) : Color(nsColor: .systemYellow) }

    // Glow variants (for animations)
    static var accentGlow: Color { isTerminal
        ? Color(red: 0/255.0, green: 255/255.0, blue: 65/255.0, opacity: 0.15)
        : Color(hex: 0x34C759).opacity(0.08)
    }
    static var errorGlow: Color { isTerminal
        ? Color(red: 255/255.0, green: 51/255.0, blue: 51/255.0, opacity: 0.15)
        : Color(nsColor: .systemRed).opacity(0.08)
    }
    static var hoverBg: Color { isTerminal ? Color(hex: 0x1A1A1A) : Color(nsColor: .controlBackgroundColor).opacity(0.5) }

    // MARK: - Animation
    static let flashDuration: Double = 0.15
    static let glowDuration: Double = 0.8

    // MARK: - Typography
    static let monoFont: Font = .system(.body, design: .monospaced)
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Borders
    static var cornerRadius: CGFloat { isTerminal ? 0 : 4 }
    static let borderWidth: CGFloat = 1

    // MARK: - Spacing
    static let spacingXs: CGFloat = 4
    static let spacingSm: CGFloat = 8
    static let spacingMd: CGFloat = 16
    static let spacingLg: CGFloat = 24
    static let spacingXl: CGFloat = 32
    static let spacingXxl: CGFloat = 48

    // MARK: - Theme-specific
    static var showScanLines: Bool { isTerminal }
}

// MARK: - View helpers

extension View {
    /// Apply themed background: solid dark for terminal, thinMaterial glass for macOS
    @ViewBuilder
    func sudoBackground() -> some View {
        if SudoTheme.current == .macos {
            self.background(.thinMaterial)
        } else {
            self.background(SudoTheme.bg)
        }
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

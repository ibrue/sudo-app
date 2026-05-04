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

    // Glow + hover variants
    static let accentGlow = Color(hex: 0x34C759).opacity(0.08)
    static let errorGlow = Color(nsColor: .systemRed).opacity(0.08)
    static let hoverBg = Color.white.opacity(0.06)

    // Card surfaces — semantic, used by the redesigned popover + panels.
    // These read better than ad-hoc opacities on `.thinMaterial` because
    // they layer over the existing material instead of competing with it.
    static let cardSurface = Color.primary.opacity(0.04)
    static let cardSurfaceHover = Color.primary.opacity(0.07)
    static let cardSurfaceActive = Color.primary.opacity(0.10)

    /// Background for code/terminal/log surfaces. The macOS-native
    /// "text background" color picks up the system's editor surface,
    /// which is what reads best behind monospaced log output.
    static let codeBackground = Color(nsColor: .textBackgroundColor)

    // MARK: - Typography ramp
    //
    // Two lanes:
    //   • System fonts for body / labels / sections — native macOS feel.
    //   • Mono lane for brand callouts and code-like content (the
    //     `[sudo]` mark, version strings, hotkeys, debug logs, API
    //     keys, terminal output, action-log timestamps).
    //
    // `mono(size:weight:)` is preserved so the rollout is incremental;
    // new code should reach for the semantic helpers first.

    static let title = Font.system(size: 22, weight: .semibold)
    static let heading = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasized = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11)
    static let captionMuted = Font.system(size: 11, weight: .regular)

    /// Brand mark — `[sudo]` and similar bracketed callouts.
    static let brand = Font.system(size: 13, weight: .semibold, design: .monospaced)

    /// Code-like content (hotkeys, API keys, debug logs, terminal output).
    static func code(size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Legacy mono helper — kept so existing call sites compile while
    /// they're migrated to the semantic ramp above.
    static let monoFont: Font = .system(.body, design: .monospaced)
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Layout v2
    //
    // Bigger than before. The popover used to be 300/320pt with ~36pt
    // button cards and 10pt corners; macOS conventions want more
    // breathing room.

    static let popoverWidth: CGFloat = 360       // was 300/320
    static let cardCornerRadius: CGFloat = 14    // was 10
    static let cornerRadius: CGFloat = 10        // legacy alias for older callers
    static let pillRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14         // inside-card padding
    static let buttonCardHeight: CGFloat = 52    // was ~36
    static let sectionSpacing: CGFloat = 12

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
    func glassCard(cornerRadius: CGFloat = SudoTheme.cardCornerRadius) -> some View {
        self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Color hex extensions

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    /// Counterpart to `Color(hex:)` for use inside dark/light dynamic
    /// providers — `NSColor(name:dynamicProvider:)` returns NSColor and
    /// SwiftUI bridges it back to `Color(nsColor:)`.
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

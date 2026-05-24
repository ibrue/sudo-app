import SwiftUI
import AppKit

enum SudoTheme {
    // MARK: - Colors (macOS native, glass-friendly)
    static let bg = Color.clear
    static let text = Color.primary
    static let textMuted = Color.secondary
    /// Brand green — `[ ok ]`, status dots, success states, connected
    /// indicator. Use this for *status semantics*. For primary user
    /// actions (save / done / open settings), use `Color.accentColor`
    /// instead so users who've picked a different system accent see
    /// it honoured. The Asset Catalog default still ships green.
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

    /// One source of "accent-tinted background" — replaces the
    /// ad-hoc .accent.opacity(0.06 / 0.10 / 0.12) used across panels.
    static let accentSoft = Color(hex: 0x34C759).opacity(0.10)
    /// Danger-tinted background — InlineBanner(.danger), warning banners.
    static let dangerSoft = Color(nsColor: .systemRed).opacity(0.10)
    /// Info-tinted background — MCP overlay, neutral info banners.
    static let infoSoft = Color(nsColor: .controlAccentColor).opacity(0.10)

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

    /// Section label — uppercase, +0.5 tracking, 11pt semibold.
    /// Pair with `SectionLabel("...")` which applies the casing + tracking.
    /// Replaces the seven `private func sectionHeader(_:)` helpers that
    /// were scattered across settings panels.
    static let sectionTitle = Font.system(size: 11, weight: .semibold)

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

    // Popover-scoped paddings (separate from settings-window paddings).
    static let popoverHPadding: CGFloat = 16
    static let popoverVPadding: CGFloat = 12
    static let popoverSectionGap: CGFloat = 8

    // Settings-window paddings.
    static let panelHPadding: CGFloat = 28
    static let panelVPadding: CGFloat = 20

    /// Single label column width for form-style rows in custom panels.
    /// Replaces 50pt (ButtonsPanel), 60pt (MacrosPanel), 80pt
    /// (AutoApprovePanel) — those ragged left edges were jarring when
    /// switching between panels.
    static let formLabelWidth: CGFloat = 76

    /// Default height for the developer panel's three code scrollers
    /// (pad console, debug, build terminal). Was duplicated as a magic
    /// `260` in three different spots.
    static let codeWindowHeight: CGFloat = 260

    static let borderWidth: CGFloat = 0.5
    /// Ring around a card / button card / editor in its at-rest state.
    static let ringWidth: CGFloat = 0.5
    /// Ring when the card is "the active one" (last-touched button card,
    /// editor being edited). Emphasis comes from line width, not from
    /// dulling the tint color via opacity.
    static let ringWidthEmphasized: CGFloat = 1.2

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
    /// Solid-tint card surface — counterpart to glassCard when you want
    /// the cardSurface / accentSoft / dangerSoft fill rather than the
    /// material blur. Pairs naturally with the new SettingsCard.
    func sudoCard(
        _ surface: Color = SudoTheme.cardSurface,
        cornerRadius: CGFloat = SudoTheme.cardCornerRadius,
        ringColor: Color? = nil,
        ringWidth: CGFloat = SudoTheme.ringWidth
    ) -> some View {
        self
            .background(surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                if let ring = ringColor {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(ring, lineWidth: ringWidth)
                }
            }
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

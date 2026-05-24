import SwiftUI

/// Small inline action button used in editor rows, card headers,
/// and footer affordances. Replaces the scattered triplets of
/// `Button("edit").font(.caption).foregroundColor(...).buttonStyle(.plain)`
/// that drifted out of sync across panels.
///
/// Variants:
/// - `.accent`  → primary action (save / done / add). Tinted with
///   the *system* `Color.accentColor` so users who picked a non-green
///   accent in System Settings → Appearance see it honoured. The
///   brand green is still the default via the Asset Catalog.
/// - `.muted`   → secondary / cancel / reset.
/// - `.danger`  → destructive (delete / remove / quit).
struct ActionPillButton: View {
    enum Variant {
        case accent
        case muted
        case danger
    }

    let title: String
    let systemImage: String?
    let variant: Variant
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        variant: Variant = .muted,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
            }
            .font(SudoTheme.caption)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch variant {
        case .accent: return Color.accentColor
        case .muted:  return .secondary
        case .danger: return Color(nsColor: .systemRed)
        }
    }

    private var background: Color {
        switch variant {
        case .accent: return Color.accentColor.opacity(0.12)
        case .muted:  return Color.primary.opacity(0.06)
        case .danger: return Color(nsColor: .systemRed).opacity(0.10)
        }
    }
}

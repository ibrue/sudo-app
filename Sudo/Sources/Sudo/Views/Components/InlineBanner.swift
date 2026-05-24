import SwiftUI

/// Banner used for permission alerts, MCP approval prompts, and
/// warning callouts. Replaces the bespoke `permissionBanner` block
/// in MainView and the `warningBanner` in AutoApprovePanel — both
/// were the same shape (icon + title + body + actions) with
/// drift on padding, button arrangement, and tinting.
///
/// Variants control the tint:
/// - `.danger`   → systemRed soft fill, red triangle icon
/// - `.warning`  → systemYellow soft fill, yellow exclamation icon
/// - `.info`     → accent soft fill, info circle icon
///
/// Actions are passed in a vertical stack via `@ViewBuilder actions:`
/// — three crammed buttons in a horizontal row was the original sin.
struct InlineBanner<Actions: View>: View {
    enum Variant {
        case danger
        case warning
        case info
    }

    let variant: Variant
    let title: String
    let message: String?
    let actions: Actions

    init(
        _ variant: Variant,
        title: String,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.variant = variant
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(SudoTheme.bodyEmphasized)
                if let message {
                    Text(message)
                        .font(SudoTheme.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    actions
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fillColor, in: RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius))
    }

    private var icon: String {
        switch variant {
        case .danger:  return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch variant {
        case .danger:  return Color(nsColor: .systemRed)
        case .warning: return Color(nsColor: .systemYellow)
        case .info:    return Color.accentColor
        }
    }

    private var fillColor: Color {
        switch variant {
        case .danger:  return SudoTheme.dangerSoft
        case .warning: return Color(nsColor: .systemYellow).opacity(0.10)
        case .info:    return SudoTheme.accentSoft
        }
    }
}

// Convenience overload for banners with no actions.
extension InlineBanner where Actions == EmptyView {
    init(_ variant: Variant, title: String, message: String? = nil) {
        self.init(variant, title: title, message: message, actions: { EmptyView() })
    }
}

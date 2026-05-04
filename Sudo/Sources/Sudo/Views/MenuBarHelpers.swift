import SwiftUI

/// Shared helper views used across the menu bar UI.

// MARK: - Divider

struct SudoDivider: View {
    var body: some View {
        Rectangle()
            .fill(SudoTheme.border.opacity(0.3))
            .frame(height: 0.5)
    }
}

// MARK: - Section Header

/// Collapsible section header — accent text when expanded, rounded hover.
/// Used in places that still need a disclosure affordance (the popover
/// no longer collapses sections, but EditPreset and a few panels do).
struct SectionHeader: View {
    let title: String
    let count: Int?
    let badge: String?
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    init(_ title: String, isExpanded: Binding<Bool>, count: Int? = nil, badge: String? = nil) {
        self.title = title
        self.count = count
        self.badge = badge
        self._isExpanded = isExpanded
    }

    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Text(title)
                    .font(isExpanded ? SudoTheme.heading : SudoTheme.body)
                    .foregroundColor(isExpanded ? SudoTheme.accent : (isHovered ? SudoTheme.text : SudoTheme.textMuted))
                if let count = count {
                    Text("(\(count))")
                        .font(SudoTheme.caption)
                        .foregroundColor(SudoTheme.textMuted)
                }
                if let badge = badge {
                    Text(badge)
                        .font(SudoTheme.caption)
                        .foregroundColor(SudoTheme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(SudoTheme.accentDim))
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SudoTheme.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovered ? SudoTheme.hoverBg : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title) section")
        .accessibilityHint(isExpanded ? "collapse" : "expand")
    }
}

// MARK: - Setting Toggle

/// Native-feeling checkbox: SF Symbol filled square + system body label.
/// The legacy `[x]/[ ]` mono glyphs got dropped in the macOS pivot —
/// kept the brand brackets for the `[sudo]` mark and footers, but
/// toggles now use the system control vocabulary so the popover matches
/// the rest of macOS.
struct SettingToggle: View {
    let label: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } }) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(isOn ? SudoTheme.accent : SudoTheme.textMuted)
                Text(label)
                    .font(SudoTheme.body)
                    .foregroundColor(isHovered ? SudoTheme.text : SudoTheme.textMuted)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

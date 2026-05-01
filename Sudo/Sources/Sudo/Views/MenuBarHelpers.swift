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

/// Collapsible section header — accent text when expanded, rounded hover
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
            HStack {
                Text(title)
                    .font(SudoTheme.mono(size: 11, weight: isExpanded ? .semibold : .regular))
                    .foregroundColor(isExpanded ? SudoTheme.accent : (isHovered ? SudoTheme.text : SudoTheme.textMuted))
                if let count = count {
                    Text("(\(count))")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.textMuted)
                }
                if let badge = badge {
                    Text(badge)
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.accent)
                }
                Spacer()
                Text(isExpanded ? "▾" : "▸")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovered ? SudoTheme.hoverBg : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title) section")
        .accessibilityHint(isExpanded ? "collapse" : "expand")
    }
}

// MARK: - Setting Toggle

/// Checkbox toggle: `[x]` mono + SF Pro label
struct SettingToggle: View {
    let label: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } }) {
            HStack {
                Text(isOn ? "[x]" : "[ ]")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.accent)
                Text(label)
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(isHovered ? SudoTheme.text : SudoTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}


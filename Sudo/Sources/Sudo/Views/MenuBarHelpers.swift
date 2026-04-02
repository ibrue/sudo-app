import SwiftUI

/// Shared helper views used across the menu bar UI.

extension View {
    /// Standard 1px divider line
    func sudoDivider() -> some View {
        Rectangle()
            .fill(SudoTheme.border)
            .frame(height: 1)
    }
}

struct SudoDivider: View {
    var body: some View {
        Rectangle()
            .fill(SudoTheme.border)
            .frame(height: 1)
    }
}

/// Collapsible section header with toggle arrow
struct SectionHeader: View {
    let title: String
    let count: Int?
    let badge: String?
    @Binding var isExpanded: Bool

    init(_ title: String, isExpanded: Binding<Bool>, count: Int? = nil, badge: String? = nil) {
        self.title = title
        self.count = count
        self.badge = badge
        self._isExpanded = isExpanded
    }

    var body: some View {
        Button(action: { isExpanded.toggle() }) {
            HStack {
                Text("> \(title)")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.textMuted)
                if let count = count {
                    Text("(\(count))")
                        .font(SudoTheme.mono(size: 9))
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
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) section")
        .accessibilityHint(isExpanded ? "collapse" : "expand")
    }
}

/// Setting toggle: `[x] label` or `[ ] label`
struct SettingToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack {
                Text(isOn ? "[x]" : "[ ]")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.accent)
                Text(label)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// Interactive device button row
struct DeviceButton: View {
    let action: PadAction
    let mode: ActionMode
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: action.buttonColorHex))
                    .frame(width: 3)
                HStack {
                    Text("\(action.buttonNumber)")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.textMuted)
                        .frame(width: 14, alignment: .leading)
                    Text(action.displayName)
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.text)
                        .lineLimit(1)
                    Spacer()
                    if mode == .keyCombo {
                        Text("⌨")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.surface)
                    } else if mode == .mediaKey {
                        Text("♫")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.surface)
                    } else {
                        // aiSearch mode indicator
                        Text("◉")
                            .font(SudoTheme.mono(size: 7))
                            .foregroundColor(SudoTheme.surface)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(SudoTheme.bg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("button \(action.buttonNumber): \(action.displayName)")
    }
}

/// The visual device replica — 4 interactive buttons in physical order
struct DeviceView: View {
    @ObservedObject var engine: SudoEngine
    let settings = SudoSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                DeviceButton(
                    action: action,
                    mode: settings.actionMode(for: action),
                    onPress: { engine.triggerAction(action) }
                )
                if action != PadAction.physicalOrder.first {
                    SudoDivider()
                }
            }
        }
        .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
    }
}

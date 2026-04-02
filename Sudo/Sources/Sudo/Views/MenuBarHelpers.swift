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

/// Collapsible section header with toggle arrow and accent border
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
            HStack(spacing: 0) {
                // Accent stripe when expanded
                Rectangle()
                    .fill(isExpanded ? SudoTheme.accent : Color.clear)
                    .frame(width: 2)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)

                HStack {
                    Text("> \(title)")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(isHovered ? SudoTheme.text : SudoTheme.textMuted)
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
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.leading, 4)
            }
            .background(isHovered ? SudoTheme.hoverBg : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title) section")
        .accessibilityHint(isExpanded ? "collapse" : "expand")
    }
}

/// Setting toggle: `[x] label` or `[ ] label`
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
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(isHovered ? SudoTheme.text : SudoTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// Interactive device button row with press flash + LED dot + hover state
struct DeviceButton: View {
    let action: PadAction
    let mode: ActionMode
    let isActive: Bool  // true when this button was last pressed
    let onPress: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            // Flash animation
            withAnimation(.easeOut(duration: SudoTheme.flashDuration)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.3)) { isPressed = false }
            }
            onPress()
        }) {
            HStack(spacing: 0) {
                // Color stripe — expands on press
                Rectangle()
                    .fill(Color(hex: action.buttonColorHex))
                    .frame(width: isPressed ? 8 : 3)
                    .animation(.easeOut(duration: SudoTheme.flashDuration), value: isPressed)
                HStack {
                    // LED dot
                    Circle()
                        .fill(isActive ? Color(hex: action.buttonColorHex) : SudoTheme.surface.opacity(0.3))
                        .frame(width: 4, height: 4)
                        .shadow(color: isActive ? Color(hex: action.buttonColorHex).opacity(0.6) : .clear, radius: 3)
                    Text("\(action.buttonNumber)")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.textMuted)
                        .frame(width: 14, alignment: .leading)
                    Text(action.displayName)
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(isPressed ? Color(hex: action.buttonColorHex) : SudoTheme.text)
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
                        Text("◉")
                            .font(SudoTheme.mono(size: 7))
                            .foregroundColor(SudoTheme.surface)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(isPressed ? Color(hex: action.buttonColorHex).opacity(0.08) :
                        isHovered ? SudoTheme.hoverBg : SudoTheme.bg)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                    isActive: engine.lastAction.lowercased().contains(action.displayName.lowercased().components(separatedBy: " ").first ?? ""),
                    onPress: { engine.triggerAction(action) }
                )
                if action != PadAction.physicalOrder.first {
                    SudoDivider()
                }
            }
        }
        .overlay(Rectangle().stroke(
            resultBorderColor.opacity(resultBorderOpacity),
            lineWidth: engine.lastResult == .idle ? 1 : 2
        ))
        .animation(.easeOut(duration: SudoTheme.flashDuration), value: engine.lastResult)
    }

    private var resultBorderColor: Color {
        switch engine.lastResult {
        case .success: return SudoTheme.accent
        case .failure: return SudoTheme.error
        case .processing: return SudoTheme.accent
        default: return SudoTheme.border
        }
    }

    private var resultBorderOpacity: Double {
        switch engine.lastResult {
        case .success, .failure: return 0.8
        case .processing: return 0.5
        default: return 1.0
        }
    }
}

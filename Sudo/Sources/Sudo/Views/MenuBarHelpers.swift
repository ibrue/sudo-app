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

// MARK: - Device Button (Floating Pill)

/// Interactive button — tinted glass pill with LED dot
struct DeviceButton: View {
    let action: PadAction
    let mode: ActionMode
    let isActive: Bool
    let onPress: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    private var buttonColor: Color { Color(hex: action.buttonColorHex) }

    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: SudoTheme.flashDuration)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.3)) { isPressed = false }
            }
            onPress()
        }) {
            HStack(spacing: 8) {
                // LED dot
                Circle()
                    .fill(isActive ? buttonColor : SudoTheme.surface.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .shadow(color: isActive ? buttonColor.opacity(0.6) : .clear, radius: 6)

                // Button number (SF Pro)
                Text("\(action.buttonNumber)")
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.textMuted)
                    .frame(width: 14, alignment: .leading)

                // Display name (monospace — it's a value)
                Text(action.displayName)
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(isPressed ? buttonColor : SudoTheme.text)
                    .lineLimit(1)

                Spacer()

                // Mode indicator
                Group {
                    if mode == .keyCombo {
                        Text("⌨").font(SudoTheme.mono(size: 9))
                    } else if mode == .mediaKey {
                        Text("♫").font(SudoTheme.mono(size: 9))
                    } else {
                        Text("◉").font(SudoTheme.mono(size: 7))
                    }
                }
                .foregroundColor(SudoTheme.textMuted.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: SudoTheme.pillRadius)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: SudoTheme.pillRadius)
                            .fill(buttonColor.opacity(isPressed ? 0.12 : isHovered ? 0.08 : 0.04))
                    )
            )
            .shadow(color: isPressed ? buttonColor.opacity(0.15) : .clear, radius: 8, y: 2)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: SudoTheme.flashDuration), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("button \(action.buttonNumber): \(action.displayName)")
    }
}

// MARK: - Device View (Pill Stack)

/// The visual device replica — 4 floating pill buttons
struct DeviceView: View {
    @ObservedObject var engine: SudoEngine
    let settings = SudoSettings.shared

    var body: some View {
        VStack(spacing: 6) {
            ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                DeviceButton(
                    action: action,
                    mode: settings.actionMode(for: action),
                    isActive: engine.lastAction.lowercased().contains(action.displayName.lowercased().components(separatedBy: " ").first ?? ""),
                    onPress: { engine.triggerAction(action) }
                )
            }
        }
        // Subtle glow on the whole container for result feedback
        .shadow(color: resultGlowColor, radius: resultGlowRadius)
        .animation(.easeOut(duration: SudoTheme.flashDuration), value: engine.lastResult)
    }

    private var resultGlowColor: Color {
        switch engine.lastResult {
        case .success: return SudoTheme.accent.opacity(0.2)
        case .failure: return SudoTheme.error.opacity(0.2)
        case .processing: return SudoTheme.accent.opacity(0.1)
        default: return .clear
        }
    }

    private var resultGlowRadius: CGFloat {
        engine.lastResult == .idle ? 0 : 12
    }
}

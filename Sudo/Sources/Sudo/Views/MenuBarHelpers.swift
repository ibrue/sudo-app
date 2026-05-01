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

/// Interactive button — tinted glass pill with LED dot.
///
/// UI 2: shows last-triggered time + success/fail status, so the user can
/// glance at any row and see when it was last used and whether it worked.
struct DeviceButton: View {
    let action: PadAction
    let mode: ActionMode
    let isActive: Bool
    let lastTriggered: Date?
    let lastSucceeded: Bool?
    let onPress: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    private var buttonColor: Color { Color(hex: action.buttonColorHex) }

    /// Compact "3m ago" string for the row's right-hand side.
    private var lastTriggeredText: String? {
        guard let date = lastTriggered else { return nil }
        let s = Int(Date().timeIntervalSince(date))
        if s < 5  { return "now" }
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d"
    }

    /// One-char mode glyph: keyboard / media / AI search.
    private var modeGlyph: String {
        switch mode {
        case .keyCombo: return "⌨"
        case .mediaKey: return "♫"
        case .aiSearch: return "◉"
        }
    }

    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: SudoTheme.flashDuration)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.3)) { isPressed = false }
            }
            onPress()
        }) {
            HStack(spacing: 8) {
                // LED dot — colored when active, ghosted otherwise.
                Circle()
                    .fill(isActive ? buttonColor : SudoTheme.surface.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .shadow(color: isActive ? buttonColor.opacity(0.6) : .clear, radius: 6)

                Text("\(action.buttonNumber)")
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.textMuted)
                    .frame(width: 14, alignment: .leading)

                Text(action.displayName)
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(isPressed ? buttonColor : SudoTheme.text)
                    .lineLimit(1)

                Spacer()

                // Last triggered: "3m" + ✓/✗ dot — only if there's history.
                if let label = lastTriggeredText {
                    HStack(spacing: 3) {
                        if let ok = lastSucceeded {
                            Circle()
                                .fill(ok ? SudoTheme.accent : SudoTheme.error)
                                .frame(width: 4, height: 4)
                        }
                        Text(label)
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }

                // Mode glyph
                Text(modeGlyph)
                    .font(SudoTheme.mono(size: mode == .aiSearch ? 7 : 9))
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
        .help(modeHelpText)
        .accessibilityLabel("button \(action.buttonNumber): \(action.displayName)")
    }

    private var modeHelpText: String {
        switch mode {
        case .keyCombo: return "key combo — sends a shortcut directly"
        case .mediaKey: return "media key — play/pause/next"
        case .aiSearch: return "ai search — finds matching button in the frontmost app"
        }
    }
}

// MARK: - Device View (Pill Stack)

/// The visual device replica — 4 floating pill buttons.
///
/// UI 8: right-click any row to get a context menu with rename, mode switch,
/// and "edit details" (which opens ConfigView). Rename is inline — the row
/// turns into a TextField; press Return to commit, Escape to cancel.
struct DeviceView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var settings: SudoSettings = .shared

    /// PadAction currently being renamed inline; nil = not renaming.
    @State private var renamingAction: PadAction? = nil
    @State private var renameDraft: String = ""

    private func mostRecent(for action: PadAction) -> ActionLogEntry? {
        let displayName = action.displayName.lowercased()
        return engine.actionLog.first { $0.action.lowercased() == displayName }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                if renamingAction == action {
                    inlineRenameRow(for: action)
                } else {
                    rowWithContextMenu(for: action)
                }
            }
        }
        .shadow(color: resultGlowColor, radius: resultGlowRadius)
        .animation(.easeOut(duration: SudoTheme.flashDuration), value: engine.lastResult)
    }

    // MARK: - Per-row builders

    @ViewBuilder
    private func rowWithContextMenu(for action: PadAction) -> some View {
        let last = mostRecent(for: action)
        DeviceButton(
            action: action,
            mode: settings.actionMode(for: action),
            isActive: engine.lastAction.lowercased().contains(action.displayName.lowercased().components(separatedBy: " ").first ?? ""),
            lastTriggered: last?.timestamp,
            lastSucceeded: last?.succeeded,
            onPress: { engine.triggerAction(action) }
        )
        .contextMenu {
            Button("rename") { startRenaming(action) }
            Divider()
            Section("mode") {
                Button {
                    setMode(.aiSearch, for: action)
                } label: {
                    Label("ai search", systemImage: settings.actionMode(for: action) == .aiSearch ? "checkmark" : "")
                }
                Button {
                    setMode(.keyCombo, for: action)
                } label: {
                    Label("key combo", systemImage: settings.actionMode(for: action) == .keyCombo ? "checkmark" : "")
                }
                Button {
                    setMode(.mediaKey, for: action)
                } label: {
                    Label("media key", systemImage: settings.actionMode(for: action) == .mediaKey ? "checkmark" : "")
                }
            }
            Divider()
            Button("test press") { engine.triggerAction(action) }
        }
    }

    @ViewBuilder
    private func inlineRenameRow(for action: PadAction) -> some View {
        HStack(spacing: 8) {
            Text("\(action.buttonNumber)")
                .font(SudoTheme.mono(size: 11))
                .foregroundColor(SudoTheme.textMuted)
                .frame(width: 14, alignment: .leading)
            TextField("", text: $renameDraft, onCommit: { commitRename(for: action) })
                .textFieldStyle(.plain)
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(SudoTheme.text)
            Button("save") { commitRename(for: action) }
                .font(SudoTheme.mono(size: 9, weight: .bold))
                .foregroundColor(SudoTheme.accent)
                .buttonStyle(.plain)
            Button("cancel") { renamingAction = nil }
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: SudoTheme.pillRadius)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: SudoTheme.pillRadius)
                        .strokeBorder(SudoTheme.accent.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Actions

    private func startRenaming(_ action: PadAction) {
        renameDraft = settings.displayName(for: action)
        renamingAction = action
    }

    private func commitRename(for action: PadAction) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            settings.buttonNames[action.rawValue] = trimmed
        }
        renamingAction = nil
    }

    private func setMode(_ mode: ActionMode, for action: PadAction) {
        settings.buttonModes[action.rawValue] = mode.rawValue
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

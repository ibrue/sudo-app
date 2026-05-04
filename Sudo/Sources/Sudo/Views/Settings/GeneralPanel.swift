import SwiftUI
import CoreGraphics

/// Preferences toggles + debounce + hotkey bindings. All cross-platform
/// SwiftUI; the only platform-specific bit is CGEventFlags decoding for
/// the hotkey display, which would need a small shim on iOS.
struct GeneralPanel: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject private var settings = SudoSettings.shared

    var body: some View {
        SettingsPanelScaffold(
            title: "general",
            subtitle: "global behaviour, sound, telemetry, and hotkey bindings."
        ) {
            sectionHeader("behaviour")
            VStack(alignment: .leading, spacing: 8) {
                SettingToggle(label: "search all apps", isOn: Binding(
                    get: { engine.searchAllApps }, set: { engine.searchAllApps = $0 }
                ))
                SettingToggle(label: "sound feedback", isOn: $settings.soundEnabled)
                SettingToggle(label: "notify on failure", isOn: $settings.notifyOnFailure)
                SettingToggle(label: "launch at login", isOn: $settings.launchAtLogin)
                SettingToggle(label: "anonymous telemetry", isOn: $settings.telemetryEnabled)
            }

            SudoDivider()

            sectionHeader("debounce")
            HStack(spacing: 12) {
                Text("\(Int(settings.debounceDuration * 1000))ms")
                    .font(SudoTheme.code(size: 13))
                    .foregroundColor(SudoTheme.text)
                    .monospacedDigit()
                    .frame(width: 70, alignment: .leading)
                Slider(
                    value: $settings.debounceDuration,
                    in: 0.01...0.5,
                    step: 0.01
                )
                .tint(SudoTheme.accent)
                .frame(maxWidth: 320)
                Button("reset") {
                    settings.debounceDuration = 0.02
                }
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.textMuted)
                .buttonStyle(.plain)
            }

            SudoDivider()

            sectionHeader("hotkey bindings")
            Text("the keystrokes the app listens for. f-keys are paired with ctrl+shift so they don't collide with anything you'd type.")
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                    let binding = settings.hotkeyBindings[action.rawValue]
                    let keyCode = binding?["keyCode"] ?? 0
                    let mods = binding?["modifiers"] ?? 0
                    HStack(spacing: 12) {
                        Circle()
                            .fill(action.buttonColor)
                            .frame(width: 10, height: 10)
                        Text("button \(action.buttonNumber)")
                            .font(SudoTheme.body)
                            .foregroundColor(SudoTheme.text)
                            .frame(width: 90, alignment: .leading)
                        Text(describeHotkey(keyCode: keyCode, modifiers: mods))
                            .font(SudoTheme.code(size: 12))
                            .foregroundColor(SudoTheme.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(SudoTheme.cardSurface))
                        Spacer()
                    }
                }
            }

            Button("reset to defaults") { settings.resetHotkeyBindings() }
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.textMuted)
                .buttonStyle(.plain)
                .accessibilityLabel("reset hotkey bindings to defaults")
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SudoTheme.heading)
            .foregroundColor(SudoTheme.text)
    }

    private func describeHotkey(keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskAlternate) { parts.append("opt") }
        let keyName: String
        switch UInt16(keyCode) {
        case 105: keyName = "F13"; case 107: keyName = "F14"
        case 113: keyName = "F15"; case 106: keyName = "F16"
        case 122: keyName = "F1";  case 120: keyName = "F2"
        case 99:  keyName = "F3";  case 118: keyName = "F4"
        default:  keyName = "key\(keyCode)"
        }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }
}

import SwiftUI
import AppKit
import CoreGraphics

/// Wizard that walks through the 4 buttons one at a time. Step 1..4:
/// edit name, mode, and the per-mode payload (search hint, key combo,
/// or media key). Saves on Next / Done; Cancel discards in-progress
/// changes for the current step (committed steps stay).
struct EditPresetView: View {
    @ObservedObject var settings = SudoSettings.shared
    let onClose: () -> Void

    /// Top-to-bottom physical order — matches what the popover shows.
    private let order: [PadAction] = Array(PadAction.physicalOrder.reversed())

    @State private var stepIndex: Int = 0

    // Per-step draft state
    @State private var draftName: String = ""
    @State private var draftMode: ActionMode = .aiSearch
    @State private var draftKeyCode: UInt16 = 0
    @State private var draftModifiers: UInt64 = 0
    @State private var draftMediaKey: Int = 16

    // Key recorder
    @State private var isRecording = false
    @State private var keyMonitor: Any?

    private var currentAction: PadAction { order[stepIndex] }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: 460, height: 500)
        .background(.regularMaterial)
        .onAppear { loadDraft() }
        .onDisappear { stopRecording() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text("edit preset")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 6) {
                ForEach(0..<order.count, id: \.self) { i in
                    Capsule()
                        .fill(i == stepIndex
                              ? SudoTheme.accent
                              : (i < stepIndex ? SudoTheme.accent.opacity(0.4)
                                              : Color.primary.opacity(0.12)))
                        .frame(width: i == stepIndex ? 24 : 8, height: 4)
                        .animation(.easeInOut(duration: 0.2), value: stepIndex)
                }
            }

            Text("button \(currentAction.buttonNumber) of \(order.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Spacer(); avatar; Spacer() }

            field(label: "name") {
                TextField("e.g. approve, reject…", text: $draftName)
                    .textFieldStyle(.roundedBorder)
            }

            field(label: "action") {
                Picker("", selection: $draftMode) {
                    Text("ai search").tag(ActionMode.aiSearch)
                    Text("key combo").tag(ActionMode.keyCombo)
                    Text("media key").tag(ActionMode.mediaKey)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            modeSpecificEditor

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var avatar: some View {
        let tint = Color(hex: currentAction.buttonColorHex)
        return ZStack {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: 64, height: 64)
            Circle()
                .strokeBorder(tint.opacity(0.5), lineWidth: 1)
                .frame(width: 64, height: 64)
            Text("\(currentAction.buttonNumber)")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.lowercase)
            content()
        }
    }

    @ViewBuilder
    private var modeSpecificEditor: some View {
        switch draftMode {
        case .aiSearch:
            field(label: "ai search") {
                Text("the app finds a button matching this name in whatever app is frontmost — Allow / Approve / Continue / etc. fine-tune search terms in settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .keyCombo:
            field(label: "key combo") {
                HStack(spacing: 10) {
                    Text(comboLabel)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(draftKeyCode == 0 ? .secondary : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 120, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.thinMaterial)
                        )

                    Spacer()

                    Button(isRecording ? "press a key…" : (draftKeyCode == 0 ? "record" : "re-record")) {
                        isRecording ? stopRecording() : startRecording()
                    }
                    .buttonStyle(isRecording ? .borderedProminent : .bordered)
                    .controlSize(.small)
                    .tint(isRecording ? SudoTheme.accent : .accentColor)

                    if draftKeyCode != 0 {
                        Button("clear") {
                            draftKeyCode = 0
                            draftModifiers = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        case .mediaKey:
            field(label: "media key") {
                Picker("", selection: $draftMediaKey) {
                    Text("play / pause").tag(16)
                    Text("next track").tag(17)
                    Text("previous track").tag(18)
                    Text("stop").tag(19)
                    Text("mute").tag(20)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var comboLabel: String {
        if draftKeyCode == 0 { return "<not set>" }
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: draftModifiers)
        if flags.contains(.maskControl)   { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)     { parts.append("⇧") }
        if flags.contains(.maskCommand)   { parts.append("⌘") }
        parts.append(keyName(draftKeyCode))
        return parts.joined()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("back") { goBack() }
                .buttonStyle(.bordered)
                .disabled(stepIndex == 0)

            Spacer()

            Text("\(stepIndex + 1) / \(order.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            if stepIndex < order.count - 1 {
                Button("next") { goNext() }
                    .buttonStyle(.borderedProminent)
                    .tint(SudoTheme.accent)
                    .keyboardShortcut(.return, modifiers: [])
            } else {
                Button("done") { commit(); onClose() }
                    .buttonStyle(.borderedProminent)
                    .tint(SudoTheme.accent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(Color.primary.opacity(0.04))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        )
    }

    // MARK: - Step nav

    private func goNext() {
        commit()
        if stepIndex < order.count - 1 {
            stepIndex += 1
            loadDraft()
        }
    }

    private func goBack() {
        commit()
        if stepIndex > 0 {
            stepIndex -= 1
            loadDraft()
        }
    }

    private func loadDraft() {
        let action = currentAction
        draftName = settings.displayName(for: action)
        draftMode = settings.actionMode(for: action)
        if let kc = settings.keyCombo(for: action) {
            draftKeyCode = kc.keyCode
            draftModifiers = kc.modifiers.rawValue
            if draftMode == .mediaKey { draftMediaKey = Int(kc.keyCode) }
        } else {
            draftKeyCode = 0
            draftModifiers = 0
            draftMediaKey = 16
        }
    }

    private func commit() {
        let action = currentAction
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            settings.buttonNames[action.rawValue] = trimmed
        }
        settings.buttonModes[action.rawValue] = draftMode.rawValue
        switch draftMode {
        case .keyCombo where draftKeyCode != 0:
            settings.buttonKeyCombos[action.rawValue] = [
                "keyCode":   Int(draftKeyCode),
                "modifiers": Int(draftModifiers),
            ]
        case .mediaKey:
            settings.buttonKeyCombos[action.rawValue] = [
                "keyCode":   draftMediaKey,
                "modifiers": 0,
            ]
        default:
            break
        }
    }

    // MARK: - Key recorder
    //
    // Hooks NSEvent's local key-down monitor while recording. The first
    // keystroke captured (with its modifier flags) becomes the new combo.
    // Returning nil from the handler swallows the event so it doesn't
    // also fire the [next] button when the user records Return.

    private func startRecording() {
        guard keyMonitor == nil else { return }
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Translate NSEvent.ModifierFlags → CGEventFlags
            var flags: UInt64 = 0
            let mod = event.modifierFlags
            if mod.contains(.shift)   { flags |= CGEventFlags.maskShift.rawValue }
            if mod.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
            if mod.contains(.option)  { flags |= CGEventFlags.maskAlternate.rawValue }
            if mod.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
            draftKeyCode = event.keyCode
            draftModifiers = flags
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        isRecording = false
    }

    // Display name for a macOS virtual key code. Covers letters, common
    // punctuation, function keys, and a handful of special keys. Anything
    // unknown falls back to "key<n>".
    private func keyName(_ code: UInt16) -> String {
        switch code {
        case 0:   return "A"
        case 1:   return "S"
        case 2:   return "D"
        case 3:   return "F"
        case 4:   return "H"
        case 5:   return "G"
        case 6:   return "Z"
        case 7:   return "X"
        case 8:   return "C"
        case 9:   return "V"
        case 11:  return "B"
        case 12:  return "Q"
        case 13:  return "W"
        case 14:  return "E"
        case 15:  return "R"
        case 16:  return "Y"
        case 17:  return "T"
        case 18:  return "1"
        case 19:  return "2"
        case 20:  return "3"
        case 21:  return "4"
        case 22:  return "6"
        case 23:  return "5"
        case 25:  return "9"
        case 26:  return "7"
        case 28:  return "8"
        case 29:  return "0"
        case 31:  return "O"
        case 32:  return "U"
        case 34:  return "I"
        case 35:  return "P"
        case 36:  return "↩"
        case 37:  return "L"
        case 38:  return "J"
        case 40:  return "K"
        case 41:  return ";"
        case 43:  return ","
        case 44:  return "/"
        case 46:  return "M"
        case 47:  return "."
        case 49:  return "space"
        case 51:  return "⌫"
        case 53:  return "esc"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 90:  return "F20"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 99:  return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        default:  return "key\(code)"
        }
    }
}

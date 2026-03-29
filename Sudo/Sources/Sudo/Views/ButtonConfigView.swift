import SwiftUI

/// View for customizing what each macro pad button does (its search terms).
struct ButtonConfigView: View {
    @ObservedObject var configStore: ButtonConfigStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingAction: PadAction?
    @State private var editText: String = ""
    @State private var recordingHotkeyAction: PadAction?
    @State private var hotkeyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("> key bindings")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x00FF41))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: 0x666666))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle().fill(Color(hex: 0x1E1E1E)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PadAction.allCases, id: \.rawValue) { action in
                        actionRow(action)
                        Rectangle().fill(Color(hex: 0x1E1E1E)).frame(height: 1)
                    }
                }
            }

            Rectangle().fill(Color(hex: 0x1E1E1E)).frame(height: 1)

            // Reset all button
            HStack {
                Spacer()
                Button(action: { configStore.resetAllToDefaults() }) {
                    Text("[ RESET ALL TO DEFAULTS ]")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: 0xFF3333))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 320, height: 420)
        .background(Color(hex: 0x0A0A0A))
    }

    @ViewBuilder
    private func actionRow(_ action: PadAction) -> some View {
        let mode = configStore.buttonMode(for: action)

        VStack(alignment: .leading, spacing: 6) {
            // Key label + action name
            HStack {
                Text("F\(action.fKeyNumber)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x00FF41))
                Text(action.displayName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                if case .complex = mode, configStore.isCustomized(action) {
                    Button(action: { configStore.resetToDefaults(action) }) {
                        Text("reset")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color(hex: 0xFF3333))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Hotkey binding
            hotkeyRow(action)

            // Mode toggle
            modeToggle(action, mode: mode)

            // Mode-specific content
            if case .simple = mode {
                simpleActionPicker(action, mode: mode)
            } else {
                if editingAction == action {
                    editField(action)
                } else {
                    termsDisplay(action)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func hotkeyRow(_ action: PadAction) -> some View {
        let config = configStore.hotkeyConfig(for: action)
        let isRecording = recordingHotkeyAction == action
        let isCustom = configStore.hotkeyConfigs[action.rawValue] != nil

        HStack(spacing: 6) {
            Text("hotkey:")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(hex: 0x666666))

            if isRecording {
                Text("Press keys...")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x00FF41))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: 0x1A1A1A))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color(hex: 0x00FF41), lineWidth: 1)
                    )

                Button(action: { stopRecordingHotkey() }) {
                    Text("cancel")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(hex: 0x666666))
                }
                .buttonStyle(.plain)
            } else {
                Text(config.displayString)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isCustom ? Color(hex: 0x00BFFF) : Color(hex: 0x888888))

                Button(action: { startRecordingHotkey(for: action) }) {
                    Text("record")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(hex: 0x00FF41))
                }
                .buttonStyle(.plain)

                if isCustom {
                    Button(action: { configStore.resetHotkeyConfig(for: action) }) {
                        Text("reset")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color(hex: 0xFF3333))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
    }

    private func startRecordingHotkey(for action: PadAction) {
        // Stop any existing recording
        stopRecordingHotkey()

        recordingHotkeyAction = action
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            let keyCode = event.keyCode
            let modifiers = HotkeyConfig.normalizedModifiers(from: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))

            // Ignore bare modifier presses and Escape to cancel
            if keyCode == 53 { // Escape
                stopRecordingHotkey()
                return nil
            }

            let config = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
            configStore.setHotkeyConfig(config, for: action)
            stopRecordingHotkey()
            return nil  // consume the event
        }
    }

    private func stopRecordingHotkey() {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
        recordingHotkeyAction = nil
    }

    @ViewBuilder
    private func modeToggle(_ action: PadAction, mode: ButtonMode) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                configStore.setButtonMode(.simple(.copy), for: action)
            }) {
                Text("SIMPLE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(mode.isSimple ? Color(hex: 0x0A0A0A) : Color(hex: 0x666666))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(mode.isSimple ? Color(hex: 0x00FF41) : Color.clear)
            }
            .buttonStyle(.plain)

            Button(action: {
                configStore.setButtonMode(.complex, for: action)
            }) {
                Text("COMPLEX")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(!mode.isSimple ? Color(hex: 0x0A0A0A) : Color(hex: 0x666666))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(!mode.isSimple ? Color(hex: 0x00FF41) : Color.clear)
            }
            .buttonStyle(.plain)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(hex: 0x333333), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func simpleActionPicker(_ action: PadAction, mode: ButtonMode) -> some View {
        let selectedAction: SimpleAction? = {
            if case .simple(let a) = mode { return a }
            return nil
        }()

        VStack(alignment: .leading, spacing: 6) {
            ForEach(SimpleAction.categories, id: \.self) { category in
                Text(category.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x666666))
                    .padding(.top, 2)

                let actions = SimpleAction.actions(in: category)
                let columns = [GridItem(.adaptive(minimum: 80), spacing: 4)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(actions, id: \.rawValue) { simpleAction in
                        Button(action: {
                            configStore.setButtonMode(.simple(simpleAction), for: action)
                        }) {
                            Text(simpleAction.displayName)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(selectedAction == simpleAction ? Color(hex: 0x0A0A0A) : Color(hex: 0x00FF41))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedAction == simpleAction ? Color(hex: 0x00FF41) : Color(hex: 0x1A1A1A))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color(hex: 0x333333), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func termsDisplay(_ action: PadAction) -> some View {
        let terms = configStore.searchTerms(for: action)
        Text(terms.joined(separator: ", "))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(configStore.isCustomized(action) ? Color(hex: 0x00BFFF) : Color(hex: 0x666666))
            .lineLimit(3)
            .onTapGesture {
                editText = configStore.searchTerms(for: action).joined(separator: ", ")
                editingAction = action
            }

        Text("tap to edit")
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(Color(hex: 0x333333))
    }

    @ViewBuilder
    private func editField(_ action: PadAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("comma-separated search terms:")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(hex: 0x666666))

            TextEditor(text: $editText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Color(hex: 0x1A1A1A))
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color(hex: 0x00FF41), lineWidth: 1)
                )

            HStack {
                Button(action: { saveEdit(action) }) {
                    Text("[ SAVE ]")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: 0x00FF41))
                }
                .buttonStyle(.plain)

                Button(action: { editingAction = nil }) {
                    Text("[ CANCEL ]")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: 0x666666))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func saveEdit(_ action: PadAction) {
        let terms = editText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        configStore.setSearchTerms(terms.isEmpty ? nil : terms, for: action)
        editingAction = nil
    }
}

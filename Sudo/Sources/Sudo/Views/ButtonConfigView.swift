import SwiftUI

/// View for customizing what each macro pad button does (its search terms).
struct ButtonConfigView: View {
    @ObservedObject var configStore: ButtonConfigStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingAction: PadAction?
    @State private var editText: String = ""

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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("F\(action.fKeyNumber)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x00FF41))
                Text(action.displayName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                if configStore.isCustomized(action) {
                    Button(action: { configStore.resetToDefaults(action) }) {
                        Text("reset")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color(hex: 0xFF3333))
                    }
                    .buttonStyle(.plain)
                }
            }

            if editingAction == action {
                editField(action)
            } else {
                termsDisplay(action)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

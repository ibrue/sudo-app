import SwiftUI

/// Per-button name + search-term editor and quick preset chips. The
/// guided 4-step wizard still lives in EditPresetWindowManager; this
/// panel is for the fine-grained edits the wizard skips over.
struct ButtonsPanel: View {
    @ObservedObject private var settings = SudoSettings.shared
    @State private var editingAction: PadAction? = nil
    @State private var editName: String = ""
    @State private var editTerms: String = ""

    var body: some View {
        SettingsPanelScaffold(
            title: "buttons",
            subtitle: "rename buttons, tune their search terms, or apply a quick preset."
        ) {
            Button(action: { EditPresetWindowManager.shared.open() }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                    Text("walk through all 4 buttons")
                }
                .font(SudoTheme.mono(size: 11, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(SudoTheme.accent.opacity(0.12)))
                .foregroundStyle(SudoTheme.accent)
            }
            .buttonStyle(.plain)

            SudoDivider()

            sectionHeader("quick presets")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ButtonPreset.all) { preset in
                    Button(action: { preset.apply(); editingAction = nil }) {
                        HStack {
                            Text(preset.name.lowercased())
                                .font(SudoTheme.mono(size: 11, weight: .bold))
                                .foregroundColor(SudoTheme.accent)
                            Text("·")
                                .font(SudoTheme.mono(size: 10))
                                .foregroundColor(SudoTheme.border)
                            Text(preset.description)
                                .font(SudoTheme.mono(size: 10))
                                .foregroundColor(SudoTheme.textMuted)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("apply \(preset.name.lowercased()) preset")
                }
            }

            SudoDivider()

            sectionHeader("custom mapping")
            ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                if editingAction == action {
                    editorRow(for: action)
                } else {
                    summaryRow(for: action)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryRow(for action: PadAction) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: action.buttonColorHex)).frame(width: 8, height: 8)
            Text("\(action.buttonNumber)")
                .font(SudoTheme.mono(size: 11)).foregroundColor(SudoTheme.textMuted)
                .frame(width: 16, alignment: .leading)
            Text(action.displayName).font(SudoTheme.mono(size: 11)).foregroundColor(SudoTheme.text)
            Spacer()
            Button("edit") {
                editName = SudoSettings.shared.buttonNames[action.rawValue] ?? action.defaultDisplayName
                editTerms = (SudoSettings.shared.buttonSearchTerms[action.rawValue] ?? action.defaultSearchTerms)
                    .joined(separator: ", ")
                editingAction = action
            }
            .font(SudoTheme.mono(size: 10))
            .foregroundColor(SudoTheme.accent)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func editorRow(for action: PadAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: action.buttonColorHex)).frame(width: 8, height: 8)
                Text("button \(action.buttonNumber)")
                    .font(SudoTheme.mono(size: 11, weight: .semibold))
                    .foregroundColor(SudoTheme.text)
                Spacer()
            }

            field("name", text: $editName, hint: "displayed in the popover")
            field("find", text: $editTerms, hint: "comma-separated search terms")

            HStack(spacing: 10) {
                Spacer()
                Button("save") {
                    settings.buttonNames[action.rawValue] = editName.isEmpty ? nil : editName
                    let terms = editTerms
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    settings.buttonSearchTerms[action.rawValue] = terms.isEmpty ? nil : terms
                    editingAction = nil
                }
                .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                Button("reset") {
                    settings.buttonNames[action.rawValue] = nil
                    settings.buttonSearchTerms[action.rawValue] = nil
                    editingAction = nil
                }
                .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                Button("cancel") { editingAction = nil }
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
            }
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SudoTheme.accent.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, hint: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(SudoTheme.textMuted)
                .frame(width: 40, alignment: .trailing)
            TextField(hint, text: text)
                .font(SudoTheme.mono(size: 11))
                .textFieldStyle(.plain)
                .foregroundColor(SudoTheme.text)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text("> \(title)")
            .font(SudoTheme.mono(size: 10, weight: .medium))
            .foregroundColor(SudoTheme.textMuted)
            .tracking(0.5)
    }
}

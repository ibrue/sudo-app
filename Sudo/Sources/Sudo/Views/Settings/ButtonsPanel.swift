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
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                    Text("walk through all 4 buttons")
                        .font(SudoTheme.bodyEmphasized)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).fill(SudoTheme.accent.opacity(0.12)))
                .foregroundStyle(SudoTheme.accent)
            }
            .buttonStyle(.plain)

            SudoDivider()

            sectionHeader("quick presets")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ButtonPreset.all) { preset in
                    Button(action: { preset.apply(); editingAction = nil }) {
                        HStack(spacing: 10) {
                            Text(preset.name.lowercased())
                                .font(SudoTheme.bodyEmphasized)
                                .foregroundColor(SudoTheme.accent)
                            Text("·")
                                .font(SudoTheme.caption)
                                .foregroundColor(SudoTheme.border)
                            Text(preset.description)
                                .font(SudoTheme.caption)
                                .foregroundColor(SudoTheme.textMuted)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
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
        HStack(spacing: 12) {
            Circle().fill(action.buttonColor).frame(width: 10, height: 10)
            Text("\(action.buttonNumber)")
                .font(SudoTheme.body).foregroundColor(SudoTheme.textMuted)
                .frame(width: 18, alignment: .leading)
            Text(action.displayName)
                .font(SudoTheme.body).foregroundColor(SudoTheme.text)
            Spacer()
            Button("edit") {
                editName = SudoSettings.shared.buttonNames[action.rawValue] ?? action.defaultDisplayName
                editTerms = (SudoSettings.shared.buttonSearchTerms[action.rawValue] ?? action.defaultSearchTerms)
                    .joined(separator: ", ")
                editingAction = action
            }
            .font(SudoTheme.caption)
            .foregroundColor(SudoTheme.accent)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func editorRow(for action: PadAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Circle().fill(action.buttonColor).frame(width: 10, height: 10)
                Text("button \(action.buttonNumber)")
                    .font(SudoTheme.bodyEmphasized)
                    .foregroundColor(SudoTheme.text)
                Spacer()
            }

            field("name", text: $editName, hint: "displayed in the popover")
            field("find", text: $editTerms, hint: "comma-separated search terms")

            HStack(spacing: 12) {
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
                .font(SudoTheme.body).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                Button("reset") {
                    settings.buttonNames[action.rawValue] = nil
                    settings.buttonSearchTerms[action.rawValue] = nil
                    editingAction = nil
                }
                .font(SudoTheme.body).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                Button("cancel") { editingAction = nil }
                    .font(SudoTheme.body).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).stroke(SudoTheme.accent.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, hint: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.textMuted)
                .frame(width: 50, alignment: .trailing)
            TextField(hint, text: text)
                .textFieldStyle(.roundedBorder)
                .font(SudoTheme.body)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SudoTheme.heading)
            .foregroundColor(SudoTheme.text)
    }
}

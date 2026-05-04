import SwiftUI

/// Macro sequence editor — full-window version of the cramped popover
/// list. Names, button assignment, ordered steps + per-step delay.
struct MacrosPanel: View {
    @ObservedObject private var settings = SudoSettings.shared
    @State private var editingMacroID: UUID? = nil

    var body: some View {
        SettingsPanelScaffold(
            title: "macros",
            subtitle: "chained actions with per-step delays. assign one to a button to fire it on press."
        ) {
            if settings.macros.isEmpty {
                emptyState
            } else {
                ForEach(Array(settings.macros.enumerated()), id: \.element.id) { index, macro in
                    macroCard(index: index, macro: macro)
                }
            }

            Button(action: addMacro) {
                Label("add macro", systemImage: "plus.circle")
                    .font(SudoTheme.mono(size: 11, weight: .medium))
                    .foregroundColor(SudoTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("add macro")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("no macros yet")
                .font(SudoTheme.mono(size: 11)).foregroundColor(SudoTheme.text)
            Text("create one below to chain a sequence of button actions with delays between them.")
                .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
    }

    @ViewBuilder
    private func macroCard(index: Int, macro: MacroSequence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(macro.name.lowercased())
                    .font(SudoTheme.mono(size: 12, weight: .semibold))
                    .foregroundColor(SudoTheme.text)
                Text("(\(macro.steps.count) steps)")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.textMuted)
                Spacer()
                if let assigned = macro.assignedButton,
                   let action = PadAction.allCases.first(where: { $0.rawValue == assigned }) {
                    Text("→ btn \(action.buttonNumber)")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(SudoTheme.accentDim))
                }
                if editingMacroID == macro.id {
                    Button("done") { editingMacroID = nil }
                        .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                } else {
                    Button("edit") { editingMacroID = macro.id }
                        .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                    Button("delete") { settings.macros.remove(at: index) }
                        .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                }
            }

            if editingMacroID == macro.id {
                editor(index: index, macro: macro)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
    }

    @ViewBuilder
    private func editor(index: Int, macro: MacroSequence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("name")
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted)
                    .frame(width: 50, alignment: .trailing)
                TextField("macro name", text: Binding(
                    get: { settings.macros[index].name },
                    set: { settings.macros[index].name = $0 }
                ))
                .font(SudoTheme.mono(size: 11))
                .textFieldStyle(.plain)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
            }

            HStack(spacing: 8) {
                Text("button")
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted)
                    .frame(width: 50, alignment: .trailing)
                ForEach(PadAction.physicalOrder, id: \.rawValue) { action in
                    let isAssigned = settings.macros[index].assignedButton == action.rawValue
                    Button("\(action.buttonNumber)") {
                        settings.macros[index].assignedButton = isAssigned ? nil : action.rawValue
                    }
                    .font(SudoTheme.mono(size: 11, weight: isAssigned ? .bold : .regular))
                    .foregroundColor(isAssigned ? SudoTheme.accent : SudoTheme.textMuted)
                    .buttonStyle(.plain)
                    .frame(width: 22)
                }
                Button("none") { settings.macros[index].assignedButton = nil }
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
                Spacer()
            }

            Text("> steps")
                .font(SudoTheme.mono(size: 10, weight: .medium))
                .foregroundColor(SudoTheme.textMuted)

            ForEach(Array(macro.steps.enumerated()), id: \.element.id) { stepIdx, step in
                HStack(spacing: 8) {
                    Text("\(stepIdx + 1).")
                        .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted)
                        .frame(width: 22, alignment: .trailing)
                    Text(step.padAction?.defaultDisplayName.lowercased() ?? step.action)
                        .font(SudoTheme.mono(size: 11)).foregroundColor(SudoTheme.text)
                    Text("+ \(String(format: "%.1f", step.delayAfter))s")
                        .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted)
                    Spacer()
                    Button("✕") {
                        settings.macros[index].steps.remove(at: stepIdx)
                    }
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                    .accessibilityLabel("remove step \(stepIdx + 1)")
                }
            }

            HStack(spacing: 8) {
                Text("add:").font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted)
                ForEach(PadAction.physicalOrder, id: \.rawValue) { action in
                    Button(action.defaultDisplayName.lowercased().components(separatedBy: " ").first ?? action.rawValue) {
                        let step = MacroStep(action: action, delayAfter: 1.0)
                        settings.macros[index].steps.append(step)
                    }
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
    }

    private func addMacro() {
        let macro = MacroSequence(name: "new macro", steps: [])
        settings.macros.append(macro)
        editingMacroID = macro.id
    }
}

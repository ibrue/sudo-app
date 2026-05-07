import SwiftUI
import AppKit
import CoreGraphics

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
                    .font(SudoTheme.bodyEmphasized)
                    .foregroundColor(SudoTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("add macro")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("no macros yet")
                .font(SudoTheme.bodyEmphasized).foregroundColor(SudoTheme.text)
            Text("create one below to chain a sequence of button actions with delays between them.")
                .font(SudoTheme.body).foregroundColor(SudoTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
    }

    @ViewBuilder
    private func macroCard(index: Int, macro: MacroSequence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(macro.name.lowercased())
                    .font(SudoTheme.heading)
                    .foregroundColor(SudoTheme.text)
                Text("(\(macro.steps.count) steps)")
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.textMuted)
                Spacer()
                if let assigned = macro.assignedButton,
                   let action = PadAction.allCases.first(where: { $0.rawValue == assigned }) {
                    HStack(spacing: 4) {
                        Circle().fill(action.buttonColor).frame(width: 8, height: 8)
                        Text("btn \(action.buttonNumber)")
                            .font(SudoTheme.caption)
                            .foregroundColor(SudoTheme.accent)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(SudoTheme.accentDim))
                }
                if editingMacroID == macro.id {
                    Button("done") { editingMacroID = nil }
                        .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                } else {
                    Button("edit") { editingMacroID = macro.id }
                        .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                    Button("delete") { settings.macros.remove(at: index) }
                        .font(SudoTheme.caption).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                }
            }

            if editingMacroID == macro.id {
                editor(index: index, macro: macro)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).fill(SudoTheme.cardSurface))
    }

    @ViewBuilder
    private func editor(index: Int, macro: MacroSequence) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("name")
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted)
                    .frame(width: 60, alignment: .trailing)
                TextField("macro name", text: Binding(
                    get: { settings.macros[index].name },
                    set: { settings.macros[index].name = $0 }
                ))
                .font(SudoTheme.body)
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Text("button")
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted)
                    .frame(width: 60, alignment: .trailing)
                ForEach(PadAction.physicalOrder, id: \.rawValue) { action in
                    let isAssigned = settings.macros[index].assignedButton == action.rawValue
                    Button("\(action.buttonNumber)") {
                        settings.macros[index].assignedButton = isAssigned ? nil : action.rawValue
                    }
                    .font(SudoTheme.body.weight(isAssigned ? .bold : .regular))
                    .foregroundColor(isAssigned ? SudoTheme.accent : SudoTheme.textMuted)
                    .buttonStyle(.plain)
                    .frame(width: 24)
                }
                Button("none") { settings.macros[index].assignedButton = nil }
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
                Spacer()
            }

            Text("steps")
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.textMuted)

            ForEach(Array(macro.steps.enumerated()), id: \.element.id) { stepIdx, step in
                stepRow(macroIndex: index, stepIndex: stepIdx, step: step)
            }

            stepAdder(macroIndex: index)
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
    }

    private func addMacro() {
        let macro = MacroSequence(name: "new macro", steps: [])
        settings.macros.append(macro)
        editingMacroID = macro.id
    }

    // MARK: - Step row + adder

    @ViewBuilder
    private func stepRow(macroIndex: Int, stepIndex: Int, step: MacroStep) -> some View {
        HStack(spacing: 10) {
            Text("\(stepIndex + 1).")
                .font(SudoTheme.code(size: 11)).foregroundColor(SudoTheme.textMuted)
                .frame(width: 26, alignment: .trailing)

            Image(systemName: stepIcon(step))
                .font(.system(size: 11))
                .foregroundStyle(SudoTheme.accent)
                .frame(width: 16)

            stepDescription(step)

            Spacer()

            stepDelayBadge(step)

            Button("✕") {
                settings.macros[macroIndex].steps.remove(at: stepIndex)
            }
            .font(SudoTheme.caption).foregroundColor(SudoTheme.error).buttonStyle(.plain)
            .accessibilityLabel("remove step \(stepIndex + 1)")
        }
        .padding(.vertical, 2)
    }

    private func stepIcon(_ step: MacroStep) -> String {
        switch step.kind {
        case .action:      return "circle.fill"
        case .switchToApp: return "arrow.right.square"
        case .switchBack:  return "arrow.uturn.left"
        case .keystroke:   return "keyboard"
        }
    }

    @ViewBuilder
    private func stepDescription(_ step: MacroStep) -> some View {
        switch step.kind {
        case .action:
            Text(step.padAction?.defaultDisplayName.lowercased() ?? step.action)
                .font(SudoTheme.body).foregroundColor(SudoTheme.text)
        case .switchToApp:
            HStack(spacing: 6) {
                Text("switch to")
                    .font(SudoTheme.body).foregroundColor(SudoTheme.textMuted)
                Text(step.targetDisplayName ?? step.targetBundleID ?? "(unset)")
                    .font(SudoTheme.code(size: 11)).foregroundColor(SudoTheme.text)
            }
        case .switchBack:
            Text("switch back to previous app")
                .font(SudoTheme.body).foregroundColor(SudoTheme.text)
        case .keystroke:
            HStack(spacing: 6) {
                Text("send")
                    .font(SudoTheme.body).foregroundColor(SudoTheme.textMuted)
                Text(describeKeystroke(keyCode: step.keyCode ?? 0, modifiers: step.modifiers ?? 0))
                    .font(SudoTheme.code(size: 11)).foregroundColor(SudoTheme.text)
            }
        }
    }

    @ViewBuilder
    private func stepDelayBadge(_ step: MacroStep) -> some View {
        switch step.kind {
        case .action, .keystroke:
            if step.delayAfter > 0 {
                Text("+ \(String(format: "%.1f", step.delayAfter))s")
                    .font(SudoTheme.code(size: 11)).foregroundColor(SudoTheme.textMuted)
                    .monospacedDigit()
            } else {
                EmptyView()
            }
        case .switchToApp, .switchBack:
            Text("wait \(step.waitMs ?? MacroStep.defaultSwitchWaitMs)ms")
                .font(SudoTheme.code(size: 11)).foregroundColor(SudoTheme.textMuted)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func stepAdder(macroIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("add button press:")
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted)
                ForEach(PadAction.physicalOrder, id: \.rawValue) { action in
                    Button(action.defaultDisplayName.lowercased().components(separatedBy: " ").first ?? action.rawValue) {
                        settings.macros[macroIndex].steps.append(MacroStep(action: action, delayAfter: 1.0))
                    }
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Text("add scoped step:")
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted)
                Menu("+ switch to app") {
                    ForEach(runningAppChoices(), id: \.bundleID) { app in
                        Button(app.displayName) {
                            settings.macros[macroIndex].steps.append(
                                .switchToApp(bundleID: app.bundleID,
                                             displayName: app.displayName)
                            )
                        }
                    }
                    Divider()
                    Button("custom bundle id…") {
                        settings.macros[macroIndex].steps.append(
                            .switchToApp(bundleID: "com.example.app",
                                         displayName: "(edit me)")
                        )
                    }
                }
                .menuStyle(.borderlessButton)
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.accent)

                Button("+ switch back") {
                    settings.macros[macroIndex].steps.append(.switchBack())
                }
                .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)

                Button("+ keystroke") {
                    // Default to a recognisable placeholder (Cmd+S — "save").
                    settings.macros[macroIndex].steps.append(
                        .keystroke(keyCode: 1, modifiers: Int(CGEventFlags.maskCommand.rawValue))
                    )
                }
                .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private struct AppChoice {
        let bundleID: String
        let displayName: String
    }

    /// Snapshot of currently-running apps with bundle IDs, sorted by name.
    /// Lets the user pick a switch-to-app target without typing a bundle ID.
    private func runningAppChoices() -> [AppChoice] {
        NSWorkspace.shared.runningApplications
            .compactMap { app -> AppChoice? in
                guard let bid = app.bundleIdentifier,
                      let name = app.localizedName,
                      app.activationPolicy == .regular else { return nil }
                return AppChoice(bundleID: bid, displayName: name)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Render a key combo like `⌘⇧4`. Used in step rows so the keystroke
    /// step is human-readable at a glance.
    private func describeKeystroke(keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        if flags.contains(.maskControl)   { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)     { parts.append("⇧") }
        if flags.contains(.maskCommand)   { parts.append("⌘") }
        parts.append(keyName(UInt16(keyCode)))
        return parts.joined()
    }

    private func keyName(_ code: UInt16) -> String {
        switch code {
        case 0:   return "A"; case 1:   return "S"; case 2:   return "D"
        case 3:   return "F"; case 4:   return "H"; case 5:   return "G"
        case 6:   return "Z"; case 7:   return "X"; case 8:   return "C"
        case 9:   return "V"; case 11:  return "B"; case 12:  return "Q"
        case 13:  return "W"; case 14:  return "E"; case 15:  return "R"
        case 16:  return "Y"; case 17:  return "T"; case 18:  return "1"
        case 19:  return "2"; case 20:  return "3"; case 21:  return "4"
        case 22:  return "6"; case 23:  return "5"; case 25:  return "9"
        case 26:  return "7"; case 28:  return "8"; case 29:  return "0"
        case 31:  return "O"; case 32:  return "U"; case 34:  return "I"
        case 35:  return "P"; case 36:  return "↩"; case 37:  return "L"
        case 38:  return "J"; case 40:  return "K"; case 41:  return ";"
        case 43:  return ","; case 44:  return "/"; case 46:  return "M"
        case 47:  return "."; case 49:  return "space"; case 51:  return "⌫"
        case 53:  return "esc"
        default:  return "key\(code)"
        }
    }
}

import SwiftUI

/// Auto-approve rules — toggle + per-rule editor with app filter,
/// context-contains and context-excludes guards.
struct AutoApprovePanel: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject private var settings = SudoSettings.shared

    @State private var editingRuleID: UUID? = nil
    @State private var editRuleName = ""
    @State private var editRuleAppFilter = ""
    @State private var editRuleContextContains = ""
    @State private var editRuleContextExcludes = ""

    var body: some View {
        SettingsPanelScaffold(
            title: "auto-approve",
            subtitle: "experimental — auto-presses approve when a rule matches the focused app and on-screen context."
        ) {
            warningBanner

            SettingToggle(label: "enable auto-approve", isOn: Binding(
                get: { settings.autoApproveEnabled },
                set: { settings.autoApproveEnabled = $0; engine.startAutoApproveTimer() }
            ))

            SudoDivider()

            sectionHeader("rules")
            if settings.autoApproveRules.isEmpty {
                Text("no rules yet — add one below to enable safe auto-approval in specific apps.")
                    .font(SudoTheme.body)
                    .foregroundColor(SudoTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(settings.autoApproveRules.enumerated()), id: \.element.id) { index, rule in
                ruleCard(index: index, rule: rule)
            }

            Button(action: addRule) {
                Label("add rule", systemImage: "plus.circle")
                    .font(SudoTheme.bodyEmphasized)
                    .foregroundColor(SudoTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("add auto-approve rule")
        }
    }

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(SudoTheme.error)
            Text("rules fire approve presses without confirmation. always set a context-excludes guard for destructive prompts.")
                .font(SudoTheme.body)
                .foregroundColor(SudoTheme.error)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).fill(SudoTheme.error.opacity(0.10)))
    }

    @ViewBuilder
    private func ruleCard(index: Int, rule: AutoApproveRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SettingToggle(label: rule.name.lowercased(), isOn: Binding(
                    get: { settings.autoApproveRules[index].enabled },
                    set: { settings.autoApproveRules[index].enabled = $0 }
                ))
                Spacer()
                if editingRuleID == rule.id {
                    Button("done") { editingRuleID = nil }
                        .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                } else {
                    Button("edit") {
                        editingRuleID = rule.id
                        editRuleName = rule.name
                        editRuleAppFilter = rule.appFilter ?? ""
                        editRuleContextContains = rule.contextContains ?? ""
                        editRuleContextExcludes = rule.contextExcludes ?? ""
                    }
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                    Button("delete") { settings.autoApproveRules.remove(at: index) }
                        .font(SudoTheme.caption).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                }
            }

            if editingRuleID == rule.id {
                VStack(alignment: .leading, spacing: 8) {
                    field("name", text: Binding(
                        get: { editRuleName },
                        set: { editRuleName = $0; settings.autoApproveRules[index].name = $0 }
                    ), hint: "what this rule's for")
                    field("app", text: Binding(
                        get: { editRuleAppFilter },
                        set: { editRuleAppFilter = $0; settings.autoApproveRules[index].appFilter = $0.isEmpty ? nil : $0 }
                    ), hint: "bundle id substring (blank = all apps)")
                    field("contains", text: Binding(
                        get: { editRuleContextContains },
                        set: { editRuleContextContains = $0; settings.autoApproveRules[index].contextContains = $0.isEmpty ? nil : $0 }
                    ), hint: "only fire if context has this text")
                    field("excludes", text: Binding(
                        get: { editRuleContextExcludes },
                        set: { editRuleContextExcludes = $0; settings.autoApproveRules[index].contextExcludes = $0.isEmpty ? nil : $0 }
                    ), hint: "never fire if context has this text")
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).fill(SudoTheme.cardSurface))
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, hint: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.textMuted)
                .frame(width: 80, alignment: .trailing)
            TextField(hint, text: text)
                .textFieldStyle(.roundedBorder)
                .font(SudoTheme.body)
        }
    }

    private func addRule() {
        let rule = AutoApproveRule(name: "new rule")
        settings.autoApproveRules.append(rule)
        editingRuleID = rule.id
        editRuleName = rule.name
        editRuleAppFilter = ""
        editRuleContextContains = ""
        editRuleContextExcludes = ""
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SudoTheme.heading)
            .foregroundColor(SudoTheme.text)
    }
}

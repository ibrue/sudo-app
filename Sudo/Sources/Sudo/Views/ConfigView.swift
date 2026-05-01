import SwiftUI
import CoreGraphics

/// The config/settings view — all configuration in one scrollable panel.
struct ConfigView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var apiServer: LocalAPIServer
    @ObservedObject var settings = SudoSettings.shared
    @ObservedObject var pluginManager = PluginManager.shared
    let onBack: () -> Void

    @ObservedObject var flasher = FirmwareFlasher.shared
    @ObservedObject var debugLogger = DebugLogger.shared

    // Section toggles — persisted across popover open/close via SudoSettings.expandedSections
    private func sectionBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { settings.expandedSections.contains(key) },
            set: { if $0 { settings.expandedSections.insert(key) } else { settings.expandedSections.remove(key) } }
        )
    }

    // Editing state
    @State private var editingAction: PadAction? = nil
    @State private var editName = ""
    @State private var editTerms = ""
    @State private var editWebhookURL = ""
    @State private var copiedKey = false
    @State private var terminalInput = ""
    @State private var editingMacroID: UUID? = nil
    @State private var editingRuleID: UUID? = nil
    @State private var editRuleName = ""
    @State private var editRuleAppFilter = ""
    @State private var editRuleContextContains = ""
    @State private var editRuleContextExcludes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    Text("[<]")
                        .font(SudoTheme.mono(size: 11))
                        .foregroundColor(SudoTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("back to main view")
                Spacer()
                Text("settings")
                    .font(SudoTheme.mono(size: 12, weight: .bold))
                    .foregroundColor(SudoTheme.text)
                Spacer()
                Circle()
                    .fill(engine.isConnected ? SudoTheme.accent : SudoTheme.error)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.top, 14)
            .padding(.bottom, 10)

            SudoDivider()

            // Mode banner — reminds the user which top-level mode is active
            HStack(spacing: 6) {
                Text("mode:")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                Text("[\(settings.appMode.label)]")
                    .font(SudoTheme.mono(size: 9, weight: .bold))
                    .foregroundColor(SudoTheme.accent)
                Text(settings.appMode.description)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 6)

            SudoDivider()

            // Scrollable sections
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 1. Button remapping
                    section {
                        SectionHeader("button remapping", isExpanded: sectionBinding("remap"))
                        if settings.expandedSections.contains("remap") { remapContent }
                    }

                    // 2. Auto-switch (includes per-app overrides)
                    section {
                        SectionHeader("auto-switch", isExpanded: sectionBinding("autoswitch"),
                                      badge: settings.autoSwitchEnabled ? "on" : nil)
                        if settings.expandedSections.contains("autoswitch") { autoSwitchContent }
                    }

                    // 3. Macros
                    section {
                        SectionHeader("macros", isExpanded: sectionBinding("macros"), count: settings.macros.count)
                        if settings.expandedSections.contains("macros") { macrosContent }
                    }

                    // 6. Auto-approve
                    section {
                        SectionHeader("auto-approve", isExpanded: sectionBinding("autoapprove"),
                                      badge: settings.autoApproveEnabled ? "on" : nil)
                        if settings.expandedSections.contains("autoapprove") { autoApproveContent }
                    }

                    // 7. Settings (toggles + hotkeys)
                    section {
                        SectionHeader("settings", isExpanded: sectionBinding("settings"))
                        if settings.expandedSections.contains("settings") { settingsContent }
                    }

                    // 8. Developer API
                    section {
                        SectionHeader("developer api", isExpanded: sectionBinding("api"),
                                      badge: apiServer.isRunning ? "on" : nil)
                        if settings.expandedSections.contains("api") { apiContent }
                    }

                    // 9. History
                    section {
                        SectionHeader("history", isExpanded: sectionBinding("history"), count: engine.actionLog.count)
                        if settings.expandedSections.contains("history") { historyContent }
                    }

                    // 10. Debug console
                    section {
                        SectionHeader("debug console", isExpanded: sectionBinding("debug"), count: debugLogger.entries.count)
                        if settings.expandedSections.contains("debug") { debugContent }
                    }

                    // 11. Plugins (conditional)
                    if pluginManager.loadedPlugins.count > 0 {
                        section {
                            SectionHeader("plugins", isExpanded: .constant(true), count: pluginManager.loadedPlugins.count)
                            ForEach(pluginManager.loadedPlugins) { plugin in
                                Text(plugin.name.lowercased())
                                    .font(SudoTheme.mono(size: 9))
                                    .foregroundColor(SudoTheme.text)
                            }
                        }
                    }

                    // 11. Terminal (dev only)
                    if settings.isDeveloperMode {
                        section {
                            SectionHeader("terminal", isExpanded: sectionBinding("terminal"),
                                          count: rebuilder.buildLog.isEmpty ? nil : rebuilder.buildLog.count)
                            if settings.expandedSections.contains("terminal") { terminalContent }
                        }
                    }
                }
            }

            SudoDivider()

            // Footer
            HStack(spacing: 8) {
                if settings.isDeveloperMode {
                    Button(rebuilder.isRebuilding ? rebuilder.status : "pull & rebuild") {
                        rebuilder.rebuild()
                    }
                    .buttonStyle(.plain)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(rebuilder.isRebuilding ? SudoTheme.textMuted : SudoTheme.accent)
                    .disabled(rebuilder.isRebuilding)
                    Text("·").font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.border)
                }
                Button("updates") { updater.checkForUpdates() }
                    .buttonStyle(.plain).font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.textMuted)
                Text("·").font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.border)
                Button("bug?") { BugReporter.shared.fileReport(engine: engine) }
                    .buttonStyle(.plain).font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.textMuted)
                Spacer()
                Button("quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.textMuted)
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .sudoBackground()
    }

    // MARK: - Section wrapper

    @ViewBuilder
    private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(.horizontal, SudoTheme.spacingMd)
        .padding(.vertical, 8)
        SudoDivider()
    }

    // MARK: - Settings toggles + hotkeys

    @ViewBuilder
    private var settingsContent: some View {
        SettingToggle(label: "search all apps", isOn: Binding(
            get: { engine.searchAllApps }, set: { engine.searchAllApps = $0 }
        ))
        SettingToggle(label: "sound feedback", isOn: $settings.soundEnabled)
        SettingToggle(label: "notify on failure", isOn: $settings.notifyOnFailure)
        SettingToggle(label: "launch at login", isOn: $settings.launchAtLogin)
        SettingToggle(label: "anonymous telemetry", isOn: $settings.telemetryEnabled)

        SudoDivider()

        // Debounce
        HStack {
            Text("debounce:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)
            Text("\(Int(settings.debounceDuration * 1000))ms")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.text)
                .frame(width: 36)
            Spacer()
            Button("-") {
                settings.debounceDuration = max(0.01, settings.debounceDuration - 0.01)
            }.font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
            Button("+") {
                settings.debounceDuration = min(0.5, settings.debounceDuration + 0.01)
            }.font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
            Button("reset") {
                settings.debounceDuration = 0.02
            }.font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
        }

        SudoDivider()

        Text("hotkey bindings:")
            .font(SudoTheme.mono(size: 9))
            .foregroundColor(SudoTheme.textMuted)

        ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
            let binding = settings.hotkeyBindings[action.rawValue]
            let keyCode = binding?["keyCode"] ?? 0
            let mods = binding?["modifiers"] ?? 0
            HStack {
                Text("\(action.buttonNumber)")
                    .font(SudoTheme.mono(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: action.buttonColorHex))
                    .frame(width: 12)
                Text(describeHotkey(keyCode: keyCode, modifiers: mods))
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.text)
                Spacer()
            }
        }

        Button("reset to defaults") { settings.resetHotkeyBindings() }
            .font(SudoTheme.mono(size: 8))
            .foregroundColor(SudoTheme.textMuted)
            .buttonStyle(.plain)
            .accessibilityLabel("reset hotkey bindings to defaults")
    }

    // MARK: - Button remapping

    @ViewBuilder
    private var remapContent: some View {
        // Quick presets
        Text("quick presets:")
            .font(SudoTheme.mono(size: 9))
            .foregroundColor(SudoTheme.textMuted)

        ForEach(ButtonPreset.all) { preset in
            Button(action: { preset.apply(); editingAction = nil }) {
                HStack {
                    Text(preset.name.lowercased())
                        .font(SudoTheme.mono(size: 9, weight: .bold))
                        .foregroundColor(SudoTheme.accent)
                    Spacer()
                    Text(preset.description)
                        .font(SudoTheme.mono(size: 7))
                        .foregroundColor(SudoTheme.textMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("apply \(preset.name.lowercased()) preset")
        }

        SudoDivider()

        // Per-button editor
        Text("custom mapping:")
            .font(SudoTheme.mono(size: 9))
            .foregroundColor(SudoTheme.textMuted)

        ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
            if editingAction == action {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("name").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted).frame(width: 32, alignment: .trailing)
                        TextField("", text: $editName).font(SudoTheme.mono(size: 9)).textFieldStyle(.plain).foregroundColor(SudoTheme.text)
                            .padding(2).overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
                    }
                    HStack(spacing: 4) {
                        Text("find").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted).frame(width: 32, alignment: .trailing)
                        TextField("", text: $editTerms).font(SudoTheme.mono(size: 9)).textFieldStyle(.plain).foregroundColor(SudoTheme.text)
                            .padding(2).overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        Button("save") {
                            settings.buttonNames[action.rawValue] = editName.isEmpty ? nil : editName
                            let terms = editTerms.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            settings.buttonSearchTerms[action.rawValue] = terms.isEmpty ? nil : terms
                            editingAction = nil
                        }.font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                        Button("reset") {
                            settings.buttonNames[action.rawValue] = nil
                            settings.buttonSearchTerms[action.rawValue] = nil
                            editingAction = nil
                        }.font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                        Button("cancel") { editingAction = nil }
                            .font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
                    }
                }
                .padding(6).overlay(Rectangle().stroke(SudoTheme.accent.opacity(0.3), lineWidth: 1))
            } else {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: action.buttonColorHex)).frame(width: 6, height: 6)
                    Text("\(action.buttonNumber)").font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.textMuted).frame(width: 12, alignment: .leading)
                    Text(action.displayName).font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.text)
                    Spacer()
                    Button("edit") {
                        editName = settings.buttonNames[action.rawValue] ?? action.defaultDisplayName
                        editTerms = (settings.buttonSearchTerms[action.rawValue] ?? action.defaultSearchTerms).joined(separator: ", ")
                        editingAction = action
                    }.font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Macros

    @ViewBuilder
    private var macrosContent: some View {
        ForEach(Array(settings.macros.enumerated()), id: \.element.id) { index, macro in
            VStack(alignment: .leading, spacing: 4) {
                // Header row
                HStack {
                    Text(macro.name.lowercased())
                        .font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.text)
                    Text("(\(macro.steps.count))")
                        .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted)
                    Spacer()
                    if let assigned = macro.assignedButton,
                       let action = PadAction.allCases.first(where: { $0.rawValue == assigned }) {
                        Text("btn \(action.buttonNumber)")
                            .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.accent)
                    }
                    if editingMacroID == macro.id {
                        Button("done") { editingMacroID = nil }
                            .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                    } else {
                        Button("edit") { editingMacroID = macro.id }
                            .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                        Button("del") { settings.macros.remove(at: index) }
                            .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                    }
                }

                // Inline editor
                if editingMacroID == macro.id {
                    VStack(alignment: .leading, spacing: 4) {
                        // Name field
                        HStack(spacing: 4) {
                            Text("name").font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.textMuted).frame(width: 36, alignment: .trailing)
                            TextField("macro name", text: Binding(
                                get: { settings.macros[index].name },
                                set: { settings.macros[index].name = $0 }
                            ))
                            .font(SudoTheme.mono(size: 8)).textFieldStyle(.plain).foregroundColor(SudoTheme.text)
                            .padding(2).overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
                        }

                        // Assign to button
                        HStack(spacing: 4) {
                            Text("button").font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.textMuted).frame(width: 36, alignment: .trailing)
                            ForEach(PadAction.physicalOrder, id: \.rawValue) { action in
                                let isAssigned = settings.macros[index].assignedButton == action.rawValue
                                Button("\(action.buttonNumber)") {
                                    settings.macros[index].assignedButton = isAssigned ? nil : action.rawValue
                                }
                                .font(SudoTheme.mono(size: 8, weight: isAssigned ? .bold : .regular))
                                .foregroundColor(isAssigned ? SudoTheme.accent : SudoTheme.textMuted)
                                .buttonStyle(.plain)
                                .frame(width: 18)
                            }
                            Button("none") { settings.macros[index].assignedButton = nil }
                                .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
                        }

                        // Steps list
                        Text("steps:").font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.textMuted)
                        ForEach(Array(macro.steps.enumerated()), id: \.element.id) { stepIdx, step in
                            HStack(spacing: 4) {
                                Text("\(stepIdx + 1).")
                                    .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.textMuted).frame(width: 14)
                                Text(step.padAction?.defaultDisplayName.lowercased() ?? step.action)
                                    .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.text)
                                Text("+ \(String(format: "%.1f", step.delayAfter))s")
                                    .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.textMuted)
                                Spacer()
                                Button("✕") {
                                    settings.macros[index].steps.remove(at: stepIdx)
                                }
                                .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                            }
                        }

                        // Add step buttons
                        HStack(spacing: 4) {
                            Text("add:").font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.textMuted)
                            ForEach(PadAction.physicalOrder, id: \.rawValue) { action in
                                Button(action.defaultDisplayName.lowercased().components(separatedBy: " ").first ?? action.rawValue) {
                                    let step = MacroStep(action: action, delayAfter: 1.0)
                                    settings.macros[index].steps.append(step)
                                }
                                .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
                }
            }
        }

        Button("+ add macro") {
            let macro = MacroSequence(name: "new macro", steps: [])
            settings.macros.append(macro)
            editingMacroID = macro.id
        }
        .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
        .accessibilityLabel("add macro")
    }

    // MARK: - Auto-approve

    @ViewBuilder
    private var autoApproveContent: some View {
        Text("[!] experimental — auto-presses approve when rules match")
            .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.error)
            .fixedSize(horizontal: false, vertical: true)
        SettingToggle(label: "enable auto-approve", isOn: Binding(
            get: { settings.autoApproveEnabled },
            set: { settings.autoApproveEnabled = $0; engine.startAutoApproveTimer() }
        ))

        ForEach(Array(settings.autoApproveRules.enumerated()), id: \.element.id) { index, rule in
            VStack(alignment: .leading, spacing: 4) {
                // Toggle + name row
                HStack {
                    SettingToggle(label: rule.name.lowercased(), isOn: Binding(
                        get: { settings.autoApproveRules[index].enabled },
                        set: { settings.autoApproveRules[index].enabled = $0 }
                    ))
                    Spacer()
                    if editingRuleID == rule.id {
                        Button("done") { editingRuleID = nil }
                            .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                    } else {
                        Button("edit") {
                            editingRuleID = rule.id
                            editRuleName = rule.name
                            editRuleAppFilter = rule.appFilter ?? ""
                            editRuleContextContains = rule.contextContains ?? ""
                            editRuleContextExcludes = rule.contextExcludes ?? ""
                        }
                        .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                        Button("del") {
                            settings.autoApproveRules.remove(at: index)
                        }
                        .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                    }
                }

                // Inline editor
                if editingRuleID == rule.id {
                    VStack(alignment: .leading, spacing: 3) {
                        ruleField("name", text: Binding(
                            get: { editRuleName },
                            set: { editRuleName = $0; settings.autoApproveRules[index].name = $0 }
                        ))
                        ruleField("app", text: Binding(
                            get: { editRuleAppFilter },
                            set: { editRuleAppFilter = $0; settings.autoApproveRules[index].appFilter = $0.isEmpty ? nil : $0 }
                        ), hint: "bundle id substring, blank = all")
                        ruleField("contains", text: Binding(
                            get: { editRuleContextContains },
                            set: { editRuleContextContains = $0; settings.autoApproveRules[index].contextContains = $0.isEmpty ? nil : $0 }
                        ), hint: "only if context has this text")
                        ruleField("excludes", text: Binding(
                            get: { editRuleContextExcludes },
                            set: { editRuleContextExcludes = $0; settings.autoApproveRules[index].contextExcludes = $0.isEmpty ? nil : $0 }
                        ), hint: "never if context has this text")
                    }
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
                }
            }
        }

        Button("+ add rule") {
            let rule = AutoApproveRule(name: "new rule")
            settings.autoApproveRules.append(rule)
            editingRuleID = rule.id
            editRuleName = rule.name
            editRuleAppFilter = ""
            editRuleContextContains = ""
            editRuleContextExcludes = ""
        }
        .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
        .accessibilityLabel("add auto-approve rule")
    }

    @ViewBuilder
    private func ruleField(_ label: String, text: Binding<String>, hint: String = "") -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.textMuted)
                .frame(width: 44, alignment: .trailing)
            TextField(hint, text: text)
                .font(SudoTheme.mono(size: 8)).textFieldStyle(.plain).foregroundColor(SudoTheme.text)
                .padding(2).overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
        }
    }

    // MARK: - Auto-Switch

    @ViewBuilder
    private var autoSwitchContent: some View {
        Text("automatically switches button preset when the focused app changes category")
            .font(SudoTheme.mono(size: 8))
            .foregroundColor(SudoTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)

        SettingToggle(label: "auto-switch on app focus", isOn: Binding(
            get: { settings.autoSwitchEnabled },
            set: { settings.autoSwitchEnabled = $0 }
        ))

        if let status = engine.autoSwitchStatus {
            Text(status)
                .font(SudoTheme.mono(size: 8))
                .foregroundColor(SudoTheme.accent)
        }

        if settings.autoSwitchEnabled {
            SudoDivider()

            Text("category → preset:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)

            ForEach(AppCategory.allCases.filter { $0 != .unknown }, id: \.rawValue) { category in
                let presetID = settings.categoryPresets[category.rawValue]
                let isActive = engine.currentCategory == category
                let currentPresetName = ButtonPreset.all.first(where: { $0.id == presetID })?.name.lowercased() ?? "none"

                HStack {
                    if isActive {
                        Text("●")
                            .font(SudoTheme.mono(size: 6))
                            .foregroundColor(SudoTheme.accent)
                            .frame(width: 10)
                    } else {
                        Spacer().frame(width: 10)
                    }
                    Text(category.displayName)
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(isActive ? SudoTheme.text : SudoTheme.textMuted)
                        .frame(width: 90, alignment: .leading)
                    Text("→")
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.border)
                    // Preset picker menu with current name as label
                    Menu {
                        ForEach(ButtonPreset.all) { preset in
                            Button(preset.name.lowercased()) {
                                settings.categoryPresets[category.rawValue] = preset.id
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(currentPresetName)
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.text)
                                .lineLimit(1)
                            Text("▾")
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.accent)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("change preset for \(category.displayName)")
                }
            }

            Button("reset all to defaults") {
                settings.categoryPresets = SudoSettings.defaultCategoryPresets()
            }
            .font(SudoTheme.mono(size: 8))
            .foregroundColor(SudoTheme.textMuted)
            .buttonStyle(.plain)
            .accessibilityLabel("reset category presets to defaults")

            SudoDivider()

            // Per-app overrides (takes priority over category)
            Text("per-app overrides:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)

            if !settings.appPresetOverrides.isEmpty {
                ForEach(Array(settings.appPresetOverrides.keys.sorted()), id: \.self) { bundleID in
                    let presetID = settings.appPresetOverrides[bundleID] ?? ""
                    let name = ButtonPreset.all.first(where: { $0.id == presetID })?.name.lowercased() ?? presetID
                    let shortName = bundleID.split(separator: ".").last.map(String.init)?.lowercased() ?? bundleID
                    HStack {
                        Text(shortName)
                            .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.text)
                        Text("→")
                            .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.border)
                        Text(name)
                            .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted)
                        Spacer()
                        Button("del") { settings.appPresetOverrides.removeValue(forKey: bundleID) }
                            .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                    }
                }
            }

            if let bid = engine.currentBundleID, bid != Bundle.main.bundleIdentifier {
                let shortName = bid.split(separator: ".").last.map(String.init)?.lowercased() ?? bid
                Button("+ override \(shortName) → current preset") {
                    // Save whichever preset is currently active for this specific app
                    if let lastPreset = engine.lastAppliedPresetID {
                        settings.appPresetOverrides[bid] = lastPreset
                    }
                }
                .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
            }
        }
    }

    // (Simple mode section removed — isSimpleMode badge still shows in MainView)

    // MARK: - Developer API

    @ViewBuilder
    private var apiContent: some View {
        SettingToggle(label: "enable local api", isOn: Binding(
            get: { settings.apiEnabled },
            set: { settings.apiEnabled = $0; if $0 { apiServer.start(engine: engine) } else { apiServer.stop() } }
        ))
        if settings.apiEnabled {
            HStack {
                Text("port: \(settings.apiPort)").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.text)
                Spacer()
                Text(apiServer.isRunning ? "running" : "stopped")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(apiServer.isRunning ? SudoTheme.accent : SudoTheme.error)
            }
            HStack {
                Text(settings.apiKey).font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.text).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(copiedKey ? "copied!" : "copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(settings.apiKey, forType: .string)
                    copiedKey = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedKey = false }
                }
                .font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                .accessibilityLabel("copy api key")
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historyContent: some View {
        if engine.actionLog.isEmpty {
            Text("no actions yet").font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.textMuted)
        } else {
            ForEach(engine.actionLog.prefix(20)) { entry in
                HStack(spacing: 6) {
                    Text(entry.succeeded ? "✓" : "✗").font(SudoTheme.mono(size: 9))
                        .foregroundColor(entry.succeeded ? SudoTheme.accent : SudoTheme.error).frame(width: 10)
                    Text(entry.timeString).font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted)
                    Text(entry.action).font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.text).lineLimit(1)
                    Spacer()
                    Text(entry.app).font(SudoTheme.mono(size: 7)).foregroundColor(SudoTheme.surface).lineLimit(1)
                }
            }
        }
    }

    // MARK: - Debug Console

    @ViewBuilder
    private var debugContent: some View {
        if debugLogger.entries.isEmpty {
            Text("no logs yet — press a button").font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.textMuted)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(debugLogger.entries) { entry in
                            HStack(alignment: .top, spacing: 4) {
                                let tf = Self.debugTimeFormatter
                                Text(tf.string(from: entry.timestamp))
                                    .font(SudoTheme.mono(size: 7))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 55, alignment: .leading)
                                Text(entry.message)
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(
                                        entry.message.hasPrefix("ERROR") ? SudoTheme.error :
                                        entry.message.hasPrefix("OK") ? SudoTheme.accent :
                                        SudoTheme.text
                                    )
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 180)
                .onChange(of: debugLogger.entries.count) { _ in
                    if let last = debugLogger.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            HStack {
                Button("clear") { debugLogger.clear() }
                    .buttonStyle(.plain)
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
                Spacer()
                Text("\(debugLogger.entries.count) entries")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
            }
        }
    }

    private static let debugTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Terminal

    @ViewBuilder
    private var terminalContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(rebuilder.buildLog.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(
                                line.hasPrefix("$") ? SudoTheme.accent :
                                line.hasPrefix("---") ? SudoTheme.textMuted :
                                line.contains("error") || line.contains("failed") ? SudoTheme.error :
                                line.contains("warning") ? SudoTheme.warning :
                                SudoTheme.text
                            )
                            .textSelection(.enabled)
                            .id(idx)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .padding(4)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
            .onChange(of: rebuilder.buildLog.count) { _ in
                if let last = rebuilder.buildLog.indices.last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }

        HStack(spacing: 4) {
            Text("$").font(SudoTheme.mono(size: 9)).foregroundColor(SudoTheme.accent)
            TextField("command...", text: $terminalInput)
                .font(SudoTheme.mono(size: 9)).textFieldStyle(.plain).foregroundColor(SudoTheme.text)
                .onSubmit {
                    let cmd = terminalInput.trimmingCharacters(in: .whitespaces)
                    guard !cmd.isEmpty else { return }
                    terminalInput = ""
                    rebuilder.runCommand(cmd)
                }
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))

        HStack(spacing: 8) {
            Button("copy log") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rebuilder.buildLog.joined(separator: "\n"), forType: .string)
            }.font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
            Button("clear") { rebuilder.clearLog() }
                .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

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
        case 122: keyName = "F1"; case 120: keyName = "F2"
        case 99: keyName = "F3"; case 118: keyName = "F4"
        default: keyName = "key\(keyCode)"
        }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }
}

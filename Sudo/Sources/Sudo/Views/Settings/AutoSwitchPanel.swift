import SwiftUI

/// Auto-switch settings: master toggle, category → preset table, and
/// per-app overrides. The popover shows the toggle only.
struct AutoSwitchPanel: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject private var settings = SudoSettings.shared

    var body: some View {
        SettingsPanelScaffold(
            title: "auto-switch",
            subtitle: "automatically swap button presets when the focused app changes category."
        ) {
            SettingToggle(label: "auto-switch on app focus", isOn: Binding(
                get: { settings.autoSwitchEnabled },
                set: { settings.autoSwitchEnabled = $0 }
            ))

            if let status = engine.autoSwitchStatus {
                Text(status)
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.accent)
            }

            if settings.autoSwitchEnabled {
                SudoDivider()
                sectionHeader("category → preset")
                categoryTable
                Button("reset all to defaults") {
                    settings.categoryPresets = SudoSettings.defaultCategoryPresets()
                }
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.textMuted)
                .buttonStyle(.plain)
                .accessibilityLabel("reset category presets to defaults")

                SudoDivider()
                sectionHeader("per-app overrides")
                Text("overrides take priority over the category mapping above.")
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.appPresetOverrides.isEmpty {
                    Text("no overrides yet.")
                        .font(SudoTheme.body)
                        .foregroundColor(SudoTheme.textMuted)
                } else {
                    ForEach(Array(settings.appPresetOverrides.keys.sorted()), id: \.self) { bundleID in
                        let presetID = settings.appPresetOverrides[bundleID] ?? ""
                        let name = ButtonPreset.all.first(where: { $0.id == presetID })?.name.lowercased() ?? presetID
                        let shortName = bundleID.split(separator: ".").last.map(String.init)?.lowercased() ?? bundleID
                        HStack(spacing: 10) {
                            Text(shortName).font(SudoTheme.body).foregroundColor(SudoTheme.text)
                            Text("→").font(SudoTheme.caption).foregroundColor(SudoTheme.border)
                            Text(name).font(SudoTheme.body).foregroundColor(SudoTheme.textMuted)
                            Spacer()
                            Button("remove") { settings.appPresetOverrides.removeValue(forKey: bundleID) }
                                .font(SudoTheme.caption).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                        }
                    }
                }

                if let bid = engine.currentBundleID, bid != Bundle.main.bundleIdentifier {
                    let shortName = bid.split(separator: ".").last.map(String.init)?.lowercased() ?? bid
                    Button("+ override \(shortName) → current preset") {
                        if let lastPreset = engine.lastAppliedPresetID {
                            settings.appPresetOverrides[bid] = lastPreset
                        }
                    }
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var categoryTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(AppCategory.allCases.filter { $0 != .unknown }, id: \.rawValue) { category in
                let presetID = settings.categoryPresets[category.rawValue]
                let isActive = engine.currentCategory == category
                let currentPresetName = ButtonPreset.all.first(where: { $0.id == presetID })?.name.lowercased() ?? "none"

                HStack(spacing: 10) {
                    Text(isActive ? "●" : "○")
                        .font(SudoTheme.code(size: 11))
                        .foregroundColor(isActive ? SudoTheme.accent : SudoTheme.border)
                        .frame(width: 14)
                    Text(category.displayName)
                        .font(SudoTheme.body)
                        .foregroundColor(isActive ? SudoTheme.text : SudoTheme.textMuted)
                        .frame(width: 160, alignment: .leading)
                    Text("→").font(SudoTheme.caption).foregroundColor(SudoTheme.border)
                    Menu {
                        ForEach(ButtonPreset.all) { preset in
                            Button(preset.name.lowercased()) {
                                settings.categoryPresets[category.rawValue] = preset.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentPresetName)
                                .font(SudoTheme.body)
                                .foregroundColor(SudoTheme.text)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(SudoTheme.accent)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("change preset for \(category.displayName)")
                    Spacer()
                }
                .padding(.vertical, 1)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SudoTheme.heading)
            .foregroundColor(SudoTheme.text)
    }
}

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
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.accent)
            }

            if settings.autoSwitchEnabled {
                SudoDivider()
                sectionHeader("category → preset")
                categoryTable
                Button("reset all to defaults") {
                    settings.categoryPresets = SudoSettings.defaultCategoryPresets()
                }
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(SudoTheme.textMuted)
                .buttonStyle(.plain)
                .accessibilityLabel("reset category presets to defaults")

                SudoDivider()
                sectionHeader("per-app overrides")
                Text("overrides take priority over the category mapping above.")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.appPresetOverrides.isEmpty {
                    Text("no overrides yet.")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.textMuted)
                } else {
                    ForEach(Array(settings.appPresetOverrides.keys.sorted()), id: \.self) { bundleID in
                        let presetID = settings.appPresetOverrides[bundleID] ?? ""
                        let name = ButtonPreset.all.first(where: { $0.id == presetID })?.name.lowercased() ?? presetID
                        let shortName = bundleID.split(separator: ".").last.map(String.init)?.lowercased() ?? bundleID
                        HStack(spacing: 8) {
                            Text(shortName).font(SudoTheme.mono(size: 11)).foregroundColor(SudoTheme.text)
                            Text("→").font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.border)
                            Text(name).font(SudoTheme.mono(size: 11)).foregroundColor(SudoTheme.textMuted)
                            Spacer()
                            Button("remove") { settings.appPresetOverrides.removeValue(forKey: bundleID) }
                                .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
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
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var categoryTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AppCategory.allCases.filter { $0 != .unknown }, id: \.rawValue) { category in
                let presetID = settings.categoryPresets[category.rawValue]
                let isActive = engine.currentCategory == category
                let currentPresetName = ButtonPreset.all.first(where: { $0.id == presetID })?.name.lowercased() ?? "none"

                HStack(spacing: 8) {
                    Text(isActive ? "●" : "○")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(isActive ? SudoTheme.accent : SudoTheme.border)
                        .frame(width: 12)
                    Text(category.displayName)
                        .font(SudoTheme.mono(size: 11))
                        .foregroundColor(isActive ? SudoTheme.text : SudoTheme.textMuted)
                        .frame(width: 140, alignment: .leading)
                    Text("→").font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.border)
                    Menu {
                        ForEach(ButtonPreset.all) { preset in
                            Button(preset.name.lowercased()) {
                                settings.categoryPresets[category.rawValue] = preset.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentPresetName)
                                .font(SudoTheme.mono(size: 10))
                                .foregroundColor(SudoTheme.text)
                                .lineLimit(1)
                            Text("▾").font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent)
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
        Text("> \(title)")
            .font(SudoTheme.mono(size: 10, weight: .medium))
            .foregroundColor(SudoTheme.textMuted)
            .tracking(0.5)
    }
}

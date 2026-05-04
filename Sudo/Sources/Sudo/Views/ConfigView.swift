import SwiftUI

/// The popover settings view — slim, status-first.
///
/// Heavy editors (macros, auto-approve rules, hotkey bindings, debug
/// console, terminal, API key, history) live in `SettingsWindow`. The
/// popover here is for at-a-glance status + the small set of quick
/// toggles users flip during normal use.
struct ConfigView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var apiServer: LocalAPIServer
    @ObservedObject var settings = SudoSettings.shared
    @ObservedObject var flasher = FirmwareFlasher.shared
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            SudoDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    deviceCard
                    SudoDivider()
                    quickToggles
                    SudoDivider()
                    automationCard
                    SudoDivider()
                    openSettingsCTA
                }
            }
            SudoDivider()
            footer
        }
        .frame(width: SudoTheme.popoverWidth)
        .sudoBackground()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Text("[<]")
                    .font(SudoTheme.code(size: 12, weight: .semibold))
                    .foregroundColor(SudoTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("back to main view")
            Spacer()
            Text("settings")
                .font(SudoTheme.heading)
                .foregroundColor(SudoTheme.text)
            Spacer()
            Circle()
                .fill(engine.isConnected ? SudoTheme.accent : SudoTheme.error)
                .frame(width: 6, height: 6)
                .help(engine.isConnected ? "connected" : "no accessibility permission")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Device card

    @ViewBuilder
    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("device", systemImage: "cable.connector")
            HStack(spacing: 8) {
                Circle()
                    .fill(flasher.deviceConnectionLabel.colour)
                    .frame(width: 7, height: 7)
                Text(flasher.deviceConnectionLabel.label)
                    .font(SudoTheme.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            HStack {
                switch flasher.state {
                case .idle:
                    Button("detect device") { flasher.detectDevice() }
                        .controlSize(.small).buttonStyle(.bordered)
                case .detectingDevice:
                    ProgressView().controlSize(.small)
                    Text("scanning…")
                        .font(SudoTheme.body).foregroundStyle(.secondary)
                case .readyForConfig:
                    Button("flash device") { flasher.flashFirmwareAndConfig() }
                        .controlSize(.small).buttonStyle(.borderedProminent).tint(SudoTheme.accent)
                case .readyForFirmware:
                    Button("install + flash") { flasher.flashFirmwareAndConfig() }
                        .controlSize(.small).buttonStyle(.borderedProminent).tint(SudoTheme.accent)
                case .flashing:
                    ProgressView(value: flasher.progress)
                        .progressViewStyle(.linear).tint(SudoTheme.accent)
                    Text("\(Int(flasher.progress * 100))%")
                        .font(SudoTheme.code(size: 11))
                        .foregroundStyle(.secondary).monospacedDigit()
                case .success:
                    Text("flashed ✓")
                        .font(SudoTheme.bodyEmphasized)
                        .foregroundStyle(SudoTheme.accent)
                    Spacer()
                    Button("ok") { flasher.reset() }
                        .controlSize(.small).buttonStyle(.bordered)
                case .error(let msg):
                    Text(msg)
                        .font(SudoTheme.body)
                        .foregroundStyle(SudoTheme.error)
                        .lineLimit(2)
                    Button("retry") { flasher.reset(); flasher.detectDevice() }
                        .controlSize(.small).buttonStyle(.bordered)
                }
            }
            if !flasher.phase.isEmpty {
                Text(flasher.phase)
                    .font(SudoTheme.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Quick toggles

    @ViewBuilder
    private var quickToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader("quick toggles", systemImage: "switch.2")
            SettingToggle(label: "sound feedback", isOn: $settings.soundEnabled)
            SettingToggle(label: "notify on failure", isOn: $settings.notifyOnFailure)
            SettingToggle(label: "launch at login", isOn: $settings.launchAtLogin)
            SettingToggle(label: "search all apps", isOn: Binding(
                get: { engine.searchAllApps }, set: { engine.searchAllApps = $0 }
            ))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Automation card

    @ViewBuilder
    private var automationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader("automation", systemImage: "wand.and.stars")
            SettingToggle(label: "auto-switch on app focus", isOn: Binding(
                get: { settings.autoSwitchEnabled },
                set: { settings.autoSwitchEnabled = $0 }
            ))
            if let status = engine.autoSwitchStatus {
                Text(status)
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.accent)
            }
            SettingToggle(label: "auto-approve (experimental)", isOn: Binding(
                get: { settings.autoApproveEnabled },
                set: { settings.autoApproveEnabled = $0; engine.startAutoApproveTimer() }
            ))
            HStack {
                Spacer()
                Button("edit rules + categories…") { openSettings(.autoSwitch) }
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Open settings CTA

    @ViewBuilder
    private var openSettingsCTA: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("more", systemImage: "rectangle.expand.vertical")
            Button(action: { openSettings(nil) }) {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("open full settings…")
                            .font(SudoTheme.bodyEmphasized)
                        Text("macros · hotkeys · history · developer")
                            .font(SudoTheme.caption)
                            .foregroundColor(SudoTheme.textMuted)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundStyle(SudoTheme.accent)
                }
                .padding(SudoTheme.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius)
                        .fill(SudoTheme.accent.opacity(0.10))
                )
                .foregroundStyle(SudoTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("open full settings window")

            HStack(spacing: 8) {
                quickLink("buttons", icon: "square.grid.2x2") { EditPresetWindowManager.shared.open() }
                quickLink("macros", icon: "list.number") { openSettings(.macros) }
                quickLink("history", icon: "clock") { openSettings(.history) }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button("updates") { updater.checkForUpdates() }
                    .buttonStyle(.plain).font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted)
                Text("·").font(SudoTheme.caption).foregroundColor(SudoTheme.border)
                Button("bug?") { BugReporter.shared.fileReport(engine: engine) }
                    .buttonStyle(.plain).font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted)
                Spacer()
                Button("quit") { AppLifecycle.terminate() }
                    .buttonStyle(.plain).font(SudoTheme.caption).foregroundColor(SudoTheme.error)
            }
            HStack(spacing: 8) {
                Text("[sudo]")
                    .font(SudoTheme.code(size: 10, weight: .semibold))
                    .foregroundColor(SudoTheme.accent)
                Text("v\(OTAUpdater.currentVersion)")
                    .font(SudoTheme.code(size: 10))
                    .foregroundColor(SudoTheme.textMuted)
                if updater.updateAvailable {
                    Text("·")
                        .font(SudoTheme.code(size: 10))
                        .foregroundColor(SudoTheme.border)
                    Button(action: { updater.checkForUpdates() }) {
                        Text("v\(updater.latestVersion) available ↑")
                            .font(SudoTheme.code(size: 10, weight: .medium))
                            .foregroundColor(SudoTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("install update v\(updater.latestVersion)")
                }
                Spacer()
                Button("about") { openSettings(.about) }
                    .buttonStyle(.plain)
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func cardHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(SudoTheme.accent)
            Text(title)
                .font(SudoTheme.heading)
                .foregroundColor(SudoTheme.text)
            Spacer()
        }
    }

    @ViewBuilder
    private func quickLink(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(SudoTheme.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SudoTheme.border.opacity(0.4), lineWidth: 0.5))
            .foregroundStyle(SudoTheme.textMuted)
        }
        .buttonStyle(.plain)
    }

    private func openSettings(_ section: SettingsWindow.Section?) {
        SettingsWindowManager.shared.open(
            engine: engine,
            updater: updater,
            rebuilder: rebuilder,
            apiServer: apiServer,
            initialSection: section
        )
    }
}

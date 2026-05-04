import SwiftUI
import AppKit

/// About + version info + links. The single source of truth for the
/// app version stays `OTAUpdater.currentVersion`; this panel just
/// presents it nicely and surfaces an inline update button.
struct AboutPanel: View {
    @ObservedObject var updater: OTAUpdater
    @ObservedObject private var settings = SudoSettings.shared

    var body: some View {
        SettingsPanelScaffold(title: "about") {
            HStack(alignment: .top, spacing: 20) {
                brandMark
                VStack(alignment: .leading, spacing: 4) {
                    Text("[sudo]")
                        .font(SudoTheme.mono(size: 22, weight: .bold))
                        .foregroundColor(SudoTheme.accent)
                    Text("a 4-button macropad that does the right thing per app")
                        .font(SudoTheme.mono(size: 11))
                        .foregroundColor(SudoTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    versionLine
                }
                Spacer()
            }

            SudoDivider()

            sectionHeader("links")
            VStack(alignment: .leading, spacing: 6) {
                linkRow("github.com/ibrue/sudo-app", url: "https://github.com/ibrue/sudo-app", system: "chevron.left.forwardslash.chevron.right")
                linkRow("sudo.supply", url: "https://sudo.supply", system: "globe")
                linkRow("file a bug report", url: "https://github.com/ibrue/sudo-app/issues/new", system: "ant")
            }

            SudoDivider()

            sectionHeader("environment")
            HStack(spacing: 8) {
                Image(systemName: settings.isDeveloperMode ? "hammer.fill" : "hammer")
                    .font(.system(size: 11))
                    .foregroundStyle(settings.isDeveloperMode ? SudoTheme.accent : SudoTheme.textMuted)
                Text(settings.isDeveloperMode ? "developer mode active" : "developer mode off")
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.text)
                Spacer()
            }
            Text("auto-enabled when `~/sudo-app/build.sh` exists. unlocks the terminal, pull & rebuild, and the developer panel.")
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(SudoTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            SudoDivider()

            HStack(spacing: 12) {
                Spacer()
                Text("© 2026 ibrue · MIT")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
            }
        }
    }

    @ViewBuilder
    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(SudoTheme.accent.opacity(0.12))
                .frame(width: 64, height: 64)
            Text("[]")
                .font(SudoTheme.mono(size: 26, weight: .bold))
                .foregroundColor(SudoTheme.accent)
        }
    }

    @ViewBuilder
    private var versionLine: some View {
        HStack(spacing: 8) {
            Text("v\(OTAUpdater.currentVersion)")
                .font(SudoTheme.mono(size: 12, weight: .medium))
                .foregroundColor(SudoTheme.text)
            Button("check for updates") { updater.checkForUpdates() }
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(SudoTheme.accent)
                .buttonStyle(.plain)
            if updater.updateAvailable {
                Button(action: { updater.checkForUpdates() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("v\(updater.latestVersion) available")
                    }
                    .font(SudoTheme.mono(size: 10, weight: .medium))
                    .foregroundColor(SudoTheme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(SudoTheme.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("install update v\(updater.latestVersion)")
            }
        }
    }

    @ViewBuilder
    private func linkRow(_ title: String, url: String, system: String) -> some View {
        Button(action: {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }) {
            HStack(spacing: 8) {
                Image(systemName: system)
                    .font(.system(size: 11))
                    .foregroundStyle(SudoTheme.accent)
                    .frame(width: 16)
                Text(title)
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(SudoTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text("> \(title)")
            .font(SudoTheme.mono(size: 10, weight: .medium))
            .foregroundColor(SudoTheme.textMuted)
            .tracking(0.5)
    }
}

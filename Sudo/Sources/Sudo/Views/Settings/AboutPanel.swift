import SwiftUI

/// About + version info + links. The single source of truth for the
/// app version stays `OTAUpdater.currentVersion`; this panel just
/// presents it nicely and surfaces an inline update button.
struct AboutPanel: View {
    @ObservedObject var updater: OTAUpdater
    @ObservedObject private var settings = SudoSettings.shared

    var body: some View {
        SettingsPanelScaffold(title: "about") {
            HStack(alignment: .top, spacing: 24) {
                brandMark
                VStack(alignment: .leading, spacing: 6) {
                    Text("[sudo]")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(SudoTheme.accent)
                    Text("a 4-button macropad that does the right thing per app")
                        .font(SudoTheme.body)
                        .foregroundColor(SudoTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    versionLine
                        .padding(.top, 4)
                }
                Spacer()
            }

            SudoDivider()

            sectionHeader("links")
            VStack(alignment: .leading, spacing: 8) {
                linkRow("github.com/ibrue/sudo-app", url: "https://github.com/ibrue/sudo-app", system: "chevron.left.forwardslash.chevron.right")
                linkRow("sudo.supply", url: "https://sudo.supply", system: "globe")
                linkRow("file a bug report", url: "https://github.com/ibrue/sudo-app/issues/new", system: "ant")
            }

            SudoDivider()

            sectionHeader("environment")
            HStack(spacing: 10) {
                Image(systemName: settings.isDeveloperMode ? "hammer.fill" : "hammer")
                    .font(.system(size: 13))
                    .foregroundStyle(settings.isDeveloperMode ? SudoTheme.accent : SudoTheme.textMuted)
                Text(settings.isDeveloperMode ? "developer mode active" : "developer mode off")
                    .font(SudoTheme.body)
                    .foregroundColor(SudoTheme.text)
                Spacer()
            }
            Text("auto-enabled when `~/sudo-app/build.sh` exists. unlocks the terminal, pull & rebuild, and the developer panel.")
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            SudoDivider()

            HStack(spacing: 12) {
                Spacer()
                Text("© 2026 ibrue · MIT")
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.textMuted)
            }
        }
    }

    @ViewBuilder
    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(SudoTheme.accent.opacity(0.12))
                .frame(width: 76, height: 76)
            Text("[]")
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundColor(SudoTheme.accent)
        }
    }

    @ViewBuilder
    private var versionLine: some View {
        HStack(spacing: 10) {
            Text("v\(OTAUpdater.currentVersion)")
                .font(SudoTheme.code(size: 13, weight: .medium))
                .foregroundColor(SudoTheme.text)
            Button("check for updates") { updater.checkForUpdates() }
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.accent)
                .buttonStyle(.plain)
            if updater.updateAvailable {
                Button(action: { updater.checkForUpdates() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("v\(updater.latestVersion) available")
                    }
                    .font(SudoTheme.caption.weight(.medium))
                    .foregroundColor(SudoTheme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(SudoTheme.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("install update v\(updater.latestVersion)")
            }
        }
    }

    @ViewBuilder
    private func linkRow(_ title: String, url: String, system: String) -> some View {
        Button(action: { URLOpener.open(url) }) {
            HStack(spacing: 10) {
                Image(systemName: system)
                    .font(.system(size: 13))
                    .foregroundStyle(SudoTheme.accent)
                    .frame(width: 18)
                Text(title)
                    .font(SudoTheme.body)
                    .foregroundColor(SudoTheme.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(SudoTheme.textMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SudoTheme.heading)
            .foregroundColor(SudoTheme.text)
    }
}

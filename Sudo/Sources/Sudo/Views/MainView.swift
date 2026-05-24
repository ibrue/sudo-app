import SwiftUI

/// The popover. Header strip + status card + 4 button cards.
///
/// Anything heavier (flash, settings, presets, updates, bug report, quit)
/// lives behind the gear button → a `Menu` that either opens the Settings
/// window directly or fires a one-off action. ConfigView (the old secondary
/// popover that duplicated settings state) was deleted as part of the v2
/// redesign — single source of truth lives in the Settings window.
struct MainView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var apiServer: LocalAPIServer
    @ObservedObject var settings: SudoSettings = .shared
    @ObservedObject private var flasher: FirmwareFlasher = .shared
    @ObservedObject private var padConsole: PadConsoleReader = .shared

    var body: some View {
        VStack(spacing: 0) {
            header
            statusCard

            if !engine.isConnected {
                permissionBanner
            }

            if let mcp = engine.pendingMCPRequest {
                mcpOverlay(prompt: mcp)
            }

            buttonCards
        }
        .padding(.bottom, SudoTheme.popoverVPadding)
        .frame(width: SudoTheme.popoverWidth)
        .sudoBackground()
        .animation(.smooth, value: engine.isConnected)
        .animation(.smooth, value: engine.lastResult)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: .inline)

            Text("v\(OTAUpdater.currentVersion)")
                .font(SudoTheme.code(size: 10))
                .foregroundStyle(.secondary)
                .help("sudo \(OTAUpdater.currentVersion)")

            if updater.updateAvailable {
                Button(action: { updater.checkForUpdates() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 12))
                        .foregroundStyle(SudoTheme.accent)
                }
                .buttonStyle(.plain)
                .help("update available: v\(updater.latestVersion)")
            }

            Spacer()

            StatusDot(isOn: engine.isConnected)
                .help(engine.isConnected ? "hotkeys ready" : "accessibility permission required")

            gearMenu
        }
        .padding(.horizontal, SudoTheme.popoverHPadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var gearMenu: some View {
        Menu {
            Button("settings…") { openSettings(.general) }
                .keyboardShortcut(",", modifiers: [.command])
            Button("edit buttons") { openSettings(.buttons) }
            Button("edit macros") { openSettings(.macros) }
            Divider()
            Button("flash firmware to pad…") {
                FirmwareFlasher.shared.flashFirmwareAndConfig(settings: settings)
            }
            Divider()
            if updater.updateAvailable {
                Button("install v\(updater.latestVersion)") { updater.checkForUpdates() }
            } else {
                Button("check for updates") { updater.checkForUpdates() }
            }
            Button("report bug…") { BugReporter.shared.fileReport(engine: engine) }
            Button("about") { openSettings(.about) }
            Divider()
            Button("quit sudo") { AppLifecycle.terminate() }
                .keyboardShortcut("q", modifiers: [.command])
        } label: {
            Image(systemName: "gearshape")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("settings & actions")
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Line 1: target app + mode pill + quick-toggles menu
            HStack(spacing: 8) {
                Image(systemName: "app.dashed")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(engine.targetAppName ?? engine.detectedApp)
                    .font(SudoTheme.bodyEmphasized)
                    .lineLimit(1)
                    .truncationMode(.middle)
                modePill
                Spacer()
                quickTogglesMenu
            }

            HStack(spacing: 6) {
                Image(systemName: deviceIsPresent ? "keyboard.fill" : "keyboard")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 10))
                    .foregroundStyle(deviceIsPresent ? SudoTheme.accent : .secondary)
                Text(deviceStatusText)
                    .font(SudoTheme.caption)
                    .foregroundStyle(deviceIsPresent ? SudoTheme.accent : .secondary)
                    .lineLimit(1)
            }

            // Line 2: last action + relative timestamp
            if let entry = engine.actionLog.first {
                HStack(spacing: 6) {
                    Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 10))
                        .foregroundStyle(entry.succeeded ? SudoTheme.accent : SudoTheme.error)
                    Text(entry.action.lowercased())
                        .font(SudoTheme.caption)
                        .foregroundStyle(.secondary)
                    Text("in \(entry.app.lowercased())")
                        .font(SudoTheme.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(timeAgo(entry.timestamp))
                        .font(SudoTheme.code(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            } else {
                Text("waiting for input…")
                    .font(SudoTheme.caption)
                    .foregroundStyle(.tertiary)
            }

            // Line 3 (conditional): auto-switch transient status
            if let autoSwitch = engine.autoSwitchStatus {
                Text(autoSwitch)
                    .font(SudoTheme.caption)
                    .foregroundStyle(SudoTheme.accent)
                    .transition(.opacity)
            }
        }
        .padding(SudoTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.horizontal, SudoTheme.popoverHPadding)
        .padding(.bottom, SudoTheme.popoverSectionGap)
    }

    private var deviceIsPresent: Bool {
        flasher.hidConnected || padConsole.isConnected
    }

    private var deviceStatusText: String {
        if flasher.hidConnected {
            return padConsole.padReady ? "pad connected and ready" : "pad connected"
        }
        if padConsole.isConnected {
            return "pad console connected"
        }
        return "pad not detected"
    }

    private var modePill: some View {
        Menu {
            Picker("mode", selection: $settings.appMode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 3) {
                Text(settings.appMode.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(SudoTheme.code(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(SudoTheme.cardSurface, in: RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(settings.appMode.description)
    }

    private var quickTogglesMenu: some View {
        Menu {
            Toggle("play sound on press", isOn: $settings.soundEnabled)
            Toggle("notify on failure", isOn: $settings.notifyOnFailure)
            Toggle("launch at login", isOn: $settings.launchAtLogin)
            Toggle("search all apps", isOn: $settings.searchAllApps)
            Divider()
            Toggle("auto-switch presets", isOn: $settings.autoSwitchEnabled)
            Toggle("auto-approve rules", isOn: Binding(
                get: { settings.autoApproveEnabled },
                set: { settings.autoApproveEnabled = $0; engine.startAutoApproveTimer() }
            ))
        } label: {
            Image(systemName: "ellipsis")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("quick toggles")
    }

    // MARK: - Button cards

    private var buttonCards: some View {
        VStack(spacing: 8) {
            ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                buttonCard(for: action)
            }
        }
        .padding(.horizontal, SudoTheme.popoverHPadding)
        .padding(.top, SudoTheme.popoverSectionGap)
    }

    @ViewBuilder
    private func buttonCard(for action: PadAction) -> some View {
        let tint = action.buttonColor
        let isLastTouched = engine.lastAction.lowercased()
            .contains(action.displayName.lowercased().components(separatedBy: " ").first ?? "")

        Button(action: { engine.triggerAction(action) }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.35))
                        .frame(width: 28, height: 28)
                    Circle()
                        .strokeBorder(tint.opacity(0.5), lineWidth: 1)
                        .frame(width: 28, height: 28)
                    Text("\(action.buttonNumber)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint)
                }

                Text(action.displayName)
                    .font(SudoTheme.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: SudoTheme.buttonCardHeight)
            .background(
                RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isLastTouched ? tint : Color.primary.opacity(0.08),
                        lineWidth: isLastTouched ? SudoTheme.ringWidthEmphasized : SudoTheme.ringWidth
                    )
            )
            .shadow(color: isLastTouched ? tint.opacity(0.20) : .clear, radius: 10, y: 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("test press") { engine.triggerAction(action) }
            Button("rename…") { openSettings(.buttons) }
        }
    }

    // MARK: - Permission banner (only when accessibility is missing)

    private var permissionBanner: some View {
        InlineBanner(
            .danger,
            title: "accessibility permission required",
            message: "grant accessibility, then relaunch sudo. if it already looks granted, reset permissions first."
        ) {
            Button("open settings") { URLOpener.openAccessibilitySettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color(nsColor: .systemRed))

            HStack(spacing: 6) {
                Button("relaunch") { AppLifecycle.relaunch() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("reset permissions") { AppLifecycle.resetPrivacyPermissionsAndRelaunch() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("re-check") { engine.checkAndConnect() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, SudoTheme.popoverHPadding)
        .padding(.bottom, SudoTheme.popoverSectionGap)
    }

    // MARK: - MCP overlay (when an MCP request is pending approval)

    @ViewBuilder
    private func mcpOverlay(prompt: String) -> some View {
        InlineBanner(
            .info,
            title: "mcp approval requested",
            message: prompt
        ) {
            HStack(spacing: 6) {
                Button("approve") { engine.resolveMCPRequest(approved: true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.accentColor)
                Button("reject") { engine.resolveMCPRequest(approved: false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, SudoTheme.popoverHPadding)
        .padding(.bottom, SudoTheme.popoverSectionGap)
    }

    // MARK: - Helpers

    private func openSettings(_ section: SettingsWindow.Section) {
        SettingsWindowManager.shared.open(
            engine: engine,
            updater: updater,
            rebuilder: rebuilder,
            apiServer: apiServer,
            initialSection: section
        )
    }

    /// Compact "3s/2m/1h/2d" relative time.
    private func timeAgo(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 5  { return "now" }
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d"
    }
}

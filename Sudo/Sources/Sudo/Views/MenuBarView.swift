import SwiftUI

struct MenuBarView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var apiServer: LocalAPIServer
    @ObservedObject var settings = SudoSettings.shared
    @ObservedObject var pluginManager = PluginManager.shared
    @State private var showTestPanel = false
    @State private var showRemapPanel = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showAPI = false
    @State private var editWebhookURL = ""
    @State private var copiedKey = false
    @State private var editingAction: PadAction? = nil
    @State private var editName = ""
    @State private var editTerms = ""
    @State private var showAppProfiles = false
    @State private var showMacros = false
    @State private var editingMacroID: UUID? = nil
    @State private var showAutoApprove = false
    @State private var editingRuleID: UUID? = nil
    @State private var editRuleName = ""
    @State private var editRuleAppFilter = ""
    @State private var editRuleContextContains = ""
    @State private var editRuleContextExcludes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("[sudo]")
                    .font(SudoTheme.mono(size: 14, weight: .bold))
                    .foregroundColor(SudoTheme.accent)
                Spacer()
                Circle()
                    .fill(engine.isConnected ? SudoTheme.accent : SudoTheme.error)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Permission warnings
            if !engine.isConnected {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("!")
                            .font(SudoTheme.mono(size: 10, weight: .bold))
                            .foregroundColor(SudoTheme.bg)
                            .frame(width: 16, height: 16)
                            .background(SudoTheme.error)
                        Text("accessibility permission required")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.error)
                    }
                    Text("System Settings → Privacy & Security → Accessibility → enable Sudo")
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("After enabling, quit and reopen the app.")
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.textMuted)
                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }) {
                        Text("[ OPEN SYSTEM SETTINGS ]")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .overlay(
                                Rectangle()
                                    .stroke(SudoTheme.accent, lineWidth: SudoTheme.borderWidth)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.bottom, 8)
            }

            divider

            // Status
            VStack(alignment: .leading, spacing: 6) {
                statusRow(label: "app", value: engine.detectedApp)
                statusRow(label: "last", value: engine.lastAction)
                if !engine.lastMethod.isEmpty {
                    statusRow(label: "via", value: engine.lastMethod)
                }
                if !engine.lastContext.isEmpty {
                    statusRow(label: "ctx", value: engine.lastContext)
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            divider

            // Button map
            VStack(alignment: .leading, spacing: SudoTheme.spacingXs) {
                HStack {
                    Text("> button map")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.textMuted)
                    if let bid = engine.currentBundleID, settings.appProfiles[bid] != nil {
                        let appName = bid.split(separator: ".").last.map(String.init) ?? bid
                        Text("(profile: \(appName))")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.accent)
                    }
                    Spacer()
                    Button(action: { showRemapPanel.toggle() }) {
                        Text(showRemapPanel ? "done" : "edit")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)

                if showRemapPanel {
                    remapPanel
                } else {
                    ForEach(PadAction.allCases, id: \.rawValue) { action in
                        HStack {
                            Text("F\(action.fKeyNumber)")
                                .font(SudoTheme.mono(size: 11))
                                .foregroundColor(SudoTheme.accent)
                                .frame(width: 30, alignment: .leading)
                            Text(action.displayName)
                                .font(SudoTheme.mono(size: 11))
                                .foregroundColor(SudoTheme.text)
                        }
                    }
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Action history
            divider
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { showHistory.toggle() }) {
                    HStack {
                        Text("> history (\(engine.actionLog.count))")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                        Spacer()
                        Text(showHistory ? "▾" : "▸")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showHistory {
                    if engine.actionLog.isEmpty {
                        Text("no actions yet")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.textMuted)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(engine.actionLog.prefix(20)) { entry in
                                    HStack(spacing: 6) {
                                        Text(entry.succeeded ? "✓" : "✗")
                                            .font(SudoTheme.mono(size: 9))
                                            .foregroundColor(entry.succeeded ? SudoTheme.accent : SudoTheme.error)
                                            .frame(width: 10)
                                        Text(entry.timeString)
                                            .font(SudoTheme.mono(size: 9))
                                            .foregroundColor(SudoTheme.textMuted)
                                        Text(entry.action)
                                            .font(SudoTheme.mono(size: 9))
                                            .foregroundColor(SudoTheme.text)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(entry.app)
                                            .font(SudoTheme.mono(size: 8))
                                            .foregroundColor(SudoTheme.surface)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                    }
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Test panel
            divider
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { showTestPanel.toggle() }) {
                    HStack {
                        Text("> test panel")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                        Spacer()
                        Text(showTestPanel ? "▾" : "▸")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showTestPanel {
                    Text("Click to simulate button presses:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                        .padding(.bottom, 2)

                    HStack(spacing: 6) {
                        ForEach(PadAction.allCases, id: \.rawValue) { padAction in
                            Button(action: { engine.triggerAction(padAction) }) {
                                VStack(spacing: 2) {
                                    Text("F\(padAction.fKeyNumber)")
                                        .font(SudoTheme.mono(size: 10, weight: .bold))
                                    Text(padAction.rawValue)
                                        .font(SudoTheme.mono(size: 8))
                                }
                                .foregroundColor(SudoTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(
                                    Rectangle()
                                        .stroke(SudoTheme.accent, lineWidth: SudoTheme.borderWidth)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: { TestWindowManager.shared.open() }) {
                        Text("[ OPEN TEST WINDOW ]")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .overlay(
                                Rectangle()
                                    .stroke(SudoTheme.border, lineWidth: SudoTheme.borderWidth)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Macros
            divider
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { showMacros.toggle() }) {
                    HStack {
                        Text("> macros (\(settings.macros.count))")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                        Spacer()
                        Text(showMacros ? "▾" : "▸")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showMacros {
                    macrosPanel
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Plugins
            divider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("> plugins (\(pluginManager.loadedPlugins.count))")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.textMuted)
                    Spacer()
                    Button(action: { pluginManager.openPluginsFolder() }) {
                        Text("open folder")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                if !pluginManager.loadedPlugins.isEmpty {
                    ForEach(pluginManager.loadedPlugins) { plugin in
                        HStack {
                            Text(plugin.name)
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.text)
                                .lineLimit(1)
                            Spacer()
                            Text("\(plugin.bundle_ids.count) ids")
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.surface)
                        }
                    }
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Settings
            divider
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { showSettings.toggle() }) {
                    HStack {
                        Text("> settings")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                        Spacer()
                        Text(showSettings ? "▾" : "▸")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showSettings {
                    settingsToggles
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Auto-Approve
            divider
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { showAutoApprove.toggle() }) {
                    HStack {
                        Text("> auto-approve")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                        if settings.autoApproveEnabled {
                            Text("ON")
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.accent)
                        }
                        Spacer()
                        Text(showAutoApprove ? "▾" : "▸")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showAutoApprove {
                    autoApprovePanel
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Developer API
            divider
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { showAPI.toggle() }) {
                    HStack {
                        Text("> developer api")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                        if apiServer.isRunning {
                            Text("ON")
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.accent)
                        }
                        Spacer()
                        Text(showAPI ? "▾" : "▸")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showAPI {
                    apiPanel
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Update banner
            if updater.updateAvailable {
                divider
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("update available")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.accent)
                        Spacer()
                        Text("v\(updater.latestVersion)")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    }

                    if updater.isUpdating {
                        ProgressView(value: updater.updateProgress)
                            .tint(SudoTheme.accent)
                        Text("installing...")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    } else {
                        Button(action: { updater.installUpdate() }) {
                            Text("[ INSTALL UPDATE ]")
                                .font(SudoTheme.mono(size: 11))
                                .foregroundColor(SudoTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .overlay(
                                    Rectangle()
                                        .stroke(SudoTheme.accent, lineWidth: SudoTheme.borderWidth)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.vertical, 10)
            }

            divider

            // Rebuild from git
            if rebuilder.isRebuilding {
                HStack {
                    Text("rebuilding: \(rebuilder.status)")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                    Spacer()
                }
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.vertical, 8)
                divider
            }

            // Footer
            HStack(spacing: 8) {
                Button("Pull & Rebuild") {
                    rebuilder.rebuild()
                }
                .buttonStyle(.plain)
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(rebuilder.isRebuilding ? SudoTheme.textMuted : SudoTheme.accent)
                .disabled(rebuilder.isRebuilding)

                Text("·")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.border)

                Button("Updates") {
                    updater.checkForUpdates()
                }
                .buttonStyle(.plain)
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(SudoTheme.textMuted)

                Text("·")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.border)

                Button("Bug?") {
                    BugReporter.shared.fileReport(engine: engine)
                }
                .buttonStyle(.plain)
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(SudoTheme.textMuted)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(SudoTheme.mono(size: 11))
                .foregroundColor(SudoTheme.textMuted)
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            // Version
            HStack {
                Spacer()
                Text("v\(OTAUpdater.currentVersion)")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.surface)
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.bottom, SudoTheme.spacingSm)
        }
        .frame(width: 320)
        .background(SudoTheme.bg)
    }

    // MARK: - Settings toggles

    @ViewBuilder
    private var settingsToggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingToggle("search all apps", isOn: Binding(
                get: { engine.searchAllApps },
                set: { engine.searchAllApps = $0 }
            ))
            settingToggle("sound feedback", isOn: $settings.soundEnabled)
            settingToggle("notify on failure", isOn: $settings.notifyOnFailure)
            settingToggle("launch at login", isOn: $settings.launchAtLogin)
            settingToggle("anonymous telemetry", isOn: $settings.telemetryEnabled)
        }
    }

    private func settingToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack {
                Text(isOn.wrappedValue ? "[x]" : "[ ]")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.accent)
                Text(label)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - API Panel

    @ViewBuilder
    private var apiPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Enable toggle
            settingToggle("enable local api", isOn: Binding(
                get: { settings.apiEnabled },
                set: {
                    settings.apiEnabled = $0
                    if $0 { apiServer.start(engine: engine) } else { apiServer.stop() }
                }
            ))

            if settings.apiEnabled {
                // Status
                HStack {
                    Text("status:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    Text(apiServer.isRunning ? "running on :\(settings.apiPort)" : "stopped")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(apiServer.isRunning ? SudoTheme.accent : SudoTheme.error)
                    if apiServer.requestCount > 0 {
                        Spacer()
                        Text("\(apiServer.requestCount) req")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }

                // API Key
                VStack(alignment: .leading, spacing: 2) {
                    Text("api key:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    HStack {
                        Text(settings.apiKey)
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(copiedKey ? "copied!" : "copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.apiKey, forType: .string)
                            copiedKey = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedKey = false }
                        }
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(copiedKey ? SudoTheme.accent : SudoTheme.textMuted)
                        .buttonStyle(.plain)
                    }
                }

                // Webhook URL
                VStack(alignment: .leading, spacing: 2) {
                    Text("webhook url (optional):")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    HStack {
                        TextField("https://your-server.com/webhook", text: $editWebhookURL)
                            .font(SudoTheme.mono(size: 9))
                            .textFieldStyle(.plain)
                            .foregroundColor(SudoTheme.text)
                            .onAppear { editWebhookURL = settings.webhookURL }
                        if editWebhookURL != settings.webhookURL {
                            Button("save") {
                                settings.webhookURL = editWebhookURL
                            }
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.accent)
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Endpoints docs
                divider
                VStack(alignment: .leading, spacing: 3) {
                    Text("endpoints:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    endpointRow("GET", "/status", "device status")
                    endpointRow("GET", "/log", "action history")
                    endpointRow("GET", "/config", "button mappings")
                    endpointRow("POST", "/trigger/approve", "trigger action")
                }

                // Example
                VStack(alignment: .leading, spacing: 2) {
                    Text("example:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    Text("curl -H 'X-API-Key: \\(settings.apiKey.prefix(8))...' http://localhost:\\(settings.apiPort)/status")
                        .font(SudoTheme.mono(size: 7))
                        .foregroundColor(SudoTheme.surface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func endpointRow(_ method: String, _ path: String, _ desc: String) -> some View {
        HStack(spacing: 4) {
            Text(method)
                .font(SudoTheme.mono(size: 8))
                .foregroundColor(method == "POST" ? SudoTheme.accent : SudoTheme.textMuted)
                .frame(width: 28, alignment: .leading)
            Text(path)
                .font(SudoTheme.mono(size: 8))
                .foregroundColor(SudoTheme.text)
            Spacer()
            Text(desc)
                .font(SudoTheme.mono(size: 7))
                .foregroundColor(SudoTheme.surface)
        }
    }

    // MARK: - Remap Panel

    @ViewBuilder
    private var remapPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Per-app profiles
            Button(action: { showAppProfiles.toggle() }) {
                HStack {
                    Text("> per-app profiles")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    Spacer()
                    Text(showAppProfiles ? "▾" : "▸")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                }
            }
            .buttonStyle(.plain)

            if showAppProfiles {
                VStack(alignment: .leading, spacing: 6) {
                    // Current app with save button
                    HStack {
                        Text("current app:")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.textMuted)
                        Text(engine.detectedApp.lowercased())
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.text)
                            .lineLimit(1)
                        Spacer()
                        if let bid = engine.currentBundleID {
                            Button("save profile for this app") {
                                var buttons: [PadAction: ButtonPreset.ButtonConfig] = [:]
                                for action in PadAction.allCases {
                                    buttons[action] = ButtonPreset.ButtonConfig(
                                        displayName: settings.displayName(for: action),
                                        searchTerms: settings.searchTerms(for: action)
                                    )
                                }
                                let preset = ButtonPreset(id: bid, name: bid, description: "", buttons: buttons)
                                settings.saveProfile(forBundleID: bid, preset: preset)
                            }
                            .font(SudoTheme.mono(size: 7))
                            .foregroundColor(SudoTheme.accent)
                            .buttonStyle(.plain)
                        }
                    }

                    // List of saved profiles
                    if !settings.appProfiles.isEmpty {
                        ForEach(Array(settings.appProfiles.keys.sorted()), id: \.self) { bundleID in
                            HStack {
                                let shortName = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
                                Text(shortName.lowercased())
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.text)
                                Text(bundleID)
                                    .font(SudoTheme.mono(size: 7))
                                    .foregroundColor(SudoTheme.surface)
                                    .lineLimit(1)
                                Spacer()
                                if engine.currentBundleID == bundleID {
                                    Text("active")
                                        .font(SudoTheme.mono(size: 7))
                                        .foregroundColor(SudoTheme.accent)
                                }
                                Button("delete") {
                                    settings.deleteProfile(forBundleID: bundleID)
                                }
                                .font(SudoTheme.mono(size: 7))
                                .foregroundColor(SudoTheme.error)
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Text("no saved profiles")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }
                .padding(6)
                .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
            }

            divider

            // Quick presets
            Text("quick presets:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ButtonPreset.all) { preset in
                        Button(action: {
                            preset.apply()
                            editingAction = nil
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(SudoTheme.mono(size: 9, weight: .bold))
                                    .foregroundColor(SudoTheme.accent)
                                Text(preset.description)
                                    .font(SudoTheme.mono(size: 7))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .overlay(
                                Rectangle()
                                    .stroke(SudoTheme.border, lineWidth: SudoTheme.borderWidth)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            divider

            // Per-button editing
            Text("custom mapping:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)

            ForEach(PadAction.allCases, id: \.rawValue) { action in
                VStack(alignment: .leading, spacing: 4) {
                    if editingAction == action {
                        // Edit mode
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("F\(action.fKeyNumber)")
                                    .font(SudoTheme.mono(size: 10, weight: .bold))
                                    .foregroundColor(SudoTheme.accent)
                                    .frame(width: 26, alignment: .leading)
                                Text("editing")
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.textMuted)
                            }
                            HStack(spacing: 4) {
                                Text("name")
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 32, alignment: .trailing)
                                TextField("display name", text: $editName)
                                    .font(SudoTheme.mono(size: 9))
                                    .textFieldStyle(.plain)
                                    .foregroundColor(SudoTheme.text)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
                            }
                            HStack(spacing: 4) {
                                Text("find")
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 32, alignment: .trailing)
                                TextField("comma-separated search terms", text: $editTerms)
                                    .font(SudoTheme.mono(size: 9))
                                    .textFieldStyle(.plain)
                                    .foregroundColor(SudoTheme.text)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
                            }
                            HStack(spacing: 8) {
                                Spacer()
                                Button("save") {
                                    settings.buttonNames[action.rawValue] = editName.isEmpty ? nil : editName
                                    let terms = editTerms.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                    settings.buttonSearchTerms[action.rawValue] = terms.isEmpty ? nil : terms
                                    editingAction = nil
                                }
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.accent)
                                .buttonStyle(.plain)

                                Button("reset") {
                                    settings.buttonNames[action.rawValue] = nil
                                    settings.buttonSearchTerms[action.rawValue] = nil
                                    editingAction = nil
                                }
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.error)
                                .buttonStyle(.plain)

                                Button("cancel") { editingAction = nil }
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.textMuted)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                        .overlay(Rectangle().stroke(SudoTheme.accent.opacity(0.3), lineWidth: 1))
                    } else {
                        // Display mode
                        HStack {
                            Text("F\(action.fKeyNumber)")
                                .font(SudoTheme.mono(size: 10, weight: .bold))
                                .foregroundColor(SudoTheme.accent)
                                .frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.displayName)
                                    .font(SudoTheme.mono(size: 10))
                                    .foregroundColor(SudoTheme.text)
                                    .lineLimit(1)
                                Text(settings.searchTerms(for: action).prefix(4).joined(separator: ", "))
                                    .font(SudoTheme.mono(size: 7))
                                    .foregroundColor(SudoTheme.surface)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("edit") {
                                editName = settings.buttonNames[action.rawValue] ?? action.defaultDisplayName
                                editTerms = (settings.buttonSearchTerms[action.rawValue] ?? action.defaultSearchTerms).joined(separator: ", ")
                                editingAction = action
                            }
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.accent)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(SudoTheme.border)
            .frame(height: 1)
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .font(SudoTheme.mono(size: 11))
                .foregroundColor(SudoTheme.textMuted)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(SudoTheme.mono(size: 11))
                .foregroundColor(SudoTheme.text)
                .lineLimit(2)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

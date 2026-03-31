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
    @State private var showTerminal = false
    @State private var terminalInput = ""
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

            // Permission status
            if !engine.isConnected {
                VStack(alignment: .leading, spacing: 6) {
                    // Status checks
                    HStack(spacing: 6) {
                        Text(engine.axPermissionGranted ? "✓" : "✗")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(engine.axPermissionGranted ? SudoTheme.accent : SudoTheme.error)
                        Text("accessibility api")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.text)
                        Spacer()
                        Text(engine.axPermissionGranted ? "granted" : "denied")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(engine.axPermissionGranted ? SudoTheme.accent : SudoTheme.error)
                    }
                    HStack(spacing: 6) {
                        Text(engine.isConnected ? "✓" : "✗")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(engine.isConnected ? SudoTheme.accent : SudoTheme.error)
                        Text("hotkey listener")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.text)
                        Spacer()
                        Text(engine.isConnected ? "active" : "failed")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(engine.isConnected ? SudoTheme.accent : SudoTheme.error)
                    }

                    Text(engine.permissionStatus)
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.textMuted)

                    if !engine.axPermissionGranted {
                        Text("system settings → privacy & security → accessibility → enable sudo")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }) {
                            Text("[ open settings ]")
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.accent)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            engine.checkAndConnect()
                        }) {
                            Text("[ re-check ]")
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
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
                if let mcpPrompt = engine.pendingMCPRequest {
                    HStack(alignment: .top, spacing: 6) {
                        Text("mcp:")
                            .font(SudoTheme.mono(size: 11))
                            .foregroundColor(SudoTheme.accent)
                            .frame(width: 36, alignment: .leading)
                        Text(mcpPrompt)
                            .font(SudoTheme.mono(size: 11))
                            .foregroundColor(SudoTheme.accent)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Button(action: { engine.resolveMCPRequest(approved: true) }) {
                            Text("[ approve ]")
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.accent)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .overlay(Rectangle().stroke(SudoTheme.accent, lineWidth: SudoTheme.borderWidth))
                        }
                        .buttonStyle(.plain)
                        Button(action: { engine.resolveMCPRequest(approved: false) }) {
                            Text("[ reject ]")
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.error)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .overlay(Rectangle().stroke(SudoTheme.error, lineWidth: SudoTheme.borderWidth))
                        }
                        .buttonStyle(.plain)
                    }
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
                    ForEach(PadAction.physicalOrder, id: \.rawValue) { action in
                        HStack(spacing: 0) {
                            // Color stripe matching physical button
                            Rectangle()
                                .fill(Color(hex: action.buttonColorHex))
                                .frame(width: 3, height: 20)
                                .padding(.trailing, 8)
                            Text("\(action.buttonNumber)")
                                .font(SudoTheme.mono(size: 10))
                                .foregroundColor(SudoTheme.textMuted)
                                .frame(width: 14, alignment: .leading)
                            Text(action.displayName.lowercased())
                                .font(SudoTheme.mono(size: 11))
                                .foregroundColor(SudoTheme.text)
                            Spacer()
                            Text("F\(action.fKeyNumber)")
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.surface)
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
                    // Device replica — vertical, matches physical layout
                    VStack(spacing: 0) {
                        // Screen
                        Text("[sudo]")
                            .font(SudoTheme.mono(size: 8, weight: .bold))
                            .foregroundColor(SudoTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(SudoTheme.bg)

                        Rectangle().fill(SudoTheme.border).frame(height: 1)

                        // Buttons: top (4/black) to bottom (1/green)
                        ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { padAction in
                            Button(action: { engine.triggerAction(padAction) }) {
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color(hex: padAction.buttonColorHex))
                                        .frame(width: 3)
                                    HStack {
                                        Text("\(padAction.buttonNumber)")
                                            .font(SudoTheme.mono(size: 9))
                                            .foregroundColor(SudoTheme.textMuted)
                                            .frame(width: 12, alignment: .leading)
                                        Text(padAction.displayName.lowercased())
                                            .font(SudoTheme.mono(size: 9))
                                            .foregroundColor(SudoTheme.text)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("press")
                                            .font(SudoTheme.mono(size: 7))
                                            .foregroundColor(SudoTheme.surface)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                }
                                .background(SudoTheme.bg)
                            }
                            .buttonStyle(.plain)

                            if padAction != PadAction.physicalOrder.first {
                                Rectangle().fill(SudoTheme.border).frame(height: 1)
                            }
                        }
                    }
                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))

                    Button(action: { TestWindowManager.shared.open() }) {
                        Text("[ open test window ]")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
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

            // Terminal / build log
            divider
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { showTerminal.toggle() }) {
                    HStack {
                        Text("> terminal")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                        if rebuilder.isRebuilding {
                            Text("building...")
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.accent)
                        } else if !rebuilder.buildLog.isEmpty {
                            Text("(\(rebuilder.buildLog.count) lines)")
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.textMuted)
                        }
                        Spacer()
                        Text(showTerminal ? "▾" : "▸")
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showTerminal {
                    // Log output
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
                                            line.contains("warning") ? Color(hex: 0xD4B85C) :
                                            SudoTheme.text
                                        )
                                        .textSelection(.enabled)
                                        .id(idx)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 150)
                        .padding(6)
                        .background(Color(hex: 0x050505))
                        .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
                        .onChange(of: rebuilder.buildLog.count) { _ in
                            if let last = rebuilder.buildLog.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }

                    // Command input
                    HStack(spacing: 4) {
                        Text("$")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.accent)
                        TextField("command...", text: $terminalInput)
                            .font(SudoTheme.mono(size: 9))
                            .textFieldStyle(.plain)
                            .foregroundColor(SudoTheme.text)
                            .onSubmit {
                                let cmd = terminalInput.trimmingCharacters(in: .whitespaces)
                                guard !cmd.isEmpty else { return }
                                terminalInput = ""
                                rebuilder.runCommand(cmd)
                            }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0x050505))
                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))

                    HStack(spacing: 8) {
                        Button("copy log") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rebuilder.buildLog.joined(separator: "\n"), forType: .string)
                        }
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.accent)
                        .buttonStyle(.plain)

                        Button("clear") { rebuilder.clearLog() }
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.textMuted)
                            .buttonStyle(.plain)
                        Spacer()
                    }
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

            // Stats + Version
            HStack(spacing: 0) {
                Text("\(settings.totalApproves) approves")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
                Text(" · ")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.border)
                Text("\(settings.totalRejects) rejects")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
                Text(" · ")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.border)
                Text("\(settings.currentStreak) day streak")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
                Spacer()
                Text("v\(OTAUpdater.currentVersion)")
                    .font(SudoTheme.mono(size: 8))
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

            divider

            // Hotkey bindings
            Text("hotkey bindings:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)
            Text("works with any macro pad or keyboard")
                .font(SudoTheme.mono(size: 7))
                .foregroundColor(SudoTheme.surface)

            ForEach(PadAction.physicalOrder, id: \.rawValue) { action in
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
                    Text("keyCode: \(keyCode)")
                        .font(SudoTheme.mono(size: 7))
                        .foregroundColor(SudoTheme.surface)
                }
            }

            Button("reset to defaults (ctrl+shift+F13-F16)") {
                settings.resetHotkeyBindings()
            }
            .font(SudoTheme.mono(size: 8))
            .foregroundColor(SudoTheme.textMuted)
            .buttonStyle(.plain)

            divider

            // Developer API (inline in settings)
            Button(action: { showAPI.toggle() }) {
                HStack {
                    Text("developer api")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    if apiServer.isRunning {
                        Text("on")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.accent)
                    }
                    Spacer()
                    Text(showAPI ? "▾" : "▸")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                }
            }
            .buttonStyle(.plain)

            if showAPI {
                apiPanel
            }
        }
    }

    private func describeHotkey(keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskAlternate) { parts.append("opt") }

        let keyName: String
        switch UInt16(keyCode) {
        case 105: keyName = "F13"
        case 107: keyName = "F14"
        case 113: keyName = "F15"
        case 106: keyName = "F16"
        case 122: keyName = "F1"
        case 120: keyName = "F2"
        case 99:  keyName = "F3"
        case 118: keyName = "F4"
        default:  keyName = "key\(keyCode)"
        }
        parts.append(keyName)
        return parts.joined(separator: "+")
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

    // MARK: - Auto-Approve Panel

    @ViewBuilder
    private var autoApprovePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Warning
            Text("experimental — auto-presses approve when rules match")
                .font(SudoTheme.mono(size: 8))
                .foregroundColor(SudoTheme.error)

            // Master toggle
            settingToggle("enable auto-approve", isOn: Binding(
                get: { settings.autoApproveEnabled },
                set: {
                    settings.autoApproveEnabled = $0
                    engine.startAutoApproveTimer()
                }
            ))

            if settings.autoApproveEnabled {
                // Stats
                HStack {
                    Text("auto-approved:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    Text("\(engine.autoApproveCount)")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                }

                divider

                // Rules list
                Text("rules:")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)

                ForEach(Array(settings.autoApproveRules.enumerated()), id: \.element.id) { index, rule in
                    if editingRuleID == rule.id {
                        // Inline editor
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text("name")
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 50, alignment: .trailing)
                                TextField("rule name", text: $editRuleName)
                                    .font(SudoTheme.mono(size: 9))
                                    .textFieldStyle(.plain)
                                    .foregroundColor(SudoTheme.text)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
                            }
                            HStack(spacing: 4) {
                                Text("app")
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 50, alignment: .trailing)
                                TextField("bundle id filter", text: $editRuleAppFilter)
                                    .font(SudoTheme.mono(size: 9))
                                    .textFieldStyle(.plain)
                                    .foregroundColor(SudoTheme.text)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
                            }
                            HStack(spacing: 4) {
                                Text("contains")
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 50, alignment: .trailing)
                                TextField("context must contain", text: $editRuleContextContains)
                                    .font(SudoTheme.mono(size: 9))
                                    .textFieldStyle(.plain)
                                    .foregroundColor(SudoTheme.text)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
                            }
                            HStack(spacing: 4) {
                                Text("excludes")
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 50, alignment: .trailing)
                                TextField("safety exclusions (comma-sep)", text: $editRuleContextExcludes)
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
                                    settings.autoApproveRules[index].name = editRuleName
                                    settings.autoApproveRules[index].appFilter = editRuleAppFilter.isEmpty ? nil : editRuleAppFilter
                                    settings.autoApproveRules[index].contextContains = editRuleContextContains.isEmpty ? nil : editRuleContextContains
                                    settings.autoApproveRules[index].contextExcludes = editRuleContextExcludes.isEmpty ? nil : editRuleContextExcludes
                                    editingRuleID = nil
                                }
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.accent)
                                .buttonStyle(.plain)

                                Button("delete") {
                                    settings.autoApproveRules.remove(at: index)
                                    editingRuleID = nil
                                }
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.error)
                                .buttonStyle(.plain)

                                Button("cancel") { editingRuleID = nil }
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
                            Button(action: {
                                settings.autoApproveRules[index].enabled.toggle()
                            }) {
                                Text(rule.enabled ? "[x]" : "[ ]")
                                    .font(SudoTheme.mono(size: 10))
                                    .foregroundColor(SudoTheme.accent)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.name)
                                    .font(SudoTheme.mono(size: 9))
                                    .foregroundColor(rule.enabled ? SudoTheme.text : SudoTheme.textMuted)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    if let app = rule.appFilter, !app.isEmpty {
                                        Text("app: \(app)")
                                            .font(SudoTheme.mono(size: 7))
                                            .foregroundColor(SudoTheme.surface)
                                    }
                                    if let excludes = rule.contextExcludes, !excludes.isEmpty {
                                        Text("excludes: \(excludes)")
                                            .font(SudoTheme.mono(size: 7))
                                            .foregroundColor(SudoTheme.error.opacity(0.7))
                                            .lineLimit(1)
                                    }
                                }
                            }

                            Spacer()

                            Button("edit") {
                                editRuleName = rule.name
                                editRuleAppFilter = rule.appFilter ?? ""
                                editRuleContextContains = rule.contextContains ?? ""
                                editRuleContextExcludes = rule.contextExcludes ?? ""
                                editingRuleID = rule.id
                            }
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.accent)
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Add rule button
                Button(action: {
                    var newRule = AutoApproveRule(name: "new rule")
                    newRule.enabled = false
                    settings.autoApproveRules.append(newRule)
                    editRuleName = newRule.name
                    editRuleAppFilter = ""
                    editRuleContextContains = ""
                    editRuleContextExcludes = ""
                    editingRuleID = newRule.id
                }) {
                    Text("[ add rule ]")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .overlay(
                            Rectangle()
                                .stroke(SudoTheme.border, lineWidth: SudoTheme.borderWidth)
                        )
                }
                .buttonStyle(.plain)
            }
        }
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

    // MARK: - Macros Panel

    @ViewBuilder
    private var macrosPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(settings.macros.enumerated()), id: \.element.id) { index, macro in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(macro.name)
                            .font(SudoTheme.mono(size: 10, weight: .bold))
                            .foregroundColor(SudoTheme.text)
                        Text("(\(macro.steps.count) steps)")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.textMuted)
                        Spacer()
                        Button("run") { engine.executeMacro(macro) }
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.accent)
                            .buttonStyle(.plain)
                        Button(editingMacroID == macro.id ? "done" : "edit") {
                            editingMacroID = editingMacroID == macro.id ? nil : macro.id
                        }
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.accent)
                        .buttonStyle(.plain)
                        Button("del") { settings.macros.removeAll { $0.id == macro.id } }
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.error)
                            .buttonStyle(.plain)
                    }
                    Text(macroStepsSummary(macro))
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.surface)
                        .lineLimit(2)
                    if let assigned = macro.assignedButton, let action = PadAction(rawValue: assigned) {
                        HStack {
                            Text("assigned to F\(action.fKeyNumber)")
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.accent)
                            Spacer()
                            Button("unassign") { settings.macros[index].assignedButton = nil }
                                .font(SudoTheme.mono(size: 8))
                                .foregroundColor(SudoTheme.error)
                                .buttonStyle(.plain)
                        }
                    }
                    if editingMacroID == macro.id {
                        macroEditView(index: index)
                    }
                }
                .padding(6)
                .overlay(Rectangle().stroke(editingMacroID == macro.id ? SudoTheme.accent.opacity(0.3) : SudoTheme.border, lineWidth: 1))
            }
            Button(action: {
                let m = MacroSequence(name: "new macro", steps: [MacroStep(action: .approve, delayAfter: 1.0)])
                settings.macros.append(m)
                editingMacroID = m.id
            }) {
                Text("[ + new macro ]")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: SudoTheme.borderWidth))
            }
            .buttonStyle(.plain)
            Button(action: { settings.macros = SudoSettings.defaultMacros(); editingMacroID = nil }) {
                Text("reset to defaults")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func macroEditView(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("name").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted).frame(width: 32, alignment: .trailing)
                TextField("macro name", text: Binding(get: { settings.macros[index].name }, set: { settings.macros[index].name = $0 }))
                    .font(SudoTheme.mono(size: 9)).textFieldStyle(.plain).foregroundColor(SudoTheme.text)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))
            }
            divider
            Text("steps:").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted)
            ForEach(Array(settings.macros[index].steps.enumerated()), id: \.element.id) { stepIdx, step in
                HStack(spacing: 4) {
                    Text("\(stepIdx + 1).").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted).frame(width: 16, alignment: .trailing)
                    macroActionPicker(macroIndex: index, stepIndex: stepIdx)
                    Text("wait").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted)
                    macroDelayPicker(macroIndex: index, stepIndex: stepIdx)
                    Spacer()
                    Button("x") { if settings.macros[index].steps.count > 1 { settings.macros[index].steps.remove(at: stepIdx) } }
                        .font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.error).buttonStyle(.plain)
                }
            }
            Button(action: { settings.macros[index].steps.append(MacroStep(action: .approve, delayAfter: 1.0)) }) {
                Text("[ + add step ]").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.accent)
            }.buttonStyle(.plain)
            divider
            Text("assign to button:").font(SudoTheme.mono(size: 8)).foregroundColor(SudoTheme.textMuted)
            HStack(spacing: 4) {
                ForEach(PadAction.allCases, id: \.rawValue) { action in
                    let isAssigned = settings.macros[index].assignedButton == action.rawValue
                    Button(action: {
                        for i in settings.macros.indices { if settings.macros[i].assignedButton == action.rawValue { settings.macros[i].assignedButton = nil } }
                        settings.macros[index].assignedButton = isAssigned ? nil : action.rawValue
                    }) {
                        Text("\(action.buttonNumber)")
                            .font(SudoTheme.mono(size: 8, weight: isAssigned ? .bold : .regular))
                            .foregroundColor(isAssigned ? SudoTheme.bg : Color(hex: action.buttonColorHex))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(isAssigned ? SudoTheme.accent : Color.clear)
                            .overlay(Rectangle().stroke(SudoTheme.accent, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.top, 4)
    }

    private func macroActionPicker(macroIndex: Int, stepIndex: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(PadAction.allCases, id: \.rawValue) { action in
                let sel = settings.macros[macroIndex].steps[stepIndex].action == action.rawValue
                Button(action: { let old = settings.macros[macroIndex].steps[stepIndex]; settings.macros[macroIndex].steps[stepIndex] = MacroStep(action: action, delayAfter: old.delayAfter) }) {
                    Text(action.rawValue).font(SudoTheme.mono(size: 7))
                        .foregroundColor(sel ? SudoTheme.bg : SudoTheme.textMuted)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(sel ? SudoTheme.accent : Color.clear)
                }.buttonStyle(.plain)
            }
        }
    }

    private func macroDelayPicker(macroIndex: Int, stepIndex: Int) -> some View {
        HStack(spacing: 2) {
            ForEach([0.0, 0.5, 1.0, 1.5, 2.0], id: \.self) { delay in
                let sel = settings.macros[macroIndex].steps[stepIndex].delayAfter == delay
                Button(action: {
                    let old = settings.macros[macroIndex].steps[stepIndex]
                    if let a = old.padAction { settings.macros[macroIndex].steps[stepIndex] = MacroStep(action: a, delayAfter: delay) }
                }) {
                    Text(delay == 0 ? "0s" : String(format: "%.1fs", delay)).font(SudoTheme.mono(size: 7))
                        .foregroundColor(sel ? SudoTheme.bg : SudoTheme.textMuted)
                        .padding(.horizontal, 2).padding(.vertical, 1)
                        .background(sel ? SudoTheme.accent : Color.clear)
                }.buttonStyle(.plain)
            }
        }
    }

    private func macroStepsSummary(_ macro: MacroSequence) -> String {
        var parts: [String] = []
        for (i, step) in macro.steps.enumerated() {
            parts.append(step.action)
            if step.delayAfter > 0 && i < macro.steps.count - 1 { parts.append(String(format: "%.1fs", step.delayAfter)) }
        }
        return parts.joined(separator: " → ")
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
            // Visual device layout — clean, matches website design language
            VStack(spacing: 0) {
                // Buttons in physical order: top (black) to bottom (green)
                ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                    Button(action: {
                        if editingAction == action {
                            editingAction = nil
                        } else {
                            editName = settings.buttonNames[action.rawValue] ?? action.defaultDisplayName
                            editTerms = (settings.buttonSearchTerms[action.rawValue] ?? action.defaultSearchTerms).joined(separator: ", ")
                            editingAction = action
                        }
                    }) {
                        HStack(spacing: 0) {
                            // Left color stripe
                            Rectangle()
                                .fill(Color(hex: action.buttonColorHex))
                                .frame(width: 3)
                            HStack {
                                Text("\(action.buttonNumber)")
                                    .font(SudoTheme.mono(size: 10))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 14, alignment: .leading)
                                Text(action.displayName.lowercased())
                                    .font(SudoTheme.mono(size: 10))
                                    .foregroundColor(editingAction == action ? SudoTheme.accent : SudoTheme.text)
                                    .lineLimit(1)
                                Spacer()
                                Text("F\(action.fKeyNumber)")
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.surface)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .background(editingAction == action ? SudoTheme.bgSecondary : SudoTheme.bg)
                    }
                    .buttonStyle(.plain)

                    // Divider between buttons
                    if action != PadAction.physicalOrder.first {
                        Rectangle().fill(SudoTheme.border).frame(height: 1)
                    }
                }
            }
            .overlay(Rectangle().stroke(SudoTheme.border, lineWidth: 1))

            // Edit panel for selected button
            if let action = editingAction {
                VStack(alignment: .leading, spacing: 4) {
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
            }

            divider

            // Quick presets — vertical list
            Text("quick presets:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)

            VStack(spacing: 4) {
                ForEach(ButtonPreset.all) { preset in
                    Button(action: {
                        preset.apply()
                        editingAction = nil
                    }) {
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
                        .padding(.vertical, 5)
                        .overlay(
                            Rectangle()
                                .stroke(SudoTheme.border, lineWidth: SudoTheme.borderWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            divider

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
                            Button("save profile") {
                                var buttons: [PadAction: ButtonPreset.ButtonConfig] = [:]
                                for a in PadAction.allCases {
                                    buttons[a] = ButtonPreset.ButtonConfig(
                                        displayName: settings.displayName(for: a),
                                        searchTerms: settings.searchTerms(for: a)
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

                    if !settings.appProfiles.isEmpty {
                        ForEach(Array(settings.appProfiles.keys.sorted()), id: \.self) { bundleID in
                            HStack {
                                let shortName = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
                                Text(shortName.lowercased())
                                    .font(SudoTheme.mono(size: 8))
                                    .foregroundColor(SudoTheme.text)
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

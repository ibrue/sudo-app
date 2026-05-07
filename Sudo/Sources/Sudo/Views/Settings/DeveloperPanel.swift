import SwiftUI

/// Developer-only consoles: HTTP API + key, plugin list, debug log,
/// and the pull-and-rebuild terminal. Only renders when developer
/// mode is on (the sidebar entry is hidden otherwise).
struct DeveloperPanel: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var apiServer: LocalAPIServer
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject private var settings = SudoSettings.shared
    @ObservedObject private var pluginManager = PluginManager.shared
    @ObservedObject private var debugLogger = DebugLogger.shared
    @ObservedObject private var padConsole = PadConsoleReader.shared

    @State private var copiedKey = false
    @State private var copiedPadConsole = false
    @State private var terminalInput = ""

    var body: some View {
        SettingsPanelScaffold(
            title: "developer",
            subtitle: "local api, pad console, debug log, terminal, and loaded plugins."
        ) {
            padConsoleSection
            SudoDivider()
            apiSection
            SudoDivider()
            debugSection
            SudoDivider()
            terminalSection
            SudoDivider()
            pluginsSection
        }
    }

    // MARK: - Pad console
    //
    // Tails /dev/cu.usbmodem* (the pad's USB CDC console) so a user
    // can grab the firmware boot log without opening Terminal. The
    // exact thing we'd otherwise ask them to do via `screen
    // /dev/cu.usbmodem<id> 115200`. PadConsoleReader handles the
    // POSIX side; this view is just controls + transcript display.

    @ViewBuilder
    private var padConsoleSection: some View {
        sectionHeader("pad console")
        Text("tails the pad's usb cdc serial port (`/dev/cu.usbmodem*`). use this to grab the firmware boot log when debugging connect-time issues — copy the output and share it.")
            .font(SudoTheme.caption)
            .foregroundColor(SudoTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
            Image(systemName: padConsole.isConnected ? "circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(padConsole.isConnected ? SudoTheme.accent : SudoTheme.textMuted)
            if let path = padConsole.portPath {
                Text(path)
                    .font(SudoTheme.code(size: 11))
                    .foregroundColor(SudoTheme.text)
            } else {
                Text(padConsole.isConnected ? "connected" : "not connected")
                    .font(SudoTheme.body)
                    .foregroundColor(SudoTheme.textMuted)
            }
            Spacer()
            if padConsole.isConnected {
                Button("disconnect") { padConsole.stop() }
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
                Button("reconnect") { padConsole.reconnect() }
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
            } else {
                Button("connect") { padConsole.start() }
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
            }
        }

        if let err = padConsole.lastError, !padConsole.isConnected {
            Text(err)
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.error)
                .fixedSize(horizontal: false, vertical: true)
        }

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if padConsole.lines.isEmpty {
                        Text("no output yet — click connect, then unplug and replug the pad.")
                            .font(SudoTheme.code(size: 11))
                            .foregroundColor(SudoTheme.textMuted)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(padConsole.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(SudoTheme.code(size: 11))
                                .foregroundColor(
                                    line.contains("EXCEPTION") || line.lowercased().contains("error") ? SudoTheme.error :
                                    line.hasPrefix("──") ? SudoTheme.textMuted :
                                    SudoTheme.text
                                )
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 260)
            .background(SudoTheme.codeBackground)
            .overlay(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
            .onChange(of: padConsole.lines.count) { _ in
                if let last = padConsole.lines.indices.last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }

        HStack(spacing: 14) {
            Button(copiedPadConsole ? "copied!" : "copy all") {
                Clipboard.setString(padConsole.transcript)
                copiedPadConsole = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedPadConsole = false }
            }
            .font(SudoTheme.caption)
            .foregroundColor(SudoTheme.accent)
            .buttonStyle(.plain)
            .disabled(padConsole.lines.isEmpty)

            Button("clear") { padConsole.clear() }
                .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
                .disabled(padConsole.lines.isEmpty)

            Spacer()
            Text("\(padConsole.lines.count) lines")
                .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted)
                .monospacedDigit()
        }
    }

    // MARK: - API

    @ViewBuilder
    private var apiSection: some View {
        sectionHeader("local api")
        SettingToggle(label: "enable local api", isOn: Binding(
            get: { settings.apiEnabled },
            set: { settings.apiEnabled = $0; if $0 { apiServer.start(engine: engine) } else { apiServer.stop() } }
        ))
        if settings.apiEnabled {
            HStack(spacing: 10) {
                Text("port \(settings.apiPort)")
                    .font(SudoTheme.body)
                    .foregroundColor(SudoTheme.text)
                Spacer()
                Label(apiServer.isRunning ? "running" : "stopped",
                      systemImage: apiServer.isRunning ? "circle.fill" : "circle")
                    .font(SudoTheme.caption)
                    .foregroundColor(apiServer.isRunning ? SudoTheme.accent : SudoTheme.error)
            }
            HStack(spacing: 10) {
                Text(settings.apiKey)
                    .font(SudoTheme.code(size: 11))
                    .foregroundColor(SudoTheme.text)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(copiedKey ? "copied!" : "copy") {
                    Clipboard.setString(settings.apiKey)
                    copiedKey = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedKey = false }
                }
                .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                .accessibilityLabel("copy api key")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).fill(SudoTheme.accent.opacity(0.06)))
        }
    }

    // MARK: - Debug log

    @ViewBuilder
    private var debugSection: some View {
        sectionHeader("debug console")
        if debugLogger.entries.isEmpty {
            Text("no logs yet — press a button.")
                .font(SudoTheme.body).foregroundColor(SudoTheme.textMuted)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(debugLogger.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.timeFormatter.string(from: entry.timestamp))
                                    .font(SudoTheme.code(size: 10))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 64, alignment: .leading)
                                Text(entry.message)
                                    .font(SudoTheme.code(size: 11))
                                    .foregroundColor(
                                        entry.message.hasPrefix("ERROR") ? SudoTheme.error :
                                        entry.message.hasPrefix("OK") ? SudoTheme.accent :
                                        SudoTheme.text
                                    )
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
                .background(SudoTheme.codeBackground)
                .overlay(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
                .onChange(of: debugLogger.entries.count) { _ in
                    if let last = debugLogger.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            HStack(spacing: 14) {
                Button("clear") { debugLogger.clear() }
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
                Button("copy") {
                    let text = debugLogger.entries
                        .map { "\(Self.timeFormatter.string(from: $0.timestamp))  \($0.message)" }
                        .joined(separator: "\n")
                    Clipboard.setString(text)
                }
                .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                Spacer()
                Text("\(debugLogger.entries.count) entries")
                    .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Terminal

    @ViewBuilder
    private var terminalSection: some View {
        sectionHeader("terminal")
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(rebuilder.buildLog.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(SudoTheme.code(size: 11))
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
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 260)
            .background(SudoTheme.codeBackground)
            .overlay(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
            .onChange(of: rebuilder.buildLog.count) { _ in
                if let last = rebuilder.buildLog.indices.last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }

        HStack(spacing: 8) {
            Text("$").font(SudoTheme.code(size: 12, weight: .semibold)).foregroundColor(SudoTheme.accent)
            TextField("command…", text: $terminalInput)
                .font(SudoTheme.code(size: 12)).textFieldStyle(.plain)
                .onSubmit {
                    let cmd = terminalInput.trimmingCharacters(in: .whitespaces)
                    guard !cmd.isEmpty else { return }
                    terminalInput = ""
                    rebuilder.runCommand(cmd)
                }
        }
        .padding(8)
        .background(SudoTheme.codeBackground)
        .overlay(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))

        HStack(spacing: 14) {
            Button(rebuilder.isRebuilding ? rebuilder.status : "pull & rebuild") {
                rebuilder.rebuild()
            }
            .font(SudoTheme.caption)
            .foregroundColor(rebuilder.isRebuilding ? SudoTheme.textMuted : SudoTheme.accent)
            .buttonStyle(.plain)
            .disabled(rebuilder.isRebuilding)
            Button("copy log") {
                Clipboard.setString(rebuilder.buildLog.joined(separator: "\n"))
            }
            .font(SudoTheme.caption).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
            Button("clear") { rebuilder.clearLog() }
                .font(SudoTheme.caption).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Plugins

    @ViewBuilder
    private var pluginsSection: some View {
        sectionHeader("plugins")
        if pluginManager.loadedPlugins.isEmpty {
            Text("no plugins loaded. drop .json files into ~/Library/Application Support/Sudo/Plugins/ to load them.")
                .font(SudoTheme.body)
                .foregroundColor(SudoTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(pluginManager.loadedPlugins) { plugin in
                HStack(spacing: 10) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 12))
                        .foregroundStyle(SudoTheme.accent)
                    Text(plugin.name.lowercased())
                        .font(SudoTheme.body)
                        .foregroundColor(SudoTheme.text)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SudoTheme.heading)
            .foregroundColor(SudoTheme.text)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

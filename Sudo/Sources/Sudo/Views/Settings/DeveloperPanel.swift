import SwiftUI
import AppKit

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

    @State private var copiedKey = false
    @State private var terminalInput = ""

    var body: some View {
        SettingsPanelScaffold(
            title: "developer",
            subtitle: "local api, debug log, terminal, and loaded plugins."
        ) {
            apiSection
            SudoDivider()
            debugSection
            SudoDivider()
            terminalSection
            SudoDivider()
            pluginsSection
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
            HStack(spacing: 8) {
                Text("port: \(settings.apiPort)")
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.text)
                Spacer()
                Text(apiServer.isRunning ? "● running" : "○ stopped")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(apiServer.isRunning ? SudoTheme.accent : SudoTheme.error)
            }
            HStack(spacing: 8) {
                Text(settings.apiKey)
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.text)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(copiedKey ? "copied!" : "copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(settings.apiKey, forType: .string)
                    copiedKey = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedKey = false }
                }
                .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                .accessibilityLabel("copy api key")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(SudoTheme.accent.opacity(0.06)))
        }
    }

    // MARK: - Debug log

    @ViewBuilder
    private var debugSection: some View {
        sectionHeader("debug console")
        if debugLogger.entries.isEmpty {
            Text("no logs yet — press a button.")
                .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(debugLogger.entries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(Self.timeFormatter.string(from: entry.timestamp))
                                    .font(SudoTheme.mono(size: 9))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .frame(width: 60, alignment: .leading)
                                Text(entry.message)
                                    .font(SudoTheme.mono(size: 10))
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
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
                .onChange(of: debugLogger.entries.count) { _ in
                    if let last = debugLogger.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            HStack(spacing: 12) {
                Button("clear") { debugLogger.clear() }
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
                Button("copy") {
                    let text = debugLogger.entries
                        .map { "\(Self.timeFormatter.string(from: $0.timestamp))  \($0.message)" }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
                Spacer()
                Text("\(debugLogger.entries.count) entries")
                    .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted)
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
                            .font(SudoTheme.mono(size: 10))
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
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))
            .onChange(of: rebuilder.buildLog.count) { _ in
                if let last = rebuilder.buildLog.indices.last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }

        HStack(spacing: 6) {
            Text("$").font(SudoTheme.mono(size: 11)).foregroundColor(SudoTheme.accent)
            TextField("command…", text: $terminalInput)
                .font(SudoTheme.mono(size: 11)).textFieldStyle(.plain)
                .onSubmit {
                    let cmd = terminalInput.trimmingCharacters(in: .whitespaces)
                    guard !cmd.isEmpty else { return }
                    terminalInput = ""
                    rebuilder.runCommand(cmd)
                }
        }
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5))

        HStack(spacing: 12) {
            Button(rebuilder.isRebuilding ? rebuilder.status : "pull & rebuild") {
                rebuilder.rebuild()
            }
            .font(SudoTheme.mono(size: 10))
            .foregroundColor(rebuilder.isRebuilding ? SudoTheme.textMuted : SudoTheme.accent)
            .buttonStyle(.plain)
            .disabled(rebuilder.isRebuilding)
            Button("copy log") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rebuilder.buildLog.joined(separator: "\n"), forType: .string)
            }
            .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.accent).buttonStyle(.plain)
            Button("clear") { rebuilder.clearLog() }
                .font(SudoTheme.mono(size: 10)).foregroundColor(SudoTheme.textMuted).buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Plugins

    @ViewBuilder
    private var pluginsSection: some View {
        sectionHeader("plugins")
        if pluginManager.loadedPlugins.isEmpty {
            Text("no plugins loaded. drop .json files into ~/Library/Application Support/Sudo/Plugins/ to load them.")
                .font(SudoTheme.mono(size: 10))
                .foregroundColor(SudoTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(pluginManager.loadedPlugins) { plugin in
                HStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 10))
                        .foregroundStyle(SudoTheme.accent)
                    Text(plugin.name.lowercased())
                        .font(SudoTheme.mono(size: 11))
                        .foregroundColor(SudoTheme.text)
                    Spacer()
                }
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

import SwiftUI

/// The primary view — device, status, footer. No scrolling needed.
struct MainView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    let onOpenConfig: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("[sudo]")
                    .font(SudoTheme.mono(size: 14, weight: .bold))
                    .foregroundColor(SudoTheme.accent)
                    .accessibilityLabel("sudo home")
                Spacer()
                Circle()
                    .fill(engine.isConnected ? SudoTheme.accent : SudoTheme.error)
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 6)
                    .accessibilityLabel(engine.isConnected ? "connected" : "disconnected")
                Button(action: onOpenConfig) {
                    Text("[=]")
                        .font(SudoTheme.mono(size: 11))
                        .foregroundColor(SudoTheme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("open settings")
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Permission warning (conditional)
            if !engine.isConnected {
                permissionWarning
                SudoDivider()
            }

            // MCP pending request overlay
            if let mcpPrompt = engine.pendingMCPRequest {
                mcpOverlay(prompt: mcpPrompt)
                SudoDivider()
            }

            // Device — the centerpiece
            DeviceView(engine: engine)
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.vertical, 10)
                .opacity(engine.isConnected ? 1.0 : 0.5)

            SudoDivider()

            // Auto-switch notification
            if let switchStatus = engine.autoSwitchStatus {
                HStack {
                    Text(switchStatus)
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.vertical, 4)
            }

            // Compact status line
            HStack {
                if SudoSettings.shared.isSimpleMode {
                    Text("mode:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    Text("simple")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                    Text("·")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.border)
                } else {
                    Text("app:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    Text(engine.detectedApp.lowercased())
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.border)
                }
                Text("last:")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                Text(engine.lastAction.lowercased())
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 8)

            SudoDivider()

            // Update banner
            if updater.updateAvailable {
                HStack {
                    Text("update available: v\(updater.latestVersion)")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                    Spacer()
                    if updater.isUpdating {
                        Text("installing...")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.textMuted)
                    } else {
                        Button("[ install ]") { updater.installUpdate() }
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.accent)
                            .buttonStyle(.plain)
                            .accessibilityLabel("install update")
                    }
                }
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.vertical, 6)
                SudoDivider()
            }

            // Stats
            HStack {
                Text("\(SudoSettings.shared.totalPresses) presses · \(SudoSettings.shared.currentStreak) day streak")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.surface)
                    .lineLimit(1)
                Spacer()
                Text("v\(OTAUpdater.currentVersion)")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.surface)
                    .layoutPriority(1)
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.top, 6)

            // Footer
            HStack(spacing: 8) {
                if SudoSettings.shared.isDeveloperMode {
                    Button(rebuilder.isRebuilding ? rebuilder.status : "pull & rebuild") {
                        rebuilder.rebuild()
                    }
                    .buttonStyle(.plain)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(rebuilder.isRebuilding ? SudoTheme.textMuted : SudoTheme.accent)
                    .disabled(rebuilder.isRebuilding)

                    Text("·")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.border)
                }

                Button("updates") { updater.checkForUpdates() }
                    .buttonStyle(.plain)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                    .accessibilityLabel("check for updates")

                Text("·")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.border)

                Button("bug?") { BugReporter.shared.fileReport(engine: engine) }
                    .buttonStyle(.plain)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                    .accessibilityLabel("report a bug")

                Spacer()

                Button("quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                    .accessibilityLabel("quit sudo")
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(SudoTheme.bg)
    }

    // MARK: - Permission Warning

    @ViewBuilder
    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(engine.axPermissionGranted ? "✓" : "✗")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(engine.axPermissionGranted ? SudoTheme.accent : SudoTheme.error)
                Text("accessibility")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.text)
                Spacer()
                Text(engine.axPermissionGranted ? "ok" : "denied")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(engine.axPermissionGranted ? SudoTheme.accent : SudoTheme.error)
            }

            Text("toggle sudo off then on in accessibility settings")
                .font(SudoTheme.mono(size: 8))
                .foregroundColor(SudoTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("[ open settings ]") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.accent)
                .buttonStyle(.plain)

                Button("[ re-check ]") { engine.checkAndConnect() }
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SudoTheme.spacingMd)
        .padding(.vertical, 8)
    }

    // MARK: - MCP Overlay

    @ViewBuilder
    private func mcpOverlay(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("mcp approval requested:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.accent)
            Text(prompt)
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.text)
                .lineLimit(3)
            HStack(spacing: 12) {
                Button("[ approve ]") { engine.resolveMCPRequest(approved: true) }
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("approve mcp request")
                Button("[ reject ]") { engine.resolveMCPRequest(approved: false) }
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.error)
                    .buttonStyle(.plain)
                    .accessibilityLabel("reject mcp request")
            }
        }
        .padding(.horizontal, SudoTheme.spacingMd)
        .padding(.vertical, 8)
    }
}

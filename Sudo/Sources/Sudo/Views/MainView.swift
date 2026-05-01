import SwiftUI

/// The primary view — device, status, footer. No scrolling needed.
struct MainView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var settings: SudoSettings = .shared
    @ObservedObject var flasher: FirmwareFlasher = .shared
    let onOpenConfig: () -> Void

    var body: some View {
        ZStack {
            mainContent

            // Processing glow overlay
            if engine.isProcessing {
                Rectangle()
                    .fill(SudoTheme.accentGlow)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Success/failure flash overlay
            if engine.lastResult == .success {
                Rectangle()
                    .fill(SudoTheme.accent.opacity(0.03))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else if engine.lastResult == .failure {
                Rectangle()
                    .fill(SudoTheme.error.opacity(0.05))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: 320)
        .animation(.easeOut(duration: SudoTheme.flashDuration), value: engine.lastResult)
        .animation(.easeInOut(duration: 0.3), value: engine.isProcessing)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                headerGlow
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

            // Mode selector — top-level dynamic/simple/custom
            modeSelector
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.top, 6)
                .padding(.bottom, 8)

            SudoDivider()

            // Device — the centerpiece
            DeviceView(engine: engine)
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.vertical, 10)
                .opacity(engine.isConnected ? 1.0 : 0.5)

            // Flash row — appears when bootloader is connected, or as a hint otherwise
            flashRow
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.bottom, 8)

            SudoDivider()

            // Auto-switch notification (slides in/out)
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
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Compact status line
            HStack {
                // Always show target (Sudo is frontmost when popover is open)
                Text("target:")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                if let target = engine.targetAppName {
                    Text(target)
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("none")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.warning)
                }
                if SudoSettings.shared.isSimpleMode {
                    Text("·")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.border)
                    Text("simple")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                }
                Text("·")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.border)
                Text("last:")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                if engine.isProcessing {
                    AnimatedDots()
                } else {
                    Text(engine.lastAction.lowercased())
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
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
                        Button("install") { updater.installUpdate() }
                            .font(SudoTheme.mono(size: 9, weight: .medium))
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
                    .foregroundColor(SudoTheme.textMuted)
                    .lineLimit(1)
                Spacer()
                Text("v\(OTAUpdater.currentVersion)")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
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
        .sudoBackground()
    }

    // MARK: - Mode selector

    @ViewBuilder
    private var modeSelector: some View {
        HStack(spacing: 6) {
            Text("mode:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)
            ForEach(AppMode.allCases, id: \.self) { mode in
                Button(action: { settings.appMode = mode }) {
                    Text("[\(mode.label)]")
                        .font(SudoTheme.mono(size: 9, weight: settings.appMode == mode ? .bold : .regular))
                        .foregroundColor(settings.appMode == mode ? SudoTheme.accent : SudoTheme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("set mode to \(mode.label)")
            }
            Spacer()
            Text(settings.appMode.description)
                .font(SudoTheme.mono(size: 8))
                .foregroundColor(SudoTheme.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Flash row

    @ViewBuilder
    private var flashRow: some View {
        HStack(spacing: 6) {
            switch flasher.state {
            case .idle:
                Text("device:")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                Text("ready")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.text)
                Spacer()
                Button("detect bootsel") { flasher.detectBootloader() }
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
            case .detectingDevice:
                Text("scanning for RPI-RP2...")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                Spacer()
            case .deviceFound:
                Text("bootsel:")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                Text("found")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                Spacer()
                Button("[ flash config ]") { flasher.flashCurrentConfig() }
                    .font(SudoTheme.mono(size: 9, weight: .bold))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("flash current config to device")
            case .flashing(let progress):
                Text(progress)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                    .lineLimit(1)
                Spacer()
            case .success:
                Text("flashed ✓ — device rebooting")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                Spacer()
                Button("ok") { flasher.reset() }
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                    .buttonStyle(.plain)
            case .error(let message):
                Text(message)
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.error)
                    .lineLimit(2)
                Spacer()
                Button("retry") { flasher.reset(); flasher.detectBootloader() }
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
            }
        }
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
                Button("open settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(SudoTheme.mono(size: 9, weight: .medium))
                .foregroundColor(SudoTheme.accent)
                .buttonStyle(.plain)

                Button("re-check") { engine.checkAndConnect() }
                    .font(SudoTheme.mono(size: 9, weight: .medium))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SudoTheme.spacingMd)
        .padding(.vertical, 8)
    }

    // MARK: - Animated status

    /// Pulsing header text during processing
    private var headerGlow: some View {
        Text("[sudo]")
            .font(SudoTheme.mono(size: 14, weight: .bold))
            .foregroundColor(SudoTheme.accent)
            .shadow(color: engine.isProcessing ? SudoTheme.accent.opacity(0.4) : .clear, radius: 6)
            .animation(.easeInOut(duration: SudoTheme.glowDuration).repeatForever(autoreverses: true), value: engine.isProcessing)
            .accessibilityLabel("sudo home")
    }

    // MARK: - MCP Overlay

    @ViewBuilder
    private func mcpOverlay(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("mcp approval requested:")
                .font(SudoTheme.mono(size: 9, weight: .medium))
                .foregroundColor(SudoTheme.accent)
            Text(prompt)
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.text)
                .lineLimit(3)
            HStack(spacing: 12) {
                Button("approve") { engine.resolveMCPRequest(approved: true) }
                    .font(SudoTheme.mono(size: 10, weight: .medium))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("approve mcp request")
                Button("reject") { engine.resolveMCPRequest(approved: false) }
                    .font(SudoTheme.mono(size: 10, weight: .medium))
                    .foregroundColor(SudoTheme.error)
                    .buttonStyle(.plain)
                    .accessibilityLabel("reject mcp request")
            }
        }
        .padding(.horizontal, SudoTheme.spacingMd)
        .padding(.vertical, 8)
    }
}

// MARK: - Animated Dots

/// Pulsing "searching..." dots for the status line
struct AnimatedDots: View {
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("searching" + String(repeating: ".", count: dotCount + 1))
            .font(SudoTheme.mono(size: 9))
            .foregroundColor(SudoTheme.accent)
            .onReceive(timer) { _ in
                dotCount = (dotCount + 1) % 3
            }
    }
}

import SwiftUI

/// The primary view — device, status, footer.
struct MainView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var settings: SudoSettings = .shared
    @ObservedObject var flasher: FirmwareFlasher = .shared
    let onOpenConfig: () -> Void

    /// Auto-switch banner visibility for fade-out (UI 10).
    @State private var autoSwitchVisible: Bool = false

    var body: some View {
        ZStack {
            mainContent

            if engine.isProcessing {
                Rectangle()
                    .fill(SudoTheme.accentGlow)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

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
                    .help(engine.isConnected ? "hotkey listener active" : "not connected — check accessibility permission")
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

            // UI 1: Permission warning — full-width red banner instead of a
            // small line. This is the user's only path back to a working app
            // when accessibility is denied; treat it like a real wall.
            if !engine.isConnected {
                permissionBanner
            }

            if let mcpPrompt = engine.pendingMCPRequest {
                mcpOverlay(prompt: mcpPrompt)
                SudoDivider()
            }

            // UI 3: Mode selector with the active mode's description on its
            // own line below — easier to read than the squeezed inline text.
            modeSelector
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.top, 8)
                .padding(.bottom, 4)
            modeHint
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.bottom, 8)

            SudoDivider()

            // Device — the centerpiece
            DeviceView(engine: engine)
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.vertical, 10)
                .opacity(engine.isConnected ? 1.0 : 0.5)

            // UI 4: Device status panel — connected / firmware / last press.
            // Single compact line under the buttons so the user can always
            // see at a glance whether the pad is reachable.
            deviceStatusPanel
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.bottom, 4)

            // UI 6: Flash row with 3-step indicator + progress bar.
            flashRow
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.bottom, 8)

            SudoDivider()

            // UI 5: Recent action log — last 3 entries with relative timestamps.
            if !engine.actionLog.isEmpty {
                recentActionsList
                    .padding(.horizontal, SudoTheme.spacingMd)
                    .padding(.vertical, 6)
                SudoDivider()
            }

            // UI 10: Auto-switch banner with fade in/out (was abrupt before).
            if autoSwitchVisible, let switchStatus = engine.autoSwitchStatus {
                HStack(spacing: 6) {
                    Text("→")
                        .font(SudoTheme.mono(size: 9, weight: .bold))
                        .foregroundColor(SudoTheme.accent)
                    Text(switchStatus.replacingOccurrences(of: "→ ", with: ""))
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Compact status line
            HStack {
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

            HStack {
                Text("\(SudoSettings.shared.totalPresses) presses · \(SudoSettings.shared.currentStreak) day streak")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                    .lineLimit(1)
                Spacer()
                Text("v\(OTAUpdater.currentVersion)")
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                    .layoutPriority(1)
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.top, 6)

            // Footer — quit gets its own segment so it can't be misclicked.
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
                    .padding(.leading, 12)
                    .accessibilityLabel("quit sudo")
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .sudoBackground()
        .onChange(of: engine.autoSwitchStatus) { newValue in
            if newValue != nil {
                withAnimation(.easeInOut(duration: 0.25)) { autoSwitchVisible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeInOut(duration: 0.5)) { autoSwitchVisible = false }
                }
            }
        }
    }

    // MARK: - UI 1: Permission banner (full-width red wall)

    @ViewBuilder
    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✗")
                    .font(SudoTheme.mono(size: 11, weight: .bold))
                    .foregroundColor(SudoTheme.error)
                Text("accessibility permission required")
                    .font(SudoTheme.mono(size: 10, weight: .semibold))
                    .foregroundColor(SudoTheme.error)
                Spacer()
            }
            Text("sudo needs accessibility access to listen for the macropad's hotkeys and click buttons in other apps. nothing works without it.")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("[ open accessibility settings ]")
                        .font(SudoTheme.mono(size: 10, weight: .bold))
                        .foregroundColor(SudoTheme.error)
                }
                .buttonStyle(.plain)
                Spacer()
                Button("re-check") { engine.checkAndConnect() }
                    .font(SudoTheme.mono(size: 9, weight: .medium))
                    .foregroundColor(SudoTheme.textMuted)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SudoTheme.spacingMd)
        .padding(.vertical, 10)
        .background(SudoTheme.error.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(SudoTheme.error)
                .frame(width: 2)
                .frame(maxHeight: .infinity),
            alignment: .leading
        )
    }

    // MARK: - UI 3: Mode selector + hint line

    @ViewBuilder
    private var modeSelector: some View {
        HStack(spacing: 4) {
            Text("mode:")
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)
                .padding(.trailing, 2)
            ForEach(AppMode.allCases, id: \.self) { mode in
                Button(action: { withAnimation(.easeOut(duration: 0.15)) { settings.appMode = mode } }) {
                    Text("[\(mode.label)]")
                        .font(SudoTheme.mono(size: 10, weight: settings.appMode == mode ? .bold : .regular))
                        .foregroundColor(settings.appMode == mode ? SudoTheme.accent : SudoTheme.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(settings.appMode == mode ? SudoTheme.accent.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.description)
                .accessibilityLabel("set mode to \(mode.label) — \(mode.description)")
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var modeHint: some View {
        Text(settings.appMode.description)
            .font(SudoTheme.mono(size: 8))
            .foregroundColor(SudoTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - UI 4: Device status panel

    @ViewBuilder
    private var deviceStatusPanel: some View {
        let detected = flasher.deviceConnectionLabel
        HStack(spacing: 6) {
            Circle()
                .fill(detected.colour)
                .frame(width: 5, height: 5)
            Text(detected.label)
                .font(SudoTheme.mono(size: 8))
                .foregroundColor(SudoTheme.textMuted)
            Spacer()
            if let last = engine.actionLog.first {
                Text("last: \(timeAgo(last.timestamp))")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
            }
        }
    }

    // MARK: - UI 5: Recent actions list

    @ViewBuilder
    private var recentActionsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(engine.actionLog.prefix(3), id: \.id) { entry in
                HStack(spacing: 6) {
                    Text(entry.succeeded ? "✓" : "✗")
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(entry.succeeded ? SudoTheme.accent : SudoTheme.error)
                        .frame(width: 8, alignment: .leading)
                    Text(entry.action.lowercased())
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.text)
                        .lineLimit(1)
                    Text("·")
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.border)
                    Text(entry.app.lowercased())
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(timeAgo(entry.timestamp))
                        .font(SudoTheme.mono(size: 8))
                        .foregroundColor(SudoTheme.textMuted)
                }
            }
        }
    }

    // MARK: - UI 6: Flash row with 3-step indicator

    @ViewBuilder
    private var flashRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                switch flasher.state {
                case .idle:
                    Text("flash:")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                    Spacer()
                    Button("[ detect device ]") { flasher.detectDevice() }
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                        .buttonStyle(.plain)
                case .detectingDevice:
                    Text("scanning…")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                    Spacer()
                case .readyForConfig:
                    Text("circuitpy: found")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                    Spacer()
                    Button("[ sync config ]") { flasher.flashFirmwareAndConfig() }
                        .font(SudoTheme.mono(size: 9, weight: .bold))
                        .foregroundColor(SudoTheme.accent)
                        .buttonStyle(.plain)
                        .accessibilityLabel("write current config to circuitpy")
                case .readyForFirmware:
                    Text("bootsel: found")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                    Spacer()
                    Button("[ install + flash ]") { flasher.flashFirmwareAndConfig() }
                        .font(SudoTheme.mono(size: 9, weight: .bold))
                        .foregroundColor(SudoTheme.accent)
                        .buttonStyle(.plain)
                        .accessibilityLabel("install circuitpython and flash config")
                case .flashing:
                    flashStepIndicator
                    Spacer()
                    Text("\(Int(flasher.progress * 100))%")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.text)
                case .success:
                    Text("flashed ✓")
                        .font(SudoTheme.mono(size: 9, weight: .bold))
                        .foregroundColor(SudoTheme.accent)
                    Spacer()
                    Button("ok") { flasher.reset() }
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.textMuted)
                        .buttonStyle(.plain)
                case .error:
                    Text("flash failed")
                        .font(SudoTheme.mono(size: 9, weight: .bold))
                        .foregroundColor(SudoTheme.error)
                    Spacer()
                    Button("retry") { flasher.reset(); flasher.detectDevice() }
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.accent)
                        .buttonStyle(.plain)
                }
            }

            if case .flashing = flasher.state {
                ProgressView(value: flasher.progress)
                    .progressViewStyle(.linear)
                    .tint(SudoTheme.accent)
            }

            if !flasher.phase.isEmpty {
                Text(flasher.phase)
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Three-step indicator: reboot → write → verify. Active step is bold +
    /// accent; completed steps are muted accent; pending steps are border.
    @ViewBuilder
    private var flashStepIndicator: some View {
        HStack(spacing: 4) {
            ForEach([FirmwareFlasher.FlashStep.reboot,
                     .write, .verify], id: \.rawValue) { s in
                let active = flasher.step == s
                let done = flasher.step.rawValue > s.rawValue
                Text(stepLabel(s))
                    .font(SudoTheme.mono(size: 9, weight: active ? .bold : .regular))
                    .foregroundColor(active ? SudoTheme.accent
                                     : done ? SudoTheme.accent.opacity(0.5)
                                     : SudoTheme.border)
                if s != .verify {
                    Text("→")
                        .font(SudoTheme.mono(size: 9))
                        .foregroundColor(SudoTheme.border)
                }
            }
        }
    }

    private func stepLabel(_ s: FirmwareFlasher.FlashStep) -> String {
        switch s {
        case .reboot: return "reboot"
        case .write:  return "write"
        case .verify: return "verify"
        }
    }

    // MARK: - Helpers

    /// "3s ago", "2m ago", "1h ago", "yesterday".
    private func timeAgo(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 5  { return "just now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }

    /// Pulsing header text during processing.
    private var headerGlow: some View {
        Text("[sudo]")
            .font(SudoTheme.mono(size: 14, weight: .bold))
            .foregroundColor(SudoTheme.accent)
            .shadow(color: engine.isProcessing ? SudoTheme.accent.opacity(0.4) : .clear, radius: 6)
            .animation(.easeInOut(duration: SudoTheme.glowDuration).repeatForever(autoreverses: true), value: engine.isProcessing)
            .accessibilityLabel("sudo home")
    }

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

// MARK: - FirmwareFlasher device-status helper

extension FirmwareFlasher {
    struct ConnectionLabel {
        let label: String
        let colour: Color
    }

    /// Used by MainView's device-status panel. Reads the same `state` the
    /// flash row reads — keeps "is the pad plugged in?" consistent across
    /// the UI.
    var deviceConnectionLabel: ConnectionLabel {
        switch state {
        case .readyForConfig:
            return .init(label: "device: connected (CircuitPython)", colour: SudoTheme.accent)
        case .readyForFirmware:
            return .init(label: "device: in BOOTSEL — needs install", colour: SudoTheme.warning)
        case .detectingDevice:
            return .init(label: "device: scanning…", colour: SudoTheme.warning)
        case .flashing:
            return .init(label: "device: flashing", colour: SudoTheme.accent)
        case .success:
            return .init(label: "device: just flashed", colour: SudoTheme.accent)
        case .error(let msg):
            return .init(label: "device: error — \(msg)", colour: SudoTheme.error)
        case .idle:
            return .init(label: "device: not detected", colour: SudoTheme.border)
        }
    }
}

// MARK: - Animated Dots

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

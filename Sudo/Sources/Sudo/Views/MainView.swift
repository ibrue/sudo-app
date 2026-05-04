import SwiftUI

/// The popover. Header + 4 button cards + mode picker + footer.
///
/// Anything heavier (flash, settings, presets, updates, bug report, quit)
/// lives behind the gear button → ConfigView. Mode choices are just two:
/// dynamic (app dispatches) and simple (firmware types keystrokes natively).
struct MainView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var settings: SudoSettings = .shared

    let onOpenConfig: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            if !engine.isConnected {
                permissionBanner
            }

            if let mcp = engine.pendingMCPRequest {
                mcpOverlay(prompt: mcp)
            }

            VStack(spacing: 8) {
                ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                    buttonCard(for: action)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            footer
        }
        .frame(width: SudoTheme.popoverWidth)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: engine.isConnected)
        .animation(.easeOut(duration: 0.15), value: engine.lastResult)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("[sudo]")
                .font(SudoTheme.brand)
                .foregroundStyle(SudoTheme.accent)

            Text("v\(OTAUpdater.currentVersion)")
                .font(SudoTheme.code(size: 10))
                .foregroundStyle(.secondary)
                .help("sudo \(OTAUpdater.currentVersion)")

            if updater.updateAvailable {
                Button(action: { updater.checkForUpdates() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SudoTheme.accent)
                }
                .buttonStyle(.plain)
                .help("update available: v\(updater.latestVersion)")
            }

            Spacer()

            Circle()
                .fill(engine.isConnected ? SudoTheme.accent : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
                .help(engine.isConnected ? "connected" : "no accessibility permission")

            Button(action: onOpenConfig) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Button card

    @ViewBuilder
    private func buttonCard(for action: PadAction) -> some View {
        let last = engine.actionLog.first {
            $0.action.lowercased() == action.displayName.lowercased()
        }
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

                if let entry = last {
                    Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(entry.succeeded ? SudoTheme.accent : SudoTheme.error)
                    Text(timeAgo(entry.timestamp))
                        .font(SudoTheme.code(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
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
                        isLastTouched ? tint.opacity(0.6) : Color.primary.opacity(0.08),
                        lineWidth: isLastTouched ? 1.2 : 0.5
                    )
            )
            .shadow(color: isLastTouched ? tint.opacity(0.20) : .clear, radius: 10, y: 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("test press") { engine.triggerAction(action) }
            Button("rename…") { onOpenConfig() }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Picker("", selection: $settings.appMode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 130, alignment: .leading)
            .help(settings.appMode.description)

            Spacer()

            if let target = engine.targetAppName {
                Text(target)
                    .font(SudoTheme.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color.primary.opacity(0.04))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        )
    }

    // MARK: - Permission banner (only when accessibility is missing)

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SudoTheme.error)
                Text("accessibility permission required")
                    .font(SudoTheme.bodyEmphasized)
                Spacer()
            }
            HStack {
                Button("open settings") { URLOpener.openAccessibilitySettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(SudoTheme.error)

                Button("re-check") { engine.checkAndConnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius, style: .continuous)
                .fill(SudoTheme.error.opacity(0.10))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: - MCP overlay (when an MCP request is pending approval)

    @ViewBuilder
    private func mcpOverlay(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("mcp approval requested")
                .font(SudoTheme.bodyEmphasized)
                .foregroundStyle(SudoTheme.accent)
            Text(prompt)
                .font(SudoTheme.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
            HStack(spacing: 8) {
                Button("approve") { engine.resolveMCPRequest(approved: true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(SudoTheme.accent)
                Button("reject") { engine.resolveMCPRequest(approved: false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius, style: .continuous)
                .fill(.thinMaterial)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

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

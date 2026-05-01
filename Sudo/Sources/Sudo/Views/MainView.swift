import SwiftUI
import Cocoa

/// The slim popover. Header + 4 button cards + mode picker + footer.
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

            VStack(spacing: 6) {
                ForEach(PadAction.physicalOrder.reversed(), id: \.rawValue) { action in
                    buttonCard(for: action)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            footer
        }
        .frame(width: 300)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: engine.isConnected)
        .animation(.easeOut(duration: 0.15), value: engine.lastResult)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("[sudo]")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(SudoTheme.accent)

            Spacer()

            // Connection dot
            Circle()
                .fill(engine.isConnected ? SudoTheme.accent : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
                .help(engine.isConnected ? "connected" : "no accessibility permission")

            // Settings gear
            Button(action: onOpenConfig) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Button card

    @ViewBuilder
    private func buttonCard(for action: PadAction) -> some View {
        let last = engine.actionLog.first {
            $0.action.lowercased() == action.displayName.lowercased()
        }
        let tint = Color(hex: action.buttonColorHex)
        let isLastTouched = engine.lastAction.lowercased()
            .contains(action.displayName.lowercased().components(separatedBy: " ").first ?? "")

        Button(action: { engine.triggerAction(action) }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 18, height: 18)
                    Text("\(action.buttonNumber)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint.opacity(0.95))
                }

                Text(action.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if let entry = last {
                    Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(entry.succeeded ? SudoTheme.accent : Color(nsColor: .systemRed))
                    Text(timeAgo(entry.timestamp))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isLastTouched ? tint.opacity(0.45) : Color.primary.opacity(0.06),
                        lineWidth: isLastTouched ? 1 : 0.5
                    )
            )
            .shadow(color: isLastTouched ? tint.opacity(0.18) : .clear, radius: 8, y: 1)
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
            .frame(maxWidth: 110, alignment: .leading)
            .help(settings.appMode.description)

            Spacer()

            if let target = engine.targetAppName {
                Text(target)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Color.primary.opacity(0.04))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        )
    }

    // MARK: - Permission banner (only when accessibility is missing)

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
                Text("accessibility permission required")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            HStack {
                Button("open settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color(nsColor: .systemRed))

                Button("re-check") { engine.checkAndConnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.10))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - MCP overlay (when an MCP request is pending approval)

    @ViewBuilder
    private func mcpOverlay(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("mcp approval requested")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SudoTheme.accent)
            Text(prompt)
                .font(.system(size: 11))
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
        )
        .padding(.horizontal, 12)
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

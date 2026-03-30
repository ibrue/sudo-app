import SwiftUI

struct MenuBarView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @State private var showTestPanel = false

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

            divider

            // Status
            VStack(alignment: .leading, spacing: 6) {
                statusRow(label: "app", value: engine.detectedApp)
                statusRow(label: "last", value: engine.lastAction)
                if !engine.lastMethod.isEmpty {
                    statusRow(label: "via", value: engine.lastMethod)
                }
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.vertical, 10)

            divider

            // Button map
            VStack(alignment: .leading, spacing: SudoTheme.spacingXs) {
                Text("> button map")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.textMuted)
                    .padding(.bottom, 2)

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
                        ForEach(PadAction.allCases, id: \.rawValue) { action in
                            Button(action: { engine.triggerAction(action) }) {
                                VStack(spacing: 2) {
                                    Text("F\(action.fKeyNumber)")
                                        .font(SudoTheme.mono(size: 10, weight: .bold))
                                    Text(action.rawValue)
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

            // Footer
            HStack {
                Button("Check for Updates") {
                    updater.checkForUpdates()
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

import SwiftUI

struct DevicePanel: View {
    @ObservedObject private var flasher = FirmwareFlasher.shared
    @ObservedObject private var padConsole = PadConsoleReader.shared
    @ObservedObject private var settings = SudoSettings.shared

    @State private var copiedConsole = false

    var body: some View {
        SettingsPanelScaffold(
            title: "device",
            subtitle: "flash firmware, check connection state, and collect pad diagnostics."
        ) {
            statusSection
            SudoDivider()
            firmwareSection
            SudoDivider()
            recoverySection
            SudoDivider()
            consoleSection
        }
    }

    private var statusSection: some View {
        SettingsCard("status", ringColor: statusColor.opacity(0.45)) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(flasher.deviceConnectionLabel.label)
                        .font(SudoTheme.bodyEmphasized)
                        .foregroundStyle(SudoTheme.text)
                    Text(statusDetail)
                        .font(SudoTheme.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("scan") { flasher.detectDevice() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if isFlashingOrFinished {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: flasher.progress)
                        .tint(SudoTheme.accent)
                    Text(flasher.phase)
                        .font(SudoTheme.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var firmwareSection: some View {
        SettingsCard("firmware") {
            SettingsRow("pad") {
                Text(flasher.firmwareSourceLabel)
                    .font(SudoTheme.code(size: 11))
                    .foregroundStyle(flasher.firmwareSourceLabel.hasPrefix("missing") ? SudoTheme.error : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            SettingsRow("CircuitPython", hint: FirmwareFlasher.circuitPythonVersion) {
                Text(flasher.circuitPythonSourceLabel)
                    .font(SudoTheme.code(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button("flash pad") {
                    flasher.flashFirmwareAndConfig(settings: settings)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(SudoTheme.accent)
                .disabled(!flasher.canStartFlash)

                Spacer()
            }
        }
    }

    private var recoverySection: some View {
        SettingsCard("recovery") {
            Text(recoveryText)
                .font(SudoTheme.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var consoleSection: some View {
        SettingsCard("pad console") {
            HStack(spacing: 8) {
                Image(systemName: padConsole.isConnected ? "circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(padConsole.isConnected ? SudoTheme.accent : .secondary)
                Text(padConsole.portPath ?? (padConsole.isConnected ? "connected" : "not connected"))
                    .font(padConsole.portPath == nil ? SudoTheme.body : SudoTheme.code(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if padConsole.isConnected {
                    Button("reconnect") { padConsole.reconnect() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("connect") { padConsole.start() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if let error = padConsole.lastError, !padConsole.isConnected {
                Text(error)
                    .font(SudoTheme.caption)
                    .foregroundStyle(SudoTheme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if padConsole.lines.isEmpty {
                            Text("no console output yet")
                                .font(SudoTheme.code(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(padConsole.lines.enumerated()).suffix(200), id: \.offset) { idx, line in
                                Text(line)
                                    .font(SudoTheme.code(size: 11))
                                    .foregroundStyle(consoleLineColor(line))
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: SudoTheme.codeWindowHeight)
                .background(SudoTheme.codeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius)
                        .stroke(SudoTheme.border.opacity(0.3), lineWidth: 0.5)
                )
                .onChange(of: padConsole.lines.count) { _ in
                    if let last = padConsole.lines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 14) {
                Button(copiedConsole ? "copied!" : "copy all") {
                    Clipboard.setString(padConsole.transcript)
                    copiedConsole = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedConsole = false }
                }
                .font(SudoTheme.caption)
                .foregroundColor(SudoTheme.accent)
                .buttonStyle(.plain)
                .disabled(padConsole.lines.isEmpty)

                Button("clear") { padConsole.clear() }
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.textMuted)
                    .buttonStyle(.plain)
                    .disabled(padConsole.lines.isEmpty)

                Spacer()
                Text("\(padConsole.lines.count) lines")
                    .font(SudoTheme.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var isFlashingOrFinished: Bool {
        switch flasher.state {
        case .flashing, .success(_), .failed(_):
            return true
        default:
            return !flasher.phase.isEmpty
        }
    }

    private var statusIcon: String {
        switch flasher.state {
        case .flashMode: return "externaldrive.fill"
        case .bootloader: return "arrow.down.circle.fill"
        case .flashing: return "bolt.horizontal.circle.fill"
        case .success(_): return "checkmark.circle.fill"
        case .failed(_): return "xmark.circle.fill"
        case .running: return "keyboard.fill"
        case .detectingDevice: return "magnifyingglass.circle.fill"
        case .idle, .noDevice: return "keyboard"
        }
    }

    private var statusColor: Color {
        flasher.deviceConnectionLabel.colour
    }

    private var statusDetail: String {
        switch flasher.state {
        case .flashMode:
            return "The CIRCUITPY drive is visible, so firmware and config can be written now."
        case .bootloader:
            return "The board is in BOOTSEL. Sudo will install CircuitPython first, then write pad firmware."
        case .running:
            return "Normal runtime hides CIRCUITPY. Hold button 1 while replugging to expose flash mode."
        case .flashing:
            return "Keep the pad connected until this finishes."
        case .success(let message):
            return message
        case .failed(let message):
            return message
        case .detectingDevice:
            return "Scanning mounted USB volumes and HID state."
        case .idle, .noDevice:
            return "Plug in the pad. For first install or re-flash, hold button 1 while connecting."
        }
    }

    private var recoveryText: String {
        switch flasher.state {
        case .running:
            return "To flash a running pad, unplug it, hold button 1, then plug it back in. Release once CIRCUITPY appears."
        case .flashMode:
            return "Flash is ready. After success, unplug and replug normally so boot.py hides the drive and starts the runtime firmware."
        case .bootloader:
            return "BOOTSEL is for first install or recovery. Sudo will copy the bundled CircuitPython UF2 and wait for CIRCUITPY to appear."
        case .failed(_):
            return "If the pad is unresponsive, unplug it, hold BOOTSEL, plug it back in, then scan and flash again."
        default:
            return "Normal use does not require the CIRCUITPY drive to stay mounted. The app talks to the running pad over HID and CDC."
        }
    }

    private func consoleLineColor(_ line: String) -> Color {
        if line.contains("EXCEPTION") || line.lowercased().contains("error") {
            return SudoTheme.error
        }
        if line.hasPrefix("──") {
            return SudoTheme.textMuted
        }
        return SudoTheme.text
    }
}

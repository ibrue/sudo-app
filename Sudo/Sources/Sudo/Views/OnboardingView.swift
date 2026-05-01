import SwiftUI

/// First-launch walkthrough. Four steps, each auto-checks its own
/// completion condition (no "click next when done" — we just look at
/// engine + flasher state). The user dismisses with `[ start using sudo ]`
/// when everything's green, or `skip` to bail early.
struct OnboardingView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var flasher: FirmwareFlasher = .shared
    @ObservedObject var settings: SudoSettings = .shared
    let onDismiss: () -> Void

    enum Step: Int, CaseIterable {
        case accessibility, plugIn, flash, test

        var title: String {
            switch self {
            case .accessibility: return "grant accessibility"
            case .plugIn:        return "plug in your macropad"
            case .flash:         return "flash the firmware"
            case .test:          return "test a press"
            }
        }

        var hint: String {
            switch self {
            case .accessibility: return "sudo listens for the macropad's hotkeys at the system level. requires accessibility access."
            case .plugIn:        return "USB-C in. on a fresh board, hold BOOTSEL while plugging in. on already-flashed boards, just plug it in."
            case .flash:         return "writes CircuitPython + your config. ~5 seconds on first run. you can do this later from the menu bar."
            case .test:          return "tap any button on the pad — or click a row in the menu bar — to confirm presses register."
            }
        }
    }

    private func isComplete(_ step: Step) -> Bool {
        switch step {
        case .accessibility: return engine.axPermissionGranted
        case .plugIn:
            // Either a CircuitPython device is mounted, or BOOTSEL is mounted.
            return flasher.deviceConnectionLabel.label.contains("connected")
                || flasher.deviceConnectionLabel.label.contains("BOOTSEL")
        case .flash:
            // Mark complete if the device is currently running CircuitPython
            // (which is the post-flash state) or if a flash just succeeded.
            switch flasher.state {
            case .readyForConfig, .success: return true
            default: return false
            }
        case .test:
            return !engine.actionLog.isEmpty
        }
    }

    private var allComplete: Bool {
        Step.allCases.allSatisfy(isComplete)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("[sudo]")
                    .font(SudoTheme.mono(size: 14, weight: .bold))
                    .foregroundColor(SudoTheme.accent)
                Spacer()
                Button("skip") { dismiss() }
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.textMuted)
                    .buttonStyle(.plain)
                    .accessibilityLabel("skip onboarding")
            }
            .padding(.horizontal, SudoTheme.spacingMd)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Text("welcome — let's get you set up")
                .font(SudoTheme.mono(size: 11))
                .foregroundColor(SudoTheme.text)
                .padding(.horizontal, SudoTheme.spacingMd)
                .padding(.bottom, 10)

            SudoDivider()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { step in
                    stepRow(step)
                }
            }
            .padding(SudoTheme.spacingMd)

            SudoDivider()

            HStack {
                Spacer()
                Button(action: dismiss) {
                    Text(allComplete ? "[ start using sudo ]" : "[ \(remainingCount) step\(remainingCount == 1 ? "" : "s") to go ]")
                        .font(SudoTheme.mono(size: 11, weight: .bold))
                        .foregroundColor(allComplete ? SudoTheme.accent : SudoTheme.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!allComplete)
                .accessibilityLabel(allComplete ? "start using sudo" : "complete remaining steps to continue")
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .frame(width: 320)
        .sudoBackground()
    }

    private var remainingCount: Int {
        Step.allCases.filter { !isComplete($0) }.count
    }

    private func dismiss() {
        settings.hasCompletedOnboarding = true
        onDismiss()
    }

    @ViewBuilder
    private func stepRow(_ step: Step) -> some View {
        let done = isComplete(step)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(done ? SudoTheme.accent.opacity(0.15) : SudoTheme.border.opacity(0.3))
                        .frame(width: 18, height: 18)
                    Text(done ? "✓" : "\(step.rawValue + 1)")
                        .font(SudoTheme.mono(size: 10, weight: .bold))
                        .foregroundColor(done ? SudoTheme.accent : SudoTheme.textMuted)
                }
                Text(step.title)
                    .font(SudoTheme.mono(size: 11, weight: done ? .regular : .semibold))
                    .foregroundColor(done ? SudoTheme.textMuted : SudoTheme.text)
                Spacer()
                actionButton(for: step, done: done)
            }
            Text(step.hint)
                .font(SudoTheme.mono(size: 9))
                .foregroundColor(SudoTheme.textMuted)
                .padding(.leading, 26)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(done ? Color.clear : SudoTheme.accent.opacity(0.04))
        )
    }

    @ViewBuilder
    private func actionButton(for step: Step, done: Bool) -> some View {
        if done {
            Text("done")
                .font(SudoTheme.mono(size: 8))
                .foregroundColor(SudoTheme.accent)
        } else {
            switch step {
            case .accessibility:
                Button("open settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(SudoTheme.mono(size: 9, weight: .medium))
                .foregroundColor(SudoTheme.accent)
                .buttonStyle(.plain)
            case .plugIn:
                Button("scan") { flasher.detectDevice() }
                    .font(SudoTheme.mono(size: 9))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
            case .flash:
                Button("flash") { flasher.flashFirmwareAndConfig() }
                    .font(SudoTheme.mono(size: 9, weight: .medium))
                    .foregroundColor(SudoTheme.accent)
                    .buttonStyle(.plain)
                    .disabled({
                        switch flasher.state {
                        case .readyForConfig, .readyForFirmware: return false
                        default: return true
                        }
                    }())
            case .test:
                Text("press any button")
                    .font(SudoTheme.mono(size: 8))
                    .foregroundColor(SudoTheme.textMuted)
            }
        }
    }
}

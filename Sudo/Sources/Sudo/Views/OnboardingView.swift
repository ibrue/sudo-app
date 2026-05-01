import SwiftUI
import Cocoa

/// First-launch walkthrough. Each step auto-checks its own completion
/// condition off engine + flasher state — no "click next when done."
/// Matches the v1.4 popover aesthetic: SF Pro body, glass cards, native
/// macOS controls. The [sudo] mark is the only mono element.
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
            case .accessibility: return "sudo listens for the macropad's hotkeys at the system level."
            case .plugIn:        return "USB-C in. on a fresh board, hold BOOTSEL while plugging in."
            case .flash:         return "writes CircuitPython + your config. ~5 seconds."
            case .test:          return "tap any button on the pad to confirm presses register."
            }
        }
    }

    private func isComplete(_ step: Step) -> Bool {
        switch step {
        case .accessibility: return engine.axPermissionGranted
        case .plugIn:
            return flasher.deviceConnectionLabel.label.contains("connected")
                || flasher.deviceConnectionLabel.label.contains("BOOTSEL")
        case .flash:
            switch flasher.state {
            case .readyForConfig, .success: return true
            default: return false
            }
        case .test:
            return !engine.actionLog.isEmpty
        }
    }

    private var allComplete: Bool { Step.allCases.allSatisfy(isComplete) }
    private var remaining: Int { Step.allCases.filter { !isComplete($0) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Text("welcome — let's get you set up.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { step in
                    stepRow(step)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 12)

            HStack {
                Spacer()
                Button(action: dismiss) {
                    Text(allComplete ? "start using sudo" : "\(remaining) step\(remaining == 1 ? "" : "s") remaining")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(SudoTheme.accent)
                .disabled(!allComplete)
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .frame(width: 320)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("[sudo]")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(SudoTheme.accent)

            Spacer()

            Button("skip") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func dismiss() {
        settings.hasCompletedOnboarding = true
        onDismiss()
    }

    @ViewBuilder
    private func stepRow(_ step: Step) -> some View {
        let done = isComplete(step)
        HStack(alignment: .top, spacing: 10) {
            // Status badge (number when pending, checkmark when done)
            ZStack {
                Circle()
                    .fill(done ? SudoTheme.accent.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SudoTheme.accent)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 12, weight: done ? .regular : .semibold))
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done, color: .secondary)
                Text(step.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            actionButton(for: step, done: done)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func actionButton(for step: Step, done: Bool) -> some View {
        if done { EmptyView() } else {
            switch step {
            case .accessibility:
                Button("open settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .plugIn:
                Button("scan") { flasher.detectDevice() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .flash:
                Button("flash") { flasher.flashFirmwareAndConfig() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(SudoTheme.accent)
                    .disabled({
                        switch flasher.state {
                        case .readyForConfig, .readyForFirmware: return false
                        default: return true
                        }
                    }())
            case .test:
                EmptyView()
            }
        }
    }
}

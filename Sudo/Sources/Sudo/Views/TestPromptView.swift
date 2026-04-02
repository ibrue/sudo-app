import SwiftUI

/// A fake AI agent permission prompt for testing the sudo app.
/// Opens as a separate window with Allow/Deny buttons that the
/// sudo engine can detect and click via accessibility tree.
///
/// Note: Button labels use Title Case intentionally — they simulate real app
/// buttons (e.g. "Allow", "Deny") which is what the AX finder searches for.
struct TestPromptView: View {
    @State private var log: [String] = []
    @State private var promptCount = 1

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("[sudo] test prompt")
                    .font(SudoTheme.mono(size: 13, weight: .bold))
                    .foregroundColor(SudoTheme.accent)
                Spacer()
                Text("prompt #\(promptCount)")
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            SudoDivider()

            // Fake agent request
            VStack(alignment: .leading, spacing: 8) {
                Text("$ claude agent wants to execute:")
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.textMuted)

                Text("  read_file(\"/Users/you/project/config.json\")")
                    .font(SudoTheme.mono(size: 12))
                    .foregroundColor(SudoTheme.text)

                Text("This will read a file from your filesystem.")
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.textMuted)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            SudoDivider()

            // Permission buttons — Title Case intentional (simulates real app buttons)
            HStack(spacing: 12) {
                Button("Allow") {
                    log.append("[\(timestamp())] Allow clicked (manually)")
                    promptCount += 1
                }
                .buttonStyle(TestButtonStyle(color: SudoTheme.accent))
                .accessibilityLabel("Allow")

                Button("Allow Once") {
                    log.append("[\(timestamp())] Allow Once clicked (manually)")
                    promptCount += 1
                }
                .buttonStyle(TestButtonStyle(color: SudoTheme.accent))
                .accessibilityLabel("Allow Once")

                Button("Deny") {
                    log.append("[\(timestamp())] Deny clicked (manually)")
                    promptCount += 1
                }
                .buttonStyle(TestButtonStyle(color: SudoTheme.error))
                .accessibilityLabel("Deny")
            }
            .padding(16)

            SudoDivider()

            // Action log
            VStack(alignment: .leading, spacing: 4) {
                Text("> action log")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.textMuted)

                if log.isEmpty {
                    Text("Waiting for sudo to press a button...")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.textMuted)
                } else {
                    ForEach(log.suffix(5), id: \.self) { entry in
                        Text(entry)
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.accent)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SudoTheme.bg)
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

struct TestButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SudoTheme.mono(size: 12, weight: .medium))
            .foregroundColor(configuration.isPressed ? SudoTheme.bg : color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? color : Color.clear)
            .overlay(
                Rectangle()
                    .stroke(color, lineWidth: 1)
            )
    }
}

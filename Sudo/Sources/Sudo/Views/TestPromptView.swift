import SwiftUI

/// A fake AI agent permission prompt for testing the sudo app.
/// Opens as a separate window with Allow/Deny buttons that the
/// sudo engine can detect and click via accessibility tree.
struct TestPromptView: View {
    @State private var log: [String] = []
    @State private var promptCount = 1

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("[sudo] test prompt")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x00FF41))
                Spacer()
                Text("prompt #\(promptCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: 0x666666))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(Color(hex: 0x1E1E1E)).frame(height: 1)

            // Fake agent request
            VStack(alignment: .leading, spacing: 8) {
                Text("$ claude agent wants to execute:")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: 0x666666))

                Text("  read_file(\"/Users/you/project/config.json\")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(hex: 0xF0F0F0))

                Text("This will read a file from your filesystem.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: 0x666666))
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Color(hex: 0x1E1E1E)).frame(height: 1)

            // Permission buttons — these are what sudo detects
            HStack(spacing: 12) {
                // The "Allow" button — sudo's approve action searches for this
                Button("Allow") {
                    log.append("[\(timestamp())] Allow clicked (manually)")
                    promptCount += 1
                }
                .buttonStyle(TestButtonStyle(color: Color(hex: 0x00FF41)))
                .accessibilityLabel("Allow")

                // The "Allow Once" variant
                Button("Allow Once") {
                    log.append("[\(timestamp())] Allow Once clicked (manually)")
                    promptCount += 1
                }
                .buttonStyle(TestButtonStyle(color: Color(hex: 0x00FF41)))
                .accessibilityLabel("Allow Once")

                // The "Deny" button — sudo's reject action searches for this
                Button("Deny") {
                    log.append("[\(timestamp())] Deny clicked (manually)")
                    promptCount += 1
                }
                .buttonStyle(TestButtonStyle(color: Color(hex: 0xFF3333)))
                .accessibilityLabel("Deny")
            }
            .padding(16)

            Rectangle().fill(Color(hex: 0x1E1E1E)).frame(height: 1)

            // Action log
            VStack(alignment: .leading, spacing: 4) {
                Text("> action log")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: 0x666666))

                if log.isEmpty {
                    Text("Waiting for sudo to press a button...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: 0x666666))
                } else {
                    ForEach(log.suffix(5), id: \.self) { entry in
                        Text(entry)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: 0x00FF41))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x0A0A0A))
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
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(configuration.isPressed ? Color(hex: 0x0A0A0A) : color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? color : Color.clear)
            .overlay(
                Rectangle()
                    .stroke(color, lineWidth: 1)
            )
    }
}

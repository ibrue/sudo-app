import SwiftUI

struct MenuBarView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("[sudo]")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x00FF41))
                Spacer()
                Circle()
                    .fill(engine.isConnected ? Color(hex: 0x00FF41) : Color(hex: 0xFF3333))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            divider

            // Button map
            VStack(alignment: .leading, spacing: 4) {
                Text("> button map")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: 0x666666))
                    .padding(.bottom, 2)

                ForEach(PadAction.allCases, id: \.rawValue) { action in
                    HStack {
                        Text("F\(action.fKeyNumber)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: 0x00FF41))
                            .frame(width: 30, alignment: .leading)
                        Text(action.displayName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Update banner
            if updater.updateAvailable {
                divider

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("update available")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: 0x00FF41))
                        Spacer()
                        Text("v\(updater.latestVersion)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: 0x666666))
                    }

                    if updater.isUpdating {
                        ProgressView(value: updater.updateProgress)
                            .tint(Color(hex: 0x00FF41))
                        Text("installing...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: 0x666666))
                    } else {
                        Button(action: { updater.installUpdate() }) {
                            Text("[ INSTALL UPDATE ]")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(hex: 0x00FF41))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 0)
                                        .stroke(Color(hex: 0x00FF41), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            divider

            // Footer
            HStack {
                Button("Check for Updates") {
                    updater.checkForUpdates()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: 0x666666))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: 0x666666))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Version
            HStack {
                Spacer()
                Text("v\(OTAUpdater.currentVersion)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: 0x333333))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(width: 320)
        .background(Color(hex: 0x0A0A0A))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(hex: 0x1E1E1E))
            .frame(height: 1)
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: 0x666666))
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
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

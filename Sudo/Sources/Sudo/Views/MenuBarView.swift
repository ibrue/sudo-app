import SwiftUI

struct MenuBarView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var settings = SudoSettings.shared
    @State private var showTestPanel = false
    @State private var showRemapPanel = false
    @State private var editingAction: PadAction? = nil
    @State private var editName = ""
    @State private var editTerms = ""

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
                HStack {
                    Text("> button map")
                        .font(SudoTheme.mono(size: 10))
                        .foregroundColor(SudoTheme.textMuted)
                    Spacer()
                    Button(action: { showRemapPanel.toggle() }) {
                        Text(showRemapPanel ? "done" : "edit")
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)

                if showRemapPanel {
                    remapPanel
                } else {
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
                        ForEach(PadAction.allCases, id: \.rawValue) { padAction in
                            Button(action: { engine.triggerAction(padAction) }) {
                                VStack(spacing: 2) {
                                    Text("F\(padAction.fKeyNumber)")
                                        .font(SudoTheme.mono(size: 10, weight: .bold))
                                    Text(padAction.rawValue)
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

                    // Search all apps toggle
                    Button(action: { engine.searchAllApps.toggle() }) {
                        HStack {
                            Text(engine.searchAllApps ? "[x]" : "[ ]")
                                .font(SudoTheme.mono(size: 10))
                                .foregroundColor(SudoTheme.accent)
                            Text("search all apps (not just focused)")
                                .font(SudoTheme.mono(size: 9))
                                .foregroundColor(SudoTheme.textMuted)
                        }
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

    // MARK: - Remap Panel

    @ViewBuilder
    private var remapPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(PadAction.allCases, id: \.rawValue) { action in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("F\(action.fKeyNumber)")
                            .font(SudoTheme.mono(size: 11))
                            .foregroundColor(SudoTheme.accent)
                            .frame(width: 30, alignment: .leading)

                        if editingAction == action {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("name:")
                                        .font(SudoTheme.mono(size: 9))
                                        .foregroundColor(SudoTheme.textMuted)
                                    TextField("", text: $editName)
                                        .font(SudoTheme.mono(size: 10))
                                        .textFieldStyle(.plain)
                                        .foregroundColor(SudoTheme.text)
                                }
                                HStack {
                                    Text("find:")
                                        .font(SudoTheme.mono(size: 9))
                                        .foregroundColor(SudoTheme.textMuted)
                                    TextField("comma-separated terms", text: $editTerms)
                                        .font(SudoTheme.mono(size: 10))
                                        .textFieldStyle(.plain)
                                        .foregroundColor(SudoTheme.text)
                                }
                                HStack(spacing: 8) {
                                    Button("save") {
                                        settings.buttonNames[action.rawValue] = editName.isEmpty ? nil : editName
                                        let terms = editTerms.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                        settings.buttonSearchTerms[action.rawValue] = terms.isEmpty ? nil : terms
                                        editingAction = nil
                                    }
                                    .font(SudoTheme.mono(size: 9))
                                    .foregroundColor(SudoTheme.accent)
                                    .buttonStyle(.plain)

                                    Button("reset") {
                                        settings.buttonNames[action.rawValue] = nil
                                        settings.buttonSearchTerms[action.rawValue] = nil
                                        editingAction = nil
                                    }
                                    .font(SudoTheme.mono(size: 9))
                                    .foregroundColor(SudoTheme.error)
                                    .buttonStyle(.plain)

                                    Button("cancel") {
                                        editingAction = nil
                                    }
                                    .font(SudoTheme.mono(size: 9))
                                    .foregroundColor(SudoTheme.textMuted)
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            Text(action.displayName)
                                .font(SudoTheme.mono(size: 11))
                                .foregroundColor(SudoTheme.text)
                            Spacer()
                            Button("edit") {
                                editName = settings.buttonNames[action.rawValue] ?? action.defaultDisplayName
                                editTerms = (settings.buttonSearchTerms[action.rawValue] ?? action.defaultSearchTerms).joined(separator: ", ")
                                editingAction = action
                            }
                            .font(SudoTheme.mono(size: 9))
                            .foregroundColor(SudoTheme.accent)
                            .buttonStyle(.plain)
                        }
                    }

                    if editingAction != action {
                        let terms = settings.searchTerms(for: action).prefix(3).joined(separator: ", ")
                        Text("searches: \(terms)...")
                            .font(SudoTheme.mono(size: 8))
                            .foregroundColor(SudoTheme.surface)
                            .padding(.leading, 30)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Helpers

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

import SwiftUI

/// Action history — last N executed actions with success/fail markers.
struct HistoryPanel: View {
    @ObservedObject var engine: SudoEngine

    private static let pageSize = 200

    var body: some View {
        SettingsPanelScaffold(
            title: "history",
            subtitle: "the most recent button presses, what app they targeted, and whether they succeeded."
        ) {
            if engine.actionLog.isEmpty {
                Text("no actions logged yet — press a button to see it here.")
                    .font(SudoTheme.mono(size: 11))
                    .foregroundColor(SudoTheme.textMuted)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                let entries = Array(engine.actionLog.prefix(Self.pageSize))
                Text("\(entries.count) entries")
                    .font(SudoTheme.mono(size: 10))
                    .foregroundColor(SudoTheme.textMuted)
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text(entry.succeeded ? "✓" : "✗")
                            .font(SudoTheme.mono(size: 11))
                            .foregroundColor(entry.succeeded ? SudoTheme.accent : SudoTheme.error)
                            .frame(width: 14)
                        Text(entry.timeString)
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                            .frame(width: 70, alignment: .leading)
                        Text(entry.action)
                            .font(SudoTheme.mono(size: 11))
                            .foregroundColor(SudoTheme.text)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.app)
                            .font(SudoTheme.mono(size: 10))
                            .foregroundColor(SudoTheme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

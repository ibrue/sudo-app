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
                    .font(SudoTheme.body)
                    .foregroundColor(SudoTheme.textMuted)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                let entries = Array(engine.actionLog.prefix(Self.pageSize))
                Text("\(entries.count) entries")
                    .font(SudoTheme.caption)
                    .foregroundColor(SudoTheme.textMuted)
                    .monospacedDigit()
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(entry.succeeded ? SudoTheme.accent : SudoTheme.error)
                            .frame(width: 16)
                        Text(entry.timeString)
                            .font(SudoTheme.code(size: 11))
                            .foregroundColor(SudoTheme.textMuted)
                            .frame(width: 80, alignment: .leading)
                        Text(entry.action)
                            .font(SudoTheme.body)
                            .foregroundColor(SudoTheme.text)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.app)
                            .font(SudoTheme.caption)
                            .foregroundColor(SudoTheme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

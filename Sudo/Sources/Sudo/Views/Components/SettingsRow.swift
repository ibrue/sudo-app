import SwiftUI

/// Form-style label/control row. The label column is fixed at
/// `SudoTheme.formLabelWidth` so editors across panels share a
/// left edge — fixes the ragged-edge problem where ButtonsPanel
/// used 50pt, MacrosPanel used 60pt, AutoApprovePanel used 80pt.
struct SettingsRow<Content: View>: View {
    let label: String
    let hint: String?
    let content: Content

    init(
        _ label: String,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(label)
                    .font(SudoTheme.body)
                    .foregroundStyle(.secondary)
                if let hint {
                    Text(hint)
                        .font(SudoTheme.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: SudoTheme.formLabelWidth, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

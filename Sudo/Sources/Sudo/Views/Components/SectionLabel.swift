import SwiftUI

/// Uppercase tracked label used as a section header across the
/// Settings window and the popover. Replaces the seven private
/// `sectionHeader(_:)` helpers that used to live inside each panel.
///
/// Style: 11pt semibold, +0.5 tracking, lowercased input then
/// `.textCase(.uppercase)` so callers pass natural strings.
/// The tracking + casing combo is what makes section headers
/// read as macOS-native chrome rather than as body text.
struct SectionLabel: View {
    let title: String
    let count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(SudoTheme.sectionTitle)
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(SudoTheme.code(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

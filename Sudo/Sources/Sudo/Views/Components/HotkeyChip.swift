import SwiftUI

/// Mono pill for displaying a single hotkey binding or key combo —
/// e.g. `⌃⇧F13`. Used in GeneralPanel (hotkey list) and MacrosPanel
/// (keystroke step display). One styling source so the two places
/// don't drift.
struct HotkeyChip: View {
    let text: String
    var emphasis: Emphasis = .normal

    enum Emphasis {
        case normal
        case accent
    }

    var body: some View {
        Text(text)
            .font(SudoTheme.code(size: 11, weight: .medium))
            .foregroundStyle(emphasis == .accent ? Color.accentColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(SudoTheme.cardSurface, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: SudoTheme.ringWidth)
            }
    }
}

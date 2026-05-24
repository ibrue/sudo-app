import SwiftUI

/// Monospaced scrollback list. Replaces three near-identical
/// `ScrollViewReader { ScrollView { ... }.frame(height: 260) }`
/// blocks in DeveloperPanel (pad console, debug console, build
/// terminal). Each was ~80 lines; one component is ~50.
///
/// Auto-scrolls to the bottom when the line count grows. Callers
/// pass an array of `Line` with optional severity colour and an
/// `id` Hashable for stable ScrollViewReader targeting.
struct CodeWindow<ID: Hashable>: View {
    struct Line: Identifiable {
        let id: ID
        let text: String
        var color: Color = .primary
        var monospacedDigit: Bool = false
    }

    let lines: [Line]
    var emptyText: String = "no logs yet."
    var height: CGFloat = SudoTheme.codeWindowHeight
    var fontSize: CGFloat = 11
    /// Provide stable IDs so ScrollViewReader can target a row.
    /// When `nil` we use index.

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if lines.isEmpty {
                        Text(emptyText)
                            .font(SudoTheme.body)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(SudoTheme.code(size: fontSize))
                                .foregroundStyle(line.color)
                                .textSelection(.enabled)
                                .monospacedDigit()
                                .id(line.id)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .background(SudoTheme.codeBackground)
            .overlay {
                RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: SudoTheme.ringWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius))
            .onChange(of: lines.count) { _ in
                if let last = lines.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }
}

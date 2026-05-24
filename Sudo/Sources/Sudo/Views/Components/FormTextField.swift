import SwiftUI

/// Unified single-line text field used in editor rows. One appearance
/// across every panel — `.roundedBorder` style, `SudoTheme.body` font.
/// Replaces the bare `TextField + .roundedBorder + .body` triplets
/// that were copy-pasted across ButtonsPanel, MacrosPanel,
/// AutoApprovePanel — and the rogue `.plain` style on the
/// DeveloperPanel terminal input that made the field visually disappear.
struct FormTextField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced: Bool = false
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? SudoTheme.code(size: 12) : SudoTheme.body)
            .onSubmit { onSubmit?() }
    }
}

import SwiftUI

/// `[sudo]` brand mark — the bracketed monospace logo. Sized
/// variants for: inline header (small), hero (large, used in
/// AboutPanel and the onboarding splash).
struct BrandMark: View {
    enum Size {
        case inline   // header strip (~13pt)
        case hero     // about + onboarding (~28pt in a 76pt tinted square)
    }

    var size: Size = .inline

    var body: some View {
        switch size {
        case .inline:
            Text("[sudo]")
                .font(SudoTheme.brand)
                .foregroundStyle(.primary)
        case .hero:
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SudoTheme.accentSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(SudoTheme.accent.opacity(0.4), lineWidth: SudoTheme.ringWidth)
                    }
                Text("[sudo]")
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SudoTheme.accent)
            }
            .frame(width: 76, height: 76)
        }
    }
}

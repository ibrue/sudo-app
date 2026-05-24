import SwiftUI

/// Tappable link row used in the AboutPanel and anywhere else we
/// surface an external link. Mac-native styling: leading SF Symbol
/// (hierarchical), title + secondary subtitle, trailing chevron.
struct LinkRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let urlString: String
    @State private var isHovered = false

    init(_ title: String, subtitle: String? = nil, systemImage: String, url: String) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.urlString = url
    }

    var body: some View {
        Button(action: { URLOpener.open(urlString) }) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(SudoTheme.body)
                    if let subtitle {
                        Text(subtitle)
                            .font(SudoTheme.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? SudoTheme.cardSurfaceHover : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

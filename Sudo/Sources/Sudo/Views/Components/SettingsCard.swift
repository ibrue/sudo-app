import SwiftUI

/// Generic card container used by both popover and Settings panels.
/// Replaces the ad-hoc `RoundedRectangle.fill(cardSurface).stroke(...)`
/// blocks that were scattered through MacrosPanel / AutoApprovePanel /
/// ButtonsPanel / DeveloperPanel.
///
/// Optional `title:` renders a `SectionLabel` at the top.
/// Optional `accessory:` renders trailing controls aligned with the title
/// (used by macro cards for the "btn N" chip + edit/delete pills).
struct SettingsCard<Content: View, Accessory: View>: View {
    let title: String?
    let surface: Color
    let ringColor: Color?
    let ringWidth: CGFloat
    let accessory: Accessory
    let content: Content

    init(
        _ title: String? = nil,
        surface: Color = SudoTheme.cardSurface,
        ringColor: Color? = nil,
        ringWidth: CGFloat = SudoTheme.ringWidth,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.surface = surface
        self.ringColor = ringColor
        self.ringWidth = ringWidth
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let title { SectionLabel(title) }
                    accessory
                }
            }
            content
        }
        .padding(SudoTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sudoCard(surface, ringColor: ringColor, ringWidth: ringWidth)
    }
}

// Convenience: no accessory needed.
extension SettingsCard where Accessory == EmptyView {
    init(
        _ title: String? = nil,
        surface: Color = SudoTheme.cardSurface,
        ringColor: Color? = nil,
        ringWidth: CGFloat = SudoTheme.ringWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            surface: surface,
            ringColor: ringColor,
            ringWidth: ringWidth,
            accessory: { EmptyView() },
            content: content
        )
    }
}

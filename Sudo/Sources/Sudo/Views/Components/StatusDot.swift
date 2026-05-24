import SwiftUI

/// Small status indicator dot. Used by the popover header, the
/// developer panel API row, and the pad-console "connected" badge.
/// Brand-green when "on", muted when "off" — `SudoTheme.accent`
/// (brand) is correct here because this is a *status* signal, not
/// a user-action affordance.
struct StatusDot: View {
    let isOn: Bool
    var diameter: CGFloat = 6
    var onColor: Color = SudoTheme.accent
    var offColor: Color = Color.secondary.opacity(0.4)

    var body: some View {
        Circle()
            .fill(isOn ? onColor : offColor)
            .frame(width: diameter, height: diameter)
            .animation(.smooth, value: isOn)
    }
}

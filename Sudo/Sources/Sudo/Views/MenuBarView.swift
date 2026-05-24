import SwiftUI

/// Root menu bar popover — switches between onboarding (first launch)
/// and the main view. The old ConfigView (a secondary in-popover
/// settings surface) was deleted in v2; the gear button now opens
/// the standalone Settings window directly.
struct MenuBarView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var apiServer: LocalAPIServer
    @ObservedObject var settings: SudoSettings = .shared

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                OnboardingView(engine: engine, onDismiss: {})
                    .transition(.opacity)
            } else {
                MainView(
                    engine: engine,
                    updater: updater,
                    rebuilder: rebuilder,
                    apiServer: apiServer
                )
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: settings.hasCompletedOnboarding)
    }
}

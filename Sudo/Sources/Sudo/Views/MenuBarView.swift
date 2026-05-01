import SwiftUI

/// Root menu bar popover — switches between onboarding (first launch),
/// main view, and config view.
struct MenuBarView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var apiServer: LocalAPIServer
    @ObservedObject var settings: SudoSettings = .shared

    enum ViewMode { case main, config }
    @State private var currentView: ViewMode = .main

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                OnboardingView(engine: engine, onDismiss: {})
                    .transition(.opacity)
            } else if currentView == .main {
                MainView(
                    engine: engine,
                    updater: updater,
                    rebuilder: rebuilder,
                    onOpenConfig: { withAnimation(.easeInOut(duration: 0.2)) { currentView = .config } }
                )
                .transition(.move(edge: .leading))
            } else {
                ConfigView(
                    engine: engine,
                    updater: updater,
                    rebuilder: rebuilder,
                    apiServer: apiServer,
                    onBack: { withAnimation(.easeInOut(duration: 0.2)) { currentView = .main } }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: settings.hasCompletedOnboarding)
    }
}

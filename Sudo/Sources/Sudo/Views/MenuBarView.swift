import SwiftUI

/// Root menu bar popover — switches between main view and config view.
struct MenuBarView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var apiServer: LocalAPIServer

    enum ViewMode { case main, config }
    @State private var currentView: ViewMode = .main

    var body: some View {
        if currentView == .main {
            MainView(
                engine: engine,
                updater: updater,
                rebuilder: rebuilder,
                onOpenConfig: { currentView = .config }
            )
        } else {
            ConfigView(
                engine: engine,
                updater: updater,
                rebuilder: rebuilder,
                apiServer: apiServer,
                onBack: { currentView = .main }
            )
        }
    }
}

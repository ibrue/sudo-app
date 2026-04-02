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
        Group {
            if currentView == .main {
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
    }
}

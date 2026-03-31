import SwiftUI
import Cocoa

@main
struct SudoApp: App {
    @StateObject private var engine = SudoEngine()
    @StateObject private var updater = OTAUpdater()
    @StateObject private var rebuilder = DevRebuilder()
    @StateObject private var apiServer = LocalAPIServer()
    @State private var hasLaunched = false
    @State private var dotFrame = 0

    private let dotTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Fixed 4-char content between brackets
    private var menuBarLabel: String {
        switch engine.lastResult {
        case .success:
            return "[okay]"
        case .failure:
            return "[fail]"
        case .processing:
            let frame = dotFrame % 4
            let patterns = ["·___", "··__", "···_", "····"]
            return "[\(patterns[frame])]"
        case .idle:
            return "[sudo]"
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine, updater: updater, rebuilder: rebuilder, apiServer: apiServer)
                .onAppear {
                    guard !hasLaunched else { return }
                    hasLaunched = true
                    engine.start()
                    updater.startPeriodicChecks()
                    apiServer.start(engine: engine)
                }
        } label: {
            Text(menuBarLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .onReceive(dotTimer) { _ in
                    if engine.isProcessing {
                        dotFrame += 1
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI
import Cocoa

@main
struct SudoApp: App {
    @StateObject private var engine = SudoEngine()
    @StateObject private var updater = OTAUpdater()
    @State private var hasLaunched = false
    @State private var dotFrame = 0

    private let dotTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Fixed 4-char content between brackets: "sudo" or animated dots
    private var menuBarLabel: String {
        if engine.isProcessing {
            let frame = dotFrame % 4
            // Use middle dot (·) and underscore for consistent monospace width
            let patterns = ["·___", "··__", "···_", "····"]
            return "[\(patterns[frame])]"
        }
        return "[sudo]"
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine, updater: updater)
                .onAppear {
                    guard !hasLaunched else { return }
                    hasLaunched = true
                    engine.start()
                    updater.startPeriodicChecks()
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

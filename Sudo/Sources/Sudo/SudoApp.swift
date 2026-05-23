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

    /// Menu bar label. Stays compact (≤14 chars) so it doesn't crowd the
    /// system tray. Shows a transient tag of what the pad just did, then
    /// drops back to the brand mark.
    ///
    ///   processing  → [····]  (animated)
    ///   success     → [✓ <name>]
    ///   failure     → [✗ <name>]
    ///   idle        → [sudo]
    private var menuBarLabel: String {
        switch engine.lastResult {
        case .processing:
            let frame = dotFrame % 4
            let patterns = ["·___", "··__", "···_", "····"]
            return "[\(patterns[frame])]"
        case .success:
            return "[✓ \(shortName())]"
        case .failure:
            return "[✗ \(shortName())]"
        case .idle:
            return "[sudo]"
        }
    }

    /// First word of the most recent action, lowercased, capped to 8 chars.
    /// Keeps the menu bar item readable without expanding aggressively.
    private func shortName() -> String {
        let log = engine.actionLog
        let raw = log.first?.action ?? engine.lastAction
        let word = raw.lowercased()
            .components(separatedBy: .whitespaces)
            .first ?? raw.lowercased()
        return String(word.prefix(8))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine, updater: updater, rebuilder: rebuilder, apiServer: apiServer)
                .onAppear {
                    if !hasLaunched {
                        hasLaunched = true
                        engine.start()
                        updater.startPeriodicChecks()
                        apiServer.start(engine: engine)
                    } else if !engine.isConnected {
                        // User opened the popover while the banner is showing —
                        // re-check immediately instead of waiting up to 3 s for
                        // the timer. Common case: user just granted Accessibility
                        // in System Settings and switched back to the app.
                        engine.checkAndConnect()
                    }
                }
        } label: {
            Text(menuBarLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .onReceive(dotTimer) { _ in
                    if engine.isProcessing {
                        dotFrame += 1
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

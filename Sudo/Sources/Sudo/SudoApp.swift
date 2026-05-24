import SwiftUI
import Cocoa

/// Single owner for process-wide services. The `NSApplicationDelegate`
/// instance is created by SwiftUI, so keeping services on a separate
/// singleton avoids accidentally creating a second engine/event tap graph.
final class SudoAppServices {
    static let shared = SudoAppServices()

    let engine = SudoEngine()
    let updater = OTAUpdater()
    let rebuilder = DevRebuilder()
    let apiServer = LocalAPIServer()

    private var started = false

    private init() {}

    func startIfNeeded() {
        if started { return }
        started = true
        engine.start()
        updater.startPeriodicChecks()
        apiServer.start(engine: engine)
    }
}

/// AppDelegate that triggers engine + service startup as soon as
/// `applicationDidFinishLaunching` fires — i.e. immediately at app
/// launch, BEFORE the user clicks the menu bar icon.
final class SudoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SudoAppServices.shared.startIfNeeded()
    }
}

@main
struct SudoApp: App {
    @NSApplicationDelegateAdaptor(SudoAppDelegate.self) private var appDelegate

    @ObservedObject private var engine: SudoEngine
    @ObservedObject private var updater: OTAUpdater
    @ObservedObject private var rebuilder: DevRebuilder
    @ObservedObject private var apiServer: LocalAPIServer
    @State private var dotFrame = 0

    private let dotTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    init() {
        let services = SudoAppServices.shared
        _engine = ObservedObject(initialValue: services.engine)
        _updater = ObservedObject(initialValue: services.updater)
        _rebuilder = ObservedObject(initialValue: services.rebuilder)
        _apiServer = ObservedObject(initialValue: services.apiServer)
    }

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
                    // Belt-and-suspenders: the AppDelegate already calls
                    // startIfNeeded at applicationDidFinishLaunching, but
                    // re-call here in case some launch path bypasses the
                    // delegate. Idempotent.
                    SudoAppServices.shared.startIfNeeded()
                    if engine.isConnected == false {
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

import SwiftUI
import Cocoa

@main
struct SudoApp: App {
    @StateObject private var engine = SudoEngine()
    @StateObject private var updater = OTAUpdater()
    @State private var hasLaunched = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine, updater: updater)
                .onAppear {
                    guard !hasLaunched else { return }
                    hasLaunched = true
                    engine.start()
                    updater.startPeriodicChecks()
                    checkAccessibilityPermission()
                }
        } label: {
            Text("[sudo]")
                .font(SudoTheme.mono(size: 9, weight: .medium))
        }
        .menuBarExtraStyle(.window)
    }

    private func checkAccessibilityPermission() {
        if AXIsProcessTrusted() {
            print("[sudo] Accessibility permission granted")
            return
        }

        // Only show the system prompt once — after that, the user knows where to find it
        let key = "hasShownAccessibilityPrompt"
        if UserDefaults.standard.bool(forKey: key) {
            print("[sudo] Accessibility not granted (prompt already shown before)")
            return
        }

        print("[sudo] Accessibility permission not granted — showing prompt")
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        UserDefaults.standard.set(true, forKey: key)
    }
}

import SwiftUI
import Cocoa

@main
struct SudoApp: App {
    @StateObject private var engine = SudoEngine()
    @StateObject private var updater = OTAUpdater()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine, updater: updater)
                .onAppear {
                    engine.start()
                    updater.startPeriodicChecks()
                    checkAccessibilityPermission()
                }
        } label: {
            Text("[sudo]")
                .font(SudoTheme.mono(size: 9, weight: .medium))
        }
        .menuBarExtraStyle(.window)

        // Test window — a fake AI prompt with Allow/Deny buttons
        Window("sudo test prompt", id: "test-prompt") {
            TestPromptView()
        }
        .defaultSize(width: 480, height: 320)
        .windowStyle(.hiddenTitleBar)
    }

    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("[sudo] Accessibility permission not granted.")
            print("[sudo] System Settings → Privacy & Security → Accessibility → Enable Sudo")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        } else {
            print("[sudo] Accessibility permission granted")
        }
    }
}

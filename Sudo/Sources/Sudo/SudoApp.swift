import SwiftUI
import Cocoa

/// Sudo — macOS menu bar companion for the sudo macro pad.
///
/// Listens for Ctrl+Shift+F13–F16 from the RP2040 macro pad and
/// translates them into approve/reject actions on Claude, ChatGPT, and Grok.
///
/// Detection: AX accessibility tree (primary) + Vision OCR (fallback)
/// Execution: AXUIElement.performAction (no synthetic input, anti-cheat safe)
/// Updates: OTA via GitHub Releases
@main
struct SudoApp: App {
    @StateObject private var engine = SudoEngine()
    @StateObject private var updater = OTAUpdater()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine, updater: updater)
        } label: {
            Text("[sudo]")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
        .onChange(of: engine.isConnected) { _, _ in }
        .onAppear {
            engine.start()
            updater.startPeriodicChecks()
            checkAccessibilityPermission()
        }
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

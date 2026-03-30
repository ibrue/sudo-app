import SwiftUI
import Cocoa

@main
struct SudoApp: App {
    @StateObject private var engine = SudoEngine()
    @StateObject private var updater = OTAUpdater()
    @State private var hasLaunched = false
    @State private var dotFrame = 0

    private let dotTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    private var menuBarLabel: String {
        if engine.isProcessing {
            let dots = String(repeating: ".", count: (dotFrame % 4) + 1)
            let pad = String(repeating: " ", count: 4 - dots.count)
            return "[\(dots)\(pad)]"
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
                    checkAccessibilityPermission()
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

    private func checkAccessibilityPermission() {
        if AXIsProcessTrusted() {
            print("[sudo] Accessibility permission granted")
            return
        }

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

import AppKit
import SwiftUI

/// Manages the test prompt window using AppKit directly.
/// SwiftUI's openWindow environment is not available in MenuBarExtra context.
final class TestWindowManager {
    static let shared = TestWindowManager()
    private var window: NSWindow?

    func open() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "sudo test prompt"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: TestPromptView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

import AppKit
import SwiftUI

/// Hosts the EditPreset wizard in a real NSWindow because SwiftUI's
/// `openWindow` environment crashes inside MenuBarExtra. Same pattern
/// TestWindowManager uses.
final class EditPresetWindowManager {
    static let shared = EditPresetWindowManager()
    private var window: NSWindow?

    func open() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "edit preset"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: EditPresetView(onClose: { [weak self] in
            self?.close()
        }))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }

    func close() {
        window?.close()
        window = nil
    }
}

import AppKit
import SwiftUI

/// Hosts SettingsWindow in a real NSWindow.
///
/// The popover ConfigView covers quick toggles and status. Heavy editors
/// (macros, auto-approve rules, hotkey bindings, debug console, terminal,
/// API key, history) live here so they have room to breathe and so they
/// can later be lifted onto iOS / iPadOS as a NavigationStack with no
/// AppKit deps in the panel bodies — this file is the only macOS-specific
/// piece of the settings surface.
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    func open(engine: SudoEngine,
              updater: OTAUpdater,
              rebuilder: DevRebuilder,
              apiServer: LocalAPIServer,
              initialSection: SettingsWindow.Section? = nil) {
        if let w = window, w.isVisible {
            if let section = initialSection {
                NotificationCenter.default.post(name: .settingsWindowSelectSection,
                                                object: section)
            }
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "sudo settings"
        w.minSize = NSSize(width: 620, height: 420)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsWindow(
            engine: engine,
            updater: updater,
            rebuilder: rebuilder,
            apiServer: apiServer,
            initialSection: initialSection ?? .general
        ))
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

extension Notification.Name {
    static let settingsWindowSelectSection = Notification.Name("sudo.settings.selectSection")
}

import Foundation
#if os(macOS)
import AppKit
#endif

/// Platform-neutral URL launcher. Views call `URLOpener.open(url)`
/// instead of reaching for `NSWorkspace.shared.open(_:)` directly.
enum URLOpener {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        // UIApplication.shared.open(url) — added when iOS lands
        #endif
    }

    static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        open(url)
    }

    /// Jumps to the macOS Accessibility settings pane. iOS doesn't
    /// have a direct equivalent — the iOS branch will fall through.
    static func openAccessibilitySettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

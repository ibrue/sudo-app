import Foundation
#if os(macOS)
import AppKit
#endif

/// Platform-neutral clipboard. Views should call this instead of
/// `NSPasteboard.general` so the panels port to iOS without touching
/// AppKit. The iOS branch will use `UIPasteboard.general` when added.
enum Clipboard {
    static func setString(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        // UIPasteboard.general.string = string  — added when iOS lands
        #endif
    }
}

import Foundation
#if os(macOS)
import AppKit
#endif

/// Platform-neutral app lifecycle. iOS apps don't have a "quit"
/// affordance, so the call is a no-op there.
enum AppLifecycle {
    static func terminate() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #endif
    }
}

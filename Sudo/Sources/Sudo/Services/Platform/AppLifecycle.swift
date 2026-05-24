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

    /// Launch a fresh copy of this app, then quit the current process.
    /// Used by the accessibility banner: macOS sometimes refuses to
    /// route hotkey events to a process that was already running when
    /// the user granted Accessibility, even if `CGEvent.tapCreate()`
    /// is re-attempted — a relaunch is the universal escape hatch.
    static func relaunch() {
        #if os(macOS)
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundleURL.path]
        try? task.run()
        // Small delay so the new instance gets past launchd before we exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.terminate(nil)
        }
        #endif
    }

    /// Clear stale TCC grants for ad-hoc/dev builds, then relaunch so macOS
    /// prompts against the current binary cdhash.
    static func resetPrivacyPermissionsAndRelaunch() {
        #if os(macOS)
        let bundleID = Bundle.main.bundleIdentifier ?? "supply.sudo.app"
        for service in ["Accessibility", "ListenEvent", "PostEvent", "AppleEvents"] {
            let task = Process()
            task.launchPath = "/usr/bin/tccutil"
            task.arguments = ["reset", service, bundleID]
            try? task.run()
            task.waitUntilExit()
        }
        relaunch()
        #endif
    }
}

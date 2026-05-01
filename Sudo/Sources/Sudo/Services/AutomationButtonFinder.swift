import Cocoa

/// Uses macOS Automation (System Events via AppleScript) to find and click
/// hard-to-reach UI elements — sheets, alerts, web views, nested dialogs.
///
/// Requires: System Settings → Privacy & Security → Automation → Sudo → System Events
/// This is separate from Accessibility and can reach elements the direct AX walk misses.
final class AutomationButtonFinder {

    /// Try to find and click a button matching the search terms via System Events.
    /// Returns an ActionResult — on success the button has already been clicked.
    func findAndClick(for action: PadAction, processName: String, bundleID: String?) -> ActionResult {
        let searchTerms = action.searchTerms(forApp: bundleID)
        guard !searchTerms.isEmpty else {
            return .notFound(reason: "No search terms for automation")
        }

        // Build AppleScript that searches for buttons, static texts that look clickable,
        // and UI elements in sheets/dialogs of the target process
        let script = buildSearchScript(processName: processName, searchTerms: searchTerms)

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error = error {
            let errMsg = error[NSAppleScript.errorMessage] as? String ?? "unknown"
            print("[sudo] Automation script error: \(errMsg)")
            return .notFound(reason: "Automation: \(errMsg)")
        }

        if let resultStr = result?.stringValue, resultStr == "clicked" {
            print("[sudo] Automation clicked button for \(action.displayName) in \(processName)")
            // Return a found-OCR with zero point since the click already happened
            return .foundOCR(point: .zero, method: .automation)
        }

        return .notFound(reason: "Automation found no matching button")
    }

    private func buildSearchScript(processName: String, searchTerms: [String]) -> String {
        // Escape terms for AppleScript string comparison
        let termsArray = searchTerms.map { term in
            "\"\(term.replacingOccurrences(of: "\"", with: "\\\""))\""
        }.joined(separator: ", ")

        // This script searches through the UI hierarchy of the target process
        // via System Events, checking buttons, links, and static text in:
        // 1. All windows (direct children)
        // 2. Sheets of windows
        // 3. Toolbars
        // 4. Groups (1 level deep)
        // KEY DIFFERENCE FROM THE OLD SCRIPT:
        //   `set frontmost to true` happens *only* right before a click,
        //   never up-front. System Events can enumerate windows / buttons
        //   on a non-frontmost process just fine; only the click itself
        //   needs the process to be active. Without this restructuring,
        //   merely searching for a button across multiple processes would
        //   activate each one in turn — e.g. Terminal would pop forward
        //   while we were probing it for a "mute" button that doesn't
        //   exist there.
        return """
        tell application "System Events"
            set searchTerms to {\(termsArray)}
            tell process "\(processName.replacingOccurrences(of: "\"", with: "\\\""))"
                repeat with w in windows
                    -- Search buttons in window
                    repeat with b in buttons of w
                        set bName to name of b
                        if bName is not missing value then
                            repeat with t in searchTerms
                                if bName contains t then
                                    set frontmost to true
                                    click b
                                    return "clicked"
                                end if
                            end repeat
                        end if
                    end repeat
                    -- Search buttons in sheets
                    try
                        repeat with s in sheets of w
                            repeat with b in buttons of s
                                set bName to name of b
                                if bName is not missing value then
                                    repeat with t in searchTerms
                                        if bName contains t then
                                            set frontmost to true
                                            click b
                                            return "clicked"
                                        end if
                                    end repeat
                                end if
                            end repeat
                        end repeat
                    end try
                    -- Search buttons in toolbars
                    try
                        repeat with tb in toolbars of w
                            repeat with b in buttons of tb
                                set bName to name of b
                                if bName is not missing value then
                                    repeat with t in searchTerms
                                        if bName contains t then
                                            set frontmost to true
                                            click b
                                            return "clicked"
                                        end if
                                    end repeat
                                end if
                            end repeat
                        end repeat
                    end try
                    -- Search buttons in groups (1 level)
                    try
                        repeat with g in groups of w
                            repeat with b in buttons of g
                                set bName to name of b
                                if bName is not missing value then
                                    repeat with t in searchTerms
                                        if bName contains t then
                                            set frontmost to true
                                            click b
                                            return "clicked"
                                        end if
                                    end repeat
                                end if
                            end repeat
                        end repeat
                    end try
                end repeat
            end tell
        end tell
        return "not_found"
        """
    }
}

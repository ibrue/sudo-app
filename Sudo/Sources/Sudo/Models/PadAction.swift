import Foundation

/// Maps each macro pad button to a semantic action
enum PadAction: String, CaseIterable {
    case approve = "approve"
    case reject  = "reject"
    case action3 = "action3"
    case action4 = "action4"

    /// The hotkey combo sent by the RP2040 for each button
    var keyCode: UInt16 {
        switch self {
        case .approve: return 105  // F13
        case .reject:  return 64   // F17 (F14/F15 trigger macOS brightness)
        case .action3: return 79   // F18
        case .action4: return 106  // F16
        }
    }

    var fKeyNumber: Int {
        switch self {
        case .approve: return 13
        case .reject:  return 17
        case .action3: return 18
        case .action4: return 16
        }
    }

    /// Physical button number (1 = bottom/green, 4 = top/black)
    var buttonNumber: Int {
        switch self {
        case .approve: return 1  // bottom (green)
        case .action3: return 2  // second from bottom (yellow)
        case .reject:  return 3  // second from top (red)
        case .action4: return 4  // top (black)
        }
    }

    var displayName: String {
        SudoSettings.shared.displayName(for: self)
    }

    var defaultDisplayName: String {
        switch self {
        case .approve: return "approve / yes"
        case .reject:  return "reject / no"
        case .action3: return "make it better"
        case .action4: return "yolo (allow all)"
        }
    }

    var searchTerms: [String] {
        SudoSettings.shared.searchTerms(for: self)
    }

    func displayName(forApp bundleID: String?) -> String {
        SudoSettings.shared.displayName(for: self, bundleID: bundleID)
    }

    func searchTerms(forApp bundleID: String?) -> [String] {
        SudoSettings.shared.searchTerms(for: self, bundleID: bundleID)
    }

    var defaultSearchTerms: [String] {
        switch self {
        case .approve:
            return [
                "Allow", "allow once", "allow for this chat",
                "Yes", "Approve", "Accept", "Confirm", "Continue",
                "Run", "Execute", "Allow Once", "Allow for This Chat",
                "Looks good", "LGTM", "Proceed", "Go ahead",
            ]
        case .reject:
            return [
                "Deny", "No", "Reject", "Cancel", "Decline",
                "Don't Allow", "Block", "Stop", "Start over",
            ]
        case .action3:
            return [
                "Make it better", "Improve", "Refine", "Edit",
                "Try again", "Regenerate", "Revise",
                "Continue", "Next", "Skip", "Retry",
            ]
        case .action4:
            return [
                "Allow all", "Yes to all", "Accept all",
                "Allow for This Chat", "allow for this chat",
                "Stop", "Cancel", "Close", "Dismiss", "Abort", "Escape",
            ]
        }
    }

    /// Physical button color on the sudo pad (bottom to top: green, red, yellow, black)
    var buttonColorHex: UInt32 {
        switch self {
        case .approve: return 0x6ABF73  // green
        case .reject:  return 0xC85C5C  // red
        case .action3: return 0xD4B85C  // yellow
        case .action4: return 0x2A2A2A  // black/dark
        }
    }

    /// Physical order on the pad (0 = bottom, 3 = top)
    var physicalPosition: Int {
        switch self {
        case .approve: return 0  // bottom (green)
        case .reject:  return 2  // second from top (red)
        case .action3: return 1  // second from bottom (yellow)
        case .action4: return 3  // top (black)
        }
    }

    /// Sorted by physical position (bottom to top) for visual layout
    static var physicalOrder: [PadAction] {
        allCases.sorted { $0.physicalPosition < $1.physicalPosition }
    }

    /// Keyboard fallback for Claude Code style prompts in editors/terminals.
    var editorKeyCode: UInt16? {
        switch self {
        case .approve: return 18  // "1" key
        case .reject:  return 20  // "3" key
        case .action3: return 19  // "2" key
        case .action4: return 53  // Escape key
        }
    }
}

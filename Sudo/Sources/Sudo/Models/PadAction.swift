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
        case .reject:  return 107  // F14
        case .action3: return 113  // F15
        case .action4: return 106  // F16
        }
    }

    var fKeyNumber: Int {
        switch self {
        case .approve: return 13
        case .reject:  return 14
        case .action3: return 15
        case .action4: return 16
        }
    }

    var displayName: String {
        SudoSettings.shared.displayName(for: self)
    }

    var defaultDisplayName: String {
        switch self {
        case .approve: return "Approve / Yes"
        case .reject:  return "Reject / No"
        case .action3: return "Make it better"
        case .action4: return "Stop / Cancel"
        }
    }

    var searchTerms: [String] {
        SudoSettings.shared.searchTerms(for: self)
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
            return ["Stop", "Cancel", "Close", "Dismiss", "Abort", "Escape"]
        }
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

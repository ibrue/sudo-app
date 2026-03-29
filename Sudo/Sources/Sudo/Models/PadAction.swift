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
        switch self {
        case .approve: return "Approve / Yes"
        case .reject:  return "Reject / No"
        case .action3: return "Action 3"
        case .action4: return "Action 4"
        }
    }

    var searchTerms: [String] {
        switch self {
        case .approve:
            return [
                "Allow", "allow once", "allow for this chat",
                "Yes", "Approve", "Accept", "Confirm", "Continue",
                "Run", "Execute", "allow", "yes", "approve",
                "Allow Once", "Allow for This Chat",
            ]
        case .reject:
            return [
                "Deny", "deny", "No", "Reject", "Cancel", "Decline",
                "Don't Allow", "Block", "Stop", "no", "reject", "cancel",
            ]
        case .action3:
            return ["Continue", "Next", "Skip", "Retry"]
        case .action4:
            return ["Stop", "Cancel", "Close", "Dismiss"]
        }
    }
}

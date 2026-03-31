import Foundation

/// Quick-apply preset configurations for the 4 buttons.
struct ButtonPreset: Identifiable {
    let id: String
    let name: String
    let description: String
    let buttons: [PadAction: ButtonConfig]

    struct ButtonConfig {
        let displayName: String
        let searchTerms: [String]
    }

    /// All available presets
    static let all: [ButtonPreset] = [
        aiAgent,
        planMode,
        claudeCode,
        shortcuts,
        mediaControls,
        browsing,
    ]

    // MARK: - Presets

    static let aiAgent = ButtonPreset(
        id: "ai-agent",
        name: "AI Agent (default)",
        description: "approve / reject AI actions",
        buttons: [
            .approve: .init(displayName: "Approve / Yes", searchTerms: [
                "Allow", "allow once", "allow for this chat",
                "Yes", "Approve", "Accept", "Confirm", "Continue",
                "Run", "Execute", "Allow Once", "Allow for This Chat",
            ]),
            .reject: .init(displayName: "Reject / No", searchTerms: [
                "Deny", "No", "Reject", "Cancel", "Decline",
                "Don't Allow", "Block", "Stop",
            ]),
            .action3: .init(displayName: "Make it better", searchTerms: [
                "Make it better", "Improve", "Refine", "Edit",
                "Try again", "Regenerate", "Revise",
            ]),
            .action4: .init(displayName: "YOLO (allow all)", searchTerms: [
                "Allow all", "Yes to all", "Accept all",
                "Allow for This Chat", "allow for this chat",
                "Stop", "Cancel", "Close", "Dismiss",
            ]),
        ]
    )

    static let planMode = ButtonPreset(
        id: "plan-mode",
        name: "Plan Mode",
        description: "yes / no / make it better for plans",
        buttons: [
            .approve: .init(displayName: "Yes / Approve Plan", searchTerms: [
                "Yes", "Approve", "Accept", "Looks good", "LGTM",
                "Confirm", "Execute plan", "Proceed", "Go ahead",
                "Allow", "Continue", "Run",
            ]),
            .reject: .init(displayName: "No / Reject Plan", searchTerms: [
                "No", "Reject", "Deny", "Cancel", "Start over",
                "Don't", "Stop", "Decline", "Block",
            ]),
            .action3: .init(displayName: "Make it better", searchTerms: [
                "Make it better", "Improve", "Revise", "Edit plan",
                "Try again", "Regenerate", "Refine", "Update",
                "Modify", "Change", "Redo",
            ]),
            .action4: .init(displayName: "Exit Plan Mode", searchTerms: [
                "Exit", "Leave", "Close", "Dismiss", "Cancel",
                "Exit plan mode", "Stop planning",
            ]),
        ]
    )

    static let claudeCode = ButtonPreset(
        id: "claude-code",
        name: "Claude Code (terminal)",
        description: "optimized for Claude Code prompts",
        buttons: [
            .approve: .init(displayName: "Yes", searchTerms: [
                "Yes", "Allow", "Approve", "Accept", "Confirm",
                "yes", "allow", "y",
            ]),
            .reject: .init(displayName: "No", searchTerms: [
                "No", "Deny", "Reject", "Cancel", "no", "n",
            ]),
            .action3: .init(displayName: "Yes, allow all", searchTerms: [
                "Yes, allow all", "Allow all", "allow all edits",
                "Yes, allow all edits this session",
            ]),
            .action4: .init(displayName: "Escape / Cancel", searchTerms: [
                "Cancel", "Escape", "Stop", "Abort", "Ctrl+C",
            ]),
        ]
    )

    static let shortcuts = ButtonPreset(
        id: "shortcuts",
        name: "System Shortcuts",
        description: "copy / paste / undo / screenshot",
        buttons: [
            .approve: .init(displayName: "Copy", searchTerms: ["Copy"]),
            .reject: .init(displayName: "Paste", searchTerms: ["Paste"]),
            .action3: .init(displayName: "Undo", searchTerms: ["Undo"]),
            .action4: .init(displayName: "Screenshot", searchTerms: ["Screenshot"]),
        ]
    )

    static let mediaControls = ButtonPreset(
        id: "media",
        name: "Media Controls",
        description: "play / next / prev / mute",
        buttons: [
            .approve: .init(displayName: "Play / Pause", searchTerms: ["Play", "Pause"]),
            .reject: .init(displayName: "Next Track", searchTerms: ["Next", "Skip"]),
            .action3: .init(displayName: "Previous Track", searchTerms: ["Previous", "Back"]),
            .action4: .init(displayName: "Mute", searchTerms: ["Mute", "Unmute"]),
        ]
    )

    static let browsing = ButtonPreset(
        id: "browsing",
        name: "Web Browsing",
        description: "back / forward / refresh / close tab",
        buttons: [
            .approve: .init(displayName: "Back", searchTerms: ["Back"]),
            .reject: .init(displayName: "Forward", searchTerms: ["Forward"]),
            .action3: .init(displayName: "Refresh", searchTerms: ["Refresh", "Reload"]),
            .action4: .init(displayName: "Close Tab", searchTerms: ["Close"]),
        ]
    )

    /// Apply this preset to SudoSettings
    func apply() {
        let settings = SudoSettings.shared
        for action in PadAction.allCases {
            if let config = buttons[action] {
                settings.buttonNames[action.rawValue] = config.displayName
                settings.buttonSearchTerms[action.rawValue] = config.searchTerms
            }
        }
    }
}

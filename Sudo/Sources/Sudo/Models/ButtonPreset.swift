import Foundation
import CoreGraphics

/// Execution mode for a button action.
enum ActionMode: String, Codable {
    case aiSearch    // search AX tree + OCR for buttons (default)
    case keyCombo    // send a keyboard shortcut directly
    case mediaKey    // send a media key event
}

/// Quick-apply preset configurations for the 4 buttons.
struct ButtonPreset: Identifiable {
    let id: String
    let name: String
    let description: String
    let buttons: [PadAction: ButtonConfig]

    struct ButtonConfig {
        let displayName: String
        let searchTerms: [String]
        let mode: ActionMode
        let keyCombo: KeyCombo?

        init(displayName: String, searchTerms: [String], mode: ActionMode = .aiSearch, keyCombo: KeyCombo? = nil) {
            self.displayName = displayName
            self.searchTerms = searchTerms
            self.mode = mode
            self.keyCombo = keyCombo
        }
    }

    struct KeyCombo {
        let keyCode: UInt16
        let modifiers: CGEventFlags

        // Common key codes
        static let c: UInt16 = 8
        static let v: UInt16 = 9
        static let z: UInt16 = 6
        static let w: UInt16 = 13
        static let r: UInt16 = 15
        static let t: UInt16 = 17
        static let leftBracket: UInt16 = 33   // [
        static let rightBracket: UInt16 = 30  // ]
        static let three: UInt16 = 20
        static let four: UInt16 = 21
        static let f1: UInt16 = 122
    }

    /// All available presets
    static let all: [ButtonPreset] = [
        aiAgent,
        planMode,
        claudeCode,
        shortcuts,
        mediaControls,
        browsing,
        discord,
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
            .approve: .init(displayName: "Copy", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: KeyCombo.c, modifiers: .maskCommand)),
            .reject: .init(displayName: "Paste", searchTerms: [], mode: .keyCombo,
                          keyCombo: KeyCombo(keyCode: KeyCombo.v, modifiers: .maskCommand)),
            .action3: .init(displayName: "Undo", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: KeyCombo.z, modifiers: .maskCommand)),
            .action4: .init(displayName: "Screenshot", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: KeyCombo.three, modifiers: [.maskCommand, .maskShift])),
        ]
    )

    static let mediaControls = ButtonPreset(
        id: "media",
        name: "Media Controls",
        description: "play / next / prev / mute",
        buttons: [
            .approve: .init(displayName: "Play / Pause", searchTerms: [], mode: .mediaKey,
                           keyCombo: KeyCombo(keyCode: 16, modifiers: [])),  // NX_KEYTYPE_PLAY
            .reject: .init(displayName: "Next Track", searchTerms: [], mode: .mediaKey,
                          keyCombo: KeyCombo(keyCode: 17, modifiers: [])),   // NX_KEYTYPE_NEXT
            .action3: .init(displayName: "Previous Track", searchTerms: [], mode: .mediaKey,
                           keyCombo: KeyCombo(keyCode: 18, modifiers: [])),  // NX_KEYTYPE_PREVIOUS
            .action4: .init(displayName: "Mute", searchTerms: [], mode: .mediaKey,
                           keyCombo: KeyCombo(keyCode: 7, modifiers: [])),   // NX_KEYTYPE_MUTE
        ]
    )

    static let browsing = ButtonPreset(
        id: "browsing",
        name: "Web Browsing",
        description: "back / forward / refresh / close tab",
        buttons: [
            .approve: .init(displayName: "Back", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: KeyCombo.leftBracket, modifiers: .maskCommand)),
            .reject: .init(displayName: "Forward", searchTerms: [], mode: .keyCombo,
                          keyCombo: KeyCombo(keyCode: KeyCombo.rightBracket, modifiers: .maskCommand)),
            .action3: .init(displayName: "Refresh", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: KeyCombo.r, modifiers: .maskCommand)),
            .action4: .init(displayName: "Close Tab", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: KeyCombo.w, modifiers: .maskCommand)),
        ]
    )

    static let discord = ButtonPreset(
        id: "discord",
        name: "Discord Soundboard",
        description: "trigger soundboard clips 1-4",
        buttons: [
            .approve: .init(displayName: "Sound 1", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: 18, modifiers: [.maskControl, .maskShift])),  // Ctrl+Shift+1
            .reject: .init(displayName: "Sound 2", searchTerms: [], mode: .keyCombo,
                          keyCombo: KeyCombo(keyCode: 19, modifiers: [.maskControl, .maskShift])),   // Ctrl+Shift+2
            .action3: .init(displayName: "Sound 3", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: 20, modifiers: [.maskControl, .maskShift])),  // Ctrl+Shift+3
            .action4: .init(displayName: "Mute / Deafen", searchTerms: [], mode: .keyCombo,
                           keyCombo: KeyCombo(keyCode: 2, modifiers: [.maskCommand, .maskShift])),   // Cmd+Shift+D (Discord mute)
        ]
    )

    /// Apply this preset to SudoSettings
    func apply() {
        SudoTelemetry.shared.trackPresetApplied(preset: id)
        let settings = SudoSettings.shared
        for action in PadAction.allCases {
            if let config = buttons[action] {
                settings.buttonNames[action.rawValue] = config.displayName
                settings.buttonSearchTerms[action.rawValue] = config.searchTerms
                settings.buttonModes[action.rawValue] = config.mode.rawValue
                if let kc = config.keyCombo {
                    settings.buttonKeyCombos[action.rawValue] = [
                        "keyCode": Int(kc.keyCode),
                        "modifiers": Int(kc.modifiers.rawValue)
                    ]
                } else {
                    settings.buttonKeyCombos.removeValue(forKey: action.rawValue)
                }
            }
        }
    }
}

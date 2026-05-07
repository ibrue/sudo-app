import Foundation

/// One step in a macro sequence. Four kinds:
///
///   - `.action`       — fires one of the four PadActions. Existing behaviour.
///   - `.switchToApp`  — activates the target app (launches it if needed) and
///                       waits `waitMs` for it to become frontmost so the
///                       next keystroke lands in its window.
///   - `.switchBack`   — restores whichever app was frontmost when the macro
///                       started. Same `waitMs` contract.
///   - `.keystroke`    — sends a raw key combo (any keyCode + modifier mask).
///                       Lets a macro send app-specific shortcuts that aren't
///                       wired up to one of the four PadActions, e.g. Spotify's
///                       Option+Shift+B "save to liked songs".
///
/// The struct keeps every field at the top level (rather than using a Swift
/// enum with associated values) so existing user data — saved before kinds
/// existed — keeps decoding cleanly. The custom `init(from:)` defaults `kind`
/// to `.action` when the field isn't present.
struct MacroStep: Codable, Identifiable {
    enum Kind: String, Codable {
        case action
        case switchToApp
        case switchBack
        case keystroke
    }

    let id: UUID
    var kind: Kind

    // .action fields
    var action: String        // PadAction rawValue when kind == .action
    var delayAfter: Double    // seconds to wait after this step (action + keystroke)

    // .switchToApp / .switchBack fields
    var targetBundleID: String?     // e.g. "com.spotify.client"
    var targetDisplayName: String?  // e.g. "Spotify" (for nicer UI labels)
    var waitMs: Int?                // post-activation settling time, default 150ms

    // .keystroke fields
    var keyCode: Int?               // macOS virtual keyCode
    var modifiers: Int?             // CGEventFlags raw value

    var padAction: PadAction? {
        guard kind == .action else { return nil }
        return PadAction(rawValue: action)
    }

    /// Default settling time after an app switch. Spotify-class apps accept
    /// keystrokes ~100–150ms after activation; older / heavier apps may need
    /// longer (overridable per-step).
    static let defaultSwitchWaitMs: Int = 150

    // MARK: - Convenience constructors

    init(action: PadAction, delayAfter: Double = 1.0) {
        self.id = UUID()
        self.kind = .action
        self.action = action.rawValue
        self.delayAfter = delayAfter
    }

    static func switchToApp(bundleID: String, displayName: String? = nil,
                            waitMs: Int = MacroStep.defaultSwitchWaitMs) -> MacroStep {
        var step = MacroStep(action: .approve)
        step.kind = .switchToApp
        step.action = ""
        step.delayAfter = 0
        step.targetBundleID = bundleID
        step.targetDisplayName = displayName
        step.waitMs = waitMs
        return step
    }

    static func switchBack(waitMs: Int = MacroStep.defaultSwitchWaitMs) -> MacroStep {
        var step = MacroStep(action: .approve)
        step.kind = .switchBack
        step.action = ""
        step.delayAfter = 0
        step.waitMs = waitMs
        return step
    }

    static func keystroke(keyCode: Int, modifiers: Int, delayAfter: Double = 0) -> MacroStep {
        var step = MacroStep(action: .approve)
        step.kind = .keystroke
        step.action = ""
        step.delayAfter = delayAfter
        step.keyCode = keyCode
        step.modifiers = modifiers
        return step
    }

    // MARK: - Codable (backwards-compatible decode)

    enum CodingKeys: String, CodingKey {
        case id, kind, action, delayAfter
        case targetBundleID, targetDisplayName, waitMs
        case keyCode, modifiers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .action
        self.action = (try? c.decode(String.self, forKey: .action)) ?? ""
        self.delayAfter = (try? c.decode(Double.self, forKey: .delayAfter)) ?? 0
        self.targetBundleID = try? c.decode(String.self, forKey: .targetBundleID)
        self.targetDisplayName = try? c.decode(String.self, forKey: .targetDisplayName)
        self.waitMs = try? c.decode(Int.self, forKey: .waitMs)
        self.keyCode = try? c.decode(Int.self, forKey: .keyCode)
        self.modifiers = try? c.decode(Int.self, forKey: .modifiers)
    }
    // encode is the synthesized default — emits every non-nil field, which is
    // forwards-compatible with anything that knows the new keys.
}

struct MacroSequence: Codable, Identifiable {
    let id: UUID
    var name: String
    var steps: [MacroStep]
    var assignedButton: String?  // PadAction rawValue if bound to a button

    init(name: String, steps: [MacroStep]) {
        self.id = UUID()
        self.name = name
        self.steps = steps
    }
}

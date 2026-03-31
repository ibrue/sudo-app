import Foundation

struct MacroStep: Codable, Identifiable {
    let id: UUID
    let action: String  // PadAction rawValue
    let delayAfter: Double  // seconds to wait after this step

    init(action: PadAction, delayAfter: Double = 1.0) {
        self.id = UUID()
        self.action = action.rawValue
        self.delayAfter = delayAfter
    }

    var padAction: PadAction? { PadAction(rawValue: action) }
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

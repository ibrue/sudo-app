import Foundation
import CoreGraphics

/// Executes a SimpleAction by simulating its keyboard shortcut via CGEvents.
final class SimpleActionExecutor {

    enum Result {
        case success(String)
        case failure(String)
    }

    func execute(_ action: SimpleAction) -> Result {
        let combo = action.keyCombo

        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: combo.key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: combo.key, keyDown: false) else {
            return .failure("Failed to create CGEvent")
        }

        keyDown.flags = combo.flags
        keyUp.flags = combo.flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return .success("Simulated \(action.displayName)")
    }
}

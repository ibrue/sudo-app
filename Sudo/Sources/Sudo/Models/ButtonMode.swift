import Foundation

/// Defines whether a button uses a simple preset action or complex search terms.
enum ButtonMode: Codable, Equatable {
    case simple(SimpleAction)
    case complex

    var isSimple: Bool {
        if case .simple = self { return true }
        return false
    }

    var displayLabel: String {
        switch self {
        case .simple(let action):
            return action.displayName
        case .complex:
            return "Search Terms"
        }
    }
}

import Foundation

/// Persists per-button search term customization using UserDefaults.
final class ButtonConfigStore: ObservableObject {
    static let shared = ButtonConfigStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "sudo.buttonSearchTerms"

    /// Published so SwiftUI views react to changes.
    @Published private(set) var customTerms: [String: [String]] = [:]

    private init() {
        loadFromDefaults()
    }

    /// Returns the active search terms for a given action — custom if set, otherwise default.
    func searchTerms(for action: PadAction) -> [String] {
        if let custom = customTerms[action.rawValue], !custom.isEmpty {
            return custom
        }
        return action.defaultSearchTerms
    }

    /// Updates the search terms for a given action. Pass nil or empty to reset to defaults.
    func setSearchTerms(_ terms: [String]?, for action: PadAction) {
        if let terms = terms, !terms.isEmpty {
            customTerms[action.rawValue] = terms
        } else {
            customTerms.removeValue(forKey: action.rawValue)
        }
        saveToDefaults()
    }

    /// Whether the user has customized the terms for this action.
    func isCustomized(_ action: PadAction) -> Bool {
        guard let custom = customTerms[action.rawValue] else { return false }
        return !custom.isEmpty
    }

    /// Reset a single action back to defaults.
    func resetToDefaults(_ action: PadAction) {
        customTerms.removeValue(forKey: action.rawValue)
        saveToDefaults()
    }

    /// Reset all actions back to defaults.
    func resetAllToDefaults() {
        customTerms.removeAll()
        saveToDefaults()
    }

    private func loadFromDefaults() {
        if let data = defaults.dictionary(forKey: storageKey) as? [String: [String]] {
            customTerms = data
        }
    }

    private func saveToDefaults() {
        defaults.set(customTerms, forKey: storageKey)
    }
}

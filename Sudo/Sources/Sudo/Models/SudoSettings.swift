import Foundation
import ServiceManagement

/// Persisted user settings via UserDefaults.
final class SudoSettings: ObservableObject {
    static let shared = SudoSettings()

    private let defaults = UserDefaults.standard

    @Published var searchAllApps: Bool {
        didSet { defaults.set(searchAllApps, forKey: "searchAllApps") }
    }

    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "soundEnabled") }
    }

    @Published var notifyOnFailure: Bool {
        didSet { defaults.set(notifyOnFailure, forKey: "notifyOnFailure") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    // MARK: - API Settings

    @Published var apiEnabled: Bool {
        didSet { defaults.set(apiEnabled, forKey: "apiEnabled") }
    }

    @Published var apiPort: Int {
        didSet { defaults.set(apiPort, forKey: "apiPort") }
    }

    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: "apiKey") }
    }

    @Published var webhookURL: String {
        didSet { defaults.set(webhookURL, forKey: "webhookURL") }
    }

    /// Custom display names for each button (nil = use default)
    @Published var buttonNames: [String: String] {
        didSet { defaults.set(buttonNames, forKey: "buttonNames") }
    }

    /// Custom search terms for each button (nil = use defaults)
    @Published var buttonSearchTerms: [String: [String]] {
        didSet {
            if let data = try? JSONEncoder().encode(buttonSearchTerms) {
                defaults.set(data, forKey: "buttonSearchTerms")
            }
        }
    }

    init() {
        self.searchAllApps = defaults.bool(forKey: "searchAllApps")
        self.soundEnabled = defaults.object(forKey: "soundEnabled") == nil ? true : defaults.bool(forKey: "soundEnabled")
        self.notifyOnFailure = defaults.object(forKey: "notifyOnFailure") == nil ? true : defaults.bool(forKey: "notifyOnFailure")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.apiEnabled = defaults.bool(forKey: "apiEnabled")
        self.apiPort = defaults.object(forKey: "apiPort") == nil ? 7483 : defaults.integer(forKey: "apiPort")
        self.apiKey = defaults.string(forKey: "apiKey") ?? Self.generateAPIKey()
        self.webhookURL = defaults.string(forKey: "webhookURL") ?? ""
        self.buttonNames = (defaults.dictionary(forKey: "buttonNames") as? [String: String]) ?? [:]
        if let data = defaults.data(forKey: "buttonSearchTerms"),
           let terms = try? JSONDecoder().decode([String: [String]].self, from: data) {
            self.buttonSearchTerms = terms
        } else {
            self.buttonSearchTerms = [:]
        }
    }

    func displayName(for action: PadAction) -> String {
        buttonNames[action.rawValue] ?? action.defaultDisplayName
    }

    func searchTerms(for action: PadAction) -> [String] {
        buttonSearchTerms[action.rawValue] ?? action.defaultSearchTerms
    }

    static func generateAPIKey() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let key = "sudo_" + (0..<24).map { _ in chars.randomElement()! }.map(String.init).joined()
        UserDefaults.standard.set(key, forKey: "apiKey")
        return key
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if launchAtLogin {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                print("[sudo] Login item update failed: \(error)")
            }
        }
    }
}

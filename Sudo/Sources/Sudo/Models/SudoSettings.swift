import Foundation
import CoreGraphics
import ServiceManagement

/// Top-level app mode. Replaces the old "simple mode is computed" model
/// with three explicit modes the user picks.
///
/// - `dynamic`: auto-switches the active preset based on the frontmost app
///   category. Uses the AI search pipeline. Default for new users.
/// - `simple`: one fixed preset is locked in. No auto-switch. All buttons are
///   keyCombo / mediaKey, so the pad can be flashed and work without the app.
/// - `custom`: per-button manual config. User picks each button's mode +
///   keycombo + name. Can be flashed to firmware.
enum AppMode: String, CaseIterable {
    case dynamic
    case simple
    case custom

    var label: String {
        switch self {
        case .dynamic: return "dynamic"
        case .simple:  return "simple"
        case .custom:  return "custom"
        }
    }

    var description: String {
        switch self {
        case .dynamic: return "auto-switches preset by app"
        case .simple:  return "one fixed preset, flashable"
        case .custom:  return "per-button manual config"
        }
    }
}

/// Persisted user settings via UserDefaults.
final class SudoSettings: ObservableObject {
    static let shared = SudoSettings()

    private let defaults = UserDefaults.standard

    /// Top-level app mode (dynamic / simple / custom).
    @Published var appMode: AppMode {
        didSet { defaults.set(appMode.rawValue, forKey: "appMode") }
    }

    /// In simple mode, which preset is locked in.
    @Published var simpleModePresetID: String {
        didSet { defaults.set(simpleModePresetID, forKey: "simpleModePresetID") }
    }

    /// True once the user has dismissed the first-launch onboarding flow.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

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

    @Published var telemetryEnabled: Bool {
        didSet { defaults.set(telemetryEnabled, forKey: "telemetryEnabled") }
    }

    /// Debounce duration in seconds (default 0.02 = 20ms)
    @Published var debounceDuration: Double {
        didSet { defaults.set(debounceDuration, forKey: "debounceDuration") }
    }

    /// Auto-switch presets when the frontmost app changes category
    @Published var autoSwitchEnabled: Bool {
        didSet { defaults.set(autoSwitchEnabled, forKey: "autoSwitchEnabled") }
    }

    /// Maps app category → preset ID (e.g. "media" → "media", "cad" → "cad")
    @Published var categoryPresets: [String: String] {
        didSet { defaults.set(categoryPresets, forKey: "categoryPresets") }
    }

    /// Per-app preset overrides (bundle ID → preset ID). Takes priority over category mapping.
    @Published var appPresetOverrides: [String: String] {
        didSet { defaults.set(appPresetOverrides, forKey: "appPresetOverrides") }
    }

    /// Simple mode: all buttons use keyCombo or mediaKey (no AI search needed).
    /// When enabled, the pad can be flashed to work natively without the companion app.
    var isSimpleMode: Bool {
        PadAction.allCases.allSatisfy { action in
            let mode = actionMode(for: action)
            return mode == .keyCombo || mode == .mediaKey
        }
    }

    /// Developer mode: enabled when ~/sudo-app/build.sh exists
    var isDeveloperMode: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/sudo-app/build.sh")
    }

    /// Persisted section expansion state for ConfigView
    @Published var expandedSections: Set<String> {
        didSet { defaults.set(Array(expandedSections), forKey: "expandedSections") }
    }

    /// Action mode per button (aiSearch, keyCombo, mediaKey)
    @Published var buttonModes: [String: String] {
        didSet { defaults.set(buttonModes, forKey: "buttonModes") }
    }

    /// Key combos per button (keyCode + modifiers)
    @Published var buttonKeyCombos: [String: [String: Int]] {
        didSet { defaults.set(buttonKeyCombos, forKey: "buttonKeyCombos") }
    }

    /// Hotkey bindings — which key combo triggers each button.
    /// Default: Ctrl+Shift+F13-F16. Configurable for any firmware/macro pad.
    @Published var hotkeyBindings: [String: [String: Int]] {
        didSet { defaults.set(hotkeyBindings, forKey: "hotkeyBindings") }
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

    // MARK: - Auto-Approve Settings

    @Published var autoApproveEnabled: Bool {
        didSet { defaults.set(autoApproveEnabled, forKey: "autoApproveEnabled") }
    }

    @Published var autoApproveRules: [AutoApproveRule] {
        didSet {
            if let data = try? JSONEncoder().encode(autoApproveRules) {
                defaults.set(data, forKey: "autoApproveRules")
            }
        }
    }

    /// Macro sequences (chained actions)
    @Published var macros: [MacroSequence] {
        didSet {
            if let data = try? JSONEncoder().encode(macros) {
                defaults.set(data, forKey: "macros")
            }
        }
    }

    // MARK: - Usage Stats

    @Published var totalPresses: Int {
        didSet { defaults.set(totalPresses, forKey: "totalPresses") }
    }

    @Published var currentStreak: Int {
        didSet { defaults.set(currentStreak, forKey: "currentStreak") }
    }

    @Published var lastActiveDate: String {
        didSet { defaults.set(lastActiveDate, forKey: "lastActiveDate") }
    }

    // Legacy (kept for migration)
    var totalApproves: Int { get { 0 } set {} }
    var totalRejects: Int { get { 0 } set {} }

    /// Per-app profiles keyed by bundle ID.
    /// Structure: [bundleID: [actionRawValue: ["name": String, "searchTerms": [String]]]]
    @Published var appProfiles: [String: [String: [String: Any]]] {
        didSet { persistAppProfiles() }
    }

    private func persistAppProfiles() {
        // Convert to a Codable-friendly structure for JSON serialization
        var codable: [String: [String: [String: Any]]] = [:]
        for (bundleID, actions) in appProfiles {
            var actionMap: [String: [String: Any]] = [:]
            for (actionKey, config) in actions {
                actionMap[actionKey] = config
            }
            codable[bundleID] = actionMap
        }
        if let data = try? JSONSerialization.data(withJSONObject: codable) {
            defaults.set(data, forKey: "appProfiles")
        }
    }

    private static func loadAppProfiles(from defaults: UserDefaults) -> [String: [String: [String: Any]]] {
        guard let data = defaults.data(forKey: "appProfiles"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Any]]] else {
            return [:]
        }
        return json
    }

    init() {
        // Restore appMode, migrating old installs:
        //   - had isSimpleMode buttons → .simple
        //   - had autoSwitchEnabled (default true) → .dynamic
        //   - otherwise → .custom
        if let raw = defaults.string(forKey: "appMode"), let mode = AppMode(rawValue: raw) {
            self.appMode = mode
        } else {
            let buttonModes = (defaults.dictionary(forKey: "buttonModes") as? [String: String]) ?? [:]
            let allSimple = !buttonModes.isEmpty && buttonModes.values.allSatisfy { $0 == "keyCombo" || $0 == "mediaKey" }
            let autoSwitch = defaults.object(forKey: "autoSwitchEnabled") == nil ? true : defaults.bool(forKey: "autoSwitchEnabled")
            if allSimple {
                self.appMode = .simple
            } else if autoSwitch {
                self.appMode = .dynamic
            } else {
                self.appMode = .custom
            }
        }
        self.simpleModePresetID = defaults.string(forKey: "simpleModePresetID") ?? "shortcuts"
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.searchAllApps = defaults.bool(forKey: "searchAllApps")
        self.soundEnabled = defaults.object(forKey: "soundEnabled") == nil ? true : defaults.bool(forKey: "soundEnabled")
        self.notifyOnFailure = defaults.object(forKey: "notifyOnFailure") == nil ? true : defaults.bool(forKey: "notifyOnFailure")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.apiEnabled = defaults.bool(forKey: "apiEnabled")
        self.apiPort = defaults.object(forKey: "apiPort") == nil ? 7483 : defaults.integer(forKey: "apiPort")
        self.apiKey = defaults.string(forKey: "apiKey") ?? Self.generateAPIKey()
        self.telemetryEnabled = defaults.object(forKey: "telemetryEnabled") == nil ? true : defaults.bool(forKey: "telemetryEnabled")
        self.debounceDuration = defaults.object(forKey: "debounceDuration") == nil ? 0.02 : defaults.double(forKey: "debounceDuration")
        self.autoSwitchEnabled = defaults.object(forKey: "autoSwitchEnabled") == nil ? true : defaults.bool(forKey: "autoSwitchEnabled")
        self.categoryPresets = (defaults.dictionary(forKey: "categoryPresets") as? [String: String]) ?? Self.defaultCategoryPresets()
        self.appPresetOverrides = (defaults.dictionary(forKey: "appPresetOverrides") as? [String: String]) ?? [:]

        self.expandedSections = Set(defaults.stringArray(forKey: "expandedSections") ?? [])
        self.webhookURL = defaults.string(forKey: "webhookURL") ?? ""
        self.buttonModes = (defaults.dictionary(forKey: "buttonModes") as? [String: String]) ?? [:]
        self.buttonKeyCombos = (defaults.dictionary(forKey: "buttonKeyCombos") as? [String: [String: Int]]) ?? [:]
        self.hotkeyBindings = (defaults.dictionary(forKey: "hotkeyBindings") as? [String: [String: Int]]) ?? Self.defaultHotkeyBindings
        self.buttonNames = (defaults.dictionary(forKey: "buttonNames") as? [String: String]) ?? [:]
        if let data = defaults.data(forKey: "buttonSearchTerms"),
           let terms = try? JSONDecoder().decode([String: [String]].self, from: data) {
            self.buttonSearchTerms = terms
        } else {
            self.buttonSearchTerms = [:]
        }
        self.appProfiles = Self.loadAppProfiles(from: defaults)
        self.autoApproveEnabled = defaults.bool(forKey: "autoApproveEnabled")
        if let rulesData = defaults.data(forKey: "autoApproveRules"),
           let savedRules = try? JSONDecoder().decode([AutoApproveRule].self, from: rulesData) {
            self.autoApproveRules = savedRules
        } else {
            self.autoApproveRules = Self.defaultAutoApproveRules()
        }
        // Migrate old approve/reject counters to totalPresses
        let oldTotal = defaults.integer(forKey: "totalApproves") + defaults.integer(forKey: "totalRejects")
        self.totalPresses = max(defaults.integer(forKey: "totalPresses"), oldTotal)
        self.currentStreak = defaults.integer(forKey: "currentStreak")
        self.lastActiveDate = defaults.string(forKey: "lastActiveDate") ?? ""
        if let macroData = defaults.data(forKey: "macros"),
           let saved = try? JSONDecoder().decode([MacroSequence].self, from: macroData) {
            self.macros = saved
        } else {
            self.macros = Self.defaultMacros()
        }
    }

    static func defaultCategoryPresets() -> [String: String] {
        var presets: [String: String] = [:]
        for category in AppCategory.allCases {
            if let presetID = category.defaultPresetID {
                presets[category.rawValue] = presetID
            }
        }
        return presets
    }

    static func defaultAutoApproveRules() -> [AutoApproveRule] {
        var fileReads = AutoApproveRule(
            name: "auto-approve file reads",
            contextExcludes: "rm,delete,sudo,git push,DROP"
        )
        fileReads.enabled = false

        var cursor = AutoApproveRule(
            name: "auto-approve in Cursor",
            appFilter: "cursor",
            contextExcludes: "rm,delete,sudo"
        )
        cursor.enabled = false

        return [fileReads, cursor]
    }

    static func defaultMacros() -> [MacroSequence] {
        [
            MacroSequence(name: "double approve", steps: [
                MacroStep(action: .approve, delayAfter: 1.5),
                MacroStep(action: .approve, delayAfter: 0),
            ]),
            MacroSequence(name: "approve all", steps: [
                MacroStep(action: .approve, delayAfter: 1.0),
                MacroStep(action: .approve, delayAfter: 1.0),
                MacroStep(action: .approve, delayAfter: 0),
            ]),
        ]
    }

    func actionMode(for action: PadAction) -> ActionMode {
        if let raw = buttonModes[action.rawValue], let mode = ActionMode(rawValue: raw) {
            return mode
        }
        return .aiSearch
    }

    func keyCombo(for action: PadAction) -> ButtonPreset.KeyCombo? {
        guard let data = buttonKeyCombos[action.rawValue],
              let keyCode = data["keyCode"],
              let modifiers = data["modifiers"] else { return nil }
        return ButtonPreset.KeyCombo(keyCode: UInt16(keyCode), modifiers: CGEventFlags(rawValue: UInt64(modifiers)))
    }

    func displayName(for action: PadAction) -> String {
        buttonNames[action.rawValue] ?? action.defaultDisplayName
    }

    func searchTerms(for action: PadAction) -> [String] {
        buttonSearchTerms[action.rawValue] ?? action.defaultSearchTerms
    }

    // MARK: - Per-App Profiles

    /// Get profile for a specific app (nil = use global defaults)
    func profile(forBundleID bundleID: String) -> [String: ButtonPreset.ButtonConfig]? {
        guard let actionMap = appProfiles[bundleID] else { return nil }
        var result: [String: ButtonPreset.ButtonConfig] = [:]
        for (actionKey, config) in actionMap {
            let name = config["name"] as? String ?? ""
            let terms = config["searchTerms"] as? [String] ?? []
            result[actionKey] = ButtonPreset.ButtonConfig(displayName: name, searchTerms: terms)
        }
        return result.isEmpty ? nil : result
    }

    /// Save a profile for an app
    func saveProfile(forBundleID bundleID: String, preset: ButtonPreset) {
        var actionMap: [String: [String: Any]] = [:]
        for (action, config) in preset.buttons {
            actionMap[action.rawValue] = [
                "name": config.displayName,
                "searchTerms": config.searchTerms,
            ]
        }
        appProfiles[bundleID] = actionMap
    }

    /// Delete a profile for an app
    func deleteProfile(forBundleID bundleID: String) {
        appProfiles.removeValue(forKey: bundleID)
    }

    /// Get the display name for an action, considering the current frontmost app
    func displayName(for action: PadAction, bundleID: String?) -> String {
        if let bundleID = bundleID,
           let profile = appProfiles[bundleID],
           let config = profile[action.rawValue],
           let name = config["name"] as? String {
            return name
        }
        return displayName(for: action)
    }

    /// Get search terms for an action, considering the current frontmost app
    func searchTerms(for action: PadAction, bundleID: String?) -> [String] {
        if let bundleID = bundleID,
           let profile = appProfiles[bundleID],
           let config = profile[action.rawValue],
           let terms = config["searchTerms"] as? [String] {
            return terms
        }
        return searchTerms(for: action)
    }

    /// Update the usage streak based on today's date.
    func updateStreak() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        if lastActiveDate == today {
            // Already counted today
            return
        }

        if let lastDate = formatter.date(from: lastActiveDate) {
            let calendar = Calendar.current
            let daysBetween = calendar.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            if daysBetween == 1 {
                currentStreak += 1
            } else if daysBetween > 1 {
                currentStreak = 1
            }
        } else {
            // First ever action
            currentStreak = 1
        }

        lastActiveDate = today
    }

    /// Default hotkey bindings: Ctrl+Shift+F13-F16
    static let defaultHotkeyBindings: [String: [String: Int]] = {
        let ctrlShift = Int(CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
        return [
            "approve": ["keyCode": 105, "modifiers": ctrlShift],  // F13
            "reject":  ["keyCode": 107, "modifiers": ctrlShift],  // F14
            "action3": ["keyCode": 113, "modifiers": ctrlShift],  // F15
            "action4": ["keyCode": 106, "modifiers": ctrlShift],  // F16
        ]
    }()

    func resetHotkeyBindings() {
        hotkeyBindings = Self.defaultHotkeyBindings
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

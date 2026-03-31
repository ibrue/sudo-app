import Foundation

/// Anonymous, fire-and-forget telemetry.
/// Tracks generic button presses (button 1-4), not specific action types.
/// No usernames, hostnames, or IP tracking — only a random device UUID.
final class SudoTelemetry {
    static let shared = SudoTelemetry()

    private let endpoint = URL(string: "https://sudo.supply/api/telemetry")!
    private let session: URLSession
    private let deviceID: String

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)

        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "telemetryDeviceID") {
            self.deviceID = existing
        } else {
            let newID = UUID().uuidString
            defaults.set(newID, forKey: "telemetryDeviceID")
            self.deviceID = newID
        }
    }

    /// Track a button press (generic — button number, not action type)
    func trackButtonPress(button: PadAction, mode: String) {
        guard SudoSettings.shared.telemetryEnabled else { return }
        send(payload: [
            "event": "button_press",
            "button": button.buttonNumber,
            "mode": mode,
            "version": OTAUpdater.currentVersion,
            "device_id": deviceID
        ] as [String: Any])
    }

    /// Track app launch
    func trackLaunch() {
        guard SudoSettings.shared.telemetryEnabled else { return }
        send(payload: [
            "event": "launch",
            "version": OTAUpdater.currentVersion,
            "device_id": deviceID
        ])
    }

    /// Track which preset was applied
    func trackPresetApplied(preset: String) {
        guard SudoSettings.shared.telemetryEnabled else { return }
        send(payload: [
            "event": "preset_applied",
            "preset": preset,
            "version": OTAUpdater.currentVersion,
            "device_id": deviceID
        ])
    }

    // MARK: - Private

    private func send(payload: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request).resume()
    }
}

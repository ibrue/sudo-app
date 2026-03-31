import Foundation
import Cocoa

/// Collects diagnostic info and files a bug report.
final class BugReporter {
    static let shared = BugReporter()

    private let endpoint = URL(string: "https://sudo.supply/api/bugs")!

    /// File a bug report: POST diagnostics to the server and open a mailto fallback.
    func fileReport(engine: SudoEngine, description: String = "") {
        let report = buildReport(engine: engine, description: description)

        // POST to server
        if let body = try? JSONSerialization.data(withJSONObject: report) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            URLSession.shared.dataTask(with: request).resume()
        }

        // Mailto fallback
        let subject = "[sudo] Bug Report v\(OTAUpdater.currentVersion)"
        let mailBody = report.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        if let mailto = URL(string: "mailto:ianbrueggeman@gmail.com?subject=\(subject.urlEncoded)&body=\(mailBody.urlEncoded)") {
            NSWorkspace.shared.open(mailto)
        }
    }

    // MARK: - Private

    private func buildReport(engine: SudoEngine, description: String) -> [String: Any] {
        let settings = SudoSettings.shared
        let logEntries = engine.actionLog.prefix(20).map { entry -> [String: Any] in
            [
                "time": entry.timeString,
                "action": entry.action,
                "app": entry.app,
                "method": entry.method,
                "success": entry.succeeded
            ]
        }

        let settingsSummary: [String: Any] = [
            "searchAllApps": settings.searchAllApps,
            "soundEnabled": settings.soundEnabled,
            "notifyOnFailure": settings.notifyOnFailure,
            "apiEnabled": settings.apiEnabled,
            "telemetryEnabled": settings.telemetryEnabled
        ]

        return [
            "description": description,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "appVersion": OTAUpdater.currentVersion,
            "detectedApp": engine.detectedApp,
            "isConnected": engine.isConnected,
            "settings": settingsSummary,
            "recentActions": logEntries
        ]
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

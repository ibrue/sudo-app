import Foundation

/// A recorded action for the history log.
struct ActionLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let action: String
    let app: String
    let method: String
    let succeeded: Bool
    let context: String?

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

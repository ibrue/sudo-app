import Foundation

/// Captures log messages for display in the debug console.
/// All `[sudo]` print statements should call `DebugLogger.shared.log()` instead.
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    @Published var entries: [Entry] = []

    private let maxEntries = 200
    private let queue = DispatchQueue(label: "sudo.debuglogger")

    func log(_ message: String) {
        let entry = Entry(timestamp: Date(), message: message)
        print("[sudo] \(message)")
        queue.async {
            DispatchQueue.main.async {
                self.entries.append(entry)
                if self.entries.count > self.maxEntries {
                    self.entries.removeFirst(self.entries.count - self.maxEntries)
                }
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }
}

import Foundation

struct AutoApproveRule: Codable, Identifiable {
    let id: UUID
    var name: String
    var enabled: Bool
    var appFilter: String?  // bundle ID substring to match, nil = all apps
    var contextContains: String?  // only auto-approve if context contains this text
    var contextExcludes: String?  // never auto-approve if context contains this text (safety)
    var action: String  // which PadAction to auto-trigger (default "approve")
    var timeWindowStart: Int?  // hour of day (0-23), nil = always
    var timeWindowEnd: Int?

    init(name: String, appFilter: String? = nil, contextExcludes: String? = nil) {
        self.id = UUID()
        self.name = name
        self.enabled = true
        self.appFilter = appFilter
        self.contextContains = nil
        self.contextExcludes = contextExcludes
        self.action = "approve"
        self.timeWindowStart = nil
        self.timeWindowEnd = nil
    }
}

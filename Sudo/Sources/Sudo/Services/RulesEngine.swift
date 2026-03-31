import Foundation

/// Evaluates auto-approve rules against the current app and context.
final class RulesEngine {
    static let shared = RulesEngine()

    /// Check if an action should be auto-approved given the current context.
    /// Returns the matching rule if auto-approve should happen, nil otherwise.
    func shouldAutoApprove(app: AppDetector.DetectedApp, context: String?) -> AutoApproveRule? {
        guard SudoSettings.shared.autoApproveEnabled else { return nil }

        for rule in SudoSettings.shared.autoApproveRules where rule.enabled {
            // Check app filter
            if let filter = rule.appFilter, !filter.isEmpty {
                if !app.bundleID.lowercased().contains(filter.lowercased()) &&
                   !app.name.lowercased().contains(filter.lowercased()) {
                    continue
                }
            }

            // Check time window
            if let start = rule.timeWindowStart, let end = rule.timeWindowEnd {
                let hour = Calendar.current.component(.hour, from: Date())
                if start <= end {
                    if hour < start || hour >= end { continue }
                } else {
                    if hour < start && hour >= end { continue }
                }
            }

            // Check context inclusion
            if let contains = rule.contextContains, !contains.isEmpty {
                guard let ctx = context, ctx.lowercased().contains(contains.lowercased()) else { continue }
            }

            // Check safety exclusions
            if let excludes = rule.contextExcludes, !excludes.isEmpty {
                let exclusionList = excludes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                if let ctx = context?.lowercased() {
                    if exclusionList.contains(where: { ctx.contains($0) }) { continue }
                }
            }

            return rule
        }
        return nil
    }
}

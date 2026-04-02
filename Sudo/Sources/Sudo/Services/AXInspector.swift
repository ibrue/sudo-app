import Cocoa

/// AX tree inspection tool for debugging button detection issues.
///
/// Provides tree dumps, search dry-runs, and pipeline tests that can be
/// called from the debug API endpoints or the dev terminal.
final class AXInspector {

    struct AXNode: Codable {
        let role: String
        let title: String?
        let value: String?
        let description: String?
        let enabled: Bool?
        let hasAXPress: Bool
        let hasPosition: Bool
        let position: String?
        let size: String?
        let children: [AXNode]?

        var asJSON: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(self) else { return "{}" }
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    struct SearchResult: Codable {
        let matched: Bool
        let role: String
        let text: String
        let matchedTerm: String?
        let hasPosition: Bool
        let isActionable: Bool
        let skipReason: String?
    }

    struct PipelineTestResult: Codable {
        let action: String
        let app: String
        let pid: Int
        let axResult: String
        let axElementMatched: String?
        let automationResult: String
        let ocrResult: String
        let searchStats: SearchStatsResult
        let timingMs: [String: Int]
    }

    struct SearchStatsResult: Codable {
        let elementsVisited: Int
        let maxDepthReached: Int
        let skippedNoText: Int
        let skippedTextMismatch: Int
        let skippedNotActionable: Int
        let axErrors: [String]
    }

    // MARK: - Tree Dump

    /// Dump the AX tree of the given PID, up to maxDepth levels.
    func dumpTree(pid: pid_t, maxDepth: Int = 8) -> AXNode {
        let app = AXUIElementCreateApplication(pid)
        return buildNode(element: app, depth: 0, maxDepth: maxDepth)
    }

    /// Dump tree of the frontmost app.
    func dumpFrontmostTree(maxDepth: Int = 8) -> (node: AXNode, appName: String, pid: pid_t)? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let node = dumpTree(pid: front.processIdentifier, maxDepth: maxDepth)
        return (node, front.localizedName ?? "unknown", front.processIdentifier)
    }

    private func buildNode(element: AXUIElement, depth: Int, maxDepth: Int) -> AXNode {
        let role = getAttribute(element, kAXRoleAttribute as String) as? String ?? "unknown"
        let title = getAttribute(element, kAXTitleAttribute as String) as? String
        let value = getAttribute(element, kAXValueAttribute as String) as? String
        let desc = getAttribute(element, kAXDescriptionAttribute as String) as? String
        let enabled = getAttribute(element, kAXEnabledAttribute as String) as? Bool

        var hasPress = false
        if let actions = getAttribute(element, "AXActionNames") as? [String] {
            hasPress = actions.contains("AXPress")
        }

        var posStr: String?
        var sizeStr: String?
        var hasPos = false
        if let posValue = getAttribute(element, kAXPositionAttribute as String),
           let axPos = posValue as? AXValue {
            var point = CGPoint.zero
            AXValueGetValue(axPos, .cgPoint, &point)
            posStr = "\(Int(point.x)),\(Int(point.y))"
            hasPos = true
        }
        if let sizeValue = getAttribute(element, kAXSizeAttribute as String),
           let axSize = sizeValue as? AXValue {
            var size = CGSize.zero
            AXValueGetValue(axSize, .cgSize, &size)
            sizeStr = "\(Int(size.width))x\(Int(size.height))"
        }

        var children: [AXNode]?
        if depth < maxDepth {
            if let childArray = getChildren(element) {
                children = childArray.prefix(30).map { child in
                    buildNode(element: child, depth: depth + 1, maxDepth: maxDepth)
                }
            }
        }

        return AXNode(
            role: role, title: title, value: value, description: desc,
            enabled: enabled, hasAXPress: hasPress, hasPosition: hasPos,
            position: posStr, size: sizeStr, children: children
        )
    }

    // MARK: - Search Dry-Run

    /// Search the frontmost app for elements matching the given terms.
    /// Returns all elements that match OR would have matched but were skipped.
    func searchElements(pid: pid_t, terms: [String]) -> [SearchResult] {
        let app = AXUIElementCreateApplication(pid)
        let lowerTerms = terms.map { $0.lowercased() }

        var results: [SearchResult] = []

        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return results
        }

        for window in windows.prefix(3) {
            searchNode(element: window, terms: lowerTerms, depth: 0, maxDepth: 30, results: &results)
        }
        return results
    }

    private func searchNode(element: AXUIElement, terms: [String], depth: Int, maxDepth: Int, results: inout [SearchResult]) {
        guard depth < maxDepth else { return }

        let role = getAttribute(element, kAXRoleAttribute as String) as? String ?? ""
        let text = getElementText(element)
        let hasPos = getAttribute(element, kAXPositionAttribute as String) != nil

        if let text = text {
            let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

            // Check if it matches any search term
            var matchedTerm: String?
            for term in terms {
                if lower == term || lower.contains(term) {
                    matchedTerm = term
                    break
                }
            }

            if matchedTerm != nil {
                let isActionable = hasPos && isEnabled(element)
                let skipReason: String?
                if !hasPos { skipReason = "no position" }
                else if !isEnabled(element) { skipReason = "disabled" }
                else if lower.count > 120 { skipReason = "text too long (\(lower.count) chars)" }
                else { skipReason = nil }

                results.append(SearchResult(
                    matched: true, role: role, text: text,
                    matchedTerm: matchedTerm, hasPosition: hasPos,
                    isActionable: isActionable, skipReason: skipReason
                ))
            }
        }

        // Recurse
        if let children = getChildren(element) {
            for child in children.prefix(30) {
                searchNode(element: child, terms: terms, depth: depth + 1, maxDepth: maxDepth, results: &results)
            }
        }
    }

    // MARK: - Pipeline Test

    /// Run the full detection pipeline for an action against the frontmost app.
    func runPipelineTest(action: PadAction) -> PipelineTestResult? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = front.processIdentifier
        let appName = front.localizedName ?? "unknown"
        let bundleID = front.bundleIdentifier

        let axFinder = AXButtonFinder()
        let automationFinder = AutomationButtonFinder()
        let ocrFinder = OCRButtonFinder()

        var timings: [String: Int] = [:]

        // AX tree
        let axStart = DispatchTime.now()
        let axResult = axFinder.findButton(for: action, pid: pid, bundleID: bundleID)
        let axTime = Int((DispatchTime.now().uptimeNanoseconds - axStart.uptimeNanoseconds) / 1_000_000)
        timings["ax_tree_ms"] = axTime

        let axStr: String
        let axMatch: String?
        switch axResult {
        case .found(_, let method): axStr = "found (\(method.rawValue))"; axMatch = "element found"
        case .foundOCR(_, let method): axStr = "found (\(method.rawValue))"; axMatch = nil
        case .notFound(let reason): axStr = "not found: \(reason)"; axMatch = nil
        }

        // Automation
        let autoStart = DispatchTime.now()
        let autoResult = automationFinder.findAndClick(for: action, processName: appName, bundleID: bundleID)
        let autoTime = Int((DispatchTime.now().uptimeNanoseconds - autoStart.uptimeNanoseconds) / 1_000_000)
        timings["automation_ms"] = autoTime

        let autoStr: String
        switch autoResult {
        case .found: autoStr = "found"
        case .foundOCR: autoStr = "found (clicked)"
        case .notFound(let reason): autoStr = "not found: \(reason)"
        }

        // OCR
        let ocrStart = DispatchTime.now()
        let ocrResult = ocrFinder.findButton(for: action, pid: pid)
        let ocrTime = Int((DispatchTime.now().uptimeNanoseconds - ocrStart.uptimeNanoseconds) / 1_000_000)
        timings["ocr_ms"] = ocrTime

        let ocrStr: String
        switch ocrResult {
        case .found: ocrStr = "found"
        case .foundOCR(let point, _): ocrStr = "found at (\(Int(point.x)),\(Int(point.y)))"
        case .notFound(let reason): ocrStr = "not found: \(reason)"
        }

        // Search stats from a dry-run
        let terms = action.searchTerms(forApp: bundleID)
        let searchResults = searchElements(pid: pid, terms: terms)
        let stats = SearchStatsResult(
            elementsVisited: searchResults.count,
            maxDepthReached: 0,
            skippedNoText: 0,
            skippedTextMismatch: 0,
            skippedNotActionable: searchResults.filter { $0.matched && !$0.isActionable }.count,
            axErrors: []
        )

        return PipelineTestResult(
            action: action.displayName,
            app: appName,
            pid: Int(pid),
            axResult: axStr,
            axElementMatched: axMatch,
            automationResult: autoStr,
            ocrResult: ocrStr,
            searchStats: stats,
            timingMs: timings
        )
    }

    // MARK: - Helpers

    private func getAttribute(_ element: AXUIElement, _ attr: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        return result == .success ? value : nil
    }

    private func getChildren(_ element: AXUIElement) -> [AXUIElement]? {
        // Try standard children first
        if let children = getAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement], !children.isEmpty {
            return children
        }
        // Fallback: try visible children (some elements only expose this)
        if let children = getAttribute(element, kAXVisibleChildrenAttribute as String) as? [AXUIElement], !children.isEmpty {
            return children
        }
        return nil
    }

    private func getElementText(_ element: AXUIElement) -> String? {
        let attrs = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, "AXHelp" as CFString]
        var parts: [String] = []
        for attr in attrs {
            if let val = getAttribute(element, attr as String) as? String, !val.isEmpty {
                parts.append(val)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        if let enabled = getAttribute(element, kAXEnabledAttribute as String) as? Bool {
            return enabled
        }
        return true // default to enabled if attribute missing
    }
}

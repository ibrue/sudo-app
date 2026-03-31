import Cocoa

/// Primary detection: walks the accessibility tree to find buttons matching the action.
/// Uses AXUIElement — the same API as VoiceOver. Anti-cheat compatible.
final class AXButtonFinder {

    func findButton(for action: PadAction, pid: pid_t, bundleID: String? = nil) -> ActionResult {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return .notFound(reason: "Could not access app windows")
        }

        let searchTerms = action.searchTerms(forApp: bundleID).map { $0.lowercased() }

        var focusedWindow: AnyObject?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        var orderedWindows = windows
        if let focused = focusedWindow as! AXUIElement? {
            orderedWindows.insert(focused, at: 0)
        }

        for window in orderedWindows {
            if let element = searchTree(element: window, searchTerms: searchTerms, depth: 0) {
                return .found(element: element, method: .accessibilityTree)
            }
        }

        return .notFound(reason: "No matching button found in AX tree")
    }

    private func searchTree(element: AXUIElement, searchTerms: [String], depth: Int) -> AXUIElement? {
        // Electron/webview AX trees can be 25+ levels deep
        guard depth < 30 else { return nil }

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String ?? ""

        let clickableRoles: Set<String> = [
            "AXButton", "AXLink", "AXMenuItem", "AXMenuButton",
            "AXStaticText", "AXGroup", "AXCell",
            // Electron/webview roles
            "AXRadioButton", "AXCheckBox", "AXPopUpButton",
            "AXGenericElement", "AXListItem",
        ]

        if clickableRoles.contains(roleStr) || hasAnyAction(element) {
            if let title = getElementText(element), matchesSearchTerms(title, terms: searchTerms) {
                if isElementActionable(element) {
                    return element
                }
                // For Electron apps: if element has position but no AXPress,
                // still return it — executor will try click fallback
                if hasPosition(element) {
                    return element
                }
            }
        }

        // Check groups with combined child text
        if roleStr == "AXGroup" || roleStr == "AXCell" || roleStr == "AXGenericElement" || roleStr == "AXListItem" {
            let combinedText = getCombinedChildText(element, maxDepth: 3)
            if let text = combinedText, matchesSearchTerms(text, terms: searchTerms) {
                if hasPosition(element) {
                    return element
                }
            }
        }

        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else { return nil }

        for child in childArray {
            if let found = searchTree(element: child, searchTerms: searchTerms, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private func getElementText(_ element: AXUIElement) -> String? {
        let attributes: [String] = [
            kAXTitleAttribute as String,
            kAXValueAttribute as String,
            kAXDescriptionAttribute as String,
            "AXHelp",
        ]
        var parts: [String] = []
        for attr in attributes {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
               let str = value as? String, !str.isEmpty {
                parts.append(str)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func getCombinedChildText(_ element: AXUIElement, maxDepth: Int) -> String? {
        guard maxDepth > 0 else { return getElementText(element) }

        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else { return getElementText(element) }

        var parts: [String] = []
        if let text = getElementText(element) { parts.append(text) }
        for child in childArray.prefix(15) {
            if let text = getCombinedChildText(child, maxDepth: maxDepth - 1) { parts.append(text) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Two-pass matching: exact match first, then substring.
    /// Skips long text (>60 chars) to avoid false positives on paragraphs.
    private func matchesSearchTerms(_ text: String, terms: [String]) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard lower.count <= 60 else { return false }
        // Pass 1: exact match
        if terms.contains(where: { lower == $0 }) { return true }
        // Pass 2: substring
        return terms.contains { lower.contains($0) }
    }

    private func hasAnyAction(_ element: AXUIElement) -> Bool {
        var actions: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXActionNames" as CFString, &actions) == .success,
              let actionArray = actions as? [String] else { return false }
        return !actionArray.isEmpty
    }

    private func hasPosition(_ element: AXUIElement) -> Bool {
        var position: AnyObject?
        return AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success
    }

    private func isElementActionable(_ element: AXUIElement) -> Bool {
        var enabled: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled) == .success,
           let isEnabled = enabled as? Bool, !isEnabled { return false }

        return hasPosition(element)
    }

    // MARK: - Context capture

    /// Walk the AX tree of the focused window and collect text near interactive elements.
    /// Returns up to 200 characters of surrounding context, or nil if nothing found.
    func captureContext(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow as! AXUIElement? else { return nil }

        var collected: [String] = []
        collectContextText(element: window, collected: &collected, depth: 0)

        guard !collected.isEmpty else { return nil }
        let joined = collected.joined(separator: " ")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return String(trimmed.prefix(200))
    }

    private func collectContextText(element: AXUIElement, collected: inout [String], depth: Int) {
        guard depth < 15 else { return }
        // stop early if we already have enough
        let currentLength = collected.reduce(0) { $0 + $1.count }
        guard currentLength < 200 else { return }

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String ?? ""

        let textRoles: Set<String> = ["AXStaticText", "AXTextField", "AXTextArea", "AXHeading"]
        if textRoles.contains(roleStr) {
            if let text = getElementText(element) {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && clean.count <= 120 {
                    collected.append(clean)
                }
            }
        }

        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else { return }

        for child in childArray.prefix(20) {
            collectContextText(element: child, collected: &collected, depth: depth + 1)
        }
    }
}

import Cocoa

/// Primary detection: walks the accessibility tree to find buttons matching the action.
/// Uses AXUIElement — the same API as VoiceOver. Anti-cheat compatible.
final class AXButtonFinder {

    func findButton(for action: PadAction, pid: pid_t) -> ActionResult {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return .notFound(reason: "Could not access app windows")
        }

        let searchTerms = action.searchTerms.map { $0.lowercased() }

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
        guard depth < 15 else { return nil }

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String ?? ""

        let clickableRoles: Set<String> = [
            "AXButton", "AXLink", "AXMenuItem", "AXMenuButton",
            "AXStaticText", "AXGroup", "AXCell",
        ]

        if clickableRoles.contains(roleStr) || hasClickAction(element) {
            if let title = getElementText(element), matchesSearchTerms(title, terms: searchTerms) {
                if isElementActionable(element) {
                    return element
                }
            }
        }

        if roleStr == "AXGroup" || roleStr == "AXCell" {
            let combinedText = getCombinedChildText(element, maxDepth: 2)
            if let text = combinedText, matchesSearchTerms(text, terms: searchTerms) {
                if hasClickAction(element) && isElementActionable(element) {
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
        for child in childArray.prefix(10) {
            if let text = getCombinedChildText(child, maxDepth: maxDepth - 1) { parts.append(text) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func matchesSearchTerms(_ text: String, terms: [String]) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return terms.contains { lower == $0 || lower.contains($0) }
    }

    private func hasClickAction(_ element: AXUIElement) -> Bool {
        var actions: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXActionNames" as CFString, &actions) == .success,
              let actionArray = actions as? [String] else { return true }
        return actionArray.contains("AXPress") || actionArray.contains("AXConfirm")
    }

    private func isElementActionable(_ element: AXUIElement) -> Bool {
        var enabled: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled) == .success,
           let isEnabled = enabled as? Bool, !isEnabled { return false }

        var position: AnyObject?
        return AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success
    }
}

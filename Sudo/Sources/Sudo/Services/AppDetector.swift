import Cocoa

/// Detects whether the frontmost application is a supported AI app.
final class AppDetector {

    struct DetectedApp {
        let bundleID: String
        let name: String
        let pid: pid_t
        let isBrowser: Bool
        let matchedDomain: String?
    }

    func detectFrontmostApp() -> DetectedApp? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let bundleID = frontApp.bundleIdentifier ?? ""
        let appName = frontApp.localizedName ?? ""
        let pid = frontApp.processIdentifier

        if SupportedApp.nativeBundleIDs.contains(bundleID) {
            return DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: false, matchedDomain: nil)
        }

        if SupportedApp.browserBundleIDs.contains(bundleID) {
            if let domain = detectAIDomainInBrowser(pid: pid) {
                return DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: true, matchedDomain: domain)
            }
        }

        return nil
    }

    private func detectAIDomainInBrowser(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var titleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &titleValue) == .success,
              let focusedWindow = titleValue else { return nil }

        var windowTitleValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &windowTitleValue)
        let windowTitle = (windowTitleValue as? String)?.lowercased() ?? ""

        let urlBarText = findURLField(in: appElement, depth: 0, maxDepth: 6)?.lowercased() ?? ""
        let textToSearch = windowTitle + " " + urlBarText

        for domain in SupportedApp.webDomains {
            if textToSearch.contains(domain) { return domain }
        }
        return nil
    }

    private func findURLField(in element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String ?? ""

        if roleStr == "AXTextField" || roleStr == "AXComboBox" {
            var value: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            if let text = value as? String,
               (text.contains(".com") || text.contains(".ai") || text.contains("http")) {
                return text
            }
        }

        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else { return nil }

        for child in childArray.prefix(20) {
            if let result = findURLField(in: child, depth: depth + 1, maxDepth: maxDepth) {
                return result
            }
        }
        return nil
    }
}

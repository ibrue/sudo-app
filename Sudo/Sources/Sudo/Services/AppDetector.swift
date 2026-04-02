import Cocoa

/// Detects whether the frontmost application is a supported AI app.
final class AppDetector {

    struct DetectedApp {
        let bundleID: String
        let name: String
        let pid: pid_t
        let isBrowser: Bool
        let matchedDomain: String?
        let isPlugin: Bool
        let category: AppCategory

        init(bundleID: String, name: String, pid: pid_t, isBrowser: Bool, matchedDomain: String?, isPlugin: Bool = false, category: AppCategory? = nil) {
            self.bundleID = bundleID
            self.name = name
            self.pid = pid
            self.isBrowser = isBrowser
            self.matchedDomain = matchedDomain
            self.isPlugin = isPlugin
            self.category = category ?? AppCategory.from(bundleID: bundleID, appName: name)
        }
    }

    /// Bundle IDs contributed by loaded plugins.
    var pluginBundleIDs: Set<String> {
        PluginManager.shared.pluginBundleIDs
    }

    /// Detect all running supported apps (for search-all-apps mode)
    func detectAllSupportedApps() -> [DetectedApp] {
        var results: [DetectedApp] = []
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            let bundleID = app.bundleIdentifier ?? ""
            let appName = app.localizedName ?? ""
            let pid = app.processIdentifier

            if SupportedApp.nativeBundleIDs.contains(bundleID) ||
               SupportedApp.editorBundleIDs.contains(bundleID) {
                results.append(DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: false, matchedDomain: nil))
            } else if pluginBundleIDs.contains(bundleID) {
                results.append(DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: false, matchedDomain: nil, isPlugin: true))
            } else if SupportedApp.browserBundleIDs.contains(bundleID) {
                if let domain = detectAIDomainInBrowser(pid: pid) {
                    results.append(DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: true, matchedDomain: domain))
                }
            }
        }

        // Put frontmost app first
        if let front = NSWorkspace.shared.frontmostApplication {
            let frontPid = front.processIdentifier
            if let idx = results.firstIndex(where: { $0.pid == frontPid }), idx > 0 {
                let app = results.remove(at: idx)
                results.insert(app, at: 0)
            }
        }

        return results
    }

    func detectFrontmostApp() -> DetectedApp? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let bundleID = frontApp.bundleIdentifier ?? ""
        let appName = frontApp.localizedName ?? ""
        let pid = frontApp.processIdentifier

        if SupportedApp.nativeBundleIDs.contains(bundleID) {
            return DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: false, matchedDomain: nil)
        }

        if SupportedApp.editorBundleIDs.contains(bundleID) {
            return DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: false, matchedDomain: nil)
        }

        if pluginBundleIDs.contains(bundleID) {
            return DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: false, matchedDomain: nil, isPlugin: true)
        }

        if SupportedApp.browserBundleIDs.contains(bundleID) {
            let domain = detectAIDomainInBrowser(pid: pid)
            let category: AppCategory = domain != nil ? .ai : .browser
            return DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: true, matchedDomain: domain, category: category)
        }

        // Detect other app categories (media, CAD, writing, etc.)
        let category = AppCategory.from(bundleID: bundleID, appName: appName)
        if category != .unknown {
            return DetectedApp(bundleID: bundleID, name: appName, pid: pid, isBrowser: false, matchedDomain: nil, category: category)
        }

        return nil
    }

    private func detectAIDomainInBrowser(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var titleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &titleValue) == .success,
              let focusedWindow = titleValue as? AXUIElement else { return nil }

        var windowTitleValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedWindow, kAXTitleAttribute as CFString, &windowTitleValue)
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

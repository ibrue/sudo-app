import Foundation
import CoreGraphics

/// Preset system shortcuts that can be assigned to macro pad buttons in simple mode.
enum SimpleAction: String, Codable, CaseIterable {
    case takeScreenshot
    case takeScreenshotArea
    case copy
    case paste
    case undo
    case redo
    case save
    case selectAll
    case newTab
    case closeTab
    case switchApp
    case spotlight
    case missionControl
    case showDesktop
    case lockScreen

    var displayName: String {
        switch self {
        case .takeScreenshot:     return "Screenshot"
        case .takeScreenshotArea: return "Screenshot Area"
        case .copy:               return "Copy"
        case .paste:              return "Paste"
        case .undo:               return "Undo"
        case .redo:               return "Redo"
        case .save:               return "Save"
        case .selectAll:          return "Select All"
        case .newTab:             return "New Tab"
        case .closeTab:           return "Close Tab"
        case .switchApp:          return "Switch App"
        case .spotlight:          return "Spotlight"
        case .missionControl:     return "Mission Control"
        case .showDesktop:        return "Show Desktop"
        case .lockScreen:         return "Lock Screen"
        }
    }

    var category: String {
        switch self {
        case .takeScreenshot, .takeScreenshotArea, .spotlight, .missionControl, .showDesktop, .lockScreen, .switchApp:
            return "System"
        case .copy, .paste, .undo, .redo, .save, .selectAll:
            return "Editing"
        case .newTab, .closeTab:
            return "Navigation"
        }
    }

    /// The virtual key code and modifier flags needed to simulate this shortcut.
    var keyCombo: (key: UInt16, flags: CGEventFlags) {
        switch self {
        case .takeScreenshot:
            // Cmd+Shift+3 — key 20 is '3'
            return (20, [.maskCommand, .maskShift])
        case .takeScreenshotArea:
            // Cmd+Shift+4 — key 21 is '4'
            return (21, [.maskCommand, .maskShift])
        case .copy:
            // Cmd+C — key 8
            return (8, .maskCommand)
        case .paste:
            // Cmd+V — key 9
            return (9, .maskCommand)
        case .undo:
            // Cmd+Z — key 6
            return (6, .maskCommand)
        case .redo:
            // Cmd+Shift+Z — key 6
            return (6, [.maskCommand, .maskShift])
        case .save:
            // Cmd+S — key 1
            return (1, .maskCommand)
        case .selectAll:
            // Cmd+A — key 0
            return (0, .maskCommand)
        case .newTab:
            // Cmd+T — key 17
            return (17, .maskCommand)
        case .closeTab:
            // Cmd+W — key 13
            return (13, .maskCommand)
        case .switchApp:
            // Cmd+Tab — key 48
            return (48, .maskCommand)
        case .spotlight:
            // Cmd+Space — key 49
            return (49, .maskCommand)
        case .missionControl:
            // Ctrl+Up — key 126
            return (126, .maskControl)
        case .showDesktop:
            // F11 — key 103
            return (103, CGEventFlags())
        case .lockScreen:
            // Ctrl+Cmd+Q — key 12
            return (12, [.maskControl, .maskCommand])
        }
    }

    /// All categories in display order.
    static var categories: [String] {
        ["System", "Editing", "Navigation"]
    }

    /// Actions filtered by category.
    static func actions(in category: String) -> [SimpleAction] {
        allCases.filter { $0.category == category }
    }
}

import XCTest
@testable import Sudo

final class ModelTests: XCTestCase {

    // MARK: - PadAction

    func testAllPadActionsExist() {
        XCTAssertEqual(PadAction.allCases.count, 4)
    }

    func testPadActionKeyCodes() {
        XCTAssertEqual(PadAction.approve.keyCode, 105) // F13
        XCTAssertEqual(PadAction.reject.keyCode, 64)   // F17
        XCTAssertEqual(PadAction.action3.keyCode, 79)  // F18
        XCTAssertEqual(PadAction.action4.keyCode, 106) // F16
    }

    func testPadActionFKeyNumbers() {
        XCTAssertEqual(PadAction.approve.fKeyNumber, 13)
        XCTAssertEqual(PadAction.reject.fKeyNumber, 17)
        XCTAssertEqual(PadAction.action3.fKeyNumber, 18)
        XCTAssertEqual(PadAction.action4.fKeyNumber, 16)
    }

    func testPadActionSearchTermsNotEmpty() {
        for action in PadAction.allCases {
            XCTAssertFalse(action.searchTerms.isEmpty,
                           "\(action.rawValue) should have search terms")
        }
    }

    func testApproveSearchTermsContainCommonWords() {
        let terms = PadAction.approve.searchTerms
        XCTAssertTrue(terms.contains("Allow"))
        XCTAssertTrue(terms.contains("Yes"))
        XCTAssertTrue(terms.contains("Approve"))
    }

    func testRejectSearchTermsContainCommonWords() {
        let terms = PadAction.reject.searchTerms
        XCTAssertTrue(terms.contains("Deny"))
        XCTAssertTrue(terms.contains("No"))
        XCTAssertTrue(terms.contains("Reject"))
    }

    func testPadActionDisplayNames() {
        // Default preset is ai-agent
        XCTAssertFalse(PadAction.approve.displayName.isEmpty)
        XCTAssertFalse(PadAction.reject.displayName.isEmpty)
    }

    // MARK: - SupportedApp

    func testAllSupportedAppsExist() {
        XCTAssertEqual(SupportedApp.allCases.count, 16)
    }

    func testNativeBundleIDsAreDefined() {
        XCTAssertTrue(SupportedApp.nativeBundleIDs.contains("com.anthropic.claudefordesktop"))
        XCTAssertTrue(SupportedApp.nativeBundleIDs.contains("com.openai.chat"))
    }

    func testWebDomainsAreDefined() {
        XCTAssertTrue(SupportedApp.webDomains.contains("claude.ai"))
        XCTAssertTrue(SupportedApp.webDomains.contains("chatgpt.com"))
        XCTAssertTrue(SupportedApp.webDomains.contains("grok.com"))
    }

    func testBrowserBundleIDsIncludeCommonBrowsers() {
        let browsers = SupportedApp.browserBundleIDs
        XCTAssertTrue(browsers.contains("com.apple.Safari"))
        XCTAssertTrue(browsers.contains("com.google.Chrome"))
        XCTAssertTrue(browsers.contains("org.mozilla.firefox"))
    }

    func testSupportedAppDisplayNames() {
        XCTAssertEqual(SupportedApp.claude.displayName, "Claude")
        XCTAssertEqual(SupportedApp.claudeWeb.displayName, "Claude")
        XCTAssertEqual(SupportedApp.chatgpt.displayName, "ChatGPT")
        XCTAssertEqual(SupportedApp.grok.displayName, "Grok")
    }

    // MARK: - ActionResult

    func testActionResultNotFoundFails() {
        let result = ActionResult.notFound(reason: "test")
        XCTAssertFalse(result.succeeded)
    }

    func testDetectionMethodRawValues() {
        XCTAssertEqual(DetectionMethod.accessibilityTree.rawValue, "AX Tree")
        XCTAssertEqual(DetectionMethod.automation.rawValue, "Automation")
        XCTAssertEqual(DetectionMethod.ocr.rawValue, "Vision OCR")
    }

    // MARK: - AppCategory

    func testAppCategoryDetectionAI() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.anthropic.claudefordesktop"), .ai)
        XCTAssertEqual(AppCategory.from(bundleID: "com.openai.chat"), .ai)
    }

    func testAppCategoryDetectionTerminal() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.microsoft.VSCode"), .terminal)
        XCTAssertEqual(AppCategory.from(bundleID: "com.todesktop.230313mzl4w4u92"), .terminal)
        XCTAssertEqual(AppCategory.from(bundleID: "com.apple.Terminal"), .terminal)
    }

    func testAppCategoryDetectionMedia() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.spotify.client"), .media)
        XCTAssertEqual(AppCategory.from(bundleID: "com.apple.Music"), .media)
    }

    func testAppCategoryDetectionCAD() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.autodesk.Fusion360"), .cad)
    }

    func testAppCategoryDetectionVideoEditing() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.apple.FinalCut"), .videoEditing)
        XCTAssertEqual(AppCategory.from(bundleID: "com.blackmagicdesign.resolve"), .videoEditing)
    }

    func testAppCategoryDetectionWriting() {
        XCTAssertEqual(AppCategory.from(bundleID: "notion.id"), .writing)
        XCTAssertEqual(AppCategory.from(bundleID: "md.obsidian"), .writing)
    }

    func testAppCategoryDetectionCommunication() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.tinyspeck.slackmacgap"), .communication)
        XCTAssertEqual(AppCategory.from(bundleID: "us.zoom.xos"), .communication)
    }

    func testAppCategoryDetectionDesign() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.figma.Desktop"), .design)
        XCTAssertEqual(AppCategory.from(bundleID: "com.bohemiancoding.sketch3"), .design)
    }

    func testAppCategoryDetectionBrowser() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.apple.Safari"), .browser)
        XCTAssertEqual(AppCategory.from(bundleID: "com.google.Chrome"), .browser)
    }

    func testAppCategoryDetectionUnknown() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.example.unknownapp"), .unknown)
    }

    func testAppCategoryNameHintFallback() {
        XCTAssertEqual(AppCategory.from(bundleID: "com.unknown.app", appName: "Spotify Free"), .media)
        XCTAssertEqual(AppCategory.from(bundleID: "com.unknown.app", appName: "Fusion 360"), .cad)
    }

    // MARK: - Category Presets

    func testAllCategoriesHaveDefaultPresets() {
        let defaults = SudoSettings.defaultCategoryPresets()
        for category in AppCategory.allCases where category != .unknown {
            XCTAssertNotNil(defaults[category.rawValue], "\(category.rawValue) should have a default preset")
        }
    }

    func testDefaultPresetsExistInPresetList() {
        let defaults = SudoSettings.defaultCategoryPresets()
        let presetIDs = Set(ButtonPreset.all.map { $0.id })
        for (_, presetID) in defaults {
            XCTAssertTrue(presetIDs.contains(presetID), "Preset '\(presetID)' not found in ButtonPreset.all")
        }
    }

    // MARK: - New Presets

    func testNewPresetsExist() {
        let ids = Set(ButtonPreset.all.map { $0.id })
        XCTAssertTrue(ids.contains("cad"))
        XCTAssertTrue(ids.contains("video-editing"))
        XCTAssertTrue(ids.contains("writing"))
        XCTAssertTrue(ids.contains("communication"))
        XCTAssertTrue(ids.contains("design"))
    }

    func testAllPresetsHaveFourButtons() {
        for preset in ButtonPreset.all {
            XCTAssertEqual(preset.buttons.count, 4, "Preset '\(preset.id)' should have 4 buttons")
        }
    }

    func testPresetCount() {
        XCTAssertEqual(ButtonPreset.all.count, 14)
    }
}

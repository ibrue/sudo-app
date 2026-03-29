import XCTest
@testable import Sudo

final class ModelTests: XCTestCase {

    // MARK: - PadAction

    func testAllPadActionsExist() {
        XCTAssertEqual(PadAction.allCases.count, 4)
    }

    func testPadActionKeyCodes() {
        XCTAssertEqual(PadAction.approve.keyCode, 105) // F13
        XCTAssertEqual(PadAction.reject.keyCode, 107)  // F14
        XCTAssertEqual(PadAction.action3.keyCode, 113) // F15
        XCTAssertEqual(PadAction.action4.keyCode, 106) // F16
    }

    func testPadActionFKeyNumbers() {
        XCTAssertEqual(PadAction.approve.fKeyNumber, 13)
        XCTAssertEqual(PadAction.reject.fKeyNumber, 14)
        XCTAssertEqual(PadAction.action3.fKeyNumber, 15)
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
        XCTAssertEqual(PadAction.approve.displayName, "Approve / Yes")
        XCTAssertEqual(PadAction.reject.displayName, "Reject / No")
    }

    // MARK: - SupportedApp

    func testAllSupportedAppsExist() {
        XCTAssertEqual(SupportedApp.allCases.count, 5)
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
        XCTAssertEqual(DetectionMethod.ocr.rawValue, "Vision OCR")
    }
}

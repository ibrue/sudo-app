import Foundation
import AppKit

enum ActionResult {
    case found(element: AXUIElement, method: DetectionMethod)
    case foundOCR(point: CGPoint, method: DetectionMethod)
    case notFound(reason: String)

    var succeeded: Bool {
        switch self {
        case .found, .foundOCR: return true
        case .notFound: return false
        }
    }
}

enum DetectionMethod: String {
    case accessibilityTree = "AX Tree"
    case ocr               = "Vision OCR"
}

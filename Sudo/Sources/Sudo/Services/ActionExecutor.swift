import Cocoa

/// Executes found actions via AXPress (preferred) or CGEvent click (fallback).
/// AXUIElementPerformAction is the gold standard for anti-cheat compatibility —
/// same code path as VoiceOver and Shortcuts.app.
final class ActionExecutor {

    enum ExecutionResult {
        case success(method: String)
        case failure(reason: String)
    }

    func execute(result: ActionResult) -> ExecutionResult {
        switch result {
        case .found(let element, _):
            return performAXPress(element: element)
        case .foundOCR(let point, _):
            return performClickAtPoint(point)
        case .notFound(let reason):
            return .failure(reason: reason)
        }
    }

    private func performAXPress(element: AXUIElement) -> ExecutionResult {
        for action in ["AXPress", "AXConfirm", "AXShowDefaultUI"] {
            if AXUIElementPerformAction(element, action as CFString) == .success {
                return .success(method: action)
            }
        }
        return .failure(reason: "All AX actions failed")
    }

    private func performClickAtPoint(_ point: CGPoint) -> ExecutionResult {
        // Try AX hit-test first
        let systemWide = AXUIElementCreateSystemWide()
        var elementAtPoint: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &elementAtPoint) == .success,
           let element = elementAtPoint,
           AXUIElementPerformAction(element, "AXPress" as CFString) == .success {
            return .success(method: "AXPress (hit test)")
        }

        // Fallback: CGEvent click
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        usleep(50_000)
        mouseUp?.post(tap: .cghidEventTap)

        return .success(method: "CGEvent click (\(Int(point.x)), \(Int(point.y)))")
    }
}

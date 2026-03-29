import Cocoa
import Vision

/// Fallback detection: captures window screenshot, uses Vision OCR to find buttons.
/// Runs entirely on-device — no data leaves the machine.
final class OCRButtonFinder {

    func findButton(for action: PadAction, pid: pid_t) -> ActionResult {
        guard let screenshot = captureWindow(pid: pid) else {
            return .notFound(reason: "Could not capture window screenshot")
        }

        let searchTerms = action.searchTerms.map { $0.lowercased() }

        guard let observations = performOCR(on: screenshot) else {
            return .notFound(reason: "OCR failed")
        }

        let imageSize = CGSize(width: CGFloat(screenshot.width), height: CGFloat(screenshot.height))

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.lowercased().trimmingCharacters(in: .whitespaces)

            for term in searchTerms {
                if text == term || text.contains(term) {
                    if let point = visionToScreenPoint(boundingBox: observation.boundingBox, imageSize: imageSize, pid: pid) {
                        print("[sudo] OCR found '\(candidate.string)' at (\(point.x), \(point.y))")
                        return .foundOCR(point: point, method: .ocr)
                    }
                }
            }
        }

        return .notFound(reason: "OCR found no matching text")
    }

    private func captureWindow(pid: pid_t) -> CGImage? {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        for window in windowList {
            guard let windowPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid,
                  let windowID = window[kCGWindowNumber as String] as? CGWindowID else { continue }

            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .nominalResolution]) {
                return image
            }
        }
        return nil
    }

    private func performOCR(on image: CGImage) -> [VNRecognizedTextObservation]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            return request.results
        } catch {
            print("[sudo] Vision OCR error: \(error)")
            return nil
        }
    }

    private func visionToScreenPoint(boundingBox: CGRect, imageSize: CGSize, pid: pid_t) -> CGPoint? {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

        for window in windowList {
            guard let windowPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }

            let windowX = bounds["X"] ?? 0
            let windowY = bounds["Y"] ?? 0
            let centerX = windowX + boundingBox.midX * imageSize.width
            let centerY = windowY + (1.0 - boundingBox.midY) * imageSize.height
            return CGPoint(x: centerX, y: centerY)
        }
        return nil
    }
}

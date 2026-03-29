import Cocoa

/// Central orchestrator: receives pad actions and coordinates detection → execution.
final class SudoEngine: ObservableObject {

    @Published var lastAction: String = "Waiting for input..."
    @Published var lastMethod: String = ""
    @Published var detectedApp: String = "No AI app detected"
    @Published var isConnected: Bool = false

    private let appDetector = AppDetector()
    private let axFinder = AXButtonFinder()
    private let ocrFinder = OCRButtonFinder()
    private let executor = ActionExecutor()
    private let simpleExecutor = SimpleActionExecutor()
    private let hotkeyListener = HotkeyListener()
    private let configStore = ButtonConfigStore.shared

    func start() {
        hotkeyListener.start { [weak self] action in
            self?.handleAction(action)
        }
        isConnected = true

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDetectedApp()
        }
    }

    func stop() {
        hotkeyListener.stop()
        isConnected = false
    }

    private func updateDetectedApp() {
        if let app = appDetector.detectFrontmostApp() {
            let label = app.isBrowser ? "\(app.name) (\(app.matchedDomain ?? "web"))" : app.name
            DispatchQueue.main.async { self.detectedApp = label }
        } else {
            DispatchQueue.main.async { self.detectedApp = "No AI app detected" }
        }
    }

    private func handleAction(_ action: PadAction) {
        let mode = configStore.buttonMode(for: action)

        // Simple mode: simulate a keyboard shortcut directly
        if case .simple(let simpleAction) = mode {
            lastAction = "Processing: \(simpleAction.displayName)..."
            print("[sudo] Simple action: \(simpleAction.displayName)")

            let result = simpleExecutor.execute(simpleAction)
            switch result {
            case .success(let detail):
                lastAction = simpleAction.displayName
                lastMethod = "Shortcut → \(detail)"
                print("[sudo] OK: \(simpleAction.displayName) via shortcut")
            case .failure(let reason):
                lastAction = "\(simpleAction.displayName) — failed"
                lastMethod = "Shortcut: \(reason)"
            }
            return
        }

        // Complex mode: AX tree + OCR flow
        lastAction = "Processing: \(action.displayName)..."

        guard let app = appDetector.detectFrontmostApp() else {
            lastAction = "\(action.displayName) — no AI app in focus"
            lastMethod = ""
            return
        }

        print("[sudo] Target: \(app.name) (PID \(app.pid)), action: \(action.displayName)")

        // Strategy 1: AX tree (preferred)
        let axResult = axFinder.findButton(for: action, pid: app.pid)
        if axResult.succeeded {
            let execResult = executor.execute(result: axResult)
            updateStatus(action: action, execResult: execResult, method: "AX Tree")
            return
        }

        print("[sudo] AX tree miss — falling back to OCR")

        // Strategy 2: Vision OCR fallback
        let ocrResult = ocrFinder.findButton(for: action, pid: app.pid)
        if ocrResult.succeeded {
            let execResult = executor.execute(result: ocrResult)
            updateStatus(action: action, execResult: execResult, method: "Vision OCR")
            return
        }

        lastAction = "\(action.displayName) — button not found"
        lastMethod = "Searched AX tree + OCR"
    }

    private func updateStatus(action: PadAction, execResult: ActionExecutor.ExecutionResult, method: String) {
        switch execResult {
        case .success(let detail):
            lastAction = "\(action.displayName)"
            lastMethod = "\(method) → \(detail)"
            print("[sudo] OK: \(action.displayName) via \(method) → \(detail)")
        case .failure(let reason):
            lastAction = "\(action.displayName) — failed"
            lastMethod = "\(method): \(reason)"
        }
    }
}

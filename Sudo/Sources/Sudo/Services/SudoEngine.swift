import Cocoa

/// Central orchestrator: receives pad actions and coordinates detection → execution.
final class SudoEngine: ObservableObject {

    @Published var lastAction: String = "Waiting for input..."
    @Published var lastMethod: String = ""
    @Published var detectedApp: String = "No AI app detected"
    @Published var isConnected: Bool = false
    @Published var isProcessing: Bool = false
    @Published var searchAllApps: Bool = false

    private let appDetector = AppDetector()
    private let axFinder = AXButtonFinder()
    private let ocrFinder = OCRButtonFinder()
    private let executor = ActionExecutor()
    private let hotkeyListener = HotkeyListener()

    /// Trigger an action programmatically (for the test panel UI)
    func triggerAction(_ padAction: PadAction) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.handleAction(padAction)
        }
    }

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
        DispatchQueue.main.async { self.isProcessing = true }
        defer { DispatchQueue.main.async { self.isProcessing = false } }

        DispatchQueue.main.async {
            self.lastAction = "Processing: \(action.displayName)..."
            self.lastMethod = ""
        }

        // Build list of apps to search
        let appsToSearch: [AppDetector.DetectedApp]

        if searchAllApps {
            appsToSearch = appDetector.detectAllSupportedApps()
        } else if let app = appDetector.detectFrontmostApp() {
            appsToSearch = [app]
        } else {
            DispatchQueue.main.async {
                self.lastAction = "\(action.displayName) — no AI app in focus"
                self.lastMethod = ""
            }
            return
        }

        for app in appsToSearch {
            print("[sudo] Target: \(app.name) (PID \(app.pid)), action: \(action.displayName)")

            // Strategy 1: AX tree (preferred)
            let axResult = axFinder.findButton(for: action, pid: app.pid)
            if axResult.succeeded {
                let execResult = executor.execute(result: axResult)
                updateStatus(action: action, execResult: execResult, method: "AX Tree (\(app.name))")
                return
            }

            print("[sudo] AX tree miss for \(app.name) — trying OCR")

            // Strategy 2: Vision OCR fallback
            let ocrResult = ocrFinder.findButton(for: action, pid: app.pid)
            if ocrResult.succeeded {
                let execResult = executor.execute(result: ocrResult)
                updateStatus(action: action, execResult: execResult, method: "Vision OCR (\(app.name))")
                return
            }

            // Strategy 3: Keyboard shortcut for editors/terminals
            if SupportedApp.editorBundleIDs.contains(app.bundleID) {
                print("[sudo] AX+OCR miss for editor \(app.name) — sending keypress")
                if let keyCode = action.editorKeyCode {
                    sendKeypress(keyCode: keyCode, to: app.pid)
                    updateStatus(action: action,
                                 execResult: .success(method: "Keypress"),
                                 method: "Keyboard (\(app.name))")
                    return
                }
            }
        }

        let appNames = appsToSearch.map { $0.name }.joined(separator: ", ")
        DispatchQueue.main.async {
            self.lastAction = "\(action.displayName) — button not found"
            self.lastMethod = "Searched: \(appNames)"
        }
    }

    /// Send a keypress to the target app
    private func sendKeypress(keyCode: UInt16, to pid: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        // Target the specific process
        let targetApp = NSRunningApplication(processIdentifier: pid)
        targetApp?.activate(options: [])
        usleep(100_000) // 100ms for app to come to front

        keyDown?.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp?.post(tap: .cghidEventTap)

        print("[sudo] Sent keyCode \(keyCode) to PID \(pid)")
    }

    private func updateStatus(action: PadAction, execResult: ActionExecutor.ExecutionResult, method: String) {
        switch execResult {
        case .success(let detail):
            DispatchQueue.main.async {
                self.lastAction = "\(action.displayName)"
                self.lastMethod = "\(method) → \(detail)"
            }
            print("[sudo] OK: \(action.displayName) via \(method) → \(detail)")
        case .failure(let reason):
            DispatchQueue.main.async {
                self.lastAction = "\(action.displayName) — failed"
                self.lastMethod = "\(method): \(reason)"
            }
        }
    }
}

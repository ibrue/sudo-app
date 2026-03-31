import Cocoa
import UserNotifications

/// Central orchestrator: receives pad actions and coordinates detection → execution.
final class SudoEngine: ObservableObject {

    enum ActionResult: Equatable {
        case idle, processing, success, failure
    }

    @Published var lastAction: String = "Waiting for input..."
    @Published var lastMethod: String = ""
    @Published var detectedApp: String = "No AI app detected"
    @Published var currentBundleID: String? = nil
    @Published var isConnected: Bool = false
    @Published var isProcessing: Bool = false
    @Published var lastResult: ActionResult = .idle
    @Published var actionLog: [ActionLogEntry] = []

    var searchAllApps: Bool {
        get { SudoSettings.shared.searchAllApps }
        set { SudoSettings.shared.searchAllApps = newValue; objectWillChange.send() }
    }

    private let appDetector = AppDetector()
    private let axFinder = AXButtonFinder()
    private let ocrFinder = OCRButtonFinder()
    private let executor = ActionExecutor()
    private let hotkeyListener = HotkeyListener()
    private var lastActionTime: Date = .distantPast
    private let debounceDuration: TimeInterval = 0.5
    private let searchTimeout: TimeInterval = 3.0

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
        isConnected = hotkeyListener.isListening

        // Event-driven app detection via NSWorkspace notifications
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            self?.updateDetectedApp()
        }
        // Initial detection
        updateDetectedApp()

        SudoTelemetry.shared.trackLaunch()
    }

    func stop() {
        hotkeyListener.stop()
        isConnected = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func updateDetectedApp() {
        if let app = appDetector.detectFrontmostApp() {
            let label = app.isBrowser ? "\(app.name) (\(app.matchedDomain ?? "web"))" : app.name
            DispatchQueue.main.async {
                self.detectedApp = label
                self.currentBundleID = app.bundleID
            }
        } else {
            // Also track non-AI apps for per-app profiles
            let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            DispatchQueue.main.async {
                self.detectedApp = "No AI app detected"
                self.currentBundleID = frontBundleID
            }
        }
    }

    /// Execute a macro sequence (chained actions with delays)
    func executeMacro(_ macro: MacroSequence) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for step in macro.steps {
                guard let action = step.padAction else { continue }
                self?.handleAction(action)
                if step.delayAfter > 0 {
                    Thread.sleep(forTimeInterval: step.delayAfter)
                }
            }
        }
    }

    private func handleAction(_ action: PadAction) {
        // Check if this button has a macro assigned
        if let macro = SudoSettings.shared.macros.first(where: { $0.assignedButton == action.rawValue }) {
            executeMacro(macro)
            return
        }

        // Debounce: ignore rapid double-presses
        let now = Date()
        guard now.timeIntervalSince(lastActionTime) >= debounceDuration else {
            print("[sudo] Debounced: \(action.displayName) (too fast)")
            return
        }
        lastActionTime = now

        DispatchQueue.main.async {
            self.isProcessing = true
            self.lastResult = .processing
            self.lastAction = "Searching: \(action.displayName)..."
            self.lastMethod = ""
        }

        // Build list of apps to search
        let appsToSearch: [AppDetector.DetectedApp]

        if searchAllApps {
            appsToSearch = appDetector.detectAllSupportedApps()
        } else if let app = appDetector.detectFrontmostApp() {
            appsToSearch = [app]
        } else {
            finishAction(action: action, success: false, app: "none", method: "",
                         statusText: "\(action.displayName) — no AI app in focus")
            return
        }

        let activeBundleID = self.currentBundleID

        for app in appsToSearch {
            print("[sudo] Target: \(app.name) (PID \(app.pid)), action: \(action.displayName)")

            // Strategy 1: AX tree with timeout
            if let axResult = withTimeout(seconds: searchTimeout, work: {
                self.axFinder.findButton(for: action, pid: app.pid, bundleID: activeBundleID)
            }), axResult.succeeded {
                let execResult = executor.execute(result: axResult)
                handleExecResult(execResult, action: action, app: app.name, method: "AX Tree")
                return
            }

            print("[sudo] AX tree miss for \(app.name) — trying OCR")

            // Strategy 2: Vision OCR with timeout
            if let ocrResult = withTimeout(seconds: searchTimeout, work: {
                self.ocrFinder.findButton(for: action, pid: app.pid)
            }), ocrResult.succeeded {
                let execResult = executor.execute(result: ocrResult)
                handleExecResult(execResult, action: action, app: app.name, method: "Vision OCR")
                return
            }

            // Strategy 3: Keyboard shortcut for editors/terminals
            if SupportedApp.editorBundleIDs.contains(app.bundleID) {
                print("[sudo] AX+OCR miss for editor \(app.name) — sending keypress")
                if let keyCode = action.editorKeyCode {
                    sendKeypress(keyCode: keyCode, to: app.pid)
                    finishAction(action: action, success: true, app: app.name,
                                 method: "Keyboard → keyCode \(keyCode)",
                                 statusText: action.displayName)
                    return
                }
            }
        }

        let appNames = appsToSearch.map { $0.name }.joined(separator: ", ")
        finishAction(action: action, success: false, app: appNames, method: "AX + OCR",
                     statusText: "\(action.displayName) — button not found")
    }

    // MARK: - Helpers

    private func handleExecResult(_ execResult: ActionExecutor.ExecutionResult, action: PadAction, app: String, method: String) {
        switch execResult {
        case .success(let detail):
            finishAction(action: action, success: true, app: app,
                         method: "\(method) → \(detail)", statusText: action.displayName)
        case .failure(let reason):
            finishAction(action: action, success: false, app: app,
                         method: "\(method): \(reason)",
                         statusText: "\(action.displayName) — failed")
        }
    }

    private func finishAction(action: PadAction, success: Bool, app: String, method: String, statusText: String) {
        let entry = ActionLogEntry(
            timestamp: Date(), action: action.displayName,
            app: app, method: method, succeeded: success
        )

        DispatchQueue.main.async {
            self.lastAction = statusText
            self.lastMethod = method
            self.isProcessing = false
            self.lastResult = success ? .success : .failure
            self.actionLog.insert(entry, at: 0)
            if self.actionLog.count > 50 { self.actionLog = Array(self.actionLog.prefix(50)) }

            // Sound feedback
            if SudoSettings.shared.soundEnabled {
                NSSound(named: success ? "Purr" : "Basso")?.play()
            }

            // Fire webhook
            WebhookManager.shared.fire(action: action, app: app, method: method, success: success)

            // Telemetry
            SudoTelemetry.shared.trackAction(action: action, app: app, success: success)

            // macOS notification on failure
            if !success && SudoSettings.shared.notifyOnFailure {
                self.sendFailureNotification(action: action, app: app)
            }

            // Reset flash after 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.lastResult == .success || self.lastResult == .failure {
                    self.lastResult = .idle
                }
            }
        }

        print("[sudo] \(success ? "OK" : "FAIL"): \(action.displayName) via \(method)")
    }

    /// Run work with a timeout — returns nil if timed out
    private func withTimeout<T>(seconds: TimeInterval, work: @escaping () -> T) -> T? {
        var result: T?
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            result = work()
            semaphore.signal()
        }
        let status = semaphore.wait(timeout: .now() + seconds)
        return status == .success ? result : nil
    }

    /// Send a keypress to the target app
    private func sendKeypress(keyCode: UInt16, to pid: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        // Only activate if not already frontmost
        if let targetApp = NSRunningApplication(processIdentifier: pid),
           !targetApp.isActive {
            targetApp.activate(options: [])
            usleep(100_000)
        }

        keyDown?.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp?.post(tap: .cghidEventTap)

        print("[sudo] Sent keyCode \(keyCode) to PID \(pid)")
    }

    private func sendFailureNotification(action: PadAction, app: String) {
        let content = UNMutableNotificationContent()
        content.title = "[sudo] Action failed"
        content.body = "\(action.displayName) — button not found in \(app)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

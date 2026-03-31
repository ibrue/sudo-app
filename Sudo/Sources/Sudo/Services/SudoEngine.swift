import Cocoa
import UserNotifications

/// Central orchestrator: receives pad actions and coordinates detection → execution.
final class SudoEngine: ObservableObject {

    enum ActionResult: Equatable {
        case idle, processing, success, failure
    }

    @Published var lastAction: String = "Waiting for input..."
    @Published var lastMethod: String = ""
    @Published var lastContext: String = ""
    @Published var detectedApp: String = "No AI app detected"
    @Published var currentBundleID: String? = nil
    @Published var isConnected: Bool = false
    @Published var axPermissionGranted: Bool = false
    @Published var permissionStatus: String = "checking..."
    @Published var isProcessing: Bool = false
    @Published var lastResult: ActionResult = .idle
    @Published var actionLog: [ActionLogEntry] = []
    @Published var autoApproveCount: Int = 0

    // MARK: - MCP Server support

    @Published var pendingMCPRequest: String? = nil

    /// Semaphore used to block MCP request-approval calls until a physical button press.
    private let mcpSemaphore = DispatchSemaphore(value: 0)
    private var mcpApprovalResult: Bool = false

    /// Called by the API server when an MCP approval request arrives.
    /// Blocks until `resolveMCPRequest(approved:)` is called or timeout expires.
    /// - Returns: `true` if approved, `false` if rejected or timed out.
    func waitForMCPApproval(prompt: String, timeout: TimeInterval) -> (approved: Bool, timeMs: Int) {
        DispatchQueue.main.async {
            self.pendingMCPRequest = prompt
        }
        PadCommunicator.shared.sendState(.waitingForInput)

        let start = DispatchTime.now()
        let result = mcpSemaphore.wait(timeout: .now() + timeout)
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let timeMs = Int(elapsed / 1_000_000)

        let approved: Bool
        if result == .timedOut {
            approved = false
        } else {
            approved = mcpApprovalResult
        }

        DispatchQueue.main.async {
            self.pendingMCPRequest = nil
        }
        PadCommunicator.shared.sendState(approved ? .success : .failure)

        return (approved: approved, timeMs: timeMs)
    }

    /// Resolve a pending MCP approval request (called from physical button press or UI).
    func resolveMCPRequest(approved: Bool) {
        mcpApprovalResult = approved
        mcpSemaphore.signal()
    }

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
    private let debounceDuration: TimeInterval = 0.1
    private let searchTimeout: TimeInterval = 3.0
    private var autoApproveTimer: Timer?
    private var permissionCheckTimer: Timer?

    /// Trigger an action programmatically (for the test panel UI)
    func triggerAction(_ padAction: PadAction) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.handleAction(padAction)
        }
    }

    func start() {
        // Check permissions and try to start listener
        checkAndConnect()

        // Re-check permissions every 3 seconds until connected
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isConnected {
                self.checkAndConnect()
            }
        }

        // Event-driven app detection via NSWorkspace notifications
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            self?.updateDetectedApp()
        }
        updateDetectedApp()

        PluginManager.shared.loadPlugins()
        startAutoApproveTimer()

        PadCommunicator.shared.connect()
        PadCommunicator.shared.sendState(.idle)

        SudoTelemetry.shared.trackLaunch()
    }

    /// Check permissions and (re)start the hotkey listener if possible
    func checkAndConnect() {
        let axTrusted = AXIsProcessTrusted()

        DispatchQueue.main.async {
            self.axPermissionGranted = axTrusted
        }

        if axTrusted {
            // Try to start the listener if not already running
            if !hotkeyListener.isListening {
                hotkeyListener.stop()
                hotkeyListener.start { [weak self] action in
                    self?.handleAction(action)
                }
            }

            let listening = hotkeyListener.isListening

            // Test AX tree access on a real app
            let canReadAX = testAXAccess()

            DispatchQueue.main.async {
                self.isConnected = listening
                if listening && canReadAX {
                    self.permissionStatus = "all permissions granted"
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                } else if listening {
                    self.permissionStatus = "hotkeys ok, ax tree limited"
                } else {
                    self.permissionStatus = "ax granted but event tap failed — try restarting the app"
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isConnected = false
                self.permissionStatus = "accessibility not granted"
            }
        }
    }

    /// Try to read the AX tree of the frontmost app as a real permission test
    private func testAXAccess() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        return result == .success
    }

    func stop() {
        hotkeyListener.stop()
        isConnected = false
        autoApproveTimer?.invalidate()
        autoApproveTimer = nil
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        PadCommunicator.shared.disconnect()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Auto-Approve

    /// Start or restart the auto-approve polling timer.
    func startAutoApproveTimer() {
        autoApproveTimer?.invalidate()
        autoApproveTimer = nil
        guard SudoSettings.shared.autoApproveEnabled else { return }
        autoApproveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAutoApprove()
        }
    }

    private func checkAutoApprove() {
        guard SudoSettings.shared.autoApproveEnabled else {
            autoApproveTimer?.invalidate()
            autoApproveTimer = nil
            return
        }
        guard !isProcessing else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let app = self.appDetector.detectFrontmostApp() else { return }

            // Try to find an approve button via AX
            let action = PadAction.approve
            let activeBundleID = self.currentBundleID
            guard let axResult = self.withTimeout(seconds: self.searchTimeout, work: {
                self.axFinder.findButton(for: action, pid: app.pid, bundleID: activeBundleID)
            }), axResult.succeeded else { return }

            // Capture context for rule evaluation
            let context = self.axFinder.captureContext(pid: app.pid)

            // Check rules engine
            guard let matchedRule = RulesEngine.shared.shouldAutoApprove(app: app, context: context) else { return }

            print("[sudo] auto-approve triggered by rule: \(matchedRule.name)")

            // Execute the approve action
            let execResult = self.executor.execute(result: axResult)
            let methodPrefix = "[auto] "
            switch execResult {
            case .success(let detail):
                self.finishAction(action: action, success: true, app: app.name,
                                  method: "\(methodPrefix)AX Tree → \(detail)",
                                  statusText: "[auto] \(action.displayName)", context: context)
                DispatchQueue.main.async { self.autoApproveCount += 1 }
            case .failure(let reason):
                self.finishAction(action: action, success: false, app: app.name,
                                  method: "\(methodPrefix)AX Tree: \(reason)",
                                  statusText: "[auto] \(action.displayName) — failed", context: context)
            }
        }
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

        // Check action mode — simple modes skip the AI search pipeline entirely
        let mode = SudoSettings.shared.actionMode(for: action)

        if mode == .keyCombo, let kc = SudoSettings.shared.keyCombo(for: action) {
            sendKeyComboDirect(keyCode: kc.keyCode, modifiers: kc.modifiers)
            finishAction(action: action, success: true, app: "system",
                         method: "keyCombo → \(action.displayName)",
                         statusText: action.displayName)
            return
        }

        if mode == .mediaKey, let kc = SudoSettings.shared.keyCombo(for: action) {
            sendMediaKey(keyType: Int32(kc.keyCode))
            finishAction(action: action, success: true, app: "system",
                         method: "mediaKey → \(action.displayName)",
                         statusText: action.displayName)
            return
        }

        PadCommunicator.shared.sendState(.processing)

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

            // Capture context before executing
            let context = axFinder.captureContext(pid: app.pid)

            // Strategy 1: AX tree with timeout
            if let axResult = withTimeout(seconds: searchTimeout, work: {
                self.axFinder.findButton(for: action, pid: app.pid, bundleID: activeBundleID)
            }), axResult.succeeded {
                let execResult = executor.execute(result: axResult)
                handleExecResult(execResult, action: action, app: app.name, method: "AX Tree", context: context)
                return
            }

            print("[sudo] AX tree miss for \(app.name) — trying OCR")

            // Strategy 2: Vision OCR with timeout
            if let ocrResult = withTimeout(seconds: searchTimeout, work: {
                self.ocrFinder.findButton(for: action, pid: app.pid)
            }), ocrResult.succeeded {
                let execResult = executor.execute(result: ocrResult)
                handleExecResult(execResult, action: action, app: app.name, method: "Vision OCR", context: context)
                return
            }

            // Strategy 3: Keyboard shortcut for editors/terminals
            if SupportedApp.editorBundleIDs.contains(app.bundleID) {
                print("[sudo] AX+OCR miss for editor \(app.name) — sending keypress")
                if let keyCode = action.editorKeyCode {
                    sendKeypress(keyCode: keyCode, to: app.pid)
                    finishAction(action: action, success: true, app: app.name,
                                 method: "Keyboard → keyCode \(keyCode)",
                                 statusText: action.displayName, context: context)
                    return
                }
            }
        }

        let appNames = appsToSearch.map { $0.name }.joined(separator: ", ")
        finishAction(action: action, success: false, app: appNames, method: "AX + OCR",
                     statusText: "\(action.displayName) — button not found")
    }

    // MARK: - Helpers

    private func handleExecResult(_ execResult: ActionExecutor.ExecutionResult, action: PadAction, app: String, method: String, context: String? = nil) {
        switch execResult {
        case .success(let detail):
            finishAction(action: action, success: true, app: app,
                         method: "\(method) → \(detail)", statusText: action.displayName, context: context)
        case .failure(let reason):
            finishAction(action: action, success: false, app: app,
                         method: "\(method): \(reason)",
                         statusText: "\(action.displayName) — failed", context: context)
        }
    }

    private func finishAction(action: PadAction, success: Bool, app: String, method: String, statusText: String, context: String? = nil) {
        let entry = ActionLogEntry(
            timestamp: Date(), action: action.displayName,
            app: app, method: method, succeeded: success,
            context: context
        )

        // LED feedback
        PadCommunicator.shared.sendState(success ? .success : .failure)

        // Usage stats / gamification
        let settings = SudoSettings.shared
        if action == .approve {
            settings.totalApproves += 1
        } else if action == .reject {
            settings.totalRejects += 1
        }
        settings.updateStreak()

        DispatchQueue.main.async {
            self.lastAction = statusText
            self.lastMethod = method
            self.lastContext = context ?? ""
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

            // Telemetry (generic button press, not action-specific)
            let mode = SudoSettings.shared.actionMode(for: action).rawValue
            SudoTelemetry.shared.trackButtonPress(button: action, mode: mode)

            // macOS notification on failure
            if !success && SudoSettings.shared.notifyOnFailure {
                self.sendFailureNotification(action: action, app: app)
            }

            // Reset flash after 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.lastResult == .success || self.lastResult == .failure {
                    self.lastResult = .idle
                    PadCommunicator.shared.sendState(.idle)
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

    /// Send a keyboard shortcut (e.g., Cmd+C, Cmd+V) to the frontmost app
    private func sendKeyComboDirect(keyCode: UInt16, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = modifiers
        keyUp?.flags = modifiers
        keyDown?.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp?.post(tap: .cghidEventTap)
        print("[sudo] Sent keyCombo: keyCode=\(keyCode) modifiers=\(modifiers.rawValue)")
    }

    /// Send a media key event (play/pause, next, previous, mute)
    private func sendMediaKey(keyType: Int32) {
        func doMediaKey(down: Bool) {
            let flags: Int32 = down ? 0xa00 : 0xb00
            let data1 = Int32((keyType << 16) | flags)
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: Int(data1), data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        doMediaKey(down: true)
        doMediaKey(down: false)
        print("[sudo] Sent mediaKey: type=\(keyType)")
    }

    private func sendFailureNotification(action: PadAction, app: String) {
        let content = UNMutableNotificationContent()
        content.title = "[sudo] Action failed"
        content.body = "\(action.displayName) — button not found in \(app)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

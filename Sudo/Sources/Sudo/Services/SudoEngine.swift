import Cocoa
import UserNotifications

/// Central orchestrator: receives pad actions and coordinates detection → execution.
final class SudoEngine: ObservableObject {

    enum ActionResult: Equatable {
        case idle, processing, success, failure
    }

    @Published var lastAction: String = "waiting for input..."
    @Published var lastMethod: String = ""
    @Published var lastContext: String = ""
    @Published var detectedApp: String = "none"
    @Published var currentBundleID: String? = nil

    /// The app that will be targeted when a button is pressed from Sudo's UI.
    var targetAppName: String? {
        guard let bid = currentBundleID,
              bid != Bundle.main.bundleIdentifier,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first
        else { return nil }
        return app.localizedName?.lowercased()
    }

    @Published var isConnected: Bool = false
    @Published var axPermissionGranted: Bool = false
    @Published var permissionStatus: String = "checking..."
    @Published var isProcessing: Bool = false
    @Published var lastResult: ActionResult = .idle
    @Published var actionLog: [ActionLogEntry] = []
    @Published var autoApproveCount: Int = 0
    @Published var autoSwitchStatus: String? = nil
    @Published var currentCategory: AppCategory = .unknown
    var lastAppliedPresetID: String? = nil

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
    private let automationFinder = AutomationButtonFinder()
    private let ocrFinder = OCRButtonFinder()
    private let executor = ActionExecutor()
    private let hotkeyListener = HotkeyListener()
    private var lastActionTime: Date = .distantPast
    private let searchTimeout: TimeInterval = 3.0
    private var autoApproveTimer: Timer?
    private var permissionCheckTimer: Timer?
    private var executingMacro = false

    /// Trigger an action programmatically (for the test panel UI)
    func triggerAction(_ padAction: PadAction) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.handleAction(padAction)
        }
    }

    func start() {
        // Check permissions and try to start listener
        checkAndConnect()

        // Trigger the Automation permission prompt for System Events.
        // macOS only shows the toggle in Privacy settings after the first request.
        requestAutomationPermission()

        // Permission + tap-health timer. Runs forever (no longer
        // self-invalidates once connected) so we can keep the event tap
        // alive across the lifetime of the app:
        //   - first tries the cheap recovery: re-enable a disabled tap
        //   - if that doesn't restore listening, fall back to recreating
        //     the tap entirely
        //   - syncs `isConnected` so the UI stays accurate
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.hotkeyListener.ensureEnabled()
            if !self.hotkeyListener.isListening {
                self.checkAndConnect()
            } else {
                let listening = true
                DispatchQueue.main.async {
                    if !self.isConnected { self.isConnected = listening }
                }
            }
        }

        // Event-driven app detection via NSWorkspace notifications
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            self?.updateDetectedApp()
        }
        updateDetectedApp()

        // Auto-detect the macropad. Passive scan now (so the popover shows
        // current state at launch), and again whenever a USB volume mounts
        // or unmounts — that's the cheapest, most reliable signal that the
        // CIRCUITPY / RPI-RP2 drive came/went without burning a polling timer.
        FirmwareFlasher.shared.refreshDeviceState()
        // IOKit HID hot-plug watcher: complements the volume-based
        // detection above. Boot.py hides CIRCUITPY in normal use, so
        // the mount notification never fires for a working pad — but
        // the pad still enumerates as a HID keyboard, which IOKit sees.
        FirmwareFlasher.shared.startHIDDetection()
        nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { _ in
            FirmwareFlasher.shared.refreshDeviceState()
        }
        nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { _ in
            FirmwareFlasher.shared.refreshDeviceState()
        }

        PluginManager.shared.loadPlugins()
        startAutoApproveTimer()

        PadCommunicator.shared.connect()
        PadCommunicator.shared.sendState(.idle)

        SudoTelemetry.shared.trackLaunch()
    }

    /// Check permissions and (re)start the hotkey listener if possible
    func checkAndConnect() {
        // Use AXIsProcessTrustedWithOptions instead of plain
        // AXIsProcessTrusted: the latter can return a stale "false"
        // for the lifetime of the process after `tccutil reset`
        // (which build.sh runs on every rebuild) even after the user
        // re-grants Accessibility in System Settings. Passing the
        // prompt option as `false` skips the prompt UI but still
        // forces the trust cache to refresh, which is the bit that
        // matters here. The cache miss was the likely cause behind
        // "I toggled accessibility on and the app still won't connect".
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        DebugLogger.shared.log("permission check: ax=\(axTrusted), tap=\(hotkeyListener.isListening)")

        DispatchQueue.main.async {
            self.axPermissionGranted = axTrusted
        }

        if axTrusted {
            if !hotkeyListener.isListening {
                hotkeyListener.stop()
                hotkeyListener.start { [weak self] action in
                    self?.handleAction(action)
                }
            }
            let listening = hotkeyListener.isListening
            DispatchQueue.main.async {
                self.isConnected = listening
                if listening {
                    self.permissionStatus = "all permissions granted"
                    // Don't invalidate the timer — we want it to keep
                    // pulsing so we can re-enable a tap that macOS
                    // disables under load.
                } else {
                    self.permissionStatus = "accessibility granted but event tap failed — try restarting"
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isConnected = false
                self.permissionStatus = "accessibility not granted"
            }
        }
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
                                  statusText: "[auto] \(action.displayName.lowercased())", context: context)
                DispatchQueue.main.async { self.autoApproveCount += 1 }
            case .failure(let reason):
                self.finishAction(action: action, success: false, app: app.name,
                                  method: "\(methodPrefix)AX Tree: \(reason)",
                                  statusText: "[auto] \(action.displayName.lowercased()) — failed", context: context)
            }
        }
    }

    private func updateDetectedApp() {
        // Always show the frontmost app — not just AI apps
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontName = frontApp?.localizedName ?? "none"
        let frontBundleID = frontApp?.bundleIdentifier

        // Skip if the frontmost app is Sudo itself (e.g. menu bar popover is open)
        // This prevents auto-switch from firing and overwriting the target app
        if let bid = frontBundleID, bid == Bundle.main.bundleIdentifier {
            return
        }

        if let app = appDetector.detectFrontmostApp() {
            let label = app.isBrowser ? "\(app.name) (\(app.matchedDomain ?? "web"))" : app.name
            DispatchQueue.main.async {
                self.detectedApp = label
                self.currentBundleID = app.bundleID
                self.currentCategory = app.category
            }
            handleAutoSwitch(category: app.category, appName: app.name)
        } else {
            let category = AppCategory.from(bundleID: frontBundleID ?? "", appName: frontName)
            DispatchQueue.main.async {
                self.detectedApp = frontName
                self.currentBundleID = frontBundleID
                self.currentCategory = category
            }
            handleAutoSwitch(category: category, appName: frontName)
        }
    }

    private func handleAutoSwitch(category: AppCategory, appName: String) {
        // Auto-switch only fires in dynamic mode.
        guard SudoSettings.shared.appMode == .dynamic else { return }
        guard SudoSettings.shared.autoSwitchEnabled else { return }
        guard category != .unknown else { return }
        // Don't switch presets while an action is being processed
        guard !isProcessing else { return }

        let settings = SudoSettings.shared

        // Per-app override takes priority over category mapping
        let presetID: String
        if let bundleID = currentBundleID,
           let override = settings.appPresetOverrides[bundleID] {
            presetID = override
        } else if let categoryPreset = settings.categoryPresets[category.rawValue] {
            presetID = categoryPreset
        } else {
            return
        }

        guard let preset = ButtonPreset.all.first(where: { $0.id == presetID }),
              presetID != lastAppliedPresetID else { return }

        preset.apply()
        lastAppliedPresetID = presetID

        DispatchQueue.main.async {
            self.autoSwitchStatus = "→ \(preset.name.lowercased())"
            print("[sudo] auto-switch: \(appName) → \(preset.name) (\(category.rawValue))")
            // Clear after 3s
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.autoSwitchStatus == "→ \(preset.name.lowercased())" {
                    self.autoSwitchStatus = nil
                }
            }
        }
    }

    /// Execute a macro sequence (chained actions / app switches / keystrokes).
    ///
    /// Captures the frontmost bundle ID once at the start so `.switchBack`
    /// always returns to where the user was when the macro fired, no matter
    /// how many switches happened in the middle.
    func executeMacro(_ macro: MacroSequence) {
        let originalBundleID = self.currentBundleID
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            for step in macro.steps {
                switch step.kind {
                case .action:
                    if let action = step.padAction {
                        self.handleAction(action)
                    }
                    if step.delayAfter > 0 {
                        Thread.sleep(forTimeInterval: step.delayAfter)
                    }

                case .switchToApp:
                    if let bid = step.targetBundleID, !bid.isEmpty {
                        DebugLogger.shared.log("macro: switch → \(step.targetDisplayName ?? bid)")
                        Self.activateApp(bundleID: bid)
                    }
                    let waitMs = step.waitMs ?? MacroStep.defaultSwitchWaitMs
                    Thread.sleep(forTimeInterval: Double(waitMs) / 1000.0)

                case .switchBack:
                    if let bid = originalBundleID, !bid.isEmpty {
                        DebugLogger.shared.log("macro: switch back → \(bid)")
                        Self.activateApp(bundleID: bid)
                    }
                    let waitMs = step.waitMs ?? MacroStep.defaultSwitchWaitMs
                    Thread.sleep(forTimeInterval: Double(waitMs) / 1000.0)

                case .keystroke:
                    if let kc = step.keyCode {
                        DebugLogger.shared.log("macro: keystroke \(kc) mods=\(step.modifiers ?? 0)")
                        Self.sendKeystroke(keyCode: UInt16(kc),
                                           modifiers: UInt64(step.modifiers ?? 0))
                    }
                    if step.delayAfter > 0 {
                        Thread.sleep(forTimeInterval: step.delayAfter)
                    }
                }
            }
        }
    }

    /// Activate an app by bundle ID. If the app isn't running, launches it.
    /// No-op (with a debug log) on a bundle ID we can't resolve.
    private static func activateApp(bundleID: String) {
        let running = NSWorkspace.shared.runningApplications
        if let app = running.first(where: { $0.bundleIdentifier == bundleID }) {
            app.activate(options: [])
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            DebugLogger.shared.log("macro: no app installed with bundle id \(bundleID)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                DebugLogger.shared.log("macro: launch failed for \(bundleID): \(error.localizedDescription)")
            }
        }
    }

    /// Synthesize a key-down + key-up event pair. Used by macro `.keystroke`
    /// steps to send arbitrary shortcuts (Spotify's like-song, screenshot
    /// shortcuts, etc.) without binding them to a PadAction first.
    private static func sendKeystroke(keyCode: UInt16, modifiers: UInt64) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        if modifiers != 0 {
            down?.flags = CGEventFlags(rawValue: modifiers)
            up?.flags = CGEventFlags(rawValue: modifiers)
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func handleAction(_ action: PadAction) {
        let log = DebugLogger.shared
        // Debounce: ignore rapid double-presses
        let now = Date()
        guard now.timeIntervalSince(lastActionTime) >= SudoSettings.shared.debounceDuration else {
            log.log("debounced: \(action.displayName.lowercased()) (too fast)")
            return
        }
        lastActionTime = now

        // Under-glow flash on every accepted press — fast visual feedback that
        // the press registered, before any pipeline work runs.
        PadCommunicator.shared.sendState(.buttonPressed)

        // Log every accepted action so the Debug Console shows the
        // full chain (pad input → action triggered → result). Without
        // this the only entries were debounces and macro starts, so
        // a normal press would look like nothing was happening.
        let frontmostName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "system"
        log.log("trigger: button \(action.buttonNumber) (\(action.displayName)) in \(frontmostName)")

        // Check if this button has a macro assigned
        if !executingMacro, let macro = SudoSettings.shared.macros.first(where: { $0.assignedButton == action.rawValue }) {
            log.log("running macro: \(macro.name)")
            executingMacro = true
            executeMacro(macro)
            executingMacro = false
            return
        }

        // Check action mode — simple modes skip the AI search pipeline entirely
        let mode = SudoSettings.shared.actionMode(for: action)
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontAppName = frontApp?.localizedName ?? "system"
        let frontBID = frontApp?.bundleIdentifier ?? "?"
        let isSudoFrontmost = frontApp?.bundleIdentifier == Bundle.main.bundleIdentifier

        log.log("button \(action.buttonNumber) (\(action.displayName.lowercased())) → mode: \(mode.rawValue), front: \(frontAppName) [\(frontBID)]")

        if mode == .keyCombo, let kc = SudoSettings.shared.keyCombo(for: action) {
            // Resolve the target app — use saved bundleID when Sudo is frontmost
            let target: NSRunningApplication?
            if isSudoFrontmost, let bid = currentBundleID {
                log.log("sudo is frontmost, using saved target: \(bid)")
                target = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first
            } else {
                target = frontApp
            }
            guard let app = target else {
                log.log("ERROR: no target app for keyCombo")
                finishAction(action: action, success: false, app: "none", method: "",
                             statusText: "\(action.displayName.lowercased()) — no target app")
                return
            }
            let targetName = app.localizedName?.lowercased() ?? "unknown"
            let appName = app.localizedName ?? "System Events"
            log.log("sending keyCode=\(kc.keyCode) modifiers=\(kc.modifiers.rawValue) to \(appName)")
            sendKeyComboDirect(keyCode: kc.keyCode, modifiers: kc.modifiers, appName: appName)
            finishAction(action: action, success: true, app: targetName,
                         method: "keyCombo → \(action.displayName.lowercased())",
                         statusText: action.displayName.lowercased())
            return
        }

        if mode == .mediaKey, let kc = SudoSettings.shared.keyCombo(for: action) {
            log.log("sending mediaKey: type=\(kc.keyCode)")
            sendMediaKey(keyType: Int32(kc.keyCode))
            finishAction(action: action, success: true, app: frontAppName,
                         method: "mediaKey → \(action.displayName.lowercased())",
                         statusText: action.displayName.lowercased())
            return
        }

        log.log("entering AI search pipeline for \(action.displayName.lowercased())")
        PadCommunicator.shared.sendState(.processing)

        DispatchQueue.main.async {
            self.isProcessing = true
            self.lastResult = .processing
            self.lastAction = "searching: \(action.displayName.lowercased())..."
            self.lastMethod = ""
        }

        // Build list of apps to search
        let appsToSearch: [AppDetector.DetectedApp]

        if searchAllApps {
            appsToSearch = appDetector.detectAllSupportedApps()
        } else if let app = appDetector.detectFrontmostApp(),
                  app.bundleID != Bundle.main.bundleIdentifier {
            appsToSearch = [app]
        } else if let frontApp = NSWorkspace.shared.frontmostApplication,
                  frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            // Not a recognized AI app, but still try the frontmost app
            let detected = AppDetector.DetectedApp(
                bundleID: frontApp.bundleIdentifier ?? "",
                name: frontApp.localizedName ?? "unknown",
                pid: frontApp.processIdentifier,
                isBrowser: false,
                matchedDomain: nil
            )
            appsToSearch = [detected]
        } else if let savedBundleID = self.currentBundleID,
                  savedBundleID != Bundle.main.bundleIdentifier,
                  let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: savedBundleID).first {
            // Fallback: use the previously detected app (e.g. when triggered from Sudo's UI)
            let detected = AppDetector.DetectedApp(
                bundleID: savedBundleID,
                name: targetApp.localizedName ?? "unknown",
                pid: targetApp.processIdentifier,
                isBrowser: false,
                matchedDomain: nil
            )
            appsToSearch = [detected]
        } else {
            finishAction(action: action, success: false, app: "none", method: "",
                         statusText: "\(action.displayName.lowercased()) — no app in focus")
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

            print("[sudo] AX tree miss for \(app.name) — trying Automation")

            // Strategy 2: Automation (System Events AppleScript) — reaches sheets, alerts, nested dialogs
            if let autoResult = withTimeout(seconds: searchTimeout, work: {
                self.automationFinder.findAndClick(for: action, processName: app.name, bundleID: activeBundleID)
            }), autoResult.succeeded {
                // Automation already clicked the button — just report success
                finishAction(action: action, success: true, app: app.name,
                             method: "Automation → clicked", statusText: action.displayName.lowercased(), context: context)
                return
            }

            print("[sudo] Automation miss for \(app.name) — trying OCR")

            // Strategy 3: Vision OCR with timeout
            if let ocrResult = withTimeout(seconds: searchTimeout, work: {
                self.ocrFinder.findButton(for: action, pid: app.pid)
            }), ocrResult.succeeded {
                let execResult = executor.execute(result: ocrResult)
                handleExecResult(execResult, action: action, app: app.name, method: "Vision OCR", context: context)
                return
            }

            // Strategy 4: Keyboard shortcut for editors/terminals
            if SupportedApp.editorBundleIDs.contains(app.bundleID) {
                print("[sudo] AX+OCR miss for editor \(app.name) — sending keypress")
                if let keyCode = action.editorKeyCode {
                    sendKeypress(keyCode: keyCode, to: app.pid)
                    finishAction(action: action, success: true, app: app.name,
                                 method: "Keyboard → keyCode \(keyCode)",
                                 statusText: action.displayName.lowercased(), context: context)
                    return
                }
            }
        }

        let appNames = appsToSearch.map { $0.name }.joined(separator: ", ")
        finishAction(action: action, success: false, app: appNames, method: "AX + OCR",
                     statusText: "\(action.displayName.lowercased()) — button not found")
    }

    // MARK: - Helpers

    /// Post a Return / Enter keystroke at the HID system level. Used to
    /// dismiss app-side confirmation dialogs (e.g. Fusion's Save Version
    /// sheet) after a successful primary action.
    private static func postReturnKey() {
        let kReturn: CGKeyCode = 36
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: kReturn, keyDown: true),
              let up   = CGEvent(keyboardEventSource: nil, virtualKey: kReturn, keyDown: false)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func handleExecResult(_ execResult: ActionExecutor.ExecutionResult, action: PadAction, app: String, method: String, context: String? = nil) {
        switch execResult {
        case .success(let detail):
            finishAction(action: action, success: true, app: app,
                         method: "\(method) → \(detail)", statusText: action.displayName.lowercased(), context: context)
        case .failure(let reason):
            finishAction(action: action, success: false, app: app,
                         method: "\(method): \(reason)",
                         statusText: "\(action.displayName.lowercased()) — failed", context: context)
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

        // Usage stats
        let settings = SudoSettings.shared
        settings.totalPresses += 1
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

            // macOS notification on failure (system-level, optional)
            if !success && SudoSettings.shared.notifyOnFailure {
                self.sendFailureNotification(action: action, app: app)
            }

            // Always show an in-app toast on failure — the popover may be
            // closed and the system notification may be silenced, so
            // without this a no-match press is invisible to the user.
            if !success {
                ToastWindowManager.shared.showFailure(
                    action: action.displayName,
                    app: app
                )
            }

            // Fusion 360 quirk: Cmd+S pops a "Save Version" dialog that
            // requires Enter to dismiss. After a successful save in
            // Fusion, post Return ~1s later so the save actually commits
            // instead of leaving the dialog open.
            if success
                && app.lowercased().contains("fusion")
                && action.displayName.lowercased().contains("save") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    Self.postReturnKey()
                }
            }

            // Hold the transient menu-bar label long enough to read it
            // ([✓ approve] / [✗ reject]) before falling back to [sudo].
            // Failures linger longer so the user can register what failed.
            let resetDelay: Double = success ? 2.5 : 4.0
            DispatchQueue.main.asyncAfter(deadline: .now() + resetDelay) {
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

    /// Send a keyboard shortcut via osascript — activates the target app and sends the
    /// keystroke in one atomic script so there's no race between focus and input.
    private func sendKeyComboDirect(keyCode: UInt16, modifiers: CGEventFlags, appName: String = "System Events") {
        let log = DebugLogger.shared
        let keystroke = buildKeystrokeCommand(keyCode: keyCode, modifiers: modifiers)
        let args = [
            "-e", "tell application \"\(appName)\" to activate",
            "-e", "delay 0.15",
            "-e", "tell application \"System Events\" to \(keystroke)",
        ]
        log.log("osascript: activate \"\(appName)\" → \(keystroke)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "unknown"
                log.log("ERROR osascript exit=\(process.terminationStatus): \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                log.log("OK sent \(keystroke) to \(appName)")
            }
        } catch {
            log.log("ERROR launching osascript: \(error)")
        }
    }

    /// Map virtual keyCode + modifier flags to an AppleScript keystroke command.
    private func buildKeystrokeCommand(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        let keyMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 46: "m",
            47: ".", 49: " ",
        ]
        var mods: [String] = []
        if modifiers.contains(.maskCommand) { mods.append("command down") }
        if modifiers.contains(.maskShift) { mods.append("shift down") }
        if modifiers.contains(.maskControl) { mods.append("control down") }
        if modifiers.contains(.maskAlternate) { mods.append("option down") }
        let using = mods.isEmpty ? "" : " using {\(mods.joined(separator: ", "))}"
        if let char = keyMap[keyCode] {
            return "keystroke \"\(char)\"\(using)"
        }
        return "key code \(keyCode)\(using)"
    }

    /// Trigger macOS Automation permission prompt for System Events on first launch.
    /// This makes the toggle appear in Privacy & Security → Automation.
    private func requestAutomationPermission() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"System Events\" to return \"\""]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    DebugLogger.shared.log("Automation permission: granted")
                } else {
                    DebugLogger.shared.log("Automation permission: NOT granted — enable in Privacy & Security → Automation")
                }
            } catch {
                DebugLogger.shared.log("Automation permission check failed: \(error)")
            }
        }
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
        content.body = "\(action.displayName.lowercased()) — button not found in \(app)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

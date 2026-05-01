import Cocoa
import Carbon

/// Listens for global hotkey events from any macro pad or keyboard.
/// Key bindings are configurable — works with any firmware, not just sudo's default.
/// Uses CGEvent tap — the standard macOS approach for global hotkeys.
final class HotkeyListener {
    typealias ActionHandler = (PadAction) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ActionHandler?

    /// Whether the tap is created AND currently enabled. macOS will disable
    /// the tap if it ever takes too long to process an event; if we only
    /// checked `eventTap != nil` we'd happily report "listening" while
    /// keystrokes silently dropped on the floor — which is exactly the
    /// "doesn't work for a couple of minutes" symptom.
    var isListening: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func start(handler: @escaping ActionHandler) {
        self.handler = handler

        // Listen for keyDown plus the two flavours of "system disabled
        // your tap" so we can re-enable instantly instead of waiting for
        // a periodic safety check to notice.
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<HotkeyListener>.fromOpaque(userInfo).takeUnretainedValue()
                return listener.handleEvent(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            print("[sudo] ERROR: Failed to create event tap.")
            print("[sudo] Grant Accessibility permission in System Settings → Privacy & Security → Accessibility")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[sudo] Hotkey listener active — waiting for input")
    }

    /// Temporarily disable the event tap so synthesized CGEvents aren't re-intercepted.
    func suspend() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    /// Re-enable the event tap after synthesized events have been posted.
    func resume() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Defensive: the engine's permission timer calls this every few
    /// seconds. If macOS disabled the tap (and somehow we missed the
    /// event in the callback), re-enable it.
    func ensureEnabled() {
        guard let tap = eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[sudo] Re-enabled event tap (was disabled)")
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        handler = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS killed the tap (timeout or user input flood). Re-enable
        // immediately so we don't silently drop keystrokes for the rest
        // of the session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[sudo] Event tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")) — re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check against configurable hotkey bindings
        let bindings = SudoSettings.shared.hotkeyBindings

        for action in PadAction.allCases {
            guard let binding = bindings[action.rawValue] else { continue }
            let bindingKeyCode = UInt16(binding["keyCode"] ?? 0)
            let requiredMods = binding["modifiers"] ?? 0

            if keyCode == bindingKeyCode && matchesModifiers(flags, required: requiredMods) {
                DebugLogger.shared.log("pad input: button \(action.buttonNumber) (\(action.displayName)) keyCode=\(keyCode) flags=\(flags.rawValue)")

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.handler?(action)
                }

                return nil  // consume the event
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Check if the event flags match the required modifier mask
    private func matchesModifiers(_ flags: CGEventFlags, required: Int) -> Bool {
        let reqFlags = CGEventFlags(rawValue: UInt64(required))

        // Check each required modifier is present
        if reqFlags.contains(.maskControl) && !flags.contains(.maskControl) { return false }
        if reqFlags.contains(.maskShift) && !flags.contains(.maskShift) { return false }
        if reqFlags.contains(.maskCommand) && !flags.contains(.maskCommand) { return false }
        if reqFlags.contains(.maskAlternate) && !flags.contains(.maskAlternate) { return false }

        // If no modifiers required, accept any
        if required == 0 { return true }

        return true
    }
}

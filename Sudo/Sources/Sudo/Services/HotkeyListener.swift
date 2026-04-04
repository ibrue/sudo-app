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

    /// Whether the event tap was created successfully
    var isListening: Bool { eventTap != nil }

    func start(handler: @escaping ActionHandler) {
        self.handler = handler

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, _, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<HotkeyListener>.fromOpaque(userInfo).takeUnretainedValue()
                return listener.handleEvent(event)
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

    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
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

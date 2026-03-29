import Cocoa
import Carbon

/// Listens for global hotkey events from the macro pad.
/// Uses CGEvent tap — the standard macOS approach for global hotkeys.
/// Hotkey combos are configurable via ButtonConfigStore (defaults to Ctrl+Shift+F13-F16).
final class HotkeyListener {
    typealias ActionHandler = (PadAction) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ActionHandler?
    private var configObserver: NSObjectProtocol?

    /// Maps (keyCode, normalizedModifiers) -> PadAction, built from ButtonConfigStore.
    private var keyMap: [UInt64: PadAction] = [:]

    private static func mapKey(keyCode: UInt16, modifiers: UInt32) -> UInt64 {
        return (UInt64(modifiers) << 16) | UInt64(keyCode)
    }

    private func buildKeyMap() {
        var map = [UInt64: PadAction]()
        let store = ButtonConfigStore.shared
        for action in PadAction.allCases {
            let config = store.hotkeyConfig(for: action)
            let key = Self.mapKey(keyCode: config.keyCode, modifiers: config.modifiers)
            map[key] = action
        }
        keyMap = map
    }

    func start(handler: @escaping ActionHandler) {
        self.handler = handler
        buildKeyMap()

        // Listen for hotkey config changes to rebuild the map.
        configObserver = NotificationCenter.default.addObserver(
            forName: ButtonConfigStore.hotkeyConfigsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildKeyMap()
        }

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

        print("[sudo] Hotkey listener active — waiting for macro pad input")
    }

    func stop() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
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

    /// Rebuilds the key map when hotkey configuration changes.
    /// The event tap itself does not need to be recreated — only the lookup table changes.
    func rebuildKeyMap() {
        buildKeyMap()
        print("[sudo] Hotkey map rebuilt with updated config")
    }

    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = HotkeyConfig.normalizedModifiers(from: event.flags)
        let key = Self.mapKey(keyCode: keyCode, modifiers: modifiers)

        guard let action = keyMap[key] else {
            return Unmanaged.passUnretained(event)
        }

        let config = ButtonConfigStore.shared.hotkeyConfig(for: action)
        print("[sudo] Received: \(action.displayName) (\(config.displayString))")

        DispatchQueue.main.async { [weak self] in
            self?.handler?(action)
        }

        return nil
    }
}

import Cocoa
import Carbon

/// Listens for global Ctrl+Shift+F13–F16 hotkey events from the macro pad.
/// Uses CGEvent tap — the standard macOS approach for global hotkeys.
final class HotkeyListener {
    typealias ActionHandler = (PadAction) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ActionHandler?

    private static let keyMap: [UInt16: PadAction] = {
        var map = [UInt16: PadAction]()
        for action in PadAction.allCases {
            map[action.keyCode] = action
        }
        return map
    }()

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

        print("[sudo] Hotkey listener active — waiting for macro pad input")
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

        guard flags.contains(.maskControl),
              flags.contains(.maskShift),
              let action = Self.keyMap[keyCode] else {
            return Unmanaged.passUnretained(event)
        }

        print("[sudo] Received: \(action.displayName) (F\(action.fKeyNumber))")

        DispatchQueue.main.async { [weak self] in
            self?.handler?(action)
        }

        return nil
    }
}

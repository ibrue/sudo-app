import Foundation
import IOKit
import IOKit.usb
import IOKit.hid
import Combine

/// Monitors USB connections for the Sudo Pad device (VID: 0x5D00, PID: 0x5D01).
/// Publishes `isDeviceConnected` so the app can react to attach/detach events.
final class USBDeviceMonitor: ObservableObject {

    static let vendorID: Int = 0x5D00
    static let productID: Int = 0x5D01

    @Published private(set) var isDeviceConnected: Bool = false

    private var hidManager: IOHIDManager?
    private let monitorQueue = DispatchQueue(label: "sudo.usb.monitor", qos: .utility)

    /// Callbacks for connect/disconnect events.
    var onDeviceConnected: (() -> Void)?
    var onDeviceDisconnected: (() -> Void)?

    init() {
        setupHIDManager()
    }

    deinit {
        tearDown()
    }

    // MARK: - Setup

    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            print("[sudo] USB: Failed to create HID manager")
            return
        }

        // Match only our specific device
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        // Register callbacks
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let ctx = context else { return }
            let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.deviceAttached(device)
        }, selfPtr)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let ctx = context else { return }
            let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.deviceRemoved(device)
        }, selfPtr)

        // Schedule on the monitor queue's run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[sudo] USB: Failed to open HID manager (error: \(result))")
        } else {
            print("[sudo] USB: HID manager started, watching for VID=0x5D00 PID=0x5D01")
        }

        // Check if already connected
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty {
            print("[sudo] USB: Device already connected at startup")
            DispatchQueue.main.async {
                self.isDeviceConnected = true
                self.onDeviceConnected?()
            }
        }
    }

    // MARK: - Callbacks

    private func deviceAttached(_ device: IOHIDDevice) {
        print("[sudo] USB: Sudo Pad connected")
        DispatchQueue.main.async {
            self.isDeviceConnected = true
            self.onDeviceConnected?()
        }
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        print("[sudo] USB: Sudo Pad disconnected")
        DispatchQueue.main.async {
            self.isDeviceConnected = false
            self.onDeviceDisconnected?()
        }
    }

    // MARK: - Cleanup

    func tearDown() {
        guard let manager = hidManager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
        print("[sudo] USB: HID manager stopped")
    }
}

import Foundation
import IOKit
import IOKit.hid

/// Detects the sudo macropad and writes its firmware/config.
///
/// The pad runs CircuitPython. The flash flow has two paths:
///
/// 1. **`CIRCUITPY` is mounted** — the device is in flash mode. We write
///    the bundled `boot.py`, `code.py`, `sudo_leds.py`, and generated
///    `config.json` directly to the volume, then ask the user to replug.
///
/// 2. **`RPI-RP2` is mounted** — the device is in BOOTSEL (blank board, or
///    user just held the BOOTSEL switch). We flash the CircuitPython UF2
///    onto it, wait for it to reboot and re-enumerate as `CIRCUITPY`, then
///    fall through to path 1.
///
/// 3. **Neither is mounted** — HID detection may still report a running pad
///    because production `boot.py` hides the mass-storage drive. To flash,
///    the user re-plugs while holding button 1.
///
/// The CircuitPython UF2 is bundled for offline first flash. If a development
/// build omits it, the app falls back to the existing download/cache path.
final class FirmwareFlasher: ObservableObject {
    static let shared = FirmwareFlasher()

    enum FlashState: Equatable {
        case idle
        case noDevice
        case running
        case detectingDevice
        case flashMode(circuitpyPath: String)        // CIRCUITPY visible, ready to write firmware/config
        case bootloader(rpiPath: String)             // RPI-RP2 visible, needs CP UF2 first
        case flashing
        case success(message: String)
        case failed(message: String)
    }

    /// Coarse lifecycle phase used by progress UIs.
    enum FlashStep: Int {
        case detect = 0
        case installCircuitPython = 1
        case waitForCircuitPy = 2
        case writeFirmware = 3
        case writeConfig = 4
        case verify = 5
    }

    @Published var state: FlashState = .idle
    @Published var phase: String = ""
    @Published var progress: Double = 0
    @Published var step: FlashStep = .detect

    /// True when an Adafruit USB HID device is currently attached. Set
    /// by an IOKit matching subscription, so it tracks plug/unplug
    /// without needing the CIRCUITPY mass-storage volume — which boot.py
    /// hides in normal use, leaving `state == .idle` even though the
    /// pad is fully functional. Used to drive the device label so the
    /// popover shows "connected" instead of a misleading "idle" once
    /// the pad is plugged in.
    @Published var hidConnected: Bool = false

    /// Fired on the main queue whenever IOKit reports an Adafruit-VID
    /// HID device match. SudoEngine subscribes to this to short-circuit
    /// the 3-second permission-timer wait — the moment the pad
    /// enumerates we want to re-check the event tap.
    var onPadDetected: (() -> Void)?

    private var hidWatcher: IOHIDManager?
    private let assetProvider: FirmwareAssetProviding
    private let volumesPath: String

    /// Pinned CircuitPython release for the Raspberry Pi Pico (RP2040). We
    /// don't track latest because Adafruit releases occasionally rename
    /// modules; pinning means the `code.py` we ship is always known-good.
    static let circuitPythonURL = URL(string:
        "https://downloads.circuitpython.org/bin/raspberry_pi_pico/en_US/adafruit-circuitpython-raspberry_pi_pico-en_US-9.2.1.uf2"
    )!
    static let circuitPythonVersion = "9.2.1"

    private let unmountTimeoutSeconds: Double = 30
    private let pollIntervalSeconds: Double = 0.25

    init(
        assetProvider: FirmwareAssetProviding = DefaultFirmwareAssetProvider(),
        volumesPath: String = "/Volumes"
    ) {
        self.assetProvider = assetProvider
        self.volumesPath = volumesPath
    }

    // MARK: - Detection

    /// Look for the device. Tries CIRCUITPY first (no BOOTSEL needed), then
    /// RPI-RP2. Falls back to asking the user.
    func detectDevice() {
        DispatchQueue.main.async {
            self.state = .detectingDevice
            self.phase = "looking for sudo macropad…"
            self.progress = 0
            self.step = .detect
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let cp = self.findCircuitPyVolume() {
                DispatchQueue.main.async {
                    self.state = .flashMode(circuitpyPath: cp)
                    self.phase = "CIRCUITPY is mounted — ready to flash"
                }
                return
            }

            if let rpi = self.findBootloaderVolume() {
                DispatchQueue.main.async {
                    self.state = .bootloader(rpiPath: rpi)
                    self.phase = "device in BOOTSEL — ready to install CircuitPython"
                }
                return
            }

            DispatchQueue.main.async {
                self.state = self.hidConnected ? .running : .noDevice
                self.phase = self.hidConnected
                    ? "pad connected and running — hold button 1 while replugging to flash"
                    : "no device — plug in the macropad (hold BOOTSEL on first install)"
            }
        }
    }

    /// Backwards-compatible alias for the previous bootloader-only API.
    func detectBootloader() { detectDevice() }

    /// Like `detectDevice` but silent — no phase / progress churn. Called on
    /// app launch and on every USB mount/unmount so `state` always reflects
    /// what's actually plugged in. Skips the update if we're mid-flash so we
    /// don't clobber an active operation.
    func refreshDeviceState() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let cp = self.findCircuitPyVolume()
            let rpi = self.findBootloaderVolume()
            DispatchQueue.main.async {
                switch self.state {
                case .flashing, .detectingDevice, .success(_), .failed(_):
                    return
                default:
                    break
                }
                if let cp = cp {
                    self.state = .flashMode(circuitpyPath: cp)
                } else if let rpi = rpi {
                    self.state = .bootloader(rpiPath: rpi)
                } else if self.hidConnected {
                    self.state = .running
                } else {
                    self.state = .noDevice
                }
            }
        }
    }

    // MARK: - Public flash entry points

    /// Always-correct one-button flash. Picks the right path based on
    /// current device state.
    func flashFirmwareAndConfig(settings: SudoSettings = .shared) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runFlash(settings: settings)
        }
    }

    /// Legacy alias; same behaviour as flashFirmwareAndConfig now.
    func flashCurrentConfig(settings: SudoSettings = .shared) {
        flashFirmwareAndConfig(settings: settings)
    }

    func reset() {
        DispatchQueue.main.async {
            self.state = .idle
            self.phase = ""
            self.progress = 0
            self.step = .detect
        }
    }

    // MARK: - HID hot-plug detection
    //
    // Subscribes to IOKit for any USB device with the Adafruit vendor
    // ID (0x239A — covers every CircuitPython-based board, which on a
    // user's Mac is the sudo pad). When one shows up or disappears we
    // flip `hidConnected`; the device label reads that to show
    // "connected (running)" while the CIRCUITPY drive is hidden.
    //
    // Why we don't piggyback on `HotkeyListener`'s existing watcher:
    // that one matches *any* keyboard so it can rebuild the event tap
    // when the user adds a new keyboard of any kind. We need a stricter
    // filter for "is the sudo pad here", so it lives separately.

    private static let adafruitVendorID: Int = 0x239A

    func startHIDDetection() {
        guard hidWatcher == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: Self.adafruitVendorID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            guard let ctx = ctx else { return }
            let me = Unmanaged<FirmwareFlasher>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                me.hidConnected = true
                if case .idle = me.state {
                    me.state = .running
                } else if case .noDevice = me.state {
                    me.state = .running
                }
                me.onPadDetected?()
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            guard let ctx = ctx else { return }
            let me = Unmanaged<FirmwareFlasher>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.refreshHIDState() }
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[sudo] FirmwareFlasher.startHIDDetection: IOHIDManagerOpen returned \(result)")
        }
        // The matching callback fires synchronously for any already-
        // attached devices, so `hidConnected` is correct after Open
        // returns. No initial scan needed.
        self.hidWatcher = manager
    }

    /// Re-walks the matched device set after a removal to decide whether
    /// any sudo-pad-shaped device is still attached. The removal callback
    /// fires for the device that left; we have to poll the manager to
    /// know whether anything matching the same filter remains.
    private func refreshHIDState() {
        guard let manager = hidWatcher else { return }
        let attached = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        hidConnected = !attached.isEmpty
        if hidConnected {
            if case .idle = state { state = .running }
            if case .noDevice = state { state = .running }
        } else if case .running = state {
            state = .noDevice
        }
    }

    // MARK: - Implementation

    private func runFlash(settings: SudoSettings) {
        if isFlashing {
            updatePhase("flash already in progress…")
            return
        }

        do {
            _ = try assetProvider.padFirmwareFiles()
            _ = try SudoConfigJSON.generate(from: settings)
        } catch {
            setError("preflight failed: \(error.localizedDescription)")
            return
        }

        // Re-detect each time so we don't act on stale state.
        if let cp = findCircuitPyVolume() {
            writeConfigToCircuitPy(path: cp, settings: settings)
            return
        }
        if let rpi = findBootloaderVolume() {
            installCircuitPythonThenConfig(rpiPath: rpi, settings: settings)
            return
        }
        setError("no device — plug in the macropad with BOOTSEL held (first time only)")
    }

    private var isFlashing: Bool {
        DispatchQueue.main.sync {
            if case .flashing = state { return true }
            return false
        }
    }

    /// Path 1: CIRCUITPY is mounted, write boot.py + code.py + sudo_leds.py + config.json.
    ///
    /// boot.py is what makes the firmware hot-pluggable: it hides
    /// CIRCUITPY in normal use (no more "eject before unplug" warning),
    /// only re-exposes the drive when the user holds button 1 while
    /// plugging in. Pure HID otherwise.
    private func writeConfigToCircuitPy(path: String, settings: SudoSettings) {
        beginFlashing(label: "writing firmware…", at: .writeFirmware)
        do {
            let volume = try preflightCircuitPyVolume(path)
            let firmware = try assetProvider.padFirmwareFiles()
            let metaDst = volume.appendingPathComponent(".metadata_never_index")
            let bootDst = volume.appendingPathComponent("boot.py")
            let codeDst = volume.appendingPathComponent("code.py")
            let ledsDst = volume.appendingPathComponent("sudo_leds.py")
            let configDst = volume.appendingPathComponent("config.json")
            let configData = try SudoConfigJSON.generate(from: settings)

            // Spotlight indexing CIRCUITPY was the culprit behind the
            // "pad takes minutes to connect" reports: macOS would
            // write `.Spotlight-V100/`, `.fseventsd/`, `.Trashes/`
            // metadata, every write would trigger CircuitPython's
            // auto-reload, and the pad would ping-pong through boot.py
            // for 1–2 minutes before settling. Dropping a
            // `.metadata_never_index` file (zero-byte, recognised by
            // Spotlight) tells macOS to skip this volume entirely.
            // Write it FIRST so it's in place before macOS has a
            // chance to start scanning the volume metadata we add.
            updateProgress(0.05, phase: "tagging volume to skip Spotlight…")
            try Data().write(to: metaDst, options: .atomic)

            updateProgress(0.18, phase: "writing boot.py…")
            try copyOverwriting(src: firmware.bootPy, dst: bootDst)
            updateProgress(0.38, phase: "writing code.py…")
            try copyOverwriting(src: firmware.codePy, dst: codeDst)
            updateProgress(0.58, phase: "writing sudo_leds.py…")
            try copyOverwriting(src: firmware.ledsPy, dst: ledsDst)

            DispatchQueue.main.async { self.step = .writeConfig }
            updateProgress(0.78, phase: "writing config.json (\(settings.appMode.rawValue) mode)…")
            try writeOverwriting(data: configData, to: configDst)

            DispatchQueue.main.async { self.step = .verify }
            updateProgress(0.92, phase: "verifying files…")
            try verifyCircuitPyWrite(volume: volume, expectedFiles: ["boot.py", "code.py", "sudo_leds.py", "config.json"])

            updateProgress(0.97, phase: "settling…")
            Thread.sleep(forTimeInterval: 0.3)

            finishSuccess(label: "flashed — unplug + replug normally to start (hold button 1 to re-flash)")
        } catch {
            setError("config write failed: \(error.localizedDescription)")
        }
    }

    /// Path 2: RPI-RP2 is mounted. Flash CircuitPython UF2 to it, wait for
    /// CIRCUITPY to enumerate, then write config.
    private func installCircuitPythonThenConfig(rpiPath: String, settings: SudoSettings) {
        beginFlashing(label: "preparing CircuitPython…", at: .installCircuitPython)
        do {
            _ = try preflightBootloaderVolume(rpiPath)
            let cpURL = try locateOrDownloadCircuitPython()
            updatePhase("flashing CircuitPython \(Self.circuitPythonVersion) to RPI-RP2…")
            let cpDst = URL(fileURLWithPath: rpiPath).appendingPathComponent("circuitpython.uf2")
            try copyToBootloader(src: cpURL, dst: cpDst, label: "writing CircuitPython")

            DispatchQueue.main.async { self.step = .waitForCircuitPy }
            updatePhase("waiting for CIRCUITPY to mount…")
            guard let cpPath = waitForCircuitPyMount(timeout: 20) else {
                throw NSError(domain: "FirmwareFlasher", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "CIRCUITPY didn't mount within 20s — try unplugging and replugging"
                ])
            }
            // Recurse into the config-write path.
            writeConfigToCircuitPy(path: cpPath, settings: settings)
        } catch {
            setError("install failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CircuitPython UF2 sourcing

    private func locateOrDownloadCircuitPython() throws -> URL {
        if let bundled = assetProvider.circuitPythonUF2(version: Self.circuitPythonVersion) {
            return bundled
        }
        // Bundled (most reliable, but ships ~1 MB extra in .app)
        if let bundleURL = Bundle.main.url(forResource: "circuitpython-pico", withExtension: "uf2") {
            return bundleURL
        }
        // Cached locally
        let cache = circuitPythonCacheURL
        if FileManager.default.fileExists(atPath: cache.path) {
            return cache
        }
        // Download from Adafruit
        return try downloadCircuitPython(to: cache)
    }

    private var circuitPythonCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sudo/Firmware/circuitpython-pico-\(Self.circuitPythonVersion).uf2")
    }

    private func downloadCircuitPython(to dest: URL) throws -> URL {
        updateProgress(0, phase: "downloading CircuitPython \(Self.circuitPythonVersion)…")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<URL, Error>!

        let delegate = FirmwareDownloadDelegate { [weak self] received, expected in
            guard let self = self, expected > 0 else { return }
            let p = min(Double(received) / Double(expected), 1.0)
            self.updateProgress(p, phase: "downloading CircuitPython… \(Int(p * 100))%")
        }
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: Self.circuitPythonURL) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error = error { result = .failure(error); return }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(NSError(domain: "FirmwareFlasher", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "CircuitPython download HTTP \(http.statusCode)"
                ]))
                return
            }
            guard let tempURL = tempURL else {
                result = .failure(NSError(domain: "FirmwareFlasher", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "no file downloaded"
                ]))
                return
            }
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                result = .success(dest)
            } catch {
                result = .failure(error)
            }
        }
        task.resume()
        semaphore.wait()
        session.invalidateAndCancel()

        return try result.get()
    }

    // MARK: - Preflight / verification

    private func preflightCircuitPyVolume(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "FirmwareFlasher", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "CIRCUITPY is no longer mounted"
            ])
        }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("boot_out.txt").path) else {
            throw NSError(domain: "FirmwareFlasher", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "CIRCUITPY marker boot_out.txt was not found"
            ])
        }
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            throw NSError(domain: "FirmwareFlasher", code: 12, userInfo: [
                NSLocalizedDescriptionKey: "CIRCUITPY is not writable"
            ])
        }
        return url
    }

    private func preflightBootloaderVolume(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "FirmwareFlasher", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "RPI-RP2 is no longer mounted"
            ])
        }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("INFO_UF2.TXT").path) else {
            throw NSError(domain: "FirmwareFlasher", code: 21, userInfo: [
                NSLocalizedDescriptionKey: "RPI-RP2 marker INFO_UF2.TXT was not found"
            ])
        }
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            throw NSError(domain: "FirmwareFlasher", code: 22, userInfo: [
                NSLocalizedDescriptionKey: "RPI-RP2 is not writable"
            ])
        }
        return url
    }

    private func verifyCircuitPyWrite(volume: URL, expectedFiles: [String]) throws {
        for name in expectedFiles {
            let url = volume.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: "FirmwareFlasher", code: 30, userInfo: [
                    NSLocalizedDescriptionKey: "\(name) was not written"
                ])
            }
            guard fileSize(at: url) > 0 else {
                throw NSError(domain: "FirmwareFlasher", code: 31, userInfo: [
                    NSLocalizedDescriptionKey: "\(name) was written but is empty"
                ])
            }
        }
    }

    // MARK: - Copy helpers

    /// Spawn `cp`, then poll for the bootloader volume to unmount. The
    /// RP2040 bootloader unmounts after it processes a UF2 — that's our
    /// completion signal. `cp` itself usually hangs on close() until the
    /// volume reappears or we kill it.
    func copyToBootloader(src: URL, dst: URL, label: String) throws {
        updatePhase("\(label) — \(formatBytes(fileSize(at: src)))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = [src.path, dst.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let start = Date()
        var lastSeenMounted = true
        while true {
            let mounted = findBootloaderVolume() != nil
            let elapsed = Date().timeIntervalSince(start)
            // Model progress as elapsed/expected window during the write.
            let modelled = min(elapsed / 4.0, 0.95)
            updateProgress(modelled, phase: "\(label)… \(Int(modelled * 100))%")

            if !mounted && lastSeenMounted {
                Thread.sleep(forTimeInterval: 0.4)
                process.terminate()
                updateProgress(1.0, phase: "device rebooting")
                return
            }
            lastSeenMounted = mounted

            if elapsed > unmountTimeoutSeconds {
                process.terminate()
                throw NSError(domain: "FirmwareFlasher", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "device didn't unmount after \(Int(unmountTimeoutSeconds)) s — try unplugging and re-entering BOOTSEL"
                ])
            }
            Thread.sleep(forTimeInterval: pollIntervalSeconds)
        }
    }

    private func copyOverwriting(src: URL, dst: URL) throws {
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
    }

    private func writeOverwriting(data: Data, to dst: URL) throws {
        try data.write(to: dst, options: [.atomic])
    }

    // MARK: - Volume discovery

    private func findBootloaderVolume() -> String? {
        findVolume(named: "RPI-RP2", marker: "INFO_UF2.TXT")
    }

    private func findCircuitPyVolume() -> String? {
        findVolume(named: "CIRCUITPY", marker: "boot_out.txt")
    }

    private func findVolume(named name: String, marker: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: volumesPath) else {
            return nil
        }
        for volume in contents where volume == name {
            let path = "\(volumesPath)/\(volume)"
            let markerPath = "\(path)/\(marker)"
            if FileManager.default.fileExists(atPath: markerPath) {
                return path
            }
        }
        return nil
    }

    private func waitForCircuitPyMount(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let path = findCircuitPyVolume() {
                return path
            }
            // Also model progress while we wait
            let elapsed = timeout - deadline.timeIntervalSinceNow
            updateProgress(min(elapsed / timeout, 0.95),
                           phase: "waiting for CIRCUITPY to mount…")
            Thread.sleep(forTimeInterval: pollIntervalSeconds)
        }
        return nil
    }

    // MARK: - State helpers

    private func beginFlashing(label: String, at step: FlashStep) {
        DispatchQueue.main.async {
            self.state = .flashing
            self.phase = label
            self.progress = 0
            self.step = step
        }
    }

    private func updatePhase(_ label: String) {
        DispatchQueue.main.async { self.phase = label }
    }

    private func updateProgress(_ value: Double, phase: String) {
        DispatchQueue.main.async {
            self.progress = value
            self.phase = phase
        }
    }

    private func finishSuccess(label: String) {
        DispatchQueue.main.async {
            self.state = .success(message: label)
            self.phase = label
            self.progress = 1.0
            self.step = .verify
            print("[sudo] \(label)")
        }
    }

    private func setError(_ message: String) {
        DispatchQueue.main.async {
            self.state = .failed(message: message)
            self.phase = message
            self.progress = 0
            print("[sudo] flash error: \(message)")
        }
    }

    // MARK: - Misc helpers

    private func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }
}

/// URLSession delegate that forwards download progress to a closure.
private final class FirmwareDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Int64, Int64) -> Void
    init(onProgress: @escaping (Int64, Int64) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

// MARK: - Connection-status label

import SwiftUI

extension FirmwareFlasher {
    struct ConnectionLabel {
        let label: String
        let colour: Color
    }

    var canStartFlash: Bool {
        switch state {
        case .flashMode, .bootloader:
            return true
        default:
            return false
        }
    }

    var firmwareSourceLabel: String {
        do {
            return try assetProvider.padFirmwareFiles().sourceDescription
        } catch {
            return "missing pad firmware: \(error.localizedDescription)"
        }
    }

    var circuitPythonSourceLabel: String {
        if let url = assetProvider.circuitPythonUF2(version: Self.circuitPythonVersion) {
            return url.path
        }
        if FileManager.default.fileExists(atPath: circuitPythonCacheURL.path) {
            return circuitPythonCacheURL.path
        }
        return "will download CircuitPython \(Self.circuitPythonVersion) if needed"
    }

    /// Human-readable status used by the settings device panel and the
    /// onboarding flow. Reads `state` so the same source of truth drives
    /// every "is the pad plugged in?" UI.
    var deviceConnectionLabel: ConnectionLabel {
        switch state {
        case .flashMode:
            return .init(label: "device: flash mode (CIRCUITPY mounted)", colour: SudoTheme.accent)
        case .bootloader:
            return .init(label: "device: in BOOTSEL — needs install", colour: Color(nsColor: .systemYellow))
        case .detectingDevice:
            return .init(label: "device: scanning…", colour: Color(nsColor: .systemYellow))
        case .flashing:
            return .init(label: "device: flashing", colour: SudoTheme.accent)
        case .success(_):
            return .init(label: "device: flashed — replug normally", colour: SudoTheme.accent)
        case .failed(let msg):
            return .init(label: "device: error — \(msg)", colour: Color(nsColor: .systemRed))
        case .running:
            return .init(label: "device: connected (running)",
                         colour: SudoTheme.accent)
        case .idle, .noDevice:
            return .init(label: "device: not detected (hold button 1 + replug to flash)",
                         colour: Color(nsColor: .separatorColor))
        }
    }
}

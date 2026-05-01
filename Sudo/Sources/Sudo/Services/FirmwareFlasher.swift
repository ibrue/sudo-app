import Foundation

/// Detects the sudo macropad and writes its firmware/config.
///
/// The pad runs CircuitPython. The flash flow has two paths:
///
/// 1. **`CIRCUITPY` is mounted** — the device is already running our firmware.
///    We just write `code.py` and `config.json` directly to the volume.
///    CircuitPython auto-reloads on save, so changes are live in <1 s. No
///    BOOTSEL, no UF2, no reboot. Most common path after the very first
///    flash.
///
/// 2. **`RPI-RP2` is mounted** — the device is in BOOTSEL (blank board, or
///    user just held the BOOTSEL switch). We flash the CircuitPython UF2
///    onto it, wait for it to reboot and re-enumerate as `CIRCUITPY`, then
///    fall through to path 1.
///
/// 3. **Neither is mounted** — we ask the user to plug in the pad while
///    holding BOOTSEL.
///
/// The CircuitPython UF2 is downloaded once from the Adafruit CDN and cached
/// in `~/Library/Application Support/Sudo/Firmware/` — same place the old C
/// firmware path used.
final class FirmwareFlasher: ObservableObject {
    static let shared = FirmwareFlasher()

    enum FlashState: Equatable {
        case idle
        case detectingDevice
        case readyForConfig(circuitpyPath: String)   // device is running CP, just write config
        case readyForFirmware(rpiPath: String)       // device is in BOOTSEL, needs CP UF2 first
        case flashing
        case success
        case error(message: String)
    }

    /// Coarse lifecycle phase used by the UI's 3-step indicator.
    /// `.reboot` covers BOOTSEL detection + UF2 copy. `.write` is the
    /// `code.py` / `config.json` write to CIRCUITPY. `.verify` is the brief
    /// settle period after the write before we report success.
    enum FlashStep: Int { case reboot = 0, write = 1, verify = 2 }

    @Published var state: FlashState = .idle
    @Published var phase: String = ""
    @Published var progress: Double = 0
    @Published var step: FlashStep = .reboot

    /// Pinned CircuitPython release for the Raspberry Pi Pico (RP2040). We
    /// don't track latest because Adafruit releases occasionally rename
    /// modules; pinning means the `code.py` we ship is always known-good.
    static let circuitPythonURL = URL(string:
        "https://downloads.circuitpython.org/bin/raspberry_pi_pico/en_US/adafruit-circuitpython-raspberry_pi_pico-en_US-9.2.1.uf2"
    )!
    static let circuitPythonVersion = "9.2.1"

    private let unmountTimeoutSeconds: Double = 30
    private let pollIntervalSeconds: Double = 0.25

    // MARK: - Detection

    /// Look for the device. Tries CIRCUITPY first (no BOOTSEL needed), then
    /// RPI-RP2. Falls back to asking the user.
    func detectDevice() {
        DispatchQueue.main.async {
            self.state = .detectingDevice
            self.phase = "looking for sudo macropad…"
            self.progress = 0
            self.step = .reboot
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let cp = self.findCircuitPyVolume() {
                DispatchQueue.main.async {
                    self.state = .readyForConfig(circuitpyPath: cp)
                    self.phase = "device running CircuitPython — ready for config"
                }
                return
            }

            if let rpi = self.findBootloaderVolume() {
                DispatchQueue.main.async {
                    self.state = .readyForFirmware(rpiPath: rpi)
                    self.phase = "device in BOOTSEL — ready to install CircuitPython"
                }
                return
            }

            DispatchQueue.main.async {
                self.state = .idle
                self.phase = "no device — plug in the macropad (hold BOOTSEL on first install)"
            }
        }
    }

    /// Backwards-compatible alias for the previous bootloader-only API.
    func detectBootloader() { detectDevice() }

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
            self.step = .reboot
        }
    }

    // MARK: - Implementation

    private func runFlash(settings: SudoSettings) {
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

    /// Path 1: CIRCUITPY is mounted, just write code.py + config.json.
    private func writeConfigToCircuitPy(path: String, settings: SudoSettings) {
        beginFlashing(label: "writing code.py and config.json…", at: .write)
        do {
            let codeSrc = try locateCodePy()
            let codeDst = URL(fileURLWithPath: path).appendingPathComponent("code.py")
            let configDst = URL(fileURLWithPath: path).appendingPathComponent("config.json")
            let configData = try SudoConfigJSON.generate(from: settings)

            // Copy code.py first — this is the larger / less-changing file.
            updateProgress(0.1, phase: "copying code.py…")
            try copyOverwriting(src: codeSrc, dst: codeDst)
            updateProgress(0.6, phase: "writing config.json (\(settings.appMode.rawValue) mode)…")
            try writeOverwriting(data: configData, to: configDst)

            DispatchQueue.main.async { self.step = .verify }
            updateProgress(0.9, phase: "waiting for CircuitPython auto-reload…")
            // CircuitPython watches for filesystem changes and reloads after
            // ~250 ms of stability. Give it a beat.
            Thread.sleep(forTimeInterval: 0.6)

            finishSuccess(label: "config live (\(settings.appMode.rawValue) mode)")
        } catch {
            setError("config write failed: \(error.localizedDescription)")
        }
    }

    /// Path 2: RPI-RP2 is mounted. Flash CircuitPython UF2 to it, wait for
    /// CIRCUITPY to enumerate, then write config.
    private func installCircuitPythonThenConfig(rpiPath: String, settings: SudoSettings) {
        beginFlashing(label: "preparing CircuitPython…", at: .reboot)
        do {
            let cpURL = try locateOrDownloadCircuitPython()
            updatePhase("flashing CircuitPython \(Self.circuitPythonVersion) to RPI-RP2…")
            let cpDst = URL(fileURLWithPath: rpiPath).appendingPathComponent("circuitpython.uf2")
            try copyToBootloader(src: cpURL, dst: cpDst, label: "writing CircuitPython")

            DispatchQueue.main.async { self.step = .write }
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

    private func locateCodePy() throws -> URL {
        if let bundleURL = Bundle.main.url(forResource: "code", withExtension: "py") {
            return bundleURL
        }
        // Dev fallback: sibling sudo-supply checkout
        let supplyPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("sudo-supply/hardware/firmware/code.py")
        if FileManager.default.fileExists(atPath: supplyPath.path) {
            return supplyPath
        }
        throw NSError(domain: "FirmwareFlasher", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "code.py not bundled — rebuild with ./build.sh from a fresh checkout"
        ])
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
        let volumesPath = "/Volumes"
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
            self.state = .success
            self.phase = label
            self.progress = 1.0
            self.step = .verify
            print("[sudo] \(label)")
        }
    }

    private func setError(_ message: String) {
        DispatchQueue.main.async {
            self.state = .error(message: message)
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

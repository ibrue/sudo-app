import Foundation

/// Detects RP2040 in bootloader mode and writes UF2s to it.
///
/// Two flavors:
///
/// - `flashFirmwareAndConfig()` — the always-works button. Reads the bundled
///   base firmware UF2, splices the user's current button config in as a
///   final block, writes the combined UF2 to RPI-RP2. Works on a blank chip
///   because the firmware lives at 0x10000000; the config sector is just an
///   extra block at 0x101FF000.
///
/// - `flashCurrentConfig()` — config-only. Faster, but only valid when the
///   base firmware is already on the chip. Mostly useful in dev.
///
/// Both use a copy-and-watch strategy instead of `FileManager.copyItem`: the
/// RP2040 bootloader unmounts mid-sync after it processes a UF2, which makes
/// `copyItem` block forever. We spawn `cp`, then poll for the volume to
/// disappear; vanish == success.
final class FirmwareFlasher: ObservableObject {
    static let shared = FirmwareFlasher()

    enum FlashState: Equatable {
        case idle
        case detectingDevice
        case deviceFound(path: String)
        case flashing
        case success
        case error(message: String)
    }

    @Published var state: FlashState = .idle
    @Published var bootloaderDetected: Bool = false
    /// Human-readable description of the current step. e.g.
    /// "preparing firmware (12 KB)", "writing… 47%", "waiting for reboot".
    @Published var phase: String = ""
    /// 0.0 – 1.0. Progress through the current flash operation.
    @Published var progress: Double = 0

    /// Maximum seconds we wait for the bootloader volume to unmount after we
    /// finish writing. The bootloader normally unmounts within ~2 s.
    private let unmountTimeoutSeconds: Double = 30
    /// How often we poll the volume during write/wait.
    private let pollIntervalSeconds: Double = 0.25

    /// Known firmware profiles — kept for the legacy preset flash flow.
    struct FirmwareProfile: Identifiable {
        let id: String
        let name: String
        let description: String
        let buttons: [String]
    }

    static let profiles: [FirmwareProfile] = [
        FirmwareProfile(id: "default",   name: "default (AI agent)",
                        description: "ctrl+shift+F13-F16 — requires companion app",
                        buttons: ["ctrl+shift+F13", "ctrl+shift+F15", "ctrl+shift+F14", "ctrl+shift+F16"]),
        FirmwareProfile(id: "shortcuts", name: "system shortcuts",
                        description: "copy / paste / undo / screenshot — works without app",
                        buttons: ["cmd+C", "cmd+V", "cmd+Z", "cmd+shift+3"]),
        FirmwareProfile(id: "media",     name: "media controls",
                        description: "play / next / prev / like — works without app",
                        buttons: ["play/pause", "next track", "prev track", "media key"]),
        FirmwareProfile(id: "browsing",  name: "web browsing",
                        description: "back / forward / refresh / close tab — works without app",
                        buttons: ["cmd+[", "cmd+]", "cmd+R", "cmd+W"]),
        FirmwareProfile(id: "discord",   name: "discord soundboard",
                        description: "sound clips 1-4 — works without app",
                        buttons: ["ctrl+shift+1", "ctrl+shift+2", "ctrl+shift+3", "cmd+shift+D"]),
        FirmwareProfile(id: "custom",    name: "current config",
                        description: "flash your current button config — works without app",
                        buttons: ["button 1", "button 2", "button 3", "button 4"]),
    ]

    // MARK: - Detection

    /// Check if RP2040 is in bootloader mode (RPI-RP2 volume mounted).
    /// If the device isn't already in BOOTSEL, ask the running firmware to
    /// reboot into BOOTSEL via the CDC channel. The user only needs to hold
    /// the BOOTSEL switch on the very first flash — after that this path
    /// re-enters BOOTSEL automatically.
    func detectBootloader() {
        DispatchQueue.main.async {
            self.state = .detectingDevice
            self.phase = "scanning for RPI-RP2…"
            self.progress = 0
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Already mounted? Done.
            if let path = self.findBootloaderVolume() {
                DispatchQueue.main.async {
                    self.state = .deviceFound(path: path)
                    self.bootloaderDetected = true
                    self.phase = "ready to flash"
                }
                return
            }

            // Try the soft path: ask the firmware to jump to BOOTSEL.
            DispatchQueue.main.async {
                self.phase = "asking firmware to reboot into BOOTSEL…"
            }
            PadCommunicator.shared.sendState(.rebootBootsel)

            // Wait up to 8 s for RPI-RP2 to enumerate.
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if let path = self.findBootloaderVolume() {
                    DispatchQueue.main.async {
                        self.state = .deviceFound(path: path)
                        self.bootloaderDetected = true
                        self.phase = "ready to flash"
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.25)
            }

            DispatchQueue.main.async {
                self.state = .idle
                self.bootloaderDetected = false
                self.phase = "no device — hold BOOTSEL while plugging in (first flash only)"
            }
        }
    }

    // MARK: - Public flash entry points

    /// Always-works flash: writes base firmware + current config in one go.
    /// Works on a blank RP2040.
    func flashFirmwareAndConfig(settings: SudoSettings = .shared) {
        guard case .deviceFound(let path) = state else {
            setError("no device in bootloader mode — click `detect bootsel` first")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runFlashFirmwareAndConfig(devicePath: path, settings: settings)
        }
    }

    /// Config-only flash. Requires the base firmware to already be on the chip.
    func flashCurrentConfig(settings: SudoSettings = .shared) {
        guard case .deviceFound(let path) = state else {
            setError("no device in bootloader mode")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runFlashCurrentConfig(devicePath: path, settings: settings)
        }
    }

    /// Legacy: flash a pre-built profile UF2 by id.
    func flash(profile: FirmwareProfile) {
        guard case .deviceFound(let path) = state else {
            setError("no device in bootloader mode")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let uf2URL = self.findUF2(for: profile.id) else {
                self.setError("preset firmware not bundled — download from sudo.supply/download")
                return
            }
            self.beginFlashing(label: "preparing \(profile.name)…")
            do {
                let dst = URL(fileURLWithPath: path).appendingPathComponent(uf2URL.lastPathComponent)
                try self.copyToBootloader(src: uf2URL, dst: dst, label: "writing \(profile.name)")
                self.finishSuccess(label: "flashed \(profile.name) — device rebooting")
            } catch {
                self.setError("flash failed: \(error.localizedDescription)")
            }
        }
    }

    func reset() {
        DispatchQueue.main.async {
            self.state = .idle
            self.bootloaderDetected = false
            self.phase = ""
            self.progress = 0
        }
    }

    // MARK: - Implementations

    private func runFlashFirmwareAndConfig(devicePath: String, settings: SudoSettings) {
        beginFlashing(label: "preparing firmware…")
        do {
            // Look locally first; if that fails, transparently pull the rolling
            // firmware release from sudo-supply. Means users without the Pico
            // SDK installed can still flash a blank board on first run.
            let baseURL: URL
            if let local = SudoConfigUF2.locateBaseFirmware() {
                baseURL = local
            } else {
                baseURL = try downloadFirmware()
            }
            let firmwareData = try Data(contentsOf: baseURL)
            updatePhase("building combined UF2 (\(firmwareData.count / 512) firmware blocks + 1 config)")
            let combined = try SudoConfigUF2.combineWithFirmware(firmwareData: firmwareData, settings: settings)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sudo-firmware-\(Int(Date().timeIntervalSince1970)).uf2")
            try combined.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let dst = URL(fileURLWithPath: devicePath).appendingPathComponent("sudo-firmware.uf2")
            try copyToBootloader(src: tempURL, dst: dst, label: "writing firmware + config")
            finishSuccess(label: "flashed firmware + config (\(settings.appMode.rawValue) mode)")
        } catch {
            setError("flash failed: \(error.localizedDescription)")
        }
    }

    private func runFlashCurrentConfig(devicePath: String, settings: SudoSettings) {
        beginFlashing(label: "generating config UF2…")
        do {
            let tempURL = try SudoConfigUF2.writeTemp(from: settings)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            let dst = URL(fileURLWithPath: devicePath).appendingPathComponent("sudo-config.uf2")
            try copyToBootloader(src: tempURL, dst: dst, label: "writing config")
            finishSuccess(label: "flashed config (\(settings.appMode.rawValue) mode)")
        } catch {
            setError("config flash failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Copy helper (avoids copyItem hang)

    /// Spawn `cp`, then poll for the bootloader volume to unmount. The
    /// bootloader unmounts after it finishes processing the UF2 — we treat
    /// that as our completion signal. The `cp` process is a hedge: if it
    /// returns first we honour that, but it usually hangs on close() until
    /// the volume reappears or we kill it.
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

            // While volume is mounted, we model progress as the elapsed
            // fraction of the typical write window (~3 s). Capped at 95%
            // until we actually see the unmount.
            let modelled = min(elapsed / 3.0, 0.95)
            updateProgress(modelled, phase: "\(label)… \(Int(modelled * 100))%")

            if !mounted && lastSeenMounted {
                // Bootloader unmounted = success. Give the kernel a beat to
                // tear down before we report.
                Thread.sleep(forTimeInterval: 0.4)
                process.terminate()
                updateProgress(1.0, phase: "device rebooted")
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

    // MARK: - State helpers

    private func beginFlashing(label: String) {
        DispatchQueue.main.async {
            self.state = .flashing
            self.phase = label
            self.progress = 0
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
            self.bootloaderDetected = false
            self.phase = label
            self.progress = 1.0
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

    // MARK: - Auto-download firmware

    /// Where the rolling firmware release lives. `firmware-latest` is updated
    /// on every push to `hardware/firmware/**` in sudo-supply by the
    /// `Build firmware` GitHub Actions workflow.
    private static let firmwareReleaseAssetURL = URL(
        string: "https://github.com/ibrue/sudo-supply/releases/download/firmware-latest/sudo-firmware.uf2"
    )!

    /// Cache location for the downloaded UF2 — same path `locateBaseFirmware()`
    /// already searches, so subsequent flashes are local-only.
    private static var firmwareCacheURL: URL {
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sudo/Firmware")
        return supportDir.appendingPathComponent("sudo-firmware.uf2")
    }

    /// Synchronously download the rolling firmware UF2 from GitHub. Surfaces
    /// progress through the existing `progress` + `phase` publishers so the
    /// flash UI shows the download as a normal phase. Returns the cached URL.
    private func downloadFirmware() throws -> URL {
        updateProgress(0, phase: "downloading firmware from sudo-supply…")

        let dest = Self.firmwareCacheURL
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        let semaphore = DispatchSemaphore(value: 0)
        var downloadResult: Result<URL, Error>!

        let delegate = FirmwareDownloadDelegate { [weak self] received, expected in
            guard let self = self, expected > 0 else { return }
            let p = min(Double(received) / Double(expected), 1.0)
            self.updateProgress(p, phase: "downloading firmware… \(Int(p * 100))%")
        }

        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: Self.firmwareReleaseAssetURL) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error = error {
                downloadResult = .failure(error)
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                downloadResult = .failure(NSError(domain: "FirmwareFlasher", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "firmware download HTTP \(http.statusCode) — has CI built it yet? check sudo-supply Actions"
                ]))
                return
            }
            guard let tempURL = tempURL else {
                downloadResult = .failure(NSError(domain: "FirmwareFlasher", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "download produced no file"
                ]))
                return
            }
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                downloadResult = .success(dest)
            } catch {
                downloadResult = .failure(error)
            }
        }
        task.resume()
        semaphore.wait()
        session.invalidateAndCancel()

        switch downloadResult! {
        case .success(let url):
            updatePhase("firmware cached — preparing flash")
            return url
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Volume + filesystem helpers

    private func findBootloaderVolume() -> String? {
        let volumesPath = "/Volumes"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: volumesPath) else { return nil }
        for volume in contents where volume == "RPI-RP2" {
            let path = "\(volumesPath)/\(volume)"
            let infoPath = "\(path)/INFO_UF2.TXT"
            if FileManager.default.fileExists(atPath: infoPath) {
                return path
            }
        }
        return nil
    }

    private func findUF2(for profileID: String) -> URL? {
        if let bundlePath = Bundle.main.url(forResource: "sudo-\(profileID)", withExtension: "uf2") {
            return bundlePath
        }
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sudo/Firmware")
        let uf2Path = supportDir.appendingPathComponent("sudo-\(profileID).uf2")
        if FileManager.default.fileExists(atPath: uf2Path.path) {
            return uf2Path
        }
        return nil
    }

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

    // The completion handler on downloadTask handles the finished file —
    // we don't need anything in didFinishDownloadingTo.
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

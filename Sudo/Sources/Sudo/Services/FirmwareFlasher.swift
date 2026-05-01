import Foundation

/// Detects RP2040 in bootloader mode and flashes firmware for simple mode presets.
///
/// When the RP2040 is in BOOTSEL mode, it appears as a USB mass storage device
/// named "RPI-RP2". We copy a UF2 firmware file to it and the device auto-reboots.
///
/// Simple mode means all 4 buttons are keyCombo or mediaKey — no AI search needed.
/// The pad can work natively on any computer without the companion app.
final class FirmwareFlasher: ObservableObject {
    static let shared = FirmwareFlasher()

    enum FlashState: Equatable {
        case idle
        case detectingDevice
        case deviceFound(path: String)
        case flashing(progress: String)
        case success
        case error(message: String)
    }

    @Published var state: FlashState = .idle
    @Published var bootloaderDetected: Bool = false

    /// Known firmware profiles — each maps a preset to the key combos the firmware should send.
    struct FirmwareProfile: Identifiable {
        let id: String
        let name: String
        let description: String
        let buttons: [String]  // human-readable key descriptions for each button 1-4
    }

    /// Pre-defined firmware profiles for common presets
    static let profiles: [FirmwareProfile] = [
        FirmwareProfile(
            id: "default",
            name: "default (AI agent)",
            description: "ctrl+shift+F13-F16 — requires companion app",
            buttons: ["ctrl+shift+F13", "ctrl+shift+F15", "ctrl+shift+F14", "ctrl+shift+F16"]
        ),
        FirmwareProfile(
            id: "shortcuts",
            name: "system shortcuts",
            description: "copy / paste / undo / screenshot — works without app",
            buttons: ["cmd+C", "cmd+V", "cmd+Z", "cmd+shift+3"]
        ),
        FirmwareProfile(
            id: "media",
            name: "media controls",
            description: "play / next / prev / like — works without app",
            buttons: ["play/pause", "next track", "prev track", "media key"]
        ),
        FirmwareProfile(
            id: "browsing",
            name: "web browsing",
            description: "back / forward / refresh / close tab — works without app",
            buttons: ["cmd+[", "cmd+]", "cmd+R", "cmd+W"]
        ),
        FirmwareProfile(
            id: "discord",
            name: "discord soundboard",
            description: "sound clips 1-4 — works without app",
            buttons: ["ctrl+shift+1", "ctrl+shift+2", "ctrl+shift+3", "cmd+shift+D"]
        ),
        FirmwareProfile(
            id: "custom",
            name: "current config",
            description: "flash your current button config — works without app",
            buttons: ["button 1", "button 2", "button 3", "button 4"]
        ),
    ]

    /// Check if RP2040 is in bootloader mode (RPI-RP2 volume mounted)
    func detectBootloader() {
        state = .detectingDevice

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let bootloaderPath = self?.findBootloaderVolume()
            DispatchQueue.main.async {
                if let path = bootloaderPath {
                    self?.state = .deviceFound(path: path)
                    self?.bootloaderDetected = true
                } else {
                    self?.state = .idle
                    self?.bootloaderDetected = false
                }
            }
        }
    }

    /// Flash a firmware profile to the connected RP2040
    func flash(profile: FirmwareProfile) {
        guard case .deviceFound(let path) = state else {
            state = .error(message: "no device in bootloader mode")
            return
        }

        state = .flashing(progress: "preparing firmware...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Check if we have a pre-built UF2 for this profile
            let uf2URL = self?.findUF2(for: profile.id)

            if let uf2URL = uf2URL {
                DispatchQueue.main.async {
                    self?.state = .flashing(progress: "copying firmware to device...")
                }

                let destURL = URL(fileURLWithPath: path).appendingPathComponent(uf2URL.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: uf2URL, to: destURL)
                    // RP2040 auto-reboots after receiving UF2
                    Thread.sleep(forTimeInterval: 2.0)
                    DispatchQueue.main.async {
                        self?.state = .success
                        self?.bootloaderDetected = false
                        print("[sudo] Firmware flashed successfully: \(profile.name)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.state = .error(message: "copy failed: \(error.localizedDescription)")
                    }
                }
            } else {
                // No pre-built UF2 — direct user to download
                DispatchQueue.main.async {
                    self?.state = .error(message: "firmware not found — download from sudo.supply/download")
                }
            }
        }
    }

    /// Flash the user's current per-button config to the device as a generated UF2.
    ///
    /// Builds a config-only UF2 from `SudoSettings` and copies it to the RPI-RP2
    /// volume. The firmware reads this region on boot and applies the mappings.
    /// The device must already have the sudo base firmware installed.
    func flashCurrentConfig(settings: SudoSettings = .shared) {
        guard case .deviceFound(let path) = state else {
            state = .error(message: "no device in bootloader mode")
            return
        }

        state = .flashing(progress: "generating config UF2...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let url = try SudoConfigUF2.writeTemp(from: settings)

                DispatchQueue.main.async {
                    self?.state = .flashing(progress: "copying config to device...")
                }

                let destURL = URL(fileURLWithPath: path).appendingPathComponent("sudo-config.uf2")
                try FileManager.default.copyItem(at: url, to: destURL)
                Thread.sleep(forTimeInterval: 2.0)
                try? FileManager.default.removeItem(at: url)

                DispatchQueue.main.async {
                    self?.state = .success
                    self?.bootloaderDetected = false
                    print("[sudo] flashed current config (\(settings.appMode.rawValue))")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.state = .error(message: "config flash failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Reset state
    func reset() {
        state = .idle
        bootloaderDetected = false
    }

    // MARK: - Private

    private func findBootloaderVolume() -> String? {
        let volumesPath = "/Volumes"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: volumesPath) else { return nil }

        for volume in contents {
            // RP2040 bootloader mounts as "RPI-RP2"
            if volume == "RPI-RP2" {
                let path = "\(volumesPath)/\(volume)"
                // Verify it's a real RP2040 bootloader volume
                let infoPath = "\(path)/INFO_UF2.TXT"
                if FileManager.default.fileExists(atPath: infoPath) {
                    return path
                }
            }
        }
        return nil
    }

    private func findUF2(for profileID: String) -> URL? {
        // Check app bundle resources first
        if let bundlePath = Bundle.main.url(forResource: "sudo-\(profileID)", withExtension: "uf2") {
            return bundlePath
        }

        // Check ~/Library/Application Support/Sudo/Firmware/
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sudo/Firmware")
        let uf2Path = supportDir.appendingPathComponent("sudo-\(profileID).uf2")
        if FileManager.default.fileExists(atPath: uf2Path.path) {
            return uf2Path
        }

        return nil
    }
}

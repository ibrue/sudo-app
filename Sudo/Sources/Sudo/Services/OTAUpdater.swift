import Foundation
import Cocoa

/// Over-the-air updater that checks GitHub Releases for new versions.
///
/// Flow:
/// 1. On launch (+ periodic check), fetches latest release from GitHub API
/// 2. Compares version tag against current build version
/// 3. If newer, shows notification with changelog
/// 4. Downloads the .dmg, mounts it, copies the new .app, relaunches
///
/// Uses standard HTTPS — no custom update protocol, no code signing bypass.
final class OTAUpdater: ObservableObject {

    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var isUpdating: Bool = false
    @Published var updateProgress: Double = 0

    static let currentVersion = "1.0.0"

    private let repoOwner = "ibrue"
    private let repoName = "sudo-app"
    private let releasesURL: URL

    private var checkTimer: Timer?

    struct GitHubRelease: Codable {
        let tag_name: String
        let name: String?
        let body: String?
        let assets: [GitHubAsset]
        let prerelease: Bool
    }

    struct GitHubAsset: Codable {
        let name: String
        let browser_download_url: String
        let size: Int
    }

    init() {
        releasesURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    }

    /// Start periodic update checks (every 4 hours)
    func startPeriodicChecks() {
        checkForUpdates()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func stopPeriodicChecks() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Check GitHub Releases API for a newer version
    func checkForUpdates() {
        print("[sudo] Checking for updates...")

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Sudo/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("[sudo] Update check failed: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[sudo] Update check: no release found or API error")
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

                guard !release.prerelease else {
                    print("[sudo] Latest release is pre-release, skipping")
                    return
                }

                let remoteVersion = release.tag_name.replacingOccurrences(of: "v", with: "")

                if self.isNewer(remote: remoteVersion, current: Self.currentVersion) {
                    DispatchQueue.main.async {
                        self.latestVersion = remoteVersion
                        self.releaseNotes = release.body ?? "No release notes."
                        self.updateAvailable = true
                        print("[sudo] Update available: v\(remoteVersion)")
                    }
                } else {
                    print("[sudo] Up to date (v\(Self.currentVersion))")
                }
            } catch {
                print("[sudo] Failed to parse release: \(error)")
            }
        }.resume()
    }

    /// Download and install the update
    func installUpdate() {
        guard updateAvailable else { return }

        isUpdating = true
        updateProgress = 0

        // Fetch the release to get the DMG asset URL
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Sudo/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                DispatchQueue.main.async { self?.isUpdating = false }
                return
            }

            // Find the .dmg or .zip asset
            guard let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") || $0.name.hasSuffix(".zip") }),
                  let downloadURL = URL(string: asset.browser_download_url) else {
                print("[sudo] No downloadable asset found in release")
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }

            self.downloadAndInstall(url: downloadURL, assetName: asset.name)
        }.resume()
    }

    private func downloadAndInstall(url: URL, assetName: String) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sudo-update")
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let destination = tempDir.appendingPathComponent(assetName)

        print("[sudo] Downloading update from \(url)")

        let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, error in
            guard let self = self else { return }

            if let error = error {
                print("[sudo] Download failed: \(error)")
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }

            guard let localURL = localURL else {
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }

            do {
                try FileManager.default.moveItem(at: localURL, to: destination)
                DispatchQueue.main.async { self.updateProgress = 0.5 }

                if assetName.hasSuffix(".dmg") {
                    self.installFromDMG(at: destination)
                } else if assetName.hasSuffix(".zip") {
                    self.installFromZip(at: destination, in: tempDir)
                }
            } catch {
                print("[sudo] Failed to process download: \(error)")
                DispatchQueue.main.async { self.isUpdating = false }
            }
        }
        task.resume()
    }

    private func installFromDMG(at dmgPath: URL) {
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("sudo-mount")

        // Mount the DMG
        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountProcess.arguments = ["attach", dmgPath.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]

        do {
            try mountProcess.run()
            mountProcess.waitUntilExit()

            guard mountProcess.terminationStatus == 0 else {
                print("[sudo] Failed to mount DMG")
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }

            // Find the .app in the mounted DMG
            let contents = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                print("[sudo] No .app found in DMG")
                unmountDMG(at: mountPoint)
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }

            // Replace current app
            let currentAppPath = Bundle.main.bundleURL
            let backupPath = currentAppPath.deletingLastPathComponent().appendingPathComponent("Sudo.app.bak")

            try? FileManager.default.removeItem(at: backupPath)
            try FileManager.default.moveItem(at: currentAppPath, to: backupPath)
            try FileManager.default.copyItem(at: appBundle, to: currentAppPath)

            DispatchQueue.main.async { self.updateProgress = 0.9 }

            // Unmount
            unmountDMG(at: mountPoint)

            // Relaunch
            print("[sudo] Update installed — relaunching...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.relaunch()
            }

        } catch {
            print("[sudo] Install from DMG failed: \(error)")
            unmountDMG(at: mountPoint)
            DispatchQueue.main.async { self.isUpdating = false }
        }
    }

    private func installFromZip(at zipPath: URL, in tempDir: URL) {
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", zipPath.path, "-d", tempDir.path]

        do {
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                print("[sudo] No .app found in zip")
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }

            let currentAppPath = Bundle.main.bundleURL
            let backupPath = currentAppPath.deletingLastPathComponent().appendingPathComponent("Sudo.app.bak")

            try? FileManager.default.removeItem(at: backupPath)
            try FileManager.default.moveItem(at: currentAppPath, to: backupPath)
            try FileManager.default.copyItem(at: appBundle, to: currentAppPath)

            print("[sudo] Update installed — relaunching...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.relaunch()
            }

        } catch {
            print("[sudo] Install from zip failed: \(error)")
            DispatchQueue.main.async { self.isUpdating = false }
        }
    }

    private func unmountDMG(at mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    private func relaunch() {
        let appPath = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appPath]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// Semantic version comparison
    private func isNewer(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}

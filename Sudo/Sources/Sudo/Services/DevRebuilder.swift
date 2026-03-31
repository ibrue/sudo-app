import Cocoa

/// Pulls latest code from git, rebuilds, and relaunches the app.
/// One-click dev workflow from the menu bar.
final class DevRebuilder: ObservableObject {
    @Published var isRebuilding = false
    @Published var status = ""

    /// Path to the source repo (detected from the running app's bundle)
    private var repoPath: String {
        // If running from /Applications/Sudo.app, the source is ~/sudo-app
        // If running from dist/, walk up from the bundle
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("/dist/") {
            return (bundlePath as NSString).deletingLastPathComponent
                .replacingOccurrences(of: "/dist", with: "")
        }
        // Default to ~/sudo-app
        return NSHomeDirectory() + "/sudo-app"
    }

    func rebuild() {
        guard !isRebuilding else { return }
        isRebuilding = true
        status = "pulling..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let steps: [(String, [String])] = [
                ("pulling...", ["git", "pull", "origin", "main"]),
                ("building...", ["bash", "-c", "cd \(repoPath)/Sudo && swift build -c release"]),
                ("installing...", ["bash", "-c", """
                    rm -rf /Applications/Sudo.app && \
                    bash \(repoPath)/build.sh && \
                    cp -r \(repoPath)/dist/Sudo.app /Applications/Sudo.app
                    """]),
            ]

            for (label, args) in steps {
                DispatchQueue.main.async { self.status = label }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        print("[sudo] Rebuild failed at '\(label)': \(output)")
                        DispatchQueue.main.async {
                            self.status = "failed at \(label)"
                            self.isRebuilding = false
                        }
                        return
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.status = "error: \(error.localizedDescription)"
                        self.isRebuilding = false
                    }
                    return
                }
            }

            // Relaunch
            DispatchQueue.main.async {
                self.status = "relaunching..."
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let appPath = "/Applications/Sudo.app"
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = ["-n", appPath]
                    try? process.run()
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

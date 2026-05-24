import Cocoa

/// Pulls latest code from git, rebuilds, and relaunches the app.
/// Captures full build output for the terminal view.
final class DevRebuilder: ObservableObject {
    @Published var isRebuilding = false
    @Published var status = ""
    @Published var buildLog: [String] = []

    /// Path to the source repo
    private var repoPath: String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("/dist/") {
            return (bundlePath as NSString).deletingLastPathComponent
                .replacingOccurrences(of: "/dist", with: "")
        }
        return NSHomeDirectory() + "/sudo-app"
    }

    /// Run an arbitrary shell command and capture output
    func runCommand(_ command: String) {
        appendLog("$ \(command)")

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Stream output line by line
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                for line in lines {
                    self?.appendLog(line)
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                // Read any remaining data
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                    for line in text.components(separatedBy: "\n") where !line.isEmpty {
                        appendLog(line)
                    }
                }
                let code = process.terminationStatus
                appendLog(code == 0 ? "[exit 0]" : "[exit \(code) — failed]")
            } catch {
                appendLog("[error: \(error.localizedDescription)]")
            }
        }
    }

    func rebuild() {
        guard !isRebuilding else { return }
        isRebuilding = true
        buildLog = []
        status = "pulling..."

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let steps: [(String, String)] = [
                ("pulling...", "git fetch origin main && git reset --hard origin/main"),
                ("building...", "cd \(repoPath) && rm -rf Sudo/.build && ./build.sh"),
                ("installing...", "rm -rf /Applications/Sudo.app && cp -r \(repoPath)/dist/Sudo.app /Applications/Sudo.app && codesign --force --deep --sign - --identifier supply.sudo.app --requirements '=designated => identifier \"supply.sudo.app\"' /Applications/Sudo.app"),
            ]

            for (label, command) in steps {
                DispatchQueue.main.async {
                    self.status = label
                }
                appendLog("--- \(label) ---")
                appendLog("$ \(command)")

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]
                process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    for line in text.components(separatedBy: "\n") where !line.isEmpty {
                        self?.appendLog(line)
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                        for line in text.components(separatedBy: "\n") where !line.isEmpty {
                            appendLog(line)
                        }
                    }

                    if process.terminationStatus != 0 {
                        appendLog("[exit \(process.terminationStatus) — failed]")
                        DispatchQueue.main.async {
                            self.status = "failed at \(label)"
                            self.isRebuilding = false
                        }
                        return
                    }
                } catch {
                    appendLog("[error: \(error.localizedDescription)]")
                    DispatchQueue.main.async {
                        self.status = "error: \(error.localizedDescription)"
                        self.isRebuilding = false
                    }
                    return
                }
            }

            appendLog("--- relaunching... ---")
            DispatchQueue.main.async {
                self.status = "relaunching..."
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = ["-n", "/Applications/Sudo.app"]
                    try? process.run()
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func clearLog() {
        buildLog = []
    }

    private func appendLog(_ line: String) {
        DispatchQueue.main.async {
            self.buildLog.append(line)
            // Keep last 200 lines
            if self.buildLog.count > 200 {
                self.buildLog = Array(self.buildLog.suffix(200))
            }
        }
    }
}

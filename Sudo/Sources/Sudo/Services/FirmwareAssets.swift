import Foundation

struct PadFirmwareFiles: Equatable {
    let bootPy: URL
    let codePy: URL
    let ledsPy: URL
    let sourceDescription: String

    var required: [(name: String, url: URL)] {
        [
            ("boot.py", bootPy),
            ("code.py", codePy),
            ("sudo_leds.py", ledsPy),
        ]
    }
}

protocol FirmwareAssetProviding {
    func padFirmwareFiles() throws -> PadFirmwareFiles
    func circuitPythonUF2(version: String) -> URL?
}

enum FirmwareAssetError: LocalizedError, Equatable {
    case missingPadFirmware
    case missingFile(String)
    case emptyFile(String)

    var errorDescription: String? {
        switch self {
        case .missingPadFirmware:
            return "bundled pad firmware was not found"
        case .missingFile(let name):
            return "\(name) was not found"
        case .emptyFile(let name):
            return "\(name) is empty"
        }
    }
}

struct DefaultFirmwareAssetProvider: FirmwareAssetProviding {
    private let fileManager: FileManager
    private let bundle: Bundle
    private let currentDirectory: URL

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.currentDirectory = currentDirectory
    }

    func padFirmwareFiles() throws -> PadFirmwareFiles {
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Firmware/pad"),
            currentDirectory.appendingPathComponent("Sudo/Resources/Firmware/pad"),
            currentDirectory.appendingPathComponent("Resources/Firmware/pad"),
            currentDirectory.deletingLastPathComponent().appendingPathComponent("Resources/Firmware/pad"),
        ].compactMap { $0 }

        for directory in candidates {
            let files = PadFirmwareFiles(
                bootPy: directory.appendingPathComponent("boot.py"),
                codePy: directory.appendingPathComponent("code.py"),
                ledsPy: directory.appendingPathComponent("sudo_leds.py"),
                sourceDescription: directory.path
            )
            if validate(files, allowMissing: true) {
                try validate(files)
                return files
            }
        }
        throw FirmwareAssetError.missingPadFirmware
    }

    func circuitPythonUF2(version: String) -> URL? {
        let names = [
            "circuitpython-pico-\(version).uf2",
            "circuitpython-pico.uf2",
        ]
        let directories = [
            bundle.resourceURL?.appendingPathComponent("Firmware"),
            bundle.resourceURL,
            currentDirectory.appendingPathComponent("Sudo/Resources/Firmware"),
            currentDirectory.appendingPathComponent("Resources/Firmware"),
            currentDirectory.deletingLastPathComponent().appendingPathComponent("Resources/Firmware"),
        ].compactMap { $0 }

        for directory in directories {
            for name in names {
                let url = directory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path), fileSize(at: url) > 0 {
                    return url
                }
            }
        }
        return nil
    }

    private func validate(_ files: PadFirmwareFiles, allowMissing: Bool = false) -> Bool {
        for file in files.required {
            guard fileManager.fileExists(atPath: file.url.path) else { return false }
            if !allowMissing, fileSize(at: file.url) <= 0 { return false }
        }
        return true
    }

    private func validate(_ files: PadFirmwareFiles) throws {
        for file in files.required {
            guard fileManager.fileExists(atPath: file.url.path) else {
                throw FirmwareAssetError.missingFile(file.name)
            }
            guard fileSize(at: file.url) > 0 else {
                throw FirmwareAssetError.emptyFile(file.name)
            }
        }
    }

    private func fileSize(at url: URL) -> Int {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}


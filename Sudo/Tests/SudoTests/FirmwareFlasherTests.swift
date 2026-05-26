import XCTest
@testable import Sudo

final class FirmwareFlasherTests: XCTestCase {

    func testDefaultFirmwareAssetProviderFindsRepoFirmwareAndUF2() throws {
        let provider = DefaultFirmwareAssetProvider(
            currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )

        let files = try provider.padFirmwareFiles()
        XCTAssertEqual(files.bootPy.lastPathComponent, "boot.py")
        XCTAssertEqual(files.codePy.lastPathComponent, "code.py")
        XCTAssertEqual(files.ledsPy.lastPathComponent, "sudo_leds.py")
        for file in files.required {
            XCTAssertGreaterThan(fileSize(at: file.url), 0, "\(file.name) should be non-empty")
        }

        let uf2 = provider.circuitPythonUF2(version: FirmwareFlasher.circuitPythonVersion)
        XCTAssertNotNil(uf2)
        XCTAssertGreaterThan(fileSize(at: uf2!), 0)
    }

    func testDetectDeviceFindsCircuitPyFlashMode() {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let circuitpy = root.appendingPathComponent("CIRCUITPY")
        try! FileManager.default.createDirectory(at: circuitpy, withIntermediateDirectories: true)
        try! Data("ok".utf8).write(to: circuitpy.appendingPathComponent("boot_out.txt"))

        let flasher = FirmwareFlasher(assetProvider: StubFirmwareAssetProvider(), volumesPath: root.path)
        let expectation = expectation(description: "detect CIRCUITPY")
        flasher.detectDevice()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if case .flashMode(let path) = flasher.state {
                XCTAssertEqual(path, circuitpy.path)
            } else {
                XCTFail("expected flashMode, got \(flasher.state)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testDetectDeviceFindsBootloader() {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rpi = root.appendingPathComponent("RPI-RP2")
        try! FileManager.default.createDirectory(at: rpi, withIntermediateDirectories: true)
        try! Data("ok".utf8).write(to: rpi.appendingPathComponent("INFO_UF2.TXT"))

        let flasher = FirmwareFlasher(assetProvider: StubFirmwareAssetProvider(), volumesPath: root.path)
        let expectation = expectation(description: "detect RPI-RP2")
        flasher.detectDevice()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if case .bootloader(let path) = flasher.state {
                XCTAssertEqual(path, rpi.path)
            } else {
                XCTFail("expected bootloader, got \(flasher.state)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sudo-flasher-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}

private struct StubFirmwareAssetProvider: FirmwareAssetProviding {
    func padFirmwareFiles() throws -> PadFirmwareFiles {
        throw FirmwareAssetError.missingPadFirmware
    }

    func circuitPythonUF2(version: String) -> URL? {
        nil
    }
}


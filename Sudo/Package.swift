// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sudo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Sudo",
            path: "Sources/Sudo",
            linkerSettings: [
                .unsafeFlags(["-framework", "Cocoa"]),
                .unsafeFlags(["-framework", "Carbon"]),
                .unsafeFlags(["-framework", "Vision"]),
            ]
        ),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacDesktopPlayer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacDesktopPlayer", targets: ["MacDesktopPlayer"])],
    targets: [
        .target(
            name: "YAMNetMac",
            path: "Sources/YAMNetMac",
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include"), .unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [
                .linkedFramework("Foundation"), .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"), .linkedFramework("CoreML"),
                .linkedFramework("AudioToolbox"), .linkedFramework("CoreServices")
            ]
        ),
        .target(
            name: "HTDemucsMac",
            path: "Sources/HTDemucsMac",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"), .linkedFramework("CoreML"),
                .linkedFramework("AudioToolbox")
            ]
        ),
        .target(
            name: "RealtimeDSP",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("Accelerate")]
        ),
        .executableTarget(
            name: "MacDesktopPlayer",
            dependencies: ["RealtimeDSP", "YAMNetMac", "HTDemucsMac"],
            resources: [.process("Resources")]
        )
    ]
)

// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TimelineApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "TimelineApp",
            dependencies: ["Yams"],
            path: "Sources/TimelineApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Quick Look preview appex. Shares renderer sources via symlinks
        // (SPM forbids one file in two targets); the entry point is the
        // extension loader, not main.swift.
        .executableTarget(
            name: "TimelineQuickLook",
            dependencies: ["Yams"],
            path: "Sources/TimelineQuickLook",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("QuickLookUI"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
        .executableTarget(
            name: "TimelineThumbnail",
            dependencies: ["Yams"],
            path: "Sources/TimelineThumbnail",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("QuickLookThumbnailing"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
    ]
)

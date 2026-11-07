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
            dependencies: ["Yams", "llama"],
            path: "Sources/TimelineApp",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // make app copies llama.framework into Contents/Frameworks
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // llama.cpp (runs Gemma 4 for image import). Prebuilt upstream
        // release, so the SwiftPM-only build needs no Xcode or Metal compile.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b12110/llama-b12110-xcframework.zip",
            checksum: "fca702506b04cba11c7f1226056371d16ddfa80e1248da979166a1eec36c415f"
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

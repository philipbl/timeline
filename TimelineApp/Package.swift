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
        )
    ]
)

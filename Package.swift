// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeStatusBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StatusCore"),
        .target(name: "TestSupport"),
        .executableTarget(
            name: "ClaudeStatusBarTests",
            dependencies: ["StatusCore", "TestSupport"]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeStatusBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StatusCore"),
        .target(name: "StatusStore", dependencies: ["StatusCore"]),
        .target(name: "TestSupport"),
        .executableTarget(
            name: "claude-statusbar-hook",
            dependencies: ["StatusCore", "StatusStore"]
        ),
        .executableTarget(
            name: "ClaudeStatusBarTests",
            dependencies: ["StatusCore", "StatusStore", "TestSupport"]
        ),
    ]
)

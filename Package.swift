// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeStatusBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StatusCore"),
        .target(name: "StatusStore", dependencies: ["StatusCore"]),
        .target(name: "StatusApp", dependencies: ["StatusCore", "StatusStore"]),
        .target(name: "StatusInstall"),
        .target(name: "TestSupport"),
        .executableTarget(
            name: "claude-statusbar-hook",
            dependencies: ["StatusCore", "StatusStore"]
        ),
        .executableTarget(
            name: "ClaudeStatusBarApp",
            dependencies: ["StatusApp", "StatusCore", "StatusStore", "StatusInstall"]
        ),
        .executableTarget(
            name: "ClaudeStatusBarTests",
            dependencies: ["StatusCore", "StatusStore", "StatusApp", "StatusInstall", "TestSupport"]
        ),
    ]
)

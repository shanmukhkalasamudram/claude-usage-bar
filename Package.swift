// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Reusable, UI-free domain logic. Everything testable lives here.
        .library(name: "ClaudeUsageKit", targets: ["ClaudeUsageKit"]),
        // The menu bar application.
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
        // A headless CLI over the same core — handy for scripting and for
        // cross-checking numbers against other tools.
        .executable(name: "usagectl", targets: ["usagectl"]),
    ],
    targets: [
        .target(
            name: "ClaudeUsageKit"
        ),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageKit"]
        ),
        .executableTarget(
            name: "usagectl",
            dependencies: ["ClaudeUsageKit"]
        ),
        .testTarget(
            name: "ClaudeUsageKitTests",
            dependencies: ["ClaudeUsageKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vibe-achievements",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibeAchievementsCore", targets: ["VibeAchievementsCore"]),
        .executable(name: "vibe-achievements-cli", targets: ["VibeAchievementsCLI"]),
        .executable(name: "vibe-achievements-app", targets: ["VibeAchievementsApp"])
    ],
    targets: [
        .target(
            name: "VibeAchievementsCore",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "VibeAchievementsCLI", dependencies: ["VibeAchievementsCore"], path: "Sources/vibe-achievements-cli"),
        .executableTarget(
            name: "VibeAchievementsApp",
            dependencies: ["VibeAchievementsCore"],
            path: "Sources/vibe-achievements-app",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VibeAchievementsCoreTests",
            dependencies: ["VibeAchievementsCore"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "VibeAchievementsAppTests",
            dependencies: ["VibeAchievementsApp", "VibeAchievementsCore"]
        )
    ]
)

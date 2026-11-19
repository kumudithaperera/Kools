// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kools",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RepoRadarCore"),
        .target(name: "KoolsCore", dependencies: ["RepoRadarCore"]),
        .executableTarget(name: "Kools", dependencies: ["RepoRadarCore", "KoolsCore"]),
        .testTarget(name: "RepoRadarCoreTests", dependencies: ["RepoRadarCore"]),
        .testTarget(name: "KoolsCoreTests", dependencies: ["KoolsCore", "RepoRadarCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RepoRadar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RepoRadarCore"),
        .executableTarget(name: "RepoRadar", dependencies: ["RepoRadarCore"]),
        .testTarget(name: "RepoRadarCoreTests", dependencies: ["RepoRadarCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionRadar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RadarCore"),
        .executableTarget(name: "radar-hook", dependencies: ["RadarCore"]),
        .testTarget(name: "RadarCoreTests", dependencies: ["RadarCore"]),
    ],
    swiftLanguageModes: [.v6]
)

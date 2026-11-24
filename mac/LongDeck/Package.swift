// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LongDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LongDeckCore"),
        .executableTarget(name: "LongDeckApp", dependencies: ["LongDeckCore"]),
        .testTarget(name: "LongDeckCoreTests", dependencies: ["LongDeckCore"]),
    ]
)

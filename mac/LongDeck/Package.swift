// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LongDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LongDeckCore"),
        .executableTarget(name: "LongDeckApp", dependencies: ["LongDeckCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LongDeckCoreTests", dependencies: ["LongDeckCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LongDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LongDeckCore", resources: [.copy("Resources/sprites")]),
        .target(name: "LongDeckEditor", dependencies: ["LongDeckCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "LongDeckApp", dependencies: ["LongDeckCore", "LongDeckEditor"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LongDeckCoreTests", dependencies: ["LongDeckCore"]),
        .testTarget(name: "LongDeckEditorTests", dependencies: ["LongDeckEditor", "LongDeckCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

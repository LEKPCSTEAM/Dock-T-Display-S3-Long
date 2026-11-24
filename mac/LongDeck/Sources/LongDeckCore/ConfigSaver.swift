import Foundation

public enum SaveOutcome: Equatable, Sendable { case sent, savedOffline, failed(String) }

public enum ConfigSaveError: Error, Equatable, CustomStringConvertible {
    case layoutTooLarge(bytes: Int, max: Int)

    public var description: String {
        switch self {
        case .layoutTooLarge(let bytes, let max):
            return "Layout is \(bytes) bytes, the board takes at most \(max)"
        }
    }
}

public enum LayoutSize {
    // A real sequence number has up to 10 digits, the probe has 1.
    public static let sequenceSlack = 9

    public static func sealedBytes(_ config: DeckConfig) -> Int {
        let json = LayoutBuilder.build(config, render: { _ in Data() }).json
        var sealer = FrameSealer(sessionKey: Data(count: 32))
        return sealer.seal(type: "layout", body: json).utf8.count + sequenceSlack
    }
}

public enum ConfigSaver {
    public static func prepare(_ config: DeckConfig) throws -> Data {
        try config.validate()
        let bytes = LayoutSize.sealedBytes(config)
        guard LayoutPushPolicy.fits(frameBytes: bytes) else {
            throw ConfigSaveError.layoutTooLarge(bytes: bytes, max: LayoutPushPolicy.maxWebSocketFrame)
        }
        return try config.fileData()
    }

    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public struct ConfigWriteGuard: Sendable {
    private var last: Data?

    public init() {}

    public mutating func recordWrite(_ data: Data) {
        last = data
    }

    public func matches(_ data: Data) -> Bool {
        last == data
    }
}

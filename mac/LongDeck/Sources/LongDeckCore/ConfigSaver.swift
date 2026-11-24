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
        let fm = FileManager.default
        let target = url.resolvingSymlinksInPath()
        let dir = target.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let oldMode = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
        let temp = dir.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try fm.setAttributes([.posixPermissions: oldMode ?? 0o644], ofItemAtPath: temp.path)
            guard rename(temp.path, target.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}

public struct ConfigWriteGuard: Sendable {
    private var last: Data?

    public init() {}

    public mutating func recordWrite(_ data: Data) {
        last = data
    }

    public mutating func matches(_ data: Data) -> Bool {
        guard last == data else { return false }
        last = nil
        return true
    }
}

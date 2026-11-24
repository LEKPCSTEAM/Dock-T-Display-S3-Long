import Foundation

public enum KeyModifier: String, Codable, Sendable { case command, shift, option, control }
public enum MediaKey: String, Codable, Sendable { case playPause, next, previous }
public enum VolumeKey: String, Codable, Sendable { case up, down, mute }

public enum IconRef: Codable, Equatable, Sendable {
    case app(path: String)
    case symbol(name: String)
}

public enum DeckAction: Codable, Equatable, Sendable {
    case openApp(path: String)
    case openURL(String)
    case hotkey(keyCode: UInt16, modifiers: [KeyModifier])
    case media(MediaKey)
    case volume(VolumeKey)
    case typeText(String)
    case shell(String)
    case shortcut(String)
}

public struct KeyConfig: Codable, Equatable, Sendable {
    public var id: String
    public var col: Int
    public var row: Int
    public var w: Int
    public var h: Int
    public var label: String
    public var icon: IconRef?
    public var background: String
    public var action: DeckAction
    public var longAction: DeckAction?

    public init(id: String, col: Int, row: Int, w: Int, h: Int, label: String, icon: IconRef?,
                background: String, action: DeckAction, longAction: DeckAction?) {
        self.id = id
        self.col = col
        self.row = row
        self.w = w
        self.h = h
        self.label = label
        self.icon = icon
        self.background = background
        self.action = action
        self.longAction = longAction
    }
}

public struct PageConfig: Codable, Equatable, Sendable {
    public var name: String
    public var keys: [KeyConfig]

    public init(name: String, keys: [KeyConfig]) {
        self.name = name
        self.keys = keys
    }
}

public enum DeckConfigError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): return "Invalid deck config: \(message)"
        }
    }
}

public struct DeckConfig: Codable, Equatable, Sendable {
    public static let gridCols = 8
    public static let gridRows = 2
    public static let maxPages = 8
    public static let maxKeysPerPage = 16
    public static let maxKeyIdBytes = 15
    public static let maxPageNameBytes = 23

    public var version: Int
    public var pages: [PageConfig]

    public init(version: Int, pages: [PageConfig]) {
        self.version = version
        self.pages = pages
    }

    public func validate() throws {
        guard pages.count <= Self.maxPages else {
            throw DeckConfigError.invalid("\(pages.count) pages, max \(Self.maxPages)")
        }
        var ids = Set<String>()
        for page in pages {
            guard page.name.utf8.count <= Self.maxPageNameBytes else {
                throw DeckConfigError.invalid("page name \(page.name) is longer than \(Self.maxPageNameBytes) bytes")
            }
            guard page.keys.count <= Self.maxKeysPerPage else {
                throw DeckConfigError.invalid("page \(page.name) has \(page.keys.count) keys, max \(Self.maxKeysPerPage)")
            }
            var cells = Set<Int>()
            for k in page.keys {
                guard !k.id.isEmpty else {
                    throw DeckConfigError.invalid("a key on page \(page.name) has an empty id")
                }
                guard k.id.utf8.count <= Self.maxKeyIdBytes else {
                    throw DeckConfigError.invalid("key id \(k.id) is longer than \(Self.maxKeyIdBytes) bytes")
                }
                guard ids.insert(k.id).inserted else {
                    throw DeckConfigError.invalid("duplicate key id \(k.id)")
                }
                guard k.w >= 1, k.h >= 1, k.col >= 0, k.row >= 0,
                      k.col + k.w <= Self.gridCols, k.row + k.h <= Self.gridRows else {
                    throw DeckConfigError.invalid("key \(k.id) is outside the \(Self.gridCols)x\(Self.gridRows) grid")
                }
                for c in k.col..<(k.col + k.w) {
                    for r in k.row..<(k.row + k.h) {
                        guard cells.insert(r * Self.gridCols + c).inserted else {
                            throw DeckConfigError.invalid("key \(k.id) overlaps another key on page \(page.name)")
                        }
                    }
                }
            }
        }
    }

    public static func load(from url: URL) throws -> DeckConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return SampleConfig.dev }
        let config = try JSONDecoder().decode(DeckConfig.self, from: Data(contentsOf: url))
        try config.validate()
        return config
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

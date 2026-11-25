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
    public var foreground: String?

    public init(id: String, col: Int, row: Int, w: Int, h: Int, label: String, icon: IconRef?,
                background: String, action: DeckAction, longAction: DeckAction?,
                foreground: String? = nil) {
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
        self.foreground = foreground
    }
}

public enum StatMetric: String, Codable, CaseIterable, Sendable {
    case cpu, ram, gpu, temp
    case netDown = "net_down"
    case netUp = "net_up"
    case diskFree = "disk_free"
    case diskIO = "disk_io"
    case battery
}

public enum StatStyle: String, Codable, CaseIterable, Sendable { case bar, number, sparkline }

public enum LiveKind: Equatable, Sendable {
    case stat(StatMetric, StatStyle)
    case volume
    case clock
    case claudeSessions, claudeUsage, claudeAgents
}

public struct LiveWidgetConfig: Codable, Equatable, Sendable {
    public var id: String
    public var col: Int
    public var row: Int
    public var w: Int
    public var h: Int
    public var kind: LiveKind

    public init(id: String, col: Int, row: Int, w: Int, h: Int, kind: LiveKind) {
        self.id = id
        self.col = col
        self.row = row
        self.w = w
        self.h = h
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case id, type, metric, style, col, row, w, h }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        col = try c.decode(Int.self, forKey: .col)
        row = try c.decode(Int.self, forKey: .row)
        w = try c.decode(Int.self, forKey: .w)
        h = try c.decode(Int.self, forKey: .h)
        switch try c.decode(String.self, forKey: .type) {
        case "stat":
            kind = .stat(try c.decode(StatMetric.self, forKey: .metric),
                         try c.decode(StatStyle.self, forKey: .style))
        case "volume": kind = .volume
        case "clock": kind = .clock
        case "claude_sessions": kind = .claudeSessions
        case "claude_usage": kind = .claudeUsage
        case "claude_agents": kind = .claudeAgents
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown live widget type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(col, forKey: .col)
        try c.encode(row, forKey: .row)
        try c.encode(w, forKey: .w)
        try c.encode(h, forKey: .h)
        switch kind {
        case .stat(let metric, let style):
            try c.encode("stat", forKey: .type)
            try c.encode(metric, forKey: .metric)
            try c.encode(style, forKey: .style)
        case .volume: try c.encode("volume", forKey: .type)
        case .clock: try c.encode("clock", forKey: .type)
        case .claudeSessions: try c.encode("claude_sessions", forKey: .type)
        case .claudeUsage: try c.encode("claude_usage", forKey: .type)
        case .claudeAgents: try c.encode("claude_agents", forKey: .type)
        }
    }
}

public struct PageConfig: Codable, Equatable, Sendable {
    public var name: String
    public var keys: [KeyConfig]
    public var live: [LiveWidgetConfig]

    public init(name: String, keys: [KeyConfig], live: [LiveWidgetConfig] = []) {
        self.name = name
        self.keys = keys
        self.live = live
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        keys = try c.decode([KeyConfig].self, forKey: .keys)
        live = try c.decodeIfPresent([LiveWidgetConfig].self, forKey: .live) ?? []
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
    public static let maxWidgetsPerPage = 16
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
            let count = page.keys.count + page.live.count
            guard count <= Self.maxWidgetsPerPage else {
                throw DeckConfigError.invalid("page \(page.name) has \(count) widgets, max \(Self.maxWidgetsPerPage)")
            }
            for l in page.live where l.kind == .claudeSessions && l.w < 2 {
                throw DeckConfigError.invalid("widget \(l.id): claude_sessions needs at least 2 columns")
            }
            for l in page.live where l.kind == .claudeAgents && l.w < 2 {
                throw DeckConfigError.invalid("widget \(l.id): claude_agents needs at least 2 columns")
            }
            var cells = Set<Int>()
            let frames = page.keys.map { ($0.id, $0.col, $0.row, $0.w, $0.h) }
                + page.live.map { ($0.id, $0.col, $0.row, $0.w, $0.h) }
            for (id, col, row, w, h) in frames {
                guard !id.isEmpty else {
                    throw DeckConfigError.invalid("a widget on page \(page.name) has an empty id")
                }
                guard id.utf8.count <= Self.maxKeyIdBytes else {
                    throw DeckConfigError.invalid("widget id \(id) is longer than \(Self.maxKeyIdBytes) bytes")
                }
                guard ids.insert(id).inserted else {
                    throw DeckConfigError.invalid("duplicate widget id \(id)")
                }
                guard w >= 1, h >= 1, col >= 0, row >= 0,
                      col + w <= Self.gridCols, row + h <= Self.gridRows else {
                    throw DeckConfigError.invalid("widget \(id) is outside the \(Self.gridCols)x\(Self.gridRows) grid")
                }
                for c in col..<(col + w) {
                    for r in row..<(row + h) {
                        guard cells.insert(r * Self.gridCols + c).inserted else {
                            throw DeckConfigError.invalid("widget \(id) overlaps another widget on page \(page.name)")
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

    public func fileData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    @discardableResult
    public func save(to url: URL) throws -> Data {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try fileData()
        try data.write(to: url, options: .atomic)
        return data
    }
}

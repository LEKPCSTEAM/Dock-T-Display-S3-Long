import Foundation

public struct ClaudeHistoryRecord: Codable, Sendable, Equatable {
    public var name: String
    public var project: String
    public var endedAt: TimeInterval

    public init(name: String, project: String, endedAt: TimeInterval) {
        self.name = name
        self.project = project
        self.endedAt = endedAt
    }
}

public struct ClaudeHistory: Sendable, Equatable {
    public static let retention: TimeInterval = 604_800

    public private(set) var records: [ClaudeHistoryRecord] = []

    public init() {}

    public mutating func record(name: String, project: String, endedAt: TimeInterval) {
        let new = ClaudeHistoryRecord(name: name, project: project, endedAt: endedAt)
        if let i = records.firstIndex(where: { $0.name == name }) {
            if endedAt > records[i].endedAt { records[i] = new }
        } else {
            records.append(new)
        }
    }

    public mutating func prune(now: TimeInterval) {
        records.removeAll { now - $0.endedAt > Self.retention }
    }

    public static func load(from url: URL) -> ClaudeHistory {
        var history = ClaudeHistory()
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([ClaudeHistoryRecord].self, from: data)
        else { return history }
        for r in records { history.record(name: r.name, project: r.project, endedAt: r.endedAt) }
        return history
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

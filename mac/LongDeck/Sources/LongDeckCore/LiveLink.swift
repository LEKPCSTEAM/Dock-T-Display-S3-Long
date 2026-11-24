import Foundation

public struct OutFrame: Equatable, Sendable {
    public let type: String
    public let body: String

    public init(type: String, body: String) {
        self.type = type
        self.body = body
    }
}

public enum LiveCommand: Equatable, Sendable { case setVolume(Int), toggleMute }

public struct LiveLink: Sendable {
    public private(set) var page: Int = -1
    private var pushing = false
    private var lastVolume: String?
    private var heldVolume: String?
    private var lastClaude: String?
    private var heldClaude: String?
    private var queuedAcks: [String] = []
    private static let maxQueuedAcks = 8

    public init() {}

    public mutating func reset() {
        page = -1
        pushing = false
        lastVolume = nil
        heldVolume = nil
        lastClaude = nil
        heldClaude = nil
        queuedAcks = []
    }

    public mutating func pageChanged(_ index: Int) {
        page = index
    }

    public mutating func pushStarted() {
        pushing = true
    }

    public mutating func pushFinished() -> [OutFrame] {
        pushing = false
        var frames: [OutFrame] = []
        if let body = heldVolume {
            heldVolume = nil
            if let frame = volumeFrame(body: body) { frames.append(frame) }
        }
        if let body = heldClaude {
            heldClaude = nil
            if let frame = claudeFrame(body: body) { frames.append(frame) }
        }
        frames += queuedAcks.map { OutFrame(type: "claude_ack", body: $0) }
        queuedAcks = []
        return frames
    }

    public mutating func claudeFrame(body: String) -> OutFrame? {
        if pushing {
            heldClaude = body
            return nil
        }
        guard body != lastClaude else { return nil }
        lastClaude = body
        return OutFrame(type: "claude", body: body)
    }

    public mutating func ackFrame(body: String) -> OutFrame? {
        if pushing {
            queuedAcks.append(body)
            if queuedAcks.count > Self.maxQueuedAcks { queuedAcks.removeFirst() }
            return nil
        }
        return OutFrame(type: "claude_ack", body: body)
    }

    public func statsFrame(body: String) -> OutFrame? {
        guard page >= 0, !pushing else { return nil }
        return OutFrame(type: "stats", body: body)
    }

    public mutating func volumeFrame(body: String) -> OutFrame? {
        if pushing {
            heldVolume = body
            return nil
        }
        guard body != lastVolume else { return nil }
        lastVolume = body
        return OutFrame(type: "volume", body: body)
    }

    public static func isLiveWidget(id: String, config: DeckConfig) -> Bool {
        config.pages.contains { $0.live.contains { $0.id == id } }
    }

    public static func command(type: String, body: String, config: DeckConfig) -> LiveCommand? {
        guard type == "slider" || type == "press",
              let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let id = object["id"] as? String,
              config.pages.contains(where: { $0.live.contains { $0.id == id && $0.kind == .volume } })
        else { return nil }
        if type == "slider" {
            guard let value = object["value"] as? Int, (0...100).contains(value) else { return nil }
            return .setVolume(value)
        }
        return object["kind"] as? String == "tap" ? .toggleMute : nil
    }
}

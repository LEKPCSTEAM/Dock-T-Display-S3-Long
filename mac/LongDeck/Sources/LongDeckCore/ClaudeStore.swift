import Foundation

public enum ClaudeState: String, Sendable { case working, permission, waiting, done }

public struct ClaudePending: Equatable, Sendable {
    public var request: String
    public var toolName: String
    public var toolInputJSON: String
    public var createdAt: TimeInterval
    public var seenOnScreen: Bool
    public var misses: Int
}

public struct ClaudeSession: Equatable, Sendable {
    public var id: String
    public var cwd: String?
    public var projectDir: String?
    public var pane: String?
    public var state: ClaudeState
    public var stateSince: TimeInterval
    public var lastSeen: TimeInterval
    public var model: String?
    public var costUSD: Double?
    public var contextPct: Double?
    public var queue: [ClaudePending] = []

    public var pending: ClaudePending? { queue.first }
    public var pendingCount: Int { queue.count }
}

public struct ClaudeStore: Sendable {
    public static let silentLimit: TimeInterval = 1800
    public static let unseenGrace: TimeInterval = 5
    private static let maxSessions = 8
    public static let tombstoneTTL: TimeInterval = 600
    private static let maxIdBytes = 39
    private static let maxQueue = 16

    private let runTag: String
    private var requestCount = 0
    private var ended: [String: TimeInterval] = [:]
    public private(set) var sessions: [String: ClaudeSession] = [:]
    public private(set) var fiveHour: UsageWindow?
    public private(set) var sevenDay: UsageWindow?

    public init(runTag: String) {
        self.runTag = runTag
    }

    public mutating func apply(_ e: ClaudeHookEvent, pane: String?, now: TimeInterval) {
        if e.event == "SessionEnd" {
            sessions[e.sessionId] = nil
            ended[e.sessionId] = now
            return
        }
        if e.event == "SessionStart" {
            ended[e.sessionId] = nil
        } else if isEnded(e.sessionId, now) {
            return
        }
        var s = sessions[e.sessionId] ?? ClaudeSession(id: e.sessionId, state: .waiting, stateSince: now, lastSeen: now)
        s.lastSeen = now
        if let cwd = e.cwd { s.cwd = cwd }
        if let pane {
            claimPane(pane, for: e.sessionId, now: now)
            s.pane = pane
        }
        switch e.event {
        case "SessionStart":
            s.queue = []
            set(&s, .waiting, now)
        case "UserPromptSubmit":
            s.queue = []
            set(&s, .working, now)
        case "PreToolUse":
            if s.queue.isEmpty { set(&s, .working, now) }
        case "PermissionRequest":
            // Claude Code shows parallel prompts oldest first, so queue in order.
            if s.queue.count < Self.maxQueue {
                requestCount += 1
                s.queue.append(ClaudePending(request: "\(runTag)-\(requestCount)", toolName: e.toolName ?? "",
                                             toolInputJSON: e.toolInputJSON ?? "{}", createdAt: now,
                                             seenOnScreen: false, misses: 0))
            }
            set(&s, .permission, now)
        case "PostToolUse", "PostToolUseFailure":
            if s.queue.isEmpty {
                set(&s, .working, now)
            } else if let i = s.queue.firstIndex(where: {
                $0.toolName == (e.toolName ?? "") && $0.toolInputJSON == (e.toolInputJSON ?? "{}")
            }) {
                s.queue.remove(at: i)
                if s.queue.isEmpty { set(&s, .working, now) }
            }
        case "Notification":
            if e.notificationType == "permission_prompt" {
                set(&s, .permission, now)
            } else if e.notificationType == "idle_prompt" {
                s.queue = []
                set(&s, .waiting, now)
            }
        case "Stop":
            s.queue = []
            set(&s, .done, now)
        default:
            break
        }
        sessions[e.sessionId] = s
    }

    public mutating func apply(_ u: ClaudeStatusUpdate, pane: String?, now: TimeInterval) {
        if isEnded(u.sessionId, now) { return }
        var s = sessions[u.sessionId] ?? ClaudeSession(id: u.sessionId, state: .waiting, stateSince: now, lastSeen: now)
        s.lastSeen = now
        if let pane {
            claimPane(pane, for: u.sessionId, now: now)
            s.pane = pane
        }
        if let model = u.model { s.model = model }
        if let cost = u.costUSD { s.costUSD = cost }
        if let ctx = u.contextPct { s.contextPct = ctx }
        if let dir = u.projectDir { s.projectDir = dir }
        sessions[u.sessionId] = s
        if let w = u.fiveHour { fiveHour = w }
        if let w = u.sevenDay { sevenDay = w }
    }

    public mutating func expire(now: TimeInterval, wall: Date) {
        sessions = sessions.filter { now - $0.value.lastSeen <= Self.silentLimit }
        ended = ended.filter { now - $0.value <= Self.tombstoneTTL }
        let t = wall.timeIntervalSince1970
        if let w = fiveHour, t >= w.resetsAt { fiveHour = nil }
        if let w = sevenDay, t >= w.resetsAt { sevenDay = nil }
    }

    public mutating func resolve(session: String, request: String, state: ClaudeState, now: TimeInterval) {
        guard var s = sessions[session], let i = s.queue.firstIndex(where: { $0.request == request }) else { return }
        s.queue.remove(at: i)
        set(&s, s.queue.isEmpty ? state : .permission, now)
        sessions[session] = s
    }

    @discardableResult
    public mutating func promptCheck(session: String, request: String, visible: Bool, now: TimeInterval) -> Bool {
        guard var s = sessions[session], let i = s.queue.firstIndex(where: { $0.request == request }) else { return false }
        var p = s.queue[i]
        var cleared = false
        if visible {
            p.seenOnScreen = true
            p.misses = 0
        } else {
            p.misses += 1
            cleared = p.misses >= 2 && (p.seenOnScreen || now - p.createdAt >= Self.unseenGrace)
        }
        if cleared {
            s.queue.remove(at: i)
            if s.queue.isEmpty { set(&s, .working, now) }
        } else {
            s.queue[i] = p
        }
        sessions[session] = s
        return cleared
    }

    public func target(session id: String) -> ClaudeTarget? {
        guard let s = sessions[id] else { return nil }
        var target = ClaudeTarget(pane: s.pane, pendingRequest: s.pending?.request, toolName: s.pending?.toolName,
                                  toolInputJSON: s.pending?.toolInputJSON, cwd: s.cwd)
        if let head = s.pending {
            target.ambiguous = s.queue.dropFirst().contains { Self.lookAlike(head, $0, cwd: s.cwd) }
        }
        return target
    }

    // Another queued request would render the same dialog rows.
    private static func lookAlike(_ a: ClaudePending, _ b: ClaudePending, cwd: String?) -> Bool {
        guard a.toolInputJSON != b.toolInputJSON || a.toolName != b.toolName else { return false }
        guard let ha = PromptHints.from(toolName: a.toolName, toolInputJSON: a.toolInputJSON, cwd: cwd),
              let hb = PromptHints.from(toolName: b.toolName, toolInputJSON: b.toolInputJSON, cwd: cwd)
        else { return false }
        // Wraps can drop or add whitespace, so compare without any.
        let flat = { (s: String) in String(s.filter { !$0.isWhitespace }) }
        return ha.titles == hb.titles && !Set(ha.renderings.map(flat)).isDisjoint(with: hb.renderings.map(flat))
    }

    public func pendingPrompts() -> [(session: ClaudeSession, pending: ClaudePending)] {
        sessions.values.compactMap { s in s.pending.map { (session: s, pending: $0) } }
            .sorted { ($0.pending.createdAt, $0.session.id) < ($1.pending.createdAt, $1.session.id) }
    }

    public func body(now: Date) -> String {
        let shown = sessions.values
            .filter { $0.id.utf8.count <= Self.maxIdBytes }
            .sorted { a, b in
                let (ra, rb) = (Self.rank(a.state), Self.rank(b.state))
                if ra != rb { return ra < rb }
                if a.stateSince != b.stateSince { return a.stateSince > b.stateSince }
                return a.id < b.id
            }
            .prefix(Self.maxSessions)
        let list: [[String: Any]] = shown.map { s in
            [
                "id": s.id,
                "project": ClaudeText.project(s.projectDir ?? s.cwd),
                "model": s.model.map { ClaudeText.capped($0, bytes: 15) } ?? "",
                "state": s.state.rawValue,
                "ctx": s.contextPct.map { Self.clampedInt($0, 0, 100) } ?? -1,
                "cost_cents": s.costUSD.map { Self.clampedInt($0 * 100, 0, 100_000_000) } ?? -1,
                "tmux": s.pane != nil,
            ]
        }
        var prompt: Any = NSNull()
        let pendings = pendingPrompts()
        if let first = pendings.first {
            prompt = [
                "pending": pendings.count,
                "project": ClaudeText.project(first.session.projectDir ?? first.session.cwd),
                "request": first.pending.request,
                "session": first.session.id,
                "summary": ClaudeText.summary(toolName: first.pending.toolName,
                                              toolInputJSON: first.pending.toolInputJSON,
                                              cwd: first.session.cwd),
                "tmux": first.session.pane != nil,
                "tool": ClaudeText.toolLabel(first.pending.toolName),
            ] as [String: Any]
        }
        let root: [String: Any] = [
            "prompt": prompt,
            "sessions": list,
            "usage": ["five_hour": windowJSON(fiveHour, now), "seven_day": windowJSON(sevenDay, now)],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "{\"prompt\":null,\"sessions\":[],\"usage\":{\"five_hour\":null,\"seven_day\":null}}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func windowJSON(_ w: UsageWindow?, _ now: Date) -> Any {
        guard let w, now.timeIntervalSince1970 < w.resetsAt else { return NSNull() }
        return ["pct": Self.clampedInt(w.pct, 0, 100), "resets_at": Self.clampedInt(w.resetsAt, 0, 4_000_000_000_000)]
    }

    private static func clampedInt(_ d: Double, _ lo: Double, _ hi: Double) -> Int {
        guard d.isFinite else { return Int(lo) }
        return Int(min(hi, max(lo, d)).rounded())
    }

    private func isEnded(_ id: String, _ now: TimeInterval) -> Bool {
        guard let at = ended[id] else { return false }
        return now - at <= Self.tombstoneTTL
    }

    private mutating func claimPane(_ pane: String, for id: String, now: TimeInterval) {
        for (key, var other) in sessions where key != id && other.pane == pane {
            other.pane = nil
            if !other.queue.isEmpty {
                other.queue = []
                if other.state == .permission { set(&other, .working, now) }
            }
            sessions[key] = other
        }
    }

    private func set(_ s: inout ClaudeSession, _ state: ClaudeState, _ now: TimeInterval) {
        if s.state != state {
            s.state = state
            s.stateSince = now
        }
    }

    private static func rank(_ state: ClaudeState) -> Int {
        switch state {
        case .permission: return 0
        case .waiting: return 1
        case .done: return 2
        case .working: return 3
        }
    }
}

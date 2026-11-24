import Foundation

public enum ClaudeState: String, Sendable { case working, permission, waiting, done }

public struct ClaudePending: Equatable, Sendable {
    public var request: String
    public var toolName: String
    public var toolInputJSON: String
    public var createdAt: Date
    public var seenOnScreen: Bool
    public var misses: Int
}

public struct ClaudeSession: Equatable, Sendable {
    public var id: String
    public var cwd: String?
    public var projectDir: String?
    public var pane: String?
    public var state: ClaudeState
    public var stateSince: Date
    public var lastSeen: Date
    public var model: String?
    public var costUSD: Double?
    public var contextPct: Double?
    public var pending: ClaudePending?
}

public struct ClaudeStore: Sendable {
    public static let silentLimit: TimeInterval = 1800
    public static let unseenGrace: TimeInterval = 5
    private static let maxSessions = 8
    private static let maxIdBytes = 39

    private let runTag: String
    private var requestCount = 0
    public private(set) var sessions: [String: ClaudeSession] = [:]
    public private(set) var fiveHour: UsageWindow?
    public private(set) var sevenDay: UsageWindow?

    public init(runTag: String) {
        self.runTag = runTag
    }

    public mutating func apply(_ e: ClaudeHookEvent, pane: String?, now: Date) {
        if e.event == "SessionEnd" {
            sessions[e.sessionId] = nil
            return
        }
        var s = sessions[e.sessionId] ?? ClaudeSession(id: e.sessionId, state: .waiting, stateSince: now, lastSeen: now)
        s.lastSeen = now
        if let cwd = e.cwd { s.cwd = cwd }
        if let pane { s.pane = pane }
        switch e.event {
        case "SessionStart":
            set(&s, .waiting, now)
        case "UserPromptSubmit":
            s.pending = nil
            set(&s, .working, now)
        case "PreToolUse":
            if s.pending == nil { set(&s, .working, now) }
        case "PermissionRequest":
            requestCount += 1
            s.pending = ClaudePending(request: "\(runTag)-\(requestCount)", toolName: e.toolName ?? "",
                                      toolInputJSON: e.toolInputJSON ?? "{}", createdAt: now,
                                      seenOnScreen: false, misses: 0)
            set(&s, .permission, now)
        case "PostToolUse":
            if let p = s.pending {
                if p.toolName == (e.toolName ?? ""), p.toolInputJSON == (e.toolInputJSON ?? "{}") {
                    s.pending = nil
                    set(&s, .working, now)
                }
            } else {
                set(&s, .working, now)
            }
        case "Notification":
            if e.notificationType == "permission_prompt" {
                set(&s, .permission, now)
            } else if e.notificationType == "idle_prompt" {
                s.pending = nil
                set(&s, .waiting, now)
            }
        case "Stop":
            s.pending = nil
            set(&s, .done, now)
        default:
            break
        }
        sessions[e.sessionId] = s
    }

    public mutating func apply(_ u: ClaudeStatusUpdate, pane: String?, now: Date) {
        var s = sessions[u.sessionId] ?? ClaudeSession(id: u.sessionId, state: .waiting, stateSince: now, lastSeen: now)
        s.lastSeen = now
        if let pane { s.pane = pane }
        if let model = u.model { s.model = model }
        if let cost = u.costUSD { s.costUSD = cost }
        if let ctx = u.contextPct { s.contextPct = ctx }
        if let dir = u.projectDir { s.projectDir = dir }
        sessions[u.sessionId] = s
        if let w = u.fiveHour { fiveHour = w }
        if let w = u.sevenDay { sevenDay = w }
    }

    public mutating func expire(now: Date) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastSeen) <= Self.silentLimit }
        let t = now.timeIntervalSince1970
        if let w = fiveHour, t >= w.resetsAt { fiveHour = nil }
        if let w = sevenDay, t >= w.resetsAt { sevenDay = nil }
    }

    public mutating func resolve(session: String, request: String, state: ClaudeState, now: Date) {
        guard var s = sessions[session], s.pending?.request == request else { return }
        s.pending = nil
        set(&s, state, now)
        sessions[session] = s
    }

    @discardableResult
    public mutating func promptCheck(session: String, request: String, visible: Bool, now: Date) -> Bool {
        guard var s = sessions[session], var p = s.pending, p.request == request else { return false }
        var cleared = false
        if visible {
            p.seenOnScreen = true
            p.misses = 0
        } else {
            p.misses += 1
            cleared = p.misses >= 2 && (p.seenOnScreen || now.timeIntervalSince(p.createdAt) >= Self.unseenGrace)
        }
        if cleared {
            s.pending = nil
            set(&s, .working, now)
        } else {
            s.pending = p
        }
        sessions[session] = s
        return cleared
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
                "ctx": s.contextPct.map { min(100, max(0, Int($0.rounded()))) } ?? -1,
                "cost_cents": s.costUSD.map { Int(($0 * 100).rounded()) } ?? -1,
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
        return ["pct": min(100, max(0, Int(w.pct.rounded()))), "resets_at": Int(w.resetsAt)]
    }

    private func set(_ s: inout ClaudeSession, _ state: ClaudeState, _ now: Date) {
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

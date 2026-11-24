import Foundation

public struct ClaudeHookEvent: Equatable, Sendable {
    public var sessionId: String
    public var event: String
    public var cwd: String?
    public var toolName: String?
    public var toolInputJSON: String?
    public var notificationType: String?

    public init(sessionId: String, event: String, cwd: String? = nil, toolName: String? = nil,
                toolInputJSON: String? = nil, notificationType: String? = nil) {
        self.sessionId = sessionId
        self.event = event
        self.cwd = cwd
        self.toolName = toolName
        self.toolInputJSON = toolInputJSON
        self.notificationType = notificationType
    }

    public static func decode(_ body: Data) -> ClaudeHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let sessionId = object["session_id"] as? String, !sessionId.isEmpty,
              let event = object["hook_event_name"] as? String, !event.isEmpty
        else { return nil }
        var toolInputJSON: String?
        if let input = object["tool_input"], JSONSerialization.isValidJSONObject(input),
           let data = try? JSONSerialization.data(withJSONObject: input,
                                                  options: [.sortedKeys, .withoutEscapingSlashes]) {
            toolInputJSON = String(decoding: data, as: UTF8.self)
        }
        return ClaudeHookEvent(sessionId: sessionId, event: event, cwd: object["cwd"] as? String,
                               toolName: object["tool_name"] as? String, toolInputJSON: toolInputJSON,
                               notificationType: object["notification_type"] as? String)
    }
}

public struct UsageWindow: Equatable, Sendable {
    public var pct: Double
    public var resetsAt: TimeInterval

    public init(pct: Double, resetsAt: TimeInterval) {
        self.pct = pct
        self.resetsAt = resetsAt
    }
}

public struct ClaudeStatusUpdate: Equatable, Sendable {
    public var sessionId: String
    public var model: String?
    public var costUSD: Double?
    public var contextPct: Double?
    public var projectDir: String?
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?

    public init(sessionId: String, model: String? = nil, costUSD: Double? = nil, contextPct: Double? = nil,
                projectDir: String? = nil, fiveHour: UsageWindow? = nil, sevenDay: UsageWindow? = nil) {
        self.sessionId = sessionId
        self.model = model
        self.costUSD = costUSD
        self.contextPct = contextPct
        self.projectDir = projectDir
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public static func decode(_ body: Data) -> ClaudeStatusUpdate? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let sessionId = object["session_id"] as? String, !sessionId.isEmpty
        else { return nil }
        let workspace = object["workspace"] as? [String: Any]
        let limits = object["rate_limits"] as? [String: Any]
        return ClaudeStatusUpdate(
            sessionId: sessionId,
            model: (object["model"] as? [String: Any])?["display_name"] as? String,
            costUSD: number((object["cost"] as? [String: Any])?["total_cost_usd"]),
            contextPct: number((object["context_window"] as? [String: Any])?["used_percentage"]),
            projectDir: (workspace?["project_dir"] as? String) ?? (workspace?["current_dir"] as? String)
                ?? (object["cwd"] as? String),
            fiveHour: window(limits?["five_hour"]),
            sevenDay: window(limits?["seven_day"]))
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let pct = number(dict["used_percentage"]),
              let resets = number(dict["resets_at"])
        else { return nil }
        return UsageWindow(pct: pct, resetsAt: resets)
    }
}

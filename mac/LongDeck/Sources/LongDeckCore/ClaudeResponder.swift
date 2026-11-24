import Foundation

public enum ClaudeActionKind: String, Sendable {
    case approve, always, deny, interrupt, focus

    var answersPrompt: Bool { self == .approve || self == .always || self == .deny }
}

public struct ClaudeActionRequest: Equatable, Sendable {
    public var session: String
    public var request: String
    public var action: ClaudeActionKind

    public init(session: String, request: String, action: ClaudeActionKind) {
        self.session = session
        self.request = request
        self.action = action
    }

    private static let maxSessionBytes = 64

    public static func parse(_ body: String) -> ClaudeActionRequest? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any],
              let action = (object["action"] as? String).flatMap(ClaudeActionKind.init(rawValue:)),
              let session = object["session"] as? String, !session.isEmpty,
              session.utf8.count <= maxSessionBytes,
              let request = object["request"] as? String,
              !(action.answersPrompt && request.isEmpty)
        else { return nil }
        return ClaudeActionRequest(session: session, request: request, action: action)
    }
}

public struct ClaudeAck: Equatable, Sendable {
    public var request: String
    public var ok: Bool
    public var reason: String

    public init(request: String, ok: Bool, reason: String) {
        self.request = request
        self.ok = ok
        self.reason = reason
    }

    public var body: String {
        let object: [String: Any] = ["ok": ok, "reason": reason, "request": request]
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.sortedKeys, .withoutEscapingSlashes])
        else { return #"{"ok":false,"reason":"","request":""}"# }
        return String(decoding: data, as: UTF8.self)
    }
}

public struct TmuxClient: Equatable, Sendable {
    public var tty: String
    public var session: String
    public var activity: Int

    public init(tty: String, session: String, activity: Int) {
        self.tty = tty
        self.session = session
        self.activity = activity
    }
}

public enum TmuxFocus {
    public static func chooseClient(_ clients: [TmuxClient], paneSession: String, frontTTY: String?) -> TmuxClient? {
        let byActivity: (TmuxClient, TmuxClient) -> Bool = { $0.activity < $1.activity }
        if let onSession = clients.filter({ $0.session == paneSession }).max(by: byActivity) { return onSession }
        if let frontTTY, let front = clients.first(where: { $0.tty == frontTTY }) { return front }
        return clients.max(by: byActivity)
    }

    static func parseClients(_ listing: String) -> [TmuxClient] {
        listing.split(whereSeparator: \.isNewline).compactMap { row in
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, validTTY(fields[0]) else { return nil }
            return TmuxClient(tty: fields[0], session: fields[1..<(fields.count - 1)].joined(separator: "\t"),
                              activity: Int(fields[fields.count - 1]) ?? 0)
        }
    }

    // Strict: the app embeds this tty in AppleScript.
    static func validTTY(_ tty: String) -> Bool {
        let name = tty.utf8.dropFirst(5)
        return tty.hasPrefix("/dev/") && !name.isEmpty && name.count <= 32
            && name.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }
    }
}

public struct ClaudeTarget: Sendable {
    public var pane: String?
    public var pendingRequest: String?
    public var toolName: String?
    public var toolInputJSON: String?
    public var cwd: String?
    public var ambiguous: Bool

    public init(pane: String?, pendingRequest: String?, toolName: String?, toolInputJSON: String?, cwd: String?,
                ambiguous: Bool = false) {
        self.pane = pane
        self.pendingRequest = pendingRequest
        self.toolName = toolName
        self.toolInputJSON = toolInputJSON
        self.cwd = cwd
        self.ambiguous = ambiguous
    }
}

public struct ClaudeResponder: Sendable {
    private static let paneFormat = "#{pane_current_command}\t#{pane_synchronized}\t#{pane_in_mode}"
        + "\t#{pane_input_off}\t#{pane_width}\t#{session_name}"
    private static let clientFormat = "#{client_tty}\t#{client_session}\t#{client_activity}"

    private let runner: any TmuxRunner
    private let frontTTY: @Sendable () -> String?
    private let activateTerminal: @Sendable (String?) -> Void

    public init(runner: TmuxRunner, frontTTY: @escaping @Sendable () -> String?,
                activateTerminal: @escaping @Sendable (String?) -> Void) {
        self.runner = runner
        self.frontTTY = frontTTY
        self.activateTerminal = activateTerminal
    }

    public func handle(_ req: ClaudeActionRequest, target: ClaudeTarget?) -> ClaudeAck {
        let refuse = { (reason: String) in ClaudeAck(request: req.request, ok: false, reason: reason) }
        guard let target else { return refuse("unknown_session") }
        guard let pane = Self.validPane(target.pane) else { return refuse("no_pane") }
        if req.action.answersPrompt {
            guard let pending = target.pendingRequest, !pending.isEmpty, pending == req.request
            else { return refuse("stale") }
            guard !target.ambiguous else { return refuse("unverifiable") }
        }
        guard let info = paneInfo(pane) else { return refuse("tmux") }
        if req.action != .focus {
            guard Self.isClaudeCode(info.command) else { return refuse("not_claude") }
            // Synchronized panes copy keys; modes and input-off swallow them.
            guard info.flags == ["0", "0", "0"] else { return refuse("pane_busy") }
        }
        let reason: String
        switch req.action {
        case .approve, .always, .deny: reason = answer(req.action, target, pane, width: info.width)
        case .interrupt: reason = interrupt(pane)
        case .focus: reason = focus(pane, session: info.session)
        }
        return ClaudeAck(request: req.request, ok: reason.isEmpty, reason: reason)
    }

    public func promptVisible(pane: String) -> Bool {
        guard let pane = Self.validPane(pane), let shot = capture(pane) else { return false }
        return PermissionPromptMatcher.parse(shot) != nil
    }

    // True only while this target's own dialog is on screen.
    public func promptVisible(pane: String, target: ClaudeTarget) -> Bool {
        guard let pane = Self.validPane(pane), let info = paneInfo(pane), let shot = capture(pane),
              let screen = PermissionPromptMatcher.parse(shot) else { return false }
        guard let tool = target.toolName, let input = target.toolInputJSON,
              let hints = PromptHints.from(toolName: tool, toolInputJSON: input, cwd: target.cwd) else { return true }
        return PermissionPromptMatcher.matches(screen, hints, paneWidth: info.width)
    }

    private func answer(_ action: ClaudeActionKind, _ target: ClaudeTarget, _ pane: String, width: Int) -> String {
        guard let tool = target.toolName, let input = target.toolInputJSON,
              let hints = PromptHints.from(toolName: tool, toolInputJSON: input, cwd: target.cwd)
        else { return "unverifiable" }
        if action == .always, hints.alwaysPrefixes.isEmpty { return "unverifiable" }
        guard let shot = capture(pane) else { return "tmux" }
        guard let screen = PermissionPromptMatcher.parse(shot) else { return "no_prompt" }
        guard PermissionPromptMatcher.matches(screen, hints, paneWidth: width) else { return "mismatch" }
        let key: Character
        switch action {
        case .always:
            guard let always = screen.always, let label = screen.alwaysLabel,
                  hints.alwaysPrefixes.contains(where: { label.hasPrefix($0) })
            else { return "no_always" }
            guard PermissionPromptMatcher.alwaysScopeVerified(screen, hints) else { return "unverifiable" }
            key = always
        case .deny: key = screen.no
        default: key = screen.yes
        }
        return send(["send-keys", "-t", pane, "-l", String(key)])
    }

    private func interrupt(_ pane: String) -> String {
        guard let shot = capture(pane) else { return "tmux" }
        guard PermissionPromptMatcher.interruptHintVisible(shot),
              PermissionPromptMatcher.parse(shot) == nil,
              !shot.contains(PermissionPromptMatcher.cutDialogNotice)
        else { return "not_working" }
        return send(["send-keys", "-t", pane, "Escape"])
    }

    private func focus(_ pane: String, session: String) -> String {
        guard let listing = try? runner.run(["list-clients", "-F", Self.clientFormat]) else { return "tmux" }
        let clients = TmuxFocus.parseClients(listing)
        let front = clients.contains { $0.session == session } ? nil : frontTTY()
        guard let client = TmuxFocus.chooseClient(clients, paneSession: session, frontTTY: front)
        else { return "no_client" }
        if client.session != session {
            let reason = send(["switch-client", "-c", client.tty, "-t", pane])
            guard reason.isEmpty else { return reason }
        }
        for args in [["select-window", "-t", pane], ["select-pane", "-t", pane]] {
            let reason = send(args)
            guard reason.isEmpty else { return reason }
        }
        activateTerminal(client.tty)
        return ""
    }

    private func paneInfo(_ pane: String) -> (command: String, flags: [String], width: Int, session: String)? {
        guard let out = try? runner.run(["display-message", "-p", "-t", pane, Self.paneFormat]),
              let line = out.split(separator: "\n", omittingEmptySubsequences: false).first
        else { return nil }
        let fields = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 6, let width = Int(fields[4]), width > 0 else { return nil }
        return (fields[0], Array(fields[1...3]), width, fields[5])
    }

    private func capture(_ pane: String) -> String? {
        try? runner.run(["capture-pane", "-p", "-t", pane])
    }

    private func send(_ args: [String]) -> String {
        (try? runner.run(args)) == nil ? "tmux" : ""
    }

    private static func validPane(_ value: String?) -> String? {
        guard let v = value, v.utf8.count >= 2, v.utf8.count <= 12, v.hasPrefix("%"),
              v.utf8.dropFirst().allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return v
    }

    private static func isClaudeCode(_ command: String) -> Bool {
        if command == "claude" { return true }
        let parts = command.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }
    }
}

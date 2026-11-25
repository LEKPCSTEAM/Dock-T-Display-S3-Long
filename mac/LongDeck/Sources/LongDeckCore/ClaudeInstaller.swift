import Foundation

public struct ClaudeInstallPaths: Sendable {
    public let settings: URL
    public let supportDir: URL

    public init(settings: URL, supportDir: URL) {
        self.settings = settings
        self.supportDir = supportDir
    }

    var wrapper: URL { supportDir.appendingPathComponent("statusline.sh") }
    var hookScript: URL { supportDir.appendingPathComponent("hook.sh") }
    var stateFile: URL { supportDir.appendingPathComponent("claude-install.json") }
}

public struct ClaudeInstallState: Codable, Equatable, Sendable {
    public var token: String
    public var port: Int
    public var statusLineCommand: String
    public var previousStatusLine: String?
    public var createdEvents: [String]
    public var createdHooksKey: Bool
    public var createdSettingsFile: Bool
    public var backupPath: String?
    public var installedAt: String
}

public enum ClaudeInstallError: Error, Equatable {
    case alreadyInstalled, notInstalled, settingsUnreadable(String), settingsNotObject,
         wrapperWithoutState, writeFailed(String)
}

public enum ClaudeInstaller {
    public static let port = 47821
    public static let hookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                    "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "SessionEnd",
                                    "SubagentStart", "SubagentStop"]

    private static let urlPrefix = "http://127.0.0.1:\(port)/"

    public static func isCurrent(_ paths: ClaudeInstallPaths) -> Bool {
        guard let data = try? Data(contentsOf: paths.settings.resolvingSymlinksInPath()),
              let root = try? JSONText.parse(data) else { return false }
        let command = StatusLineWrapper.shellQuote(paths.hookScript.path)
        return hookEvents.allSatisfy { name in
            guard case .array(let groups)? = root["hooks"]?[name] else { return false }
            return groups.contains { isLongDeckGroup($0, hookCommand: command) }
        }
    }

    public static func loadState(_ paths: ClaudeInstallPaths) -> ClaudeInstallState? {
        guard let data = try? Data(contentsOf: paths.stateFile) else { return nil }
        return try? JSONDecoder().decode(ClaudeInstallState.self, from: data)
    }

    @discardableResult
    public static func install(_ paths: ClaudeInstallPaths, token: String, now: Date) throws -> ClaudeInstallState {
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.stateFile.path) { throw ClaudeInstallError.alreadyInstalled }

        let settingsURL = paths.settings.resolvingSymlinksInPath()
        let existed = fm.fileExists(atPath: settingsURL.path)
        var original: Data?
        var root = JSONValue.object([])
        if existed {
            let data: Data
            do { data = try Data(contentsOf: settingsURL) } catch {
                throw ClaudeInstallError.settingsUnreadable(error.localizedDescription)
            }
            do { root = try JSONText.parse(data) } catch {
                throw ClaudeInstallError.settingsUnreadable("\(error)")
            }
            guard case .object = root else { throw ClaudeInstallError.settingsNotObject }
            original = data
        }

        let wrapperCommand = StatusLineWrapper.shellQuote(paths.wrapper.path)
        if root["statusLine"]?["command"] == .string(wrapperCommand) {
            throw ClaudeInstallError.wrapperWithoutState
        }

        var hooks: JSONValue
        var createdHooksKey = false
        switch root["hooks"] {
        case nil:
            hooks = .object([])
            createdHooksKey = true
        case .object?: hooks = root["hooks"]!
        default: throw ClaudeInstallError.settingsUnreadable("hooks is not an object")
        }
        let hookCommand = StatusLineWrapper.shellQuote(paths.hookScript.path)
        hooks = try stripLongDeckGroups(hooks, hookCommand: hookCommand)

        var createdEvents: [String] = []
        let group = try hookGroup(command: hookCommand)
        for name in hookEvents {
            var arr: [JSONValue]
            switch hooks[name] {
            case nil:
                arr = []
                createdEvents.append(name)
            case .array(let a)?: arr = a
            default: throw ClaudeInstallError.settingsUnreadable("hooks.\(name) is not an array")
            }
            arr.append(group)
            hooks = hooks.setting(name, .array(arr))
        }
        root = root.setting("hooks", hooks)

        var backupPath: String?
        if let original { backupPath = try writeBackup(original, of: settingsURL, now: now).path }

        var previousStatusLine: String?
        var previousCommand: String?
        if let sl = root["statusLine"] {
            previousStatusLine = JSONText.compact(sl)
            if case .string(let c)? = sl["command"] { previousCommand = c }
        }
        if case .object? = root["statusLine"] {
            root = root.setting("statusLine", root["statusLine"]!.setting("command", .string(wrapperCommand)))
        } else {
            root = root.setting("statusLine", .object([
                JSONMember(key: "type", value: .string("command")),
                JSONMember(key: "command", value: .string(wrapperCommand)),
                JSONMember(key: "padding", value: .number("0")),
            ]))
        }

        let script = StatusLineWrapper.script(previousCommand: previousCommand, url: urlPrefix + "statusline", token: token)
        let hookScript = ClaudeHookScript.script(url: urlPrefix + "hook", token: token)
        do {
            try fm.createDirectory(at: paths.supportDir, withIntermediateDirectories: true)
            try writeFile(Data(script.utf8), to: paths.wrapper, mode: 0o700)
            try writeFile(Data(hookScript.utf8), to: paths.hookScript, mode: 0o700)
        } catch { throw ClaudeInstallError.writeFailed("\(error)") }

        let mode = existed ? try fileMode(settingsURL) : 0o600
        try writeSettings(root, to: settingsURL, mode: mode)

        let state = ClaudeInstallState(
            token: token, port: port, statusLineCommand: wrapperCommand,
            previousStatusLine: previousStatusLine, createdEvents: createdEvents,
            createdHooksKey: createdHooksKey, createdSettingsFile: !existed,
            backupPath: backupPath, installedAt: isoString(now))
        do {
            try writeFile(try encoder().encode(state), to: paths.stateFile, mode: 0o600)
        } catch { throw ClaudeInstallError.writeFailed("\(error)") }
        return state
    }

    public static func uninstall(_ paths: ClaudeInstallPaths, now: Date) throws {
        let fm = FileManager.default
        guard let state = loadState(paths) else { throw ClaudeInstallError.notInstalled }

        let settingsURL = paths.settings.resolvingSymlinksInPath()
        if fm.fileExists(atPath: settingsURL.path) {
            let data: Data
            do { data = try Data(contentsOf: settingsURL) } catch {
                throw ClaudeInstallError.settingsUnreadable(error.localizedDescription)
            }
            var root: JSONValue
            do { root = try JSONText.parse(data) } catch {
                throw ClaudeInstallError.settingsUnreadable("\(error)")
            }
            guard case .object = root else { throw ClaudeInstallError.settingsNotObject }

            _ = try writeBackup(data, of: settingsURL, now: now)

            if let hooks = root["hooks"], case .object(let members) = hooks {
                var stripped = try stripLongDeckGroups(
                    hooks, hookCommand: StatusLineWrapper.shellQuote(paths.hookScript.path))
                for m in members {
                    if case .array(let a)? = stripped[m.key], a.isEmpty, state.createdEvents.contains(m.key) {
                        stripped = stripped.removing(m.key)
                    }
                }
                if case .object(let left) = stripped, left.isEmpty, state.createdHooksKey {
                    root = root.removing("hooks")
                } else {
                    root = root.setting("hooks", stripped)
                }
            }

            if root["statusLine"]?["command"] == .string(state.statusLineCommand) {
                if let prev = state.previousStatusLine {
                    do { root = root.setting("statusLine", try JSONText.parse(Data(prev.utf8))) } catch {
                        throw ClaudeInstallError.settingsUnreadable("\(error)")
                    }
                } else {
                    root = root.removing("statusLine")
                }
            }

            if state.createdSettingsFile, root == .object([]) {
                do { try fm.removeItem(at: settingsURL) } catch { throw ClaudeInstallError.writeFailed("\(error)") }
            } else {
                try writeSettings(root, to: settingsURL, mode: try fileMode(settingsURL))
            }
        }

        try? fm.removeItem(at: paths.wrapper)
        try? fm.removeItem(at: paths.hookScript)
        do { try fm.removeItem(at: paths.stateFile) } catch { throw ClaudeInstallError.writeFailed("\(error)") }
    }

    private static func hookGroup(command: String) throws -> JSONValue {
        let text = "{\"hooks\":[{\"type\":\"command\",\"command\":\(JSONText.compact(.string(command))),\"timeout\":2,\"onFailure\":\"continue\"}]}"
        return try JSONText.parse(Data(text.utf8))
    }

    private static func isLongDeckGroup(_ g: JSONValue, hookCommand: String) -> Bool {
        guard case .array(let hs)? = g["hooks"] else { return false }
        return hs.contains { h in
            if h["type"] == .string("command") { return h["command"] == .string(hookCommand) }
            // Earlier builds installed http hooks.
            guard h["type"] == .string("http"), case .string(let u)? = h["url"], u.hasPrefix(urlPrefix),
                  case .object? = h["headers"], h["headers"]?["X-LongDeck-Token"] != nil else { return false }
            return true
        }
    }

    private static func stripLongDeckGroups(_ hooks: JSONValue, hookCommand: String) throws -> JSONValue {
        guard case .object(let members) = hooks else { return hooks }
        return .object(members.map { m in
            guard case .array(let a) = m.value else { return m }
            return JSONMember(key: m.key, value: .array(a.filter { !isLongDeckGroup($0, hookCommand: hookCommand) }))
        })
    }

    private static func writeBackup(_ data: Data, of settings: URL, now: Date) throws -> URL {
        let fm = FileManager.default
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = settings.path + ".longdeck-" + f.string(from: now)
        var url = URL(fileURLWithPath: base + ".bak")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = URL(fileURLWithPath: "\(base)-\(n).bak")
            n += 1
        }
        do { try writeFile(data, to: url, mode: 0o600) } catch { throw ClaudeInstallError.writeFailed("\(error)") }
        return url
    }

    private static func writeFile(_ data: Data, to url: URL, mode: Int) throws {
        unlink(url.path)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(mode))
        guard fd >= 0 else { throw ClaudeInstallError.writeFailed(String(cString: strerror(errno))) }
        var failure: String?
        if fchmod(fd, mode_t(mode)) != 0 { failure = String(cString: strerror(errno)) }
        data.withUnsafeBytes { buf in
            var off = 0
            while failure == nil, off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n < 0 { failure = String(cString: strerror(errno)) } else { off += n }
            }
        }
        close(fd)
        if let failure {
            unlink(url.path)
            throw ClaudeInstallError.writeFailed(failure)
        }
    }

    private static func fileMode(_ url: URL) throws -> Int {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs[.posixPermissions] as? Int) ?? 0o600
        } catch { throw ClaudeInstallError.writeFailed("\(error)") }
    }

    private static func writeSettings(_ root: JSONValue, to url: URL, mode: Int) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).longdeck-\(UUID().uuidString).tmp")
        do {
            try writeFile(Data(JSONText.pretty(root).utf8), to: tmp, mode: mode)
        } catch let e as ClaudeInstallError {
            throw e
        } catch {
            throw ClaudeInstallError.writeFailed("\(error)")
        }
        if rename(tmp.path, url.path) != 0 {
            let msg = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: tmp)
            throw ClaudeInstallError.writeFailed(msg)
        }
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return e
    }

    private static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

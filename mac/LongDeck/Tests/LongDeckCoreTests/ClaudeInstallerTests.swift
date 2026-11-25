import Foundation
import Testing
@testable import LongDeckCore

private let token = String(repeating: "a", count: 64)
private let now = Date(timeIntervalSince1970: 1_795_534_200)  // 2026-11-24 15:30:00 UTC

private struct Env {
    let root: URL
    let settings: URL
    let support: URL
    var paths: ClaudeInstallPaths {
        precondition(settings.path.hasPrefix(root.path) && support.path.hasPrefix(root.path))
        return ClaudeInstallPaths(settings: settings, supportDir: support)
    }
    var state: URL { support.appendingPathComponent("claude-install.json") }
    var wrapper: URL { support.appendingPathComponent("statusline.sh") }
    var hookScript: URL { support.appendingPathComponent("hook.sh") }
    var hookCommand: String { StatusLineWrapper.shellQuote(hookScript.path) }
    var expectedGroup: String {
        "{\"hooks\":[{\"type\":\"command\",\"command\":\(JSONText.compact(.string(hookCommand))),\"timeout\":2,\"onFailure\":\"continue\"}]}"
    }
    func isLongDeckGroup(_ g: JSONValue) -> Bool {
        guard case .array(let hs)? = g["hooks"] else { return false }
        return hs.contains { h in
            if h["type"] == .string("command") { return h["command"] == .string(hookCommand) }
            return isLegacyHttpHook(h)
        }
    }
    func settingsText() throws -> String { try String(contentsOf: settings, encoding: .utf8) }
    func write(_ text: String) throws { try text.write(to: settings, atomically: true, encoding: .utf8) }
    func json() throws -> JSONValue { try JSONText.parse(Data(settingsText().utf8)) }
    func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".bak") }.sorted()
    }
}

private func makeEnv(settings text: String? = settingsFixture) throws -> Env {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
    let support = root.appendingPathComponent("support")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let env = Env(root: root, settings: root.appendingPathComponent("settings.json"), support: support)
    if let text { try env.write(text) }
    return env
}

private func isLegacyHttpHook(_ h: JSONValue) -> Bool {
    guard h["type"] == .string("http"), case .string(let u)? = h["url"], u.hasPrefix("http://127.0.0.1:47821/"),
          case .object? = h["headers"], h["headers"]?["X-LongDeck-Token"] != nil else { return false }
    return true
}

private func groups(_ v: JSONValue, _ event: String) -> [JSONValue] {
    guard case .array(let a)? = v["hooks"]?[event] else { return [] }
    return a
}

// Exactly what the http-hook build wrote.
private func legacyHttpGroup(_ tok: String) -> String {
    "{\"hooks\":[{\"type\":\"http\",\"url\":\"http://127.0.0.1:47821/hook\",\"headers\":{\"X-LongDeck-Token\":\"\(tok)\",\"X-Tmux-Pane\":\"$TMUX_PANE\"},\"allowedEnvVars\":[\"TMUX_PANE\"],\"timeout\":2,\"onFailure\":\"continue\"}]}"
}

private func parsed(_ text: String) throws -> JSONValue { try JSONText.parse(Data(text.utf8)) }

@Suite struct ClaudeInstallerTests {
    @Test func hookEventsIncludePostToolUseFailure() {
        #expect(ClaudeInstaller.hookEvents == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                               "PostToolUseFailure", "PermissionRequest", "Notification", "Stop",
                                               "SessionEnd", "SubagentStart", "SubagentStop"])
    }

    @Test func isCurrentNeedsSubagentHooks() throws {
        #expect(ClaudeInstaller.hookEvents.contains("SubagentStart"))
        #expect(ClaudeInstaller.hookEvents.contains("SubagentStop"))
        let env = try makeEnv(settings: "{}")
        #expect(!ClaudeInstaller.isCurrent(env.paths))
        let old = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                   "PermissionRequest", "Notification", "Stop", "SessionEnd"]
        let entries = old.map { "\"\($0)\":[\(env.expectedGroup)]" }.joined(separator: ",")
        try env.write("{\"hooks\":{\(entries)}}")
        #expect(!ClaudeInstaller.isCurrent(env.paths))
        try env.write("{}")
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        #expect(ClaudeInstaller.isCurrent(env.paths))
    }

    @Test func installAddsCommandHooksBesideExisting() throws {
        let env = try makeEnv()
        let before = try env.json()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let after = try env.json()
        for ev in ClaudeInstaller.hookEvents {
            let g = groups(after, ev)
            let existing = groups(before, ev)
            #expect(g.count == existing.count + 1)
            #expect(Array(g.dropLast()) == existing)
            #expect(g.last.map(JSONText.compact) == env.expectedGroup)
        }
        #expect(groups(before, "PostToolUseFailure").isEmpty)
        #expect(!JSONText.compact(after).contains(token))
        #expect(groups(after, "StopFailure") == groups(before, "StopFailure"))
        guard case .object(let b) = before, case .object(let a) = after else { Issue.record("not objects"); return }
        #expect(a.map(\.key) == b.map(\.key))
        for m in b where m.key != "hooks" && m.key != "statusLine" {
            #expect(JSONText.compact(after[m.key]!) == JSONText.compact(m.value))
        }
        let cmd = StatusLineWrapper.shellQuote(env.wrapper.path)
        #expect(JSONText.compact(after["statusLine"]!) ==
                "{\"type\":\"command\",\"command\":\(JSONText.compact(.string(cmd))),\"padding\":0,\"refreshInterval\":10}")
    }

    @Test func installWritesBackupFirst() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let name = "settings.json.longdeck-20261124-153000.bak"
        #expect(try env.backups() == [name])
        let data = try Data(contentsOf: env.root.appendingPathComponent(name))
        #expect(data == Data(settingsFixture.utf8))
        let mode = try FileManager.default.attributesOfItem(atPath: env.root.appendingPathComponent(name).path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        try ClaudeInstaller.uninstall(env.paths, now: now)
        #expect(try env.backups().contains("settings.json.longdeck-20261124-153000-2.bak"))
    }

    @Test func wrapperRunsPreviousCommand() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let mode = try FileManager.default.attributesOfItem(atPath: env.wrapper.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
        let text = try String(contentsOf: env.wrapper, encoding: .utf8)
        #expect(text.contains("/bin/sh -c 'ccstatusline'"))
        #expect(text.contains("http://127.0.0.1:47821/statusline"))
    }

    @Test func hookScriptWrittenOwnerOnly() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let mode = try FileManager.default.attributesOfItem(atPath: env.hookScript.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
        let text = try String(contentsOf: env.hookScript, encoding: .utf8)
        #expect(text == ClaudeHookScript.script(url: "http://127.0.0.1:47821/hook", token: token))
    }

    @Test func stateRecordsOriginal() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let st = try #require(ClaudeInstaller.loadState(env.paths))
        #expect(st.previousStatusLine == "{\"type\":\"command\",\"command\":\"ccstatusline\",\"padding\":0,\"refreshInterval\":10}")
        #expect(st.createdEvents == ["PostToolUseFailure", "SubagentStart"])
        #expect(st.token == token)
        #expect(st.port == 47821)
        #expect(!st.createdHooksKey)
        #expect(!st.createdSettingsFile)
        let mode = try FileManager.default.attributesOfItem(atPath: env.state.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func uninstallRestoresExactly() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        try ClaudeInstaller.uninstall(env.paths, now: now)
        #expect(try env.settingsText() == settingsFixture)
        #expect(!FileManager.default.fileExists(atPath: env.wrapper.path))
        #expect(!FileManager.default.fileExists(atPath: env.hookScript.path))
        #expect(!FileManager.default.fileExists(atPath: env.state.path))
    }

    @Test func uninstallKeepsLaterUserEdits() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        var v = try env.json()
        let mine = [
            "{\"hooks\":[{\"type\":\"command\",\"command\":\"mine\"}]}",
            "{\"hooks\":[{\"type\":\"command\",\"command\":\(JSONText.compact(.string(env.hookCommand + " --x")))}]}",
            "{\"hooks\":[{\"type\":\"command\",\"command\":\(JSONText.compact(.string(env.hookScript.path)))}]}",
        ]
        let stop = groups(v, "Stop") + (try mine.map(parsed))
        v = v.setting("hooks", v["hooks"]!.setting("Stop", .array(stop)))
        v = v.setting("theme", .string("light")).setting("newKey", .number("1"))
        try env.write(JSONText.pretty(v))
        try ClaudeInstaller.uninstall(env.paths, now: now)
        let after = try env.json()
        #expect(after["theme"] == .string("light"))
        #expect(after["newKey"] == .number("1"))
        #expect(groups(after, "Stop").count == 4)
        #expect(groups(after, "Stop").suffix(3).map(JSONText.compact) == mine)
        for ev in ClaudeInstaller.hookEvents { #expect(!groups(after, ev).contains(where: env.isLongDeckGroup)) }
        #expect(after["statusLine"]?["command"] == .string("ccstatusline"))
    }

    @Test func uninstallRemovesLegacyHttpGroups() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        var v = try env.json()
        for ev in ["Stop", "SessionEnd", "PostToolUseFailure"] {
            v = v.setting("hooks", v["hooks"]!.setting(ev, .array(groups(v, ev) + [try parsed(legacyHttpGroup("old"))])))
        }
        try env.write(JSONText.pretty(v))
        try ClaudeInstaller.uninstall(env.paths, now: now)
        #expect(try env.settingsText() == settingsFixture)
    }

    @Test func uninstallOfHttpBuildInstallRestoresExactly() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        var v = try parsed(settingsFixture)
        let oldEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "PermissionRequest", "Notification", "Stop", "SessionEnd"]
        for ev in oldEvents {
            v = v.setting("hooks", v["hooks"]!.setting(ev, .array(groups(v, ev) + [try parsed(legacyHttpGroup(token))])))
        }
        v = v.setting("statusLine", v["statusLine"]!.setting("command", .string(StatusLineWrapper.shellQuote(env.wrapper.path))))
        try env.write(JSONText.pretty(v))
        var st = try #require(ClaudeInstaller.loadState(env.paths))
        st.createdEvents = []
        try JSONEncoder().encode(st).write(to: env.state)
        try FileManager.default.removeItem(at: env.hookScript)
        try ClaudeInstaller.uninstall(env.paths, now: now)
        #expect(try env.settingsText() == settingsFixture)
        #expect(!FileManager.default.fileExists(atPath: env.state.path))
    }

    @Test func uninstallLeavesChangedStatusLine() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        var v = try env.json()
        v = v.setting("statusLine", v["statusLine"]!.setting("command", .string("other")))
        try env.write(JSONText.pretty(v))
        try ClaudeInstaller.uninstall(env.paths, now: now)
        #expect(try env.json()["statusLine"]?["command"] == .string("other"))
    }

    @Test func installIntoEmptyAndMissingFiles() throws {
        let env = try makeEnv(settings: "{}\n")
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let v = try env.json()
        for ev in ClaudeInstaller.hookEvents { #expect(groups(v, ev).count == 1) }
        #expect(v["statusLine"]?["padding"] == .number("0"))
        let st = try #require(ClaudeInstaller.loadState(env.paths))
        #expect(st.createdHooksKey)
        #expect(st.createdEvents.sorted() == ClaudeInstaller.hookEvents.sorted())
        #expect(st.previousStatusLine == nil)
        try ClaudeInstaller.uninstall(env.paths, now: now)
        #expect(try env.settingsText() == "{}\n")

        let missing = try makeEnv(settings: nil)
        try ClaudeInstaller.install(missing.paths, token: token, now: now)
        #expect(FileManager.default.fileExists(atPath: missing.settings.path))
        #expect(try missing.backups().isEmpty)
        let wrapper = try String(contentsOf: missing.wrapper, encoding: .utf8)
        #expect(!wrapper.contains("/bin/sh -c"))
        try ClaudeInstaller.uninstall(missing.paths, now: now)
        #expect(!FileManager.default.fileExists(atPath: missing.settings.path))
        #expect(!FileManager.default.fileExists(atPath: missing.hookScript.path))
    }

    @Test func installTwiceRefused() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let snapshot = try env.settingsText()
        #expect(throws: ClaudeInstallError.alreadyInstalled) {
            try ClaudeInstaller.install(env.paths, token: token, now: now)
        }
        #expect(try env.settingsText() == snapshot)
    }

    @Test func staleGroupsReplaced() throws {
        let env = try makeEnv(settings: nil)
        try env.write("{\"hooks\":{\"Stop\":[\(legacyHttpGroup("old"))],\"PreToolUse\":[\(env.expectedGroup)]}}\n")
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let v = try env.json()
        for ev in ClaudeInstaller.hookEvents {
            #expect(groups(v, ev).filter(env.isLongDeckGroup).count == 1)
            #expect(groups(v, ev).last.map(JSONText.compact) == env.expectedGroup)
        }
        #expect(groups(v, "Stop").count == 1)
        #expect(groups(v, "PreToolUse").count == 1)
    }

    @Test func invalidSettingsRefused() throws {
        for (text, expected) in [("{", 0), ("[]", 1)] {
            let env = try makeEnv(settings: text)
            do {
                try ClaudeInstaller.install(env.paths, token: token, now: now)
                Issue.record("expected throw")
            } catch let e as ClaudeInstallError {
                switch (e, expected) {
                case (.settingsUnreadable, 0), (.settingsNotObject, 1): break
                default: Issue.record("wrong error \(e)")
                }
            }
            #expect(try env.settingsText() == text)
            #expect(try env.backups().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: env.wrapper.path))
            #expect(!FileManager.default.fileExists(atPath: env.hookScript.path))
            #expect(!FileManager.default.fileExists(atPath: env.state.path))
        }
    }

    @Test func badHooksShapeLeavesNoBackup() throws {
        for text in ["{\"hooks\":[]}\n", "{\"hooks\":{\"Stop\":{}}}\n"] {
            let env = try makeEnv(settings: text)
            #expect(throws: ClaudeInstallError.self) {
                try ClaudeInstaller.install(env.paths, token: token, now: now)
            }
            #expect(try env.settingsText() == text)
            #expect(try env.backups().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: env.wrapper.path))
            #expect(!FileManager.default.fileExists(atPath: env.hookScript.path))
            #expect(!FileManager.default.fileExists(atPath: env.state.path))
        }
    }

    @Test func createdFilesAreOwnerOnlyAfterCall() throws {
        let env = try makeEnv(settings: nil)
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        func mode(_ u: URL) throws -> Int? {
            try FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int
        }
        #expect(try mode(env.settings) == 0o600)
        #expect(try mode(env.state) == 0o600)
        #expect(try mode(env.wrapper) == 0o700)
        #expect(try mode(env.hookScript) == 0o700)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: env.root.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test func wrapperWithoutStateRefused() throws {
        let env = try makeEnv(settings: "{\"statusLine\":{\"type\":\"command\",\"command\":\"x\"}}\n")
        let quoted = StatusLineWrapper.shellQuote(env.wrapper.path)
        try env.write(JSONText.pretty(.object([JSONMember(key: "statusLine", value:
            .object([JSONMember(key: "type", value: .string("command")),
                     JSONMember(key: "command", value: .string(quoted))]))])))
        let snapshot = try env.settingsText()
        #expect(throws: ClaudeInstallError.wrapperWithoutState) {
            try ClaudeInstaller.install(env.paths, token: token, now: now)
        }
        #expect(try env.settingsText() == snapshot)
        #expect(try env.backups().isEmpty)
    }

    @Test func uninstallWithoutStateRefused() throws {
        let env = try makeEnv()
        #expect(throws: ClaudeInstallError.notInstalled) {
            try ClaudeInstaller.uninstall(env.paths, now: now)
        }
    }

    @Test func settingsSymlinkFollowed() throws {
        let env = try makeEnv(settings: nil)
        let real = env.root.appendingPathComponent("real.json")
        try settingsFixture.write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: env.settings, withDestinationURL: real)
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: env.settings.path)
        #expect(dest == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8) != settingsFixture)
    }

    @Test func fileModeKept() throws {
        let env = try makeEnv()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: env.settings.path)
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let mode = try FileManager.default.attributesOfItem(atPath: env.settings.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
}

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

private func isLongDeckGroup(_ g: JSONValue) -> Bool {
    guard case .array(let hs)? = g["hooks"] else { return false }
    return hs.contains { h in
        guard h["type"] == .string("http"), case .string(let u)? = h["url"], u.hasPrefix("http://127.0.0.1:47821/"),
              case .object? = h["headers"], h["headers"]?["X-LongDeck-Token"] != nil else { return false }
        return true
    }
}

private func groups(_ v: JSONValue, _ event: String) -> [JSONValue] {
    guard case .array(let a)? = v["hooks"]?[event] else { return [] }
    return a
}

private let expectedGroup =
    "{\"hooks\":[{\"type\":\"http\",\"url\":\"http://127.0.0.1:47821/hook\",\"headers\":{\"X-LongDeck-Token\":\"\(token)\",\"X-Tmux-Pane\":\"$TMUX_PANE\"},\"allowedEnvVars\":[\"TMUX_PANE\"],\"timeout\":2,\"onFailure\":\"continue\"}]}"

@Suite struct ClaudeInstallerTests {
    @Test func installAddsHttpHooksBesideExisting() throws {
        let env = try makeEnv()
        let before = try env.json()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let after = try env.json()
        for ev in ClaudeInstaller.hookEvents {
            let g = groups(after, ev)
            #expect(g.count == 2)
            #expect(g.first == groups(before, ev).first)
            #expect(g.last.map(JSONText.compact) == expectedGroup)
        }
        for ev in ["StopFailure", "SubagentStop"] {
            #expect(groups(after, ev) == groups(before, ev))
        }
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

    @Test func stateRecordsOriginal() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let st = try #require(ClaudeInstaller.loadState(env.paths))
        #expect(st.previousStatusLine == "{\"type\":\"command\",\"command\":\"ccstatusline\",\"padding\":0,\"refreshInterval\":10}")
        #expect(st.createdEvents.isEmpty)
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
        #expect(!FileManager.default.fileExists(atPath: env.state.path))
    }

    @Test func uninstallKeepsLaterUserEdits() throws {
        let env = try makeEnv()
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        var v = try env.json()
        let stop = groups(v, "Stop") + [try JSONText.parse(Data("{\"hooks\":[{\"type\":\"command\",\"command\":\"mine\"}]}".utf8))]
        v = v.setting("hooks", v["hooks"]!.setting("Stop", .array(stop)))
        v = v.setting("theme", .string("light")).setting("newKey", .number("1"))
        try env.write(JSONText.pretty(v))
        try ClaudeInstaller.uninstall(env.paths, now: now)
        let after = try env.json()
        #expect(after["theme"] == .string("light"))
        #expect(after["newKey"] == .number("1"))
        #expect(groups(after, "Stop").count == 2)
        #expect(groups(after, "Stop").last.map(JSONText.compact) == "{\"hooks\":[{\"type\":\"command\",\"command\":\"mine\"}]}")
        for ev in ClaudeInstaller.hookEvents { #expect(!groups(after, ev).contains(where: isLongDeckGroup)) }
        #expect(after["statusLine"]?["command"] == .string("ccstatusline"))
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
        let env = try makeEnv(settings: "{\"hooks\":{\"Stop\":[\(expectedGroup.replacingOccurrences(of: token, with: "old"))]}}\n")
        try ClaudeInstaller.install(env.paths, token: token, now: now)
        let v = try env.json()
        for ev in ClaudeInstaller.hookEvents {
            #expect(groups(v, ev).filter(isLongDeckGroup).count == 1)
        }
        #expect(groups(v, "Stop").count == 1)
        #expect(groups(v, "Stop").first.map(JSONText.compact) == expectedGroup)
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
            #expect(!FileManager.default.fileExists(atPath: env.state.path))
        }
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

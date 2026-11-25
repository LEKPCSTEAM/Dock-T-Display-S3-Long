import Foundation
import Testing
@testable import LongDeckCore

private let t0: TimeInterval = 5000
private let wall0 = Date(timeIntervalSince1970: 1_795_519_000)

private func event(_ id: String, _ name: String, tool: String? = nil, agent: String? = nil, at s: TimeInterval,
                   into store: inout ClaudeStore) {
    store.apply(ClaudeHookEvent(sessionId: id, event: name, toolName: tool, agentId: agent), pane: nil,
                now: t0 + s, wall: wall0.addingTimeInterval(s))
}

private func status(_ id: String, ctx: Double? = nil, dir: String? = nil, at s: TimeInterval,
                    into store: inout ClaudeStore) {
    store.apply(ClaudeStatusUpdate(sessionId: id, contextPct: ctx, projectDir: dir), pane: nil, now: t0 + s)
}

private func rows(_ store: ClaudeStore, wall s: TimeInterval = 0) throws -> [[String: Any]] {
    let body = store.body(now: wall0.addingTimeInterval(s))
    let root = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
    return try #require(root["sessions"] as? [[String: Any]])
}

private func total(_ store: ClaudeStore, wall s: TimeInterval = 0) throws -> Int {
    let body = store.body(now: wall0.addingTimeInterval(s))
    let root = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
    return try #require(root["agents_total"] as? Int)
}

@Suite struct ClaudeAgentsStoreTests {
    @Test func tmuxFlagFollowsTmuxSessionNames() throws {
        var store = ClaudeStore(runTag: "t")
        event("s1", "SessionStart", at: 0, into: &store)
        store.setName("Caltera", forSession: "s1")
        store.history.record(name: "Old", project: "old", endedAt: wall0.timeIntervalSince1970 - 5)
        var flags = try rows(store).reduce(into: [String: Bool]()) { $0[$1["id"] as! String] = $1["tmux"] as? Bool }
        #expect(flags == ["s1": false, "h:Old": false])
        store.tmuxSessions = ["Caltera", "Old"]
        flags = try rows(store).reduce(into: [String: Bool]()) { $0[$1["id"] as! String] = $1["tmux"] as? Bool }
        #expect(flags == ["s1": true, "h:Old": true])
    }

    @Test func rowCarriesAgentFields() throws {
        var store = ClaudeStore(runTag: "t")
        event("s1", "SessionStart", at: 0, into: &store)
        store.setName("CMM iOS", forSession: "s1")
        status("s1", ctx: 98, dir: "/w/cmm", at: 1, into: &store)
        event("s1", "PreToolUse", tool: "Bash", at: 10, into: &store)
        let row = try #require(try rows(store, wall: 20).first)
        #expect(row["name"] as? String == "CMM iOS")
        #expect(row["tool"] as? String == "bash")
        #expect(row["agents"] as? Int == 0)
        #expect(row["ctx"] as? Int == 98)
        #expect(row["since"] as? Int == Int(wall0.timeIntervalSince1970) + 10)
        #expect(row["live"] as? Bool == true)
        let hat = AgentHat.of("CMM iOS")
        #expect(row["hat"] as? Int == hat.hat)
        #expect(row["tint"] as? Int == hat.tint)
    }

    @Test func nameFallsBackToProject() throws {
        var store = ClaudeStore(runTag: "t")
        event("s1", "SessionStart", at: 0, into: &store)
        status("s1", dir: "/w/caltera", at: 1, into: &store)
        let row = try #require(try rows(store).first)
        #expect(row["name"] as? String == "caltera")
    }

    @Test func subagentCountingRules() throws {
        var store = ClaudeStore(runTag: "t")
        event("s1", "UserPromptSubmit", at: 0, into: &store)
        event("s1", "SubagentStart", agent: "a", at: 1, into: &store)
        event("s1", "SubagentStart", agent: "b", at: 2, into: &store)
        event("s1", "SubagentStop", agent: "a", at: 3, into: &store)
        #expect(try rows(store, wall: 4).first?["agents"] as? Int == 1)
        event("s1", "SubagentStop", agent: "c", at: 5, into: &store)
        #expect(try rows(store, wall: 6).first?["agents"] as? Int == 1)
        #expect(try total(store, wall: 6) == 2)

        #expect(try rows(store, wall: 2 + 7201).first?["agents"] as? Int == 0)

        event("s1", "SessionEnd", at: 7, into: &store)
        #expect(try rows(store, wall: 8).allSatisfy { $0["live"] as? Bool == false })
        #expect(try total(store, wall: 8) == 0)
    }

    @Test func agentsTotalCountsWorkingAndSubagents() throws {
        var store = ClaudeStore(runTag: "t")
        event("w1", "UserPromptSubmit", at: 0, into: &store)
        event("w2", "UserPromptSubmit", at: 1, into: &store)
        event("d1", "Stop", at: 2, into: &store)
        event("d1", "SubagentStart", agent: "x", at: 3, into: &store)
        event("d1", "SubagentStart", agent: "y", at: 4, into: &store)
        #expect(try total(store, wall: 5) == 4)
    }

    @Test func needyRowsSurviveCap() throws {
        var store = ClaudeStore(runTag: "t")
        for i in 0..<30 { event("w\(i)", "UserPromptSubmit", at: Double(i), into: &store) }
        event("perm", "PermissionRequest", tool: "Bash", at: 40, into: &store)
        event("wait", "SessionStart", at: 41, into: &store)
        let list = try rows(store, wall: 50)
        #expect(list.count == 24)
        #expect(list[0]["id"] as? String == "perm")
        #expect(list[1]["id"] as? String == "wait")
    }

    @Test func namesCutAtGraphemes() throws {
        var store = ClaudeStore(runTag: "t")
        let long = "โปรเจกต์ทดสอบภาษาไทย👍🏽"
        event("s1", "SessionStart", at: 0, into: &store)
        store.setName(long, forSession: "s1")
        let name = try #require(try rows(store).first?["name"] as? String)
        #expect(name.utf8.count <= 23)
        #expect(long.hasPrefix(name))
        #expect(!name.isEmpty)
        // A cut inside a grapheme would leave the next original character glued to this one.
        #expect(Array(long).starts(with: Array(name)))
    }

    @Test func permissionRowShowsPendingTool() throws {
        var store = ClaudeStore(runTag: "t")
        event("s1", "PreToolUse", tool: "Bash", at: 0, into: &store)
        event("s1", "PermissionRequest", tool: "Edit", at: 1, into: &store)
        #expect(try rows(store, wall: 2).first?["tool"] as? String == "edit")
    }

    @Test func hatIsStable() {
        let first = AgentHat.of("Agents Deck")
        #expect(AgentHat.of("Agents Deck") == first)
        #expect((0..<8).contains(first.hat))
        #expect((0..<8).contains(first.tint))
        #expect(first == (hat: 0, tint: 6))
    }
}

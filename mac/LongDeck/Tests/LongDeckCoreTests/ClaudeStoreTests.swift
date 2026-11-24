import Foundation
import Testing
@testable import LongDeckCore

private let c1 = #"{"prompt":{"pending":1,"project":"T-Display-S3-Long","request":"a3f9-1","session":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42","summary":"pio run -e ntp_clock","tmux":true,"tool":"Bash"},"sessions":[{"cost_cents":142,"ctx":37,"id":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42","model":"Opus 5.5","project":"T-Display-S3-Long","state":"permission","tmux":true},{"cost_cents":-1,"ctx":-1,"id":"9b2d7e00-1111-4222-8333-444455556666","model":"","project":"caltera","state":"working","tmux":false}],"usage":{"five_hour":{"pct":42,"resets_at":1795530000},"seven_day":{"pct":13,"resets_at":1795900000}}}"#
private let c2 = #"{"prompt":null,"sessions":[],"usage":{"five_hour":null,"seven_day":null}}"#
private let t0 = Date(timeIntervalSince1970: 1795519000)

private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private func feed(_ store: inout ClaudeStore, _ data: Data, pane: String? = nil, at now: Date) {
    store.apply(ClaudeHookEvent.decode(data)!, pane: pane, now: now)
}

private func check(_ store: inout ClaudeStore, _ request: String, _ visible: Bool, _ s: TimeInterval) -> Bool {
    store.promptCheck(session: claudeA, request: request, visible: visible, now: at(s))
}

private func json(_ body: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
}

@Suite struct ClaudeStoreTests {
    @Test func bodyMatchesC1() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk0, pane: "%37", at: t0)
        store.apply(ClaudeStatusUpdate.decode(sl1)!, pane: nil, now: at(10))
        feed(&store, hkB, at: at(20))
        feed(&store, hk1, pane: "%37", at: at(30))
        #expect(store.body(now: Date(timeIntervalSince1970: 1795520000)) == c1)
    }

    @Test func bodyMatchesC2() {
        #expect(ClaudeStore(runTag: "a3f9").body(now: t0) == c2)
    }

    @Test func stateTransitionsFollowSpec() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk0, at: at(0))
        #expect(store.sessions[claudeA]?.state == .waiting)
        feed(&store, hookJSON(claudeA, "UserPromptSubmit"), at: at(1))
        #expect(store.sessions[claudeA]?.state == .working)
        feed(&store, hookJSON(claudeA, "PreToolUse", extra: hk1Extra), at: at(2))
        #expect(store.sessions[claudeA]?.state == .working)
        feed(&store, hk1, at: at(3))
        #expect(store.sessions[claudeA]?.state == .permission)
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-1")
        #expect(store.sessions[claudeA]?.stateSince == at(3))
        feed(&store, hk2, at: at(4))
        #expect(store.sessions[claudeA]?.state == .working)
        #expect(store.sessions[claudeA]?.pending == nil)
        feed(&store, hk4, at: at(5))
        #expect(store.sessions[claudeA]?.state == .permission)
        #expect(store.sessions[claudeA]?.pending == nil)
        feed(&store, hk3, at: at(6))
        #expect(store.sessions[claudeA]?.state == .waiting)
        feed(&store, hookJSON(claudeA, "Stop"), at: at(7))
        #expect(store.sessions[claudeA]?.state == .done)
        feed(&store, hookJSON(claudeA, "SessionEnd"), at: at(8))
        #expect(store.sessions[claudeA] == nil)
    }

    @Test func preToolUseKeepsPendingPrompt() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        feed(&store, hookJSON(claudeA, "PreToolUse", extra: #","tool_name":"Bash","tool_input":{"command":"ls"}"#), at: at(1))
        #expect(store.sessions[claudeA]?.state == .permission)
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-1")
    }

    @Test func postToolUseForOtherCallKeepsPrompt() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        feed(&store, hookJSON(claudeA, "PostToolUse", extra: #","tool_name":"Bash","tool_input":{"command":"ls"}"#), at: at(1))
        #expect(store.sessions[claudeA]?.state == .permission)
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-1")
    }

    @Test func eachPermissionRequestGetsNewId() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        feed(&store, hk1, at: at(1))
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-2")
        #expect(store.pendingPrompts().count == 1)
    }

    @Test func promptClearedByPromptStopAndIdle() {
        for clear in [hookJSON(claudeA, "UserPromptSubmit"), hookJSON(claudeA, "Stop"), hk3] {
            var store = ClaudeStore(runTag: "a3f9")
            feed(&store, hk1, at: at(0))
            feed(&store, clear, at: at(1))
            #expect(store.sessions[claudeA]?.pending == nil)
        }
    }

    @Test func paneKeptWhenLaterEventHasNone() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk0, pane: "%37", at: at(0))
        feed(&store, hk3, at: at(1))
        #expect(store.sessions[claudeA]?.pane == "%37")
    }

    @Test func silentSessionsDropped() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk0, at: t0)
        store.expire(now: at(1800))
        #expect(store.sessions[claudeA] != nil)
        store.expire(now: at(1801))
        #expect(store.sessions[claudeA] == nil)
    }

    @Test func statusLineCreatesSessionAndKeepsUsage() {
        var store = ClaudeStore(runTag: "a3f9")
        store.apply(ClaudeStatusUpdate.decode(sl1)!, pane: nil, now: t0)
        #expect(store.sessions[claudeA]?.state == .waiting)
        #expect(store.fiveHour == UsageWindow(pct: 42.2, resetsAt: 1795530000))
        store.apply(ClaudeStatusUpdate.decode(sl2)!, pane: nil, now: at(5))
        #expect(store.fiveHour == UsageWindow(pct: 42.2, resetsAt: 1795530000))
        #expect(store.sevenDay == UsageWindow(pct: 12.6, resetsAt: 1795900000))
    }

    @Test func usageWindowDroppedAfterReset() {
        var store = ClaudeStore(runTag: "a3f9")
        store.apply(ClaudeStatusUpdate.decode(sl1)!, pane: nil, now: t0)
        store.expire(now: Date(timeIntervalSince1970: 1795530000))
        #expect(store.fiveHour == nil)
        #expect(store.sevenDay != nil)
    }

    @Test func bodySortsAndCapsSessions() throws {
        var store = ClaudeStore(runTag: "a3f9")
        let ids = (0..<10).map { "s\($0)" }
        let plan: [(String, String)] = [
            ("UserPromptSubmit", ""), ("Stop", ""), ("SessionStart", ""), ("UserPromptSubmit", ""),
            ("PermissionRequest", hk1Extra), ("Stop", ""), ("SessionStart", ""), ("UserPromptSubmit", ""),
            ("Stop", ""), ("PermissionRequest", hk1Extra),
        ]
        for (i, id) in ids.enumerated() {
            feed(&store, hookJSON(id, plan[i].0, extra: plan[i].1), at: at(TimeInterval(i)))
        }
        let sessions = try #require(try json(store.body(now: t0))["sessions"] as? [[String: Any]])
        let got = sessions.map { $0["id"] as! String }
        #expect(got == ["s9", "s4", "s6", "s2", "s8", "s5", "s1", "s7"])
    }

    @Test func bodyWorstCaseFitsBoard() throws {
        var store = ClaudeStore(runTag: "a3f9")
        let noisy = String(repeating: #"\""#, count: 30)
        for i in 0..<8 {
            let id = String(format: "%039d", i)
            let dir = #"/x/\#(String(repeating: #"\""#, count: 30))"#
            let update = ClaudeStatusUpdate(sessionId: id, model: String(repeating: #"""#, count: 30),
                                            costUSD: 123.45, contextPct: 99.6, projectDir: dir)
            store.apply(update, pane: "%1", now: at(TimeInterval(i)))
        }
        let command = String(repeating: #"\""#, count: 300)
        let input = try JSONSerialization.data(withJSONObject: ["command": command])
        let extra = #","tool_name":"Bash","tool_input":"# + String(decoding: input, as: UTF8.self)
        feed(&store, hookJSON(String(format: "%039d", 0), "PermissionRequest", extra: extra), at: at(20))
        let body = store.body(now: t0)
        #expect(body.utf8.count <= 4096)
        let parsed = try json(body)
        #expect((parsed["sessions"] as? [Any])?.count == 8)
        #expect(!noisy.isEmpty)
    }

    @Test func promptIsOldestPendingWithCount() throws {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hookJSON(claudeB, "PermissionRequest", extra: hk1Extra), at: at(0))
        feed(&store, hk1, at: at(5))
        let prompt = try #require(try json(store.body(now: t0))["prompt"] as? [String: Any])
        #expect(prompt["session"] as? String == claudeB)
        #expect(prompt["pending"] as? Int == 2)
    }

    @Test func promptCheckClearsAfterTwoMissesWhenSeen() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        #expect(!check(&store, "a3f9-1", true, 1))
        #expect(!check(&store, "a3f9-1", false, 2))
        #expect(check(&store, "a3f9-1", false, 3))
        #expect(store.sessions[claudeA]?.pending == nil)
        #expect(store.sessions[claudeA]?.state == .working)
    }

    @Test func promptCheckGraceBeforeFirstSeen() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        #expect(!check(&store, "a3f9-1", false, 1))
        #expect(!check(&store, "a3f9-1", false, 2))
        #expect(store.sessions[claudeA]?.pending != nil)
        #expect(check(&store, "a3f9-1", false, 6))
        #expect(store.sessions[claudeA]?.pending == nil)
    }

    @Test func promptCheckIgnoresOtherRequest() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        for i in 1...3 {
            #expect(!check(&store, "a3f9-0", false, TimeInterval(10 * i)))
        }
        #expect(store.sessions[claudeA]?.pending?.misses == 0)
    }

    @Test func resolveNeedsCurrentRequest() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        store.resolve(session: claudeA, request: "a3f9-0", state: .waiting, now: at(1))
        #expect(store.sessions[claudeA]?.state == .permission)
        store.resolve(session: claudeA, request: "a3f9-1", state: .waiting, now: at(2))
        #expect(store.sessions[claudeA]?.state == .waiting)
        #expect(store.sessions[claudeA]?.pending == nil)
    }
}

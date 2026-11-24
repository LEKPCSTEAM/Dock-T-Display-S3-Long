import Foundation
import Testing
@testable import LongDeckCore

private let c1 = #"{"prompt":{"pending":1,"project":"T-Display-S3-Long","request":"a3f9-1","session":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42","summary":"pio run -e ntp_clock","tmux":true,"tool":"Bash"},"sessions":[{"cost_cents":142,"ctx":37,"id":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42","model":"Opus 5.5","project":"T-Display-S3-Long","state":"permission","tmux":true},{"cost_cents":-1,"ctx":-1,"id":"9b2d7e00-1111-4222-8333-444455556666","model":"","project":"caltera","state":"working","tmux":false}],"usage":{"five_hour":{"pct":42,"resets_at":1795530000},"seven_day":{"pct":13,"resets_at":1795900000}}}"#
private let c2 = #"{"prompt":null,"sessions":[],"usage":{"five_hour":null,"seven_day":null}}"#
private let t0: TimeInterval = 5000
private let wall0 = Date(timeIntervalSince1970: 1795519000)

private func at(_ s: TimeInterval) -> TimeInterval { t0 + s }

private func feed(_ store: inout ClaudeStore, _ data: Data, pane: String? = nil, at now: TimeInterval) {
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
        #expect(ClaudeStore(runTag: "a3f9").body(now: wall0) == c2)
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
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-1")
        #expect(store.pendingPrompts().count == 1)
        store.resolve(session: claudeA, request: "a3f9-1", state: .working, now: at(2))
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-2")
    }

    @Test func pendingRequestsQueueOldestFirst() {
        let ls = #","tool_name":"Bash","tool_input":{"command":"ls"}"#
        let pwd = #","tool_name":"Bash","tool_input":{"command":"pwd"}"#
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, pane: "%37", at: at(0))
        feed(&store, hookJSON(claudeA, "PermissionRequest", extra: ls), at: at(1))
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-1")
        #expect(store.pendingPrompts().map(\.pending.request) == ["a3f9-1"])
        feed(&store, hookJSON(claudeA, "PostToolUse", extra: ls), at: at(2))
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-1")
        #expect(store.sessions[claudeA]?.state == .permission)
        feed(&store, hookJSON(claudeA, "PermissionRequest", extra: pwd), at: at(3))
        store.resolve(session: claudeA, request: "a3f9-1", state: .working, now: at(4))
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-3")
        #expect(store.sessions[claudeA]?.state == .permission)
        feed(&store, hookJSON(claudeA, "PostToolUse", extra: pwd), at: at(5))
        #expect(store.sessions[claudeA]?.pending == nil)
        #expect(store.sessions[claudeA]?.state == .working)
    }

    @Test func targetFlagsLookAlikeQueuedRequests() throws {
        let described = #","tool_name":"Bash","tool_input":{"command":"npm test","description":"rm -rf ~"}"#
        let twoLines = #","tool_name":"Bash","tool_input":{"command":"npm test\nrm -rf ~"}"#
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hookJSON(claudeA, "PermissionRequest", extra: described), pane: "%37", at: at(0))
        feed(&store, hookJSON(claudeA, "PermissionRequest", extra: twoLines), at: at(1))
        let t = try #require(store.target(session: claudeA))
        #expect(t.ambiguous)
        #expect(t.pendingRequest == "a3f9-1")
        #expect(t.pane == "%37")
        #expect(t.cwd == claudeCwd)
        #expect(t.toolName == "Bash")
        #expect(store.sessions[claudeA]?.pendingCount == 2)

        var distinct = ClaudeStore(runTag: "a3f9")
        feed(&distinct, hk1, at: at(0))
        feed(&distinct, hookJSON(claudeA, "PermissionRequest", extra: #","tool_name":"Bash","tool_input":{"command":"ls"}"#), at: at(1))
        #expect(distinct.target(session: claudeA)?.ambiguous == false)

        var duplicate = ClaudeStore(runTag: "a3f9")
        feed(&duplicate, hk1, at: at(0))
        feed(&duplicate, hk1, at: at(1))
        #expect(duplicate.target(session: claudeA)?.ambiguous == false)
        #expect(duplicate.target(session: claudeB) == nil)
    }

    @Test func lookAlikeIgnoresWhitespace() {
        func ambiguous(_ head: String, _ other: String) -> Bool? {
            var store = ClaudeStore(runTag: "a3f9")
            for command in [head, other] {
                let input = String(decoding: try! JSONSerialization.data(withJSONObject: ["command": command]), as: UTF8.self)
                feed(&store, hookJSON(claudeA, "PermissionRequest", extra: #","tool_name":"Bash","tool_input":"# + input), at: at(0))
            }
            return store.target(session: claudeA)?.ambiguous
        }
        #expect(ambiguous("echo a b", "echo a\nb") == true)
        #expect(ambiguous("echo a b", "echo ab") == true)
        #expect(ambiguous("echo a  b", "echo a b") == true)
        #expect(ambiguous("echo a b", "echo a c") == false)
    }

    @Test func queueIsCapped() {
        var store = ClaudeStore(runTag: "a3f9")
        for i in 0..<20 {
            let extra = #","tool_name":"Bash","tool_input":{"command":"echo \#(i)"}"#
            feed(&store, hookJSON(claudeA, "PermissionRequest", extra: extra), at: at(TimeInterval(i)))
        }
        #expect(store.sessions[claudeA]?.pendingCount == 16)
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-1")
        #expect(store.sessions[claudeA]?.queue.last?.request == "a3f9-16")
    }

    @Test func promptCheckAdvancesQueue() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        feed(&store, hookJSON(claudeA, "PermissionRequest", extra: #","tool_name":"Bash","tool_input":{"command":"ls"}"#), at: at(1))
        #expect(!check(&store, "a3f9-1", true, 2))
        #expect(!check(&store, "a3f9-1", false, 3))
        #expect(check(&store, "a3f9-1", false, 4))
        #expect(store.sessions[claudeA]?.pending?.request == "a3f9-2")
        #expect(store.sessions[claudeA]?.state == .permission)
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
        store.expire(now: at(1800), wall: wall0)
        #expect(store.sessions[claudeA] != nil)
        store.expire(now: at(1801), wall: wall0)
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
        store.expire(now: t0, wall: Date(timeIntervalSince1970: 1795530000))
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
        let sessions = try #require(try json(store.body(now: wall0))["sessions"] as? [[String: Any]])
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
        let body = store.body(now: wall0)
        #expect(body.utf8.count <= 4096)
        let parsed = try json(body)
        #expect((parsed["sessions"] as? [Any])?.count == 8)
        #expect(!noisy.isEmpty)
    }

    @Test func promptIsOldestPendingWithCount() throws {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hookJSON(claudeB, "PermissionRequest", extra: hk1Extra), at: at(0))
        feed(&store, hk1, at: at(5))
        let prompt = try #require(try json(store.body(now: wall0))["prompt"] as? [String: Any])
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

    @Test func hugeAndNonFiniteNumbersDoNotTrap() throws {
        var store = ClaudeStore(runTag: "a3f9")
        let big = ClaudeStatusUpdate(sessionId: claudeA, costUSD: 1e300, contextPct: 1e30,
                                     fiveHour: UsageWindow(pct: .nan, resetsAt: 1e30))
        store.apply(big, pane: nil, now: t0)
        let body = try json(store.body(now: wall0))
        let s = try #require((body["sessions"] as? [[String: Any]])?.first)
        #expect(s["ctx"] as? Int == 100)
        #expect(s["cost_cents"] as? Int == 100_000_000)
        #expect(((body["usage"] as? [String: Any])?["five_hour"] as? [String: Any])?["pct"] as? Int == 0)
        let wire = Data(#"{"session_id":"A","context_window":{"used_percentage":1e999},"cost":{"total_cost_usd":1e300}}"#.utf8)
        #expect(ClaudeStatusUpdate.decode(wire)?.contextPct == nil)
        let huge = Data(#"{"session_id":"A","cost":{"total_cost_usd":1e300},"rate_limits":{"five_hour":{"used_percentage":1e30,"resets_at":1e30}}}"#.utf8)
        var s2 = ClaudeStore(runTag: "a3f9")
        s2.apply(try #require(ClaudeStatusUpdate.decode(huge)), pane: nil, now: t0)
        #expect(s2.body(now: wall0).utf8.count > 0)
    }

    @Test func lateEventsAfterSessionEndDoNotRecreateGhost() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk0, at: at(0))
        feed(&store, hookJSON(claudeA, "SessionEnd"), at: at(1))
        feed(&store, hookJSON(claudeA, "Stop"), at: at(2))
        store.apply(ClaudeStatusUpdate.decode(sl2)!, pane: nil, now: at(3))
        #expect(store.sessions[claudeA] == nil)
        feed(&store, hk0, at: at(4))
        #expect(store.sessions[claudeA] != nil)
        feed(&store, hookJSON(claudeA, "SessionEnd"), at: at(5))
        store.apply(ClaudeStatusUpdate.decode(sl2)!, pane: nil, now: at(5 + ClaudeStore.tombstoneTTL + 1))
        #expect(store.sessions[claudeA] != nil)
    }

    @Test func expiryUsesInjectedMonotonicClockNotWallClock() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk0, at: t0)
        store.expire(now: at(10), wall: Date(timeIntervalSince1970: 0))
        #expect(store.sessions[claudeA] != nil)
        store.expire(now: at(10), wall: Date(timeIntervalSince1970: 4_000_000_000))
        #expect(store.sessions[claudeA] != nil)
    }

    @Test func paneReassignmentClearsOldSessionPaneAndPrompt() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, pane: "%37", at: at(0))
        feed(&store, hookJSON(claudeB, "SessionStart"), pane: "%37", at: at(1))
        let a = store.sessions[claudeA]
        #expect(a?.pane == nil)
        #expect(a?.pending == nil)
        #expect(a?.state == .working)
        #expect(store.sessions[claudeB]?.pane == "%37")
        #expect(store.pendingPrompts().isEmpty)
    }

    @Test func sessionStartClearsPendingPrompt() {
        var store = ClaudeStore(runTag: "a3f9")
        feed(&store, hk1, at: at(0))
        feed(&store, hk0, at: at(1))
        #expect(store.sessions[claudeA]?.state == .waiting)
        #expect(store.sessions[claudeA]?.pending == nil)
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

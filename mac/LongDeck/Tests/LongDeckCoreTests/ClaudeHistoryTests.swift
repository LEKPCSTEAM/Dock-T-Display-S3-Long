import Foundation
import Testing
@testable import LongDeckCore

private let t0: TimeInterval = 5000
private let wall0 = Date(timeIntervalSince1970: 1_795_519_000)

private func event(_ id: String, _ name: String, at s: TimeInterval, into store: inout ClaudeStore) {
    store.apply(ClaudeHookEvent(sessionId: id, event: name), pane: nil, now: t0 + s,
                wall: wall0.addingTimeInterval(s))
}

private func rows(_ store: ClaudeStore, wall s: TimeInterval = 0) throws -> [[String: Any]] {
    let body = store.body(now: wall0.addingTimeInterval(s))
    let root = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
    return try #require(root["sessions"] as? [[String: Any]])
}

private struct FakeRunner: TmuxRunner {
    let calls: Counter
    let result: Result<String, TmuxError>

    func run(_ args: [String]) throws -> String {
        calls.bump(args)
        return try result.get()
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [[String]] = []
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return all }
    func bump(_ a: [String]) { lock.lock(); all.append(a); lock.unlock() }
}

@Suite struct ClaudeHistoryTests {
    @Test func recordKeepsNewestPerName() {
        var h = ClaudeHistory()
        h.record(name: "A", project: "p", endedAt: 100)
        h.record(name: "A", project: "q", endedAt: 50)
        #expect(h.records == [ClaudeHistoryRecord(name: "A", project: "p", endedAt: 100)])
        h.record(name: "A", project: "q", endedAt: 200)
        #expect(h.records == [ClaudeHistoryRecord(name: "A", project: "q", endedAt: 200)])
    }

    @Test func pruneDropsOlderThanSevenDays() {
        var h = ClaudeHistory()
        h.record(name: "keep", project: "p", endedAt: 1_000_000 - 604_799)
        h.record(name: "drop", project: "p", endedAt: 1_000_000 - 604_801)
        h.prune(now: 1_000_000)
        #expect(h.records.map(\.name) == ["keep"])
    }

    @Test func saveLoadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        var h = ClaudeHistory()
        h.record(name: "CMM", project: "cmm", endedAt: 123)
        try h.save(to: url)
        #expect(ClaudeHistory.load(from: url) == h)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func corruptFileLoadsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        try Data("{not json".utf8).write(to: url)
        #expect(ClaudeHistory.load(from: url).records.isEmpty)
        #expect(ClaudeHistory.load(from: dir.appendingPathComponent("missing.json")).records.isEmpty)
    }

    @Test func endedSessionBecomesHistoryRow() throws {
        var store = ClaudeStore(runTag: "t")
        event("s1", "SessionStart", at: 0, into: &store)
        store.setName("CMM", forSession: "s1")
        event("s1", "Stop", at: 30, into: &store)
        event("s1", "SessionEnd", at: 40, into: &store)
        #expect(store.historyChanged)
        let row = try #require(try rows(store, wall: 50).first)
        #expect(row["live"] as? Bool == false)
        #expect(row["state"] as? String == "done")
        #expect(row["id"] as? String == "h:CMM")
        #expect(row["since"] as? Int == Int(wall0.timeIntervalSince1970) + 30)
        #expect(row["ctx"] as? Int == -1)
        #expect(row["tmux"] as? Bool == false)
        #expect(store.history.records.first?.endedAt == wall0.timeIntervalSince1970 + 30)
    }

    @Test func staleSessionBecomesHistoryRow() throws {
        var store = ClaudeStore(runTag: "t")
        event("s1", "SessionStart", at: 0, into: &store)
        store.setName("Old", forSession: "s1")
        store.expire(now: t0 + 31 * 60, wall: wall0.addingTimeInterval(31 * 60))
        #expect(store.sessions.isEmpty)
        let row = try #require(try rows(store, wall: 31 * 60).first)
        #expect(row["id"] as? String == "h:Old")
        #expect(row["since"] as? Int == Int(wall0.timeIntervalSince1970))
    }

    @Test func liveHidesHistoryWithSameName() throws {
        var store = ClaudeStore(runTag: "t")
        event("s1", "SessionStart", at: 0, into: &store)
        store.setName("CMM", forSession: "s1")
        event("s1", "SessionEnd", at: 10, into: &store)
        event("s2", "SessionStart", at: 20, into: &store)
        store.setName("CMM", forSession: "s2")
        let list = try rows(store, wall: 30)
        #expect(list.map { $0["id"] as? String } == ["s2"])
    }

    @Test func historySortsAfterLive() throws {
        var store = ClaudeStore(runTag: "t")
        for (i, n) in ["Old", "Newer"].enumerated() {
            event("h\(i)", "SessionStart", at: Double(i), into: &store)
            store.setName(n, forSession: "h\(i)")
            event("h\(i)", "SessionEnd", at: Double(10 + i), into: &store)
        }
        event("live", "Stop", at: 20, into: &store)
        let list = try rows(store, wall: 30)
        #expect(list.map { $0["id"] as? String } == ["live", "h:Newer", "h:Old"])
    }

    @Test func historyIsCappedWithLiveRows() throws {
        var store = ClaudeStore(runTag: "t")
        for i in 0..<30 {
            event("s\(i)", "SessionStart", at: Double(i), into: &store)
            store.setName("n\(i)", forSession: "s\(i)")
            event("s\(i)", "SessionEnd", at: Double(100 + i), into: &store)
        }
        event("live", "Stop", at: 200, into: &store)
        #expect(try rows(store, wall: 300).count == 24)
    }

    @Test func duplicateLiveNamesGetSuffix() throws {
        var store = ClaudeStore(runTag: "t")
        event("a", "SessionStart", at: 0, into: &store)
        event("b", "SessionStart", at: 5, into: &store)
        event("c", "SessionStart", at: 6, into: &store)
        for id in ["a", "b", "c"] { store.setName("CMM", forSession: id) }
        let names = Dictionary(uniqueKeysWithValues: try rows(store, wall: 10).map {
            ($0["id"] as! String, $0["name"] as! String)
        })
        #expect(names == ["a": "CMM", "b": "CMM·2", "c": "CMM·3"])
    }

    @Test func suffixStaysWithinCap() throws {
        var store = ClaudeStore(runTag: "t")
        event("a", "SessionStart", at: 0, into: &store)
        event("b", "SessionStart", at: 5, into: &store)
        let long = String(repeating: "x", count: 30)
        for id in ["a", "b"] { store.setName(long, forSession: id) }
        let b = try #require(try rows(store, wall: 10).first { $0["id"] as? String == "b" })
        let name = try #require(b["name"] as? String)
        #expect(name.utf8.count <= 23)
        #expect(name.hasSuffix("·2"))
    }

    @Test func statusCreatedSessionGetsWallSince() throws {
        var store = ClaudeStore(runTag: "t")
        store.apply(ClaudeStatusUpdate(sessionId: "s1"), pane: nil, now: t0, wall: wall0)
        let row = try #require(try rows(store).first)
        #expect(row["since"] as? Int == Int(wall0.timeIntervalSince1970))
    }

    @Test func expiredSubagentsArePruned() {
        var store = ClaudeStore(runTag: "t")
        store.apply(ClaudeHookEvent(sessionId: "s1", event: "SubagentStart", agentId: "x"), pane: nil, now: t0,
                    wall: wall0)
        event("s1", "UserPromptSubmit", at: 7201, into: &store)
        #expect(store.sessions["s1"]?.subagents.isEmpty == true)
    }

    @Test func sessionStartClearsSubagents() {
        var store = ClaudeStore(runTag: "t")
        store.apply(ClaudeHookEvent(sessionId: "s1", event: "SubagentStart", agentId: "x"), pane: nil, now: t0,
                    wall: wall0)
        event("s1", "SessionStart", at: 10, into: &store)
        #expect(store.sessions["s1"]?.subagents.isEmpty == true)
    }

    @Test func namesCacheAndFallback() {
        let calls = Counter()
        let names = ClaudeNames(runner: FakeRunner(calls: calls, result: .success("Agents Deck\n")))
        #expect(names.name(forPane: "%1", now: 100) == "Agents Deck")
        #expect(names.name(forPane: "%1", now: 129) == "Agents Deck")
        #expect(calls.calls.count == 1)
        #expect(calls.calls.first == ["display-message", "-p", "-t", "%1", "#S"])
        #expect(names.name(forPane: "%1", now: 130) == "Agents Deck")
        #expect(calls.calls.count == 2)

        let failing = ClaudeNames(runner: FakeRunner(calls: Counter(), result: .failure(.timeout)))
        #expect(failing.name(forPane: "%1", now: 0) == nil)
        let blank = ClaudeNames(runner: FakeRunner(calls: Counter(), result: .success(" \n")))
        #expect(blank.name(forPane: "%1", now: 0) == nil)
    }
}

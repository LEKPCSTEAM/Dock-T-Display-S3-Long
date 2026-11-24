import CoreGraphics
import Foundation
import Testing
@testable import LongDeckCore

private final class MockSystem: SystemControl, @unchecked Sendable {
    var calls: [String] = []
    var isTrusted = true
    func openApp(path: String) throws { calls.append("openApp(\(path))") }
    func openURL(_ url: URL) throws { calls.append("openURL(\(url.absoluteString))") }
    func postKey(code: UInt16, flags: CGEventFlags) throws { calls.append("postKey(\(code),\(flags.rawValue))") }
    func postSystemKey(_ nx: Int32) throws { calls.append("systemKey(\(nx))") }
    func typeText(_ s: String) throws { calls.append("typeText(\(s))") }
    func runShell(_ cmd: String) throws { calls.append("shell(\(cmd))") }
    func runShortcut(_ name: String) throws { calls.append("shortcut(\(name))") }
}

private func key(_ id: String, _ action: DeckAction, long: DeckAction? = nil) -> KeyConfig {
    KeyConfig(id: id, col: 0, row: 0, w: 1, h: 1, label: id, icon: nil,
              background: "#000000", action: action, longAction: long)
}

@Suite struct ActionRunnerTests {
    @Test func mediaMapsToNxKeys() throws {
        let sys = MockSystem()
        let runner = ActionRunner(system: sys)
        try runner.run(.media(.playPause))
        try runner.run(.media(.next))
        try runner.run(.media(.previous))
        #expect(sys.calls == ["systemKey(16)", "systemKey(17)", "systemKey(18)"])
    }

    @Test func volumeMapsToNxKeys() throws {
        let sys = MockSystem()
        let runner = ActionRunner(system: sys)
        try runner.run(.volume(.up))
        try runner.run(.volume(.down))
        try runner.run(.volume(.mute))
        #expect(sys.calls == ["systemKey(0)", "systemKey(1)", "systemKey(7)"])
    }

    @Test func hotkeyMapsModifiers() throws {
        let sys = MockSystem()
        try ActionRunner(system: sys).run(.hotkey(keyCode: 21, modifiers: [.command, .shift]))
        let flags: CGEventFlags = [.maskCommand, .maskShift]
        #expect(sys.calls == ["postKey(21,\(flags.rawValue))"])
    }

    @Test func simpleActionsGoToTheirCalls() throws {
        let sys = MockSystem()
        let runner = ActionRunner(system: sys)
        try runner.run(.openApp(path: "/Applications/Notes.app"))
        try runner.run(.openURL("https://example.com"))
        try runner.run(.typeText("hi"))
        try runner.run(.shell("echo 1"))
        try runner.run(.shortcut("Focus"))
        #expect(sys.calls == [
            "openApp(/Applications/Notes.app)", "openURL(https://example.com)",
            "typeText(hi)", "shell(echo 1)", "shortcut(Focus)",
        ])
    }

    @Test func reportsPermissionError() throws {
        let sys = MockSystem()
        sys.isTrusted = false
        let runner = ActionRunner(system: sys)
        let blocked: [DeckAction] = [
            .hotkey(keyCode: 1, modifiers: []), .media(.next), .volume(.up), .typeText("x"),
        ]
        for action in blocked {
            #expect(throws: ActionError.notTrusted) { try runner.run(action) }
        }
        #expect(sys.calls.isEmpty)
        try runner.run(.openApp(path: "/Applications/Notes.app"))
        #expect(sys.calls == ["openApp(/Applications/Notes.app)"])
    }

    @Test func handlePressUnknownIdThrows() {
        let runner = ActionRunner(system: MockSystem())
        let config = DeckConfig(version: 1, pages: [PageConfig(name: "P", keys: [key("a", .shell("x"))])])
        #expect(throws: ActionError.unknownKey("zzz")) {
            try runner.handlePress(id: "zzz", kind: "tap", config: config)
        }
    }

    @Test func handlePressDispatchesTapAndLong() throws {
        let sys = MockSystem()
        let runner = ActionRunner(system: sys)
        let config = DeckConfig(version: 1, pages: [
            PageConfig(name: "P", keys: [key("a", .shell("tap"), long: .shell("long"))]),
        ])
        try runner.handlePress(id: "a", kind: "tap", config: config)
        try runner.handlePress(id: "a", kind: "long", config: config)
        #expect(sys.calls == ["shell(tap)", "shell(long)"])
    }

    @Test func handlePressLongWithoutLongActionDoesNothing() throws {
        let sys = MockSystem()
        let config = DeckConfig(version: 1, pages: [PageConfig(name: "P", keys: [key("a", .shell("tap"))])])
        try ActionRunner(system: sys).handlePress(id: "a", kind: "long", config: config)
        #expect(sys.calls.isEmpty)
    }
}

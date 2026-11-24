import Foundation
import Testing
@testable import LongDeckCore

private func key(_ id: String, _ col: Int, _ row: Int, w: Int = 1, h: Int = 1,
                 action: DeckAction = .shell("true")) -> KeyConfig {
    KeyConfig(id: id, col: col, row: row, w: w, h: h, label: id, icon: nil,
              background: "#333333", action: action, longAction: nil)
}

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
}

@Suite struct DeckConfigTests {
    @Test func configRoundTripsThroughJSON() throws {
        let actions: [DeckAction] = [
            .openApp(path: "/Applications/iTerm.app"), .openURL("https://x.dev"),
            .hotkey(keyCode: 49, modifiers: [.command, .shift, .option, .control]),
            .media(.playPause), .volume(.mute), .typeText("hi"), .shell("ls"), .shortcut("Foo"),
        ]
        let keys = actions.enumerated().map { i, a in
            var k = key("k\(i)", i, 0, action: a)
            k.icon = i % 2 == 0 ? .app(path: "/x.app") : .symbol(name: "star")
            k.longAction = i == 0 ? .openURL("file:///") : nil
            return k
        }
        let config = DeckConfig(version: 1, pages: [PageConfig(name: "P", keys: keys)])
        let url = tempURL()
        try config.save(to: url)
        #expect(try DeckConfig.load(from: url) == config)
    }

    @Test func loadMissingFileReturnsSample() throws {
        let loaded = try DeckConfig.load(from: tempURL())
        #expect(loaded == SampleConfig.dev)
    }

    @Test func sampleConfigUsesEveryActionTypeAndFitsGrid() throws {
        let keys = SampleConfig.dev.pages.flatMap(\.keys)
        var kinds = Set<String>()
        for k in keys {
            switch k.action {
            case .openApp: kinds.insert("openApp")
            case .openURL: kinds.insert("openURL")
            case .hotkey: kinds.insert("hotkey")
            case .media: kinds.insert("media")
            case .volume: kinds.insert("volume")
            case .typeText: kinds.insert("typeText")
            case .shell: kinds.insert("shell")
            case .shortcut: kinds.insert("shortcut")
            }
        }
        #expect(kinds.count == 8)
        try SampleConfig.dev.validate()
    }

    @Test func validationRejectsBadLayouts() {
        func cfg(_ keys: [KeyConfig]) -> DeckConfig {
            DeckConfig(version: 1, pages: [PageConfig(name: "P", keys: keys)])
        }
        #expect(throws: DeckConfigError.self) { try cfg([key("a", 8, 0)]).validate() }
        #expect(throws: DeckConfigError.self) { try cfg([key("a", 0, 2)]).validate() }
        #expect(throws: DeckConfigError.self) { try cfg([key("a", 7, 0, w: 2)]).validate() }
        #expect(throws: DeckConfigError.self) { try cfg([key("a", 0, 0, w: 0)]).validate() }
        #expect(throws: DeckConfigError.self) {
            try cfg([key("a", 0, 0, w: 2), key("b", 1, 0)]).validate()
        }
        #expect(throws: DeckConfigError.self) { try cfg([key("a", 0, 0), key("a", 1, 0)]).validate() }
        let nine = DeckConfig(version: 1, pages: (0..<9).map { PageConfig(name: "p\($0)", keys: []) })
        #expect(throws: DeckConfigError.self) { try nine.validate() }
    }

    @Test func loadThrowsOnInvalidFile() throws {
        let bad = DeckConfig(version: 1, pages: [PageConfig(name: "P", keys: [key("a", 9, 0)])])
        let url = tempURL()
        try bad.save(to: url)
        #expect(throws: DeckConfigError.self) { try DeckConfig.load(from: url) }
    }
}

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

    @Test func validationEnforcesBoardNameLimits() throws {
        func cfg(page: String = "P", id: String) -> DeckConfig {
            DeckConfig(version: 1, pages: [PageConfig(name: page, keys: [key(id, 0, 0)])])
        }
        #expect(throws: DeckConfigError.self) { try cfg(id: "").validate() }
        #expect(throws: DeckConfigError.self) { try cfg(id: String(repeating: "a", count: 16)).validate() }
        #expect(throws: DeckConfigError.self) { try cfg(id: String(repeating: "é", count: 8)).validate() }
        #expect(throws: DeckConfigError.self) { try cfg(page: String(repeating: "p", count: 24), id: "a").validate() }
        #expect(throws: DeckConfigError.self) { try cfg(page: String(repeating: "é", count: 12), id: "a").validate() }
        try cfg(page: String(repeating: "p", count: 23), id: String(repeating: "a", count: 15)).validate()
    }

    @Test func loadThrowsOnInvalidFile() throws {
        let bad = DeckConfig(version: 1, pages: [PageConfig(name: "P", keys: [key("a", 9, 0)])])
        let url = tempURL()
        try bad.save(to: url)
        #expect(throws: DeckConfigError.self) { try DeckConfig.load(from: url) }
    }

    @Test func liveWidgetJSONIsFlat() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let cpu = LiveWidgetConfig(id: "cpu", col: 0, row: 0, w: 2, h: 1, kind: .stat(.cpu, .sparkline))
        let vol = LiveWidgetConfig(id: "vol", col: 2, row: 0, w: 3, h: 1, kind: .volume)
        let cpuJSON = String(decoding: try encoder.encode(cpu), as: UTF8.self)
        let volJSON = String(decoding: try encoder.encode(vol), as: UTF8.self)
        #expect(cpuJSON == #"{"col":0,"h":1,"id":"cpu","metric":"cpu","row":0,"style":"sparkline","type":"stat","w":2}"#)
        #expect(volJSON == #"{"col":2,"h":1,"id":"vol","row":0,"type":"volume","w":3}"#)
        #expect(try JSONDecoder().decode(LiveWidgetConfig.self, from: Data(cpuJSON.utf8)) == cpu)
        #expect(try JSONDecoder().decode(LiveWidgetConfig.self, from: Data(volJSON.utf8)) == vol)
    }

    @Test func liveWidgetDecodeRejectsBadInput() {
        let bad = [
            #"{"col":0,"h":1,"id":"a","row":0,"type":"gauge","w":1}"#,
            #"{"col":0,"h":1,"id":"a","metric":"cpu","row":0,"type":"stat","w":1}"#,
            #"{"col":0,"h":1,"id":"a","metric":"fan","row":0,"style":"bar","type":"stat","w":1}"#,
        ]
        for json in bad {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(LiveWidgetConfig.self, from: Data(json.utf8))
            }
        }
    }

    @Test func m1ConfigLoadsUnchanged() throws {
        let data = try JSONEncoder().encode(SampleConfig.dev)
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var pages = try #require(root["pages"] as? [[String: Any]])
        for i in pages.indices { pages[i].removeValue(forKey: "live") }
        root["pages"] = pages
        let m1 = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(DeckConfig.self, from: m1)
        var expected = SampleConfig.dev
        for i in expected.pages.indices { expected.pages[i].live = [] }
        #expect(decoded == expected)
        let built = LayoutBuilder.build(decoded, render: { _ in Data() })
        let root2 = try #require(JSONSerialization.jsonObject(with: Data(built.json.utf8)) as? [String: Any])
        let dev = try #require((root2["pages"] as? [[String: Any]])?.first)
        let widgets = try #require(dev["widgets"] as? [[String: Any]])
        #expect(widgets.count == 16)
        #expect(widgets.allSatisfy { $0["type"] as? String == "key" })
        #expect(widgets.map { $0["face"] as? Int } == (1...16).map { $0 })
    }

    @Test func validationCoversLiveWidgets() throws {
        func live(_ id: String, _ col: Int, _ row: Int = 0, w: Int = 1) -> LiveWidgetConfig {
            LiveWidgetConfig(id: id, col: col, row: row, w: w, h: 1, kind: .clock)
        }
        func cfg(keys: [KeyConfig] = [], live: [LiveWidgetConfig]) -> DeckConfig {
            DeckConfig(version: 1, pages: [PageConfig(name: "P", keys: keys, live: live)])
        }
        #expect(throws: DeckConfigError.self) { try cfg(live: [live("a", 7, w: 2)]).validate() }
        #expect(throws: DeckConfigError.self) { try cfg(keys: [key("k", 0, 0)], live: [live("a", 0)]).validate() }
        let twoPages = DeckConfig(version: 1, pages: [
            PageConfig(name: "A", keys: [key("x", 0, 0)]),
            PageConfig(name: "B", keys: [], live: [live("x", 0)]),
        ])
        #expect(throws: DeckConfigError.self) { try twoPages.validate() }
        let longID = String(repeating: "a", count: 16)
        #expect(throws: DeckConfigError.self) { try cfg(live: [live(longID, 0)]).validate() }
        func mixed(keys n: Int, live m: Int) -> DeckConfig {
            let ks = (0..<n).map { key("k\($0)", $0 % 8, $0 / 8) }
            let ls = (0..<m).map { live("l\($0)", ($0 + n) % 8, ($0 + n) / 8) }
            return cfg(keys: ks, live: ls)
        }
        #expect(throws: DeckConfigError.self) { try mixed(keys: 10, live: 7).validate() }
        try mixed(keys: 10, live: 6).validate()
    }

    @Test func sampleMacPageHasEveryLiveKind() throws {
        let mac = try #require(SampleConfig.dev.pages.first { $0.name == "Mac" })
        var metrics = Set<StatMetric>()
        var styles = Set<StatStyle>()
        var volume = false, clock = false
        for w in mac.live {
            switch w.kind {
            case .stat(let m, let s): metrics.insert(m); styles.insert(s)
            case .volume: volume = true
            case .clock: clock = true
            case .claudeSessions, .claudeUsage: break
            }
        }
        #expect(volume && clock)
        #expect(styles == Set(StatStyle.allCases))
        #expect(metrics == Set(StatMetric.allCases).subtracting([.battery]))
        try SampleConfig.dev.validate()
    }

    @Test func claudeWidgetJSONIsFlat() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sessions = LiveWidgetConfig(id: "ccs", col: 0, row: 0, w: 4, h: 2, kind: .claudeSessions)
        let usage = LiveWidgetConfig(id: "ccu", col: 4, row: 0, w: 4, h: 1, kind: .claudeUsage)
        let sessionsJSON = String(decoding: try encoder.encode(sessions), as: UTF8.self)
        let usageJSON = String(decoding: try encoder.encode(usage), as: UTF8.self)
        #expect(sessionsJSON == #"{"col":0,"h":2,"id":"ccs","row":0,"type":"claude_sessions","w":4}"#)
        #expect(usageJSON == #"{"col":4,"h":1,"id":"ccu","row":0,"type":"claude_usage","w":4}"#)
        #expect(try JSONDecoder().decode(LiveWidgetConfig.self, from: Data(sessionsJSON.utf8)) == sessions)
        #expect(try JSONDecoder().decode(LiveWidgetConfig.self, from: Data(usageJSON.utf8)) == usage)
    }

    @Test func claudeSessionsNeedsTwoColumns() throws {
        func config(_ kind: LiveKind) -> DeckConfig {
            DeckConfig(version: 1, pages: [PageConfig(
                name: "C", keys: [], live: [LiveWidgetConfig(id: "c", col: 0, row: 0, w: 1, h: 1, kind: kind)])])
        }
        #expect(throws: DeckConfigError.invalid("widget c: claude_sessions needs at least 2 columns")) {
            try config(.claudeSessions).validate()
        }
        try config(.claudeUsage).validate()
    }

    @Test func sampleClaudePage() throws {
        let page = try #require(SampleConfig.dev.pages.first { $0.name == "Claude" })
        #expect(page.keys.isEmpty)
        #expect(page.live == [
            LiveWidgetConfig(id: "ccsessions", col: 0, row: 0, w: 4, h: 2, kind: .claudeSessions),
            LiveWidgetConfig(id: "ccusage", col: 4, row: 0, w: 4, h: 1, kind: .claudeUsage),
            LiveWidgetConfig(id: "ccclock", col: 4, row: 1, w: 2, h: 1, kind: .clock),
        ])
        try SampleConfig.dev.validate()
    }
}

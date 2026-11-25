import AppKit
import Testing
@testable import LongDeckCore

@Suite struct WidgetPaletteTests {
    @Test func paletteTable() {
        let rows: [(PaletteItem, String, String, CellSize, CellSize, String)] = [
            (.key, "Key", "button.programmable", CellSize(w: 1, h: 1), CellSize(w: 1, h: 1), "key"),
            (.stat, "Stat", "chart.bar.fill", CellSize(w: 2, h: 1), CellSize(w: 1, h: 1), "cpu"),
            (.volume, "Volume", "speaker.wave.2.fill", CellSize(w: 3, h: 1), CellSize(w: 1, h: 1), "volume"),
            (.clock, "Clock", "clock", CellSize(w: 2, h: 1), CellSize(w: 1, h: 1), "clock"),
            (.claudeSessions, "Claude sessions", "list.bullet.rectangle",
             CellSize(w: 4, h: 2), CellSize(w: 2, h: 1), "ccsessions"),
            (.claudeUsage, "Claude usage", "gauge.with.dots.needle.33percent",
             CellSize(w: 4, h: 1), CellSize(w: 1, h: 1), "ccusage"),
            (.claudeAgents, "Claude agents", "person.3.sequence",
             CellSize(w: 8, h: 2), CellSize(w: 2, h: 1), "ccagents"),
        ]
        #expect(PaletteItem.allCases.count == rows.count)
        for (item, title, symbol, def, min, base) in rows {
            #expect(item.title == title)
            #expect(item.symbol == symbol)
            #expect(item.defaultSize == def)
            #expect(item.minSize == min)
            #expect(item.idBase == base)
        }
        #expect(PaletteItem.claudeSessions.rawValue == "claude_sessions")
        #expect(PaletteItem.claudeAgents.rawValue == "claude_agents")
    }

    @Test func claudeAgentsDefaults() {
        let rect = CellRect(col: 0, row: 0, w: 8, h: 2)
        #expect(PaletteItem.claudeAgents.makeWidget(id: "a", rect: rect)
            == .live(LiveWidgetConfig(id: "a", col: 0, row: 0, w: 8, h: 2, kind: .claudeAgents)))
        #expect(LiveTitles.title(.claudeAgents) == "Claude agents")
    }

    @Test func paletteSymbolsExist() {
        for item in PaletteItem.allCases {
            #expect(NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test func makeWidgetUsesIdAndRect() {
        let rect = CellRect(col: 2, row: 1, w: 3, h: 1)
        let key = PaletteItem.key.makeWidget(id: "k1", rect: rect)
        #expect(key == .key(KeyConfig(id: "k1", col: 2, row: 1, w: 3, h: 1, label: "Key", icon: nil,
                                      background: "#2B2B2B", action: .openApp(path: ""),
                                      longAction: nil, foreground: nil)))
        let stat = PaletteItem.stat.makeWidget(id: "s1", rect: rect)
        #expect(stat == .live(LiveWidgetConfig(id: "s1", col: 2, row: 1, w: 3, h: 1,
                                               kind: .stat(.cpu, .sparkline))))
        #expect(PaletteItem.volume.makeWidget(id: "v", rect: rect).frame == rect)
        #expect(PaletteItem.clock.makeWidget(id: "c", rect: rect)
            == .live(LiveWidgetConfig(id: "c", col: 2, row: 1, w: 3, h: 1, kind: .clock)))
        #expect(PaletteItem.claudeSessions.makeWidget(id: "a", rect: rect).id == "a")
        #expect(PaletteItem.claudeUsage.makeWidget(id: "b", rect: rect)
            == .live(LiveWidgetConfig(id: "b", col: 2, row: 1, w: 3, h: 1, kind: .claudeUsage)))
    }

    @Test func liveTitles() {
        #expect(LiveTitles.title(.stat(.cpu, .sparkline)) == "CPU · sparkline")
        #expect(LiveTitles.title(.stat(.netDown, .bar)) == "Net down · bar")
        #expect(LiveTitles.title(.volume) == "Volume")
        #expect(LiveTitles.title(.clock) == "Clock")
        #expect(LiveTitles.title(.claudeSessions) == "Claude sessions")
        #expect(LiveTitles.title(.claudeUsage) == "Claude usage")
        #expect(LiveTitles.metricName(.diskIO) == "Disk I/O")
        #expect(LiveTitles.styleName(.number) == "Number")
    }
}

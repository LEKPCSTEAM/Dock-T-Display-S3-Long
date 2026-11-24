import Testing
@testable import LongDeckCore

@Suite struct EditorGridTests {
    @Test func cellRectBasics() {
        #expect(CellRect(col: 1, row: 0, w: 2, h: 2).cells == [1, 2, 9, 10])
        #expect(CellRect(col: 0, row: 0, w: 2, h: 1).intersects(CellRect(col: 1, row: 0, w: 1, h: 1)))
        #expect(!CellRect(col: 0, row: 0, w: 1, h: 1).intersects(CellRect(col: 1, row: 0, w: 1, h: 1)))
        #expect(!CellRect(col: 7, row: 0, w: 2, h: 1).isInGrid)
        #expect(!CellRect(col: 0, row: 1, w: 1, h: 2).isInGrid)
        #expect(!CellRect(col: -1, row: 0, w: 1, h: 1).isInGrid)
        #expect(!CellRect(col: 0, row: 0, w: 0, h: 1).isInGrid)
        #expect(CellRect(col: 0, row: 0, w: 8, h: 2).isInGrid)
    }

    @Test func fittedShiftsIntoGrid() {
        #expect(CellRect(col: 7, row: 1, w: 4, h: 1).fitted() == CellRect(col: 4, row: 1, w: 4, h: 1))
        #expect(CellRect(col: 6, row: 1, w: 2, h: 2).fitted() == CellRect(col: 6, row: 0, w: 2, h: 2))
        #expect(CellRect(col: -1, row: 0, w: 1, h: 1).fitted() == CellRect(col: 0, row: 0, w: 1, h: 1))
    }

    @Test func firstFreeIsRowMajor() {
        #expect(EditorGrid.firstFree(CellSize(w: 2, h: 1), occupied: [0])
            == CellRect(col: 1, row: 0, w: 2, h: 1))
        #expect(EditorGrid.firstFree(CellSize(w: 1, h: 1), occupied: Set(0...14))
            == CellRect(col: 7, row: 1, w: 1, h: 1))
        #expect(EditorGrid.firstFree(CellSize(w: 4, h: 2), occupied: [3])
            == CellRect(col: 4, row: 0, w: 4, h: 2))
        #expect(EditorGrid.firstFree(CellSize(w: 4, h: 2), occupied: [3, 12]) == nil)
        #expect(EditorGrid.firstFree(CellSize(w: 8, h: 1), occupied: [])
            == CellRect(col: 0, row: 0, w: 8, h: 1))
    }

    @Test func widgetsKeysThenLive() throws {
        let page = try #require(SampleConfig.dev.pages.first { $0.name == "Claude" })
        let widgets = EditorGrid.widgets(of: page)
        #expect(widgets.map(\.id) == ["ccsessions", "ccusage", "ccclock"])
        #expect(widgets[0].minSize == CellSize(w: 2, h: 1))
        #expect(widgets[1].minSize == CellSize(w: 1, h: 1))
        #expect(widgets[2].minSize == CellSize(w: 1, h: 1))
        #expect(widgets[0].frame == CellRect(col: 0, row: 0, w: 4, h: 2))
    }

    @Test func occupiedIgnoresId() throws {
        let page = try #require(SampleConfig.dev.pages.first { $0.name == "Claude" })
        let widgets = EditorGrid.widgets(of: page)
        #expect(EditorGrid.occupied(widgets, ignoring: "ccsessions") == [4, 5, 6, 7, 12, 13])
        #expect(EditorGrid.occupied(widgets, ignoring: nil).contains(0))
        #expect(EditorGrid.fits(CellRect(col: 0, row: 0, w: 1, h: 1), occupied: [1]))
        #expect(!EditorGrid.fits(CellRect(col: 0, row: 0, w: 2, h: 1), occupied: [1]))
    }

    @Test func titles() {
        let key = KeyConfig(id: "a", col: 0, row: 0, w: 1, h: 1, label: "", icon: nil,
                            background: "#000000", action: .shell(""), longAction: nil)
        #expect(EditorWidget.key(key).title == "Key")
        var named = key
        named.label = "Hi"
        #expect(EditorWidget.key(named).title == "Hi")
    }
}

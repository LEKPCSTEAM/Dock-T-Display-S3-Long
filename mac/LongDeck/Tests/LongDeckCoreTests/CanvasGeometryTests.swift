import CoreGraphics
import Testing
@testable import LongDeckCore

@Suite struct CanvasGeometryTests {
    @Test func fittingSteps() {
        #expect(CanvasGeometry.fitting(width: 500).scale == 1)
        #expect(CanvasGeometry.fitting(width: 900).scale == 1.25)
        #expect(CanvasGeometry.fitting(width: 1280).scale == 2)
        #expect(CanvasGeometry.fitting(width: 2000).scale == 2)
    }

    @Test func rectVectors() {
        #expect(CanvasGeometry(scale: 2).rect(for: CellRect(col: 1, row: 1, w: 2, h: 1))
                == CGRect(x: 166, y: 186, width: 308, height: 168))
        #expect(CanvasGeometry(scale: 1).rect(for: CellRect(col: 0, row: 0, w: 1, h: 1))
                == CGRect(x: 3, y: 3, width: 74, height: 84))
    }

    @Test func cellAtVectors() {
        let g = CanvasGeometry(scale: 1)
        let a = g.cell(at: CGPoint(x: 159.9, y: 179.9))
        #expect(a?.col == 1 && a?.row == 1)
        let b = g.cell(at: .zero)
        #expect(b?.col == 0 && b?.row == 0)
        #expect(g.cell(at: CGPoint(x: 640, y: 0)) == nil)
        #expect(g.cell(at: CGPoint(x: -1, y: 5)) == nil)
    }

    @Test func movedRoundsToCells() {
        let g = CanvasGeometry(scale: 1)
        let two = CellRect(col: 0, row: 0, w: 2, h: 1)
        #expect(g.moved(two, by: CGSize(width: 119, height: 0)).col == 1)
        #expect(g.moved(two, by: CGSize(width: 121, height: 0)).col == 2)
        #expect(g.moved(CellRect(col: 6, row: 0, w: 2, h: 1), by: CGSize(width: 400, height: 200))
                == CellRect(col: 6, row: 1, w: 2, h: 1))
    }

    @Test func resizedClamps() {
        let g = CanvasGeometry(scale: 1)
        let one = CellSize(w: 1, h: 1)
        let two = CellSize(w: 2, h: 1)
        #expect(g.resized(CellRect(col: 2, row: 0, w: 1, h: 1), handle: .right,
                          by: CGSize(width: 250, height: 0), minSize: one).w == 4)
        #expect(g.resized(CellRect(col: 2, row: 0, w: 1, h: 1), handle: .bottom,
                          by: CGSize(width: 0, height: -90), minSize: one).h == 1)
        #expect(g.resized(CellRect(col: 6, row: 0, w: 2, h: 1), handle: .bottomRight,
                          by: CGSize(width: 500, height: 100), minSize: two)
                == CellRect(col: 6, row: 0, w: 2, h: 2))
        #expect(g.resized(CellRect(col: 0, row: 0, w: 2, h: 1), handle: .right,
                          by: CGSize(width: -200, height: 0), minSize: two).w == 2)
    }

    @Test func resizedNeverOverflowsGrid() {
        let g = CanvasGeometry(scale: 1)
        let two = CellSize(w: 2, h: 2)
        let right = g.resized(CellRect(col: 7, row: 0, w: 1, h: 1), handle: .right,
                              by: .zero, minSize: two)
        #expect(right.col == 6 && right.w == 2)
        let bottom = g.resized(CellRect(col: 0, row: 1, w: 1, h: 1), handle: .bottom,
                               by: .zero, minSize: two)
        #expect(bottom.row == 0 && bottom.h == 2)
    }
}

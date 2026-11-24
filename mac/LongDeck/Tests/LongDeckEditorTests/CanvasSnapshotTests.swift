import CoreGraphics
import Foundation
import LongDeckCore
import SwiftUI
import Testing
@testable import LongDeckEditor

@Suite(.serialized) @MainActor struct CanvasSnapshotTests {
    private func store(_ config: DeckConfig) -> EditorStore {
        EditorStore(config: config, onDisk: true, diskError: nil, appRoots: [], environment: .permissive)
    }

    private func canvas(page: Int, scale: CGFloat, name: String) throws {
        let s = store(SampleConfig.dev)
        s.selectPage(page)
        let geometry = CanvasGeometry(scale: scale)
        let rep = Snapshot.render(DeckCanvasView(store: s, geometry: geometry), size: geometry.size)
        #expect(rep.pixelsWide == Int(1280 * scale))
        #expect(rep.pixelsHigh == Int(360 * scale))
        #expect(!Snapshot.isUniform(rep))
        try Snapshot.save(rep, name)
    }

    @Test func canvasDevPage() throws { try canvas(page: 0, scale: 2, name: "canvas-dev") }
    @Test func canvasMacPage() throws { try canvas(page: 1, scale: 2, name: "canvas-mac") }
    @Test func canvasClaudePage() throws { try canvas(page: 2, scale: 1, name: "canvas-claude") }

    @Test func canvasStates() throws {
        let s = store(SampleConfig.dev)
        s.selectPage(2)
        #expect(s.add(.key) != nil)
        s.select("ccusage")
        let interaction = CanvasInteraction()
        interaction.ghost = .init(id: "ccusage", rect: CellRect(col: 3, row: 0, w: 4, h: 1), valid: false)
        let geometry = CanvasGeometry(scale: 2)
        let rep = Snapshot.render(DeckCanvasView(store: s, geometry: geometry, interaction: interaction),
                                  size: geometry.size)
        #expect(rep.pixelsWide == 2560)
        #expect(rep.pixelsHigh == 720)
        #expect(!Snapshot.isUniform(rep))
        try Snapshot.save(rep, "canvas-states")
    }

    @Test func paletteNormalAndFull() throws {
        let full = store(SampleConfig.dev)
        let blank = store(DeckConfig(version: 1, pages: [PageConfig(name: "A", keys: [])]))
        let view = VStack(spacing: 12) {
            WidgetPaletteView(store: full)
            WidgetPaletteView(store: blank)
        }
        .padding(12)
        .frame(width: 640, height: 150)
        .background(BoardColors.bg)
        let rep = Snapshot.render(view, size: CGSize(width: 640, height: 150))
        #expect(rep.pixelsWide == 1280)
        #expect(rep.pixelsHigh == 300)
        #expect(!Snapshot.isUniform(rep))
        try Snapshot.save(rep, "palette")
    }

    @Test func faceCacheReturnsPreview() throws {
        let key = try #require(SampleConfig.dev.pages[0].keys.first)
        let cached = try #require(FaceImageCache.shared.image(for: key))
        let direct = try #require(FacePreview.image(for: key))
        #expect(cached.width == direct.width)
        #expect(cached.height == direct.height)
        #expect(cached.dataProvider?.data as Data? == direct.dataProvider?.data as Data?)
        #expect(FaceImageCache.shared.image(for: key) === cached)
    }
}

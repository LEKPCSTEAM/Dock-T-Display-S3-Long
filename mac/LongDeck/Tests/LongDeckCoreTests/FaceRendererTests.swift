import Foundation
import Testing
@testable import LongDeckCore

let goldenLabelKey = KeyConfig(id: "g", col: 0, row: 0, w: 2, h: 1, label: "Golden ทดสอบ", icon: nil,
                               background: "#222222", action: .shell("true"), longAction: nil)

private let spotlightGolden = "4b4b62b696228228cef79d742e0ceadad0a95724f09373925ab2cd536c533453"
private let labelGolden = "95719f8bcaffc166bcb11b49b4a7e9ef67d41ea3209ae8fb3f8887e1122e8509"

@Suite struct FaceRendererTests {
    @Test func packPrimaries() {
        #expect(FaceRenderer.pack(r: 255, g: 0, b: 0, a: 255) == [0xF8, 0x00, 0xFF])
        #expect(FaceRenderer.pack(r: 0, g: 255, b: 0, a: 128) == [0x07, 0xE0, 0x80])
        #expect(FaceRenderer.pack(r: 0, g: 0, b: 255, a: 0) == [0x00, 0x1F, 0x00])
        #expect(FaceRenderer.pack(r: 255, g: 255, b: 255, a: 255) == [0xFF, 0xFF, 0xFF])
    }

    @Test func faceSizes() {
        #expect(FaceRenderer.faceSize(w: 1, h: 1) == (74, 84))
        #expect(FaceRenderer.faceSize(w: 2, h: 2) == (154, 174))
    }

    @Test func renderSizeMatchesFaceSize() {
        let key = KeyConfig(id: "k", col: 0, row: 0, w: 1, h: 1, label: "A very long label here",
                            icon: .app(path: "/Applications/Missing.app"), background: "#FF0000",
                            action: .shell("true"), longAction: nil)
        #expect(FaceRenderer.render(key).count == 18_648)
    }

    @Test func foregroundChangesLabelPixels() {
        var k = goldenLabelKey
        k.foreground = "#FF0000"
        let face = FaceRenderer.render(k)
        #expect(face != FaceRenderer.render(goldenLabelKey))
        let (width, height) = FaceRenderer.faceSize(w: k.w, h: k.h)
        var red = false
        for y in (height - 22)..<height {
            for x in 0..<width {
                let i = (y * width + x) * 3
                let (r, g, _) = FacePreview.expand(UInt16(face[i]) << 8 | UInt16(face[i + 1]))
                if r > 200 && g < 80 { red = true }
            }
        }
        #expect(red)
    }

    @Test func foregroundTintsSymbols() throws {
        var spotlight = try #require(SampleConfig.dev.pages.flatMap(\.keys).first { $0.id == "spotlight" })
        spotlight.foreground = "#00FF00"
        #expect(DeckCrypto.hex(DeckCrypto.sha256(FaceRenderer.render(spotlight))) != spotlightGolden)
    }

    @Test func facesUnchangedForExistingKeys() throws {
        let spotlight = try #require(SampleConfig.dev.pages.flatMap(\.keys).first { $0.id == "spotlight" })
        #expect(DeckCrypto.hex(DeckCrypto.sha256(FaceRenderer.render(spotlight))) == spotlightGolden)
        #expect(DeckCrypto.hex(DeckCrypto.sha256(FaceRenderer.render(goldenLabelKey))) == labelGolden)
    }
}

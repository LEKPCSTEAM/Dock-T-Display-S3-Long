import Foundation
import Testing
@testable import LongDeckCore

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
}

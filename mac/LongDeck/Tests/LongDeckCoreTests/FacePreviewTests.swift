import Foundation
import Testing
@testable import LongDeckCore

private func key(w: Int = 1, h: Int = 1) -> KeyConfig {
    KeyConfig(id: "k", col: 0, row: 0, w: w, h: h, label: "K", icon: nil,
              background: "#222222", action: .shell("true"), longAction: nil)
}

@Suite struct FacePreviewTests {
    @Test func expandReplicatesBits() {
        #expect(FacePreview.expand(0xF800) == (255, 0, 0))
        #expect(FacePreview.expand(0x07E0) == (0, 255, 0))
        #expect(FacePreview.expand(0x001F) == (0, 0, 255))
        #expect(FacePreview.expand(0x0000) == (0, 0, 0))
        #expect(FacePreview.expand(0xFFFF) == (255, 255, 255))
        #expect(FacePreview.expand(FacePreview.panel565) == (16, 24, 33))
    }

    @Test func mixMatchesLvgl() {
        func px(_ a: UInt8) -> (UInt8, UInt8, UInt8) {
            FacePreview.expand(FacePreview.mix(0xFFFF, FacePreview.panel565, alpha: a))
        }
        #expect(px(0) == (16, 24, 33))
        #expect(px(2) == (16, 24, 33))
        #expect(px(128) == (140, 142, 148))
        #expect(px(253) == (255, 255, 255))
        #expect(px(255) == (255, 255, 255))
    }

    @Test func imageSizeMatchesFace() throws {
        let wide = try #require(FacePreview.image(for: key(w: 2)))
        #expect(wide.width == 154 && wide.height == 84)
        let one = try #require(FacePreview.image(for: key()))
        #expect(one.width == 74 && one.height == 84)
    }

    @Test func previewPixelsMatchRenderedFace() {
        let k = goldenLabelKey
        let face = FaceRenderer.render(k)
        let (w, h) = FaceRenderer.faceSize(w: k.w, h: k.h)
        let out = FacePreview.composite(face: face, width: w, height: h)
        #expect(out.count == w * h * 4)
        var mismatches = 0
        for i in 0..<(w * h) {
            let v = UInt16(face[i * 3]) << 8 | UInt16(face[i * 3 + 1])
            let (r, g, b) = FacePreview.expand(FacePreview.mix(v, FacePreview.panel565, alpha: face[i * 3 + 2]))
            if out[i * 4] != r || out[i * 4 + 1] != g || out[i * 4 + 2] != b || out[i * 4 + 3] != 255 {
                mismatches += 1
            }
        }
        #expect(mismatches == 0)
    }

    @Test func cacheKeyIgnoresActionAndPlace() {
        let base = key()
        var same = base
        same.action = .openURL("x")
        same.longAction = .shell("y")
        same.id = "other"
        same.col = 3
        same.row = 1
        #expect(FacePreview.cacheKey(same) == FacePreview.cacheKey(base))
        var l = base; l.label = "Z"
        var w = base; w.w = 2
        var b = base; b.background = "#000000"
        var f = base; f.foreground = "#FF0000"
        for changed in [l, w, b, f] {
            #expect(FacePreview.cacheKey(changed) != FacePreview.cacheKey(base))
        }
    }
}

import AppKit
import Testing
@testable import LongDeckCore

@Suite struct HexColorTests {
    @Test func parseAcceptsAnyCase() throws {
        for s in ["#1F3A5F", "#1f3a5f"] {
            let c = try #require(HexColor.parse(s))
            #expect(c == (31, 58, 95))
        }
    }

    @Test func parseRejectsMalformed() {
        for s in ["1F3A5F", "#12345", "#GG0000", "#1F3A5F0"] {
            #expect(HexColor.parse(s) == nil)
        }
    }

    @Test func formatIsUppercase() {
        #expect(HexColor.format(r: 31, g: 58, b: 95) == "#1F3A5F")
    }

    @Test func fromNSColor() {
        #expect(HexColor.from(NSColor(srgbRed: 31 / 255, green: 58 / 255, blue: 95 / 255, alpha: 1)) == "#1F3A5F")
        #expect(HexColor.from(NSColor.white) == "#FFFFFF")
    }

    @Test func nsColorParses() throws {
        let red = try #require(HexColor.nsColor("#FF0000"))
        let c = try #require(red.usingColorSpace(.sRGB))
        #expect(c.redComponent == 1 && c.greenComponent == 0 && c.blueComponent == 0)
        #expect(HexColor.nsColor("red") == nil)
    }
}

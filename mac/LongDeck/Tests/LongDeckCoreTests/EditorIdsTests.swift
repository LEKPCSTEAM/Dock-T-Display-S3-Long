import Testing
@testable import LongDeckCore

@Suite struct EditorIdsTests {
    @Test func prefixIsGraphemeSafe() {
        #expect(EditorText.prefix("abc", maxBytes: 2) == "ab")
        #expect(EditorText.prefix("ทดสอบ", maxBytes: 7) == "ทด")
        #expect(EditorText.prefix("é", maxBytes: 1) == "")
        #expect(EditorText.prefix("👍🏽x", maxBytes: 8) == "👍🏽")
        #expect(EditorText.prefix("👍🏽x", maxBytes: 7) == "")
    }

    @Test func makeVectors() {
        let cases: [(String, Set<String>, String)] = [
            ("key", [], "key"),
            ("key", ["key"], "key2"),
            ("key", ["key", "key2", "key3"], "key4"),
            ("VS Code", [], "vscode"),
            ("ทดสอบ", [], "w"),
            ("net_down", [], "netdown"),
            ("abcdefghijklmnop", [], "abcdefghijkl"),
            ("abcdefghijklmnop", ["abcdefghijkl"], "abcdefghijkl2"),
        ]
        for (base, taken, expected) in cases {
            #expect(EditorIds.make(base: base, taken: taken) == expected)
        }
    }

    @Test func idsFitFifteenBytes() {
        var taken: Set<String> = ["abcdefghijkl"]
        for n in 2...999 { taken.insert("abcdefghijkl\(n)") }
        let id = EditorIds.make(base: "abcdefghijkl", taken: taken)
        #expect(id == "abcdefghijk1000")
        #expect(id.utf8.count == 15)
    }
}

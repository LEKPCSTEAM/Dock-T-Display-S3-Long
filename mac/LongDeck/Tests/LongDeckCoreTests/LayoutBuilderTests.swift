import Foundation
import Testing
@testable import LongDeckCore

private func config(label: String = "A") -> DeckConfig {
    func k(_ id: String, _ col: Int, long: DeckAction? = nil, label: String) -> KeyConfig {
        KeyConfig(id: id, col: col, row: 0, w: 1, h: 1, label: label, icon: nil,
                  background: "#222222", action: .shell("true"), longAction: long)
    }
    return DeckConfig(version: 1, pages: [
        PageConfig(name: "One", keys: [k("a", 0, label: label), k("b", 1, long: .shell("x"), label: "B")]),
        PageConfig(name: "Two", keys: [k("c", 0, label: "C")]),
    ])
}

private func stubRender(_ key: KeyConfig) -> Data {
    Data(repeating: UInt8(truncatingIfNeeded: key.label.utf8.first ?? 0), count: 3)
}

@Suite struct LayoutBuilderTests {
    @Test func assignsFaceIdsAndHasLong() throws {
        let built = LayoutBuilder.build(config(), render: stubRender)
        let root = try #require(JSONSerialization.jsonObject(with: Data(built.json.utf8)) as? [String: Any])
        let pages = try #require(root["pages"] as? [[String: Any]])
        let w0 = try #require(pages[0]["widgets"] as? [[String: Any]])
        let w1 = try #require(pages[1]["widgets"] as? [[String: Any]])
        #expect(w0[0]["face"] as? Int == 1)
        #expect(w0[1]["face"] as? Int == 2)
        #expect(w1[0]["face"] as? Int == 3)
        #expect(w0[0]["long"] as? Bool == false)
        #expect(w0[1]["long"] as? Bool == true)
        #expect(Set(built.faces.keys) == [1, 2, 3])
        #expect(built.faces[1]?.w == 74 && built.faces[1]?.h == 84)
    }

    @Test func hashChangesWithLabelAndIsStable() {
        let a1 = LayoutBuilder.build(config(), render: stubRender)
        let a2 = LayoutBuilder.build(config(), render: stubRender)
        let b = LayoutBuilder.build(config(label: "Z"), render: stubRender)
        #expect(a1.hash == a2.hash)
        #expect(a1.hash != b.hash)
        #expect(a1.hash.count == 16)
    }

    @Test func outputParsesAsBoardSchema() throws {
        let built = LayoutBuilder.build(config(), render: stubRender)
        let root = try #require(JSONSerialization.jsonObject(with: Data(built.json.utf8)) as? [String: Any])
        #expect(root["hash"] as? String == built.hash)
        let pages = try #require(root["pages"] as? [[String: Any]])
        #expect(pages[0]["name"] as? String == "One")
        let widget = try #require((pages[0]["widgets"] as? [[String: Any]])?.first)
        for name in ["id", "type", "col", "row", "w", "h", "face", "long"] {
            #expect(widget[name] != nil)
        }
        #expect(widget["type"] as? String == "key")
        #expect(widget["id"] as? String == "a")
    }
}

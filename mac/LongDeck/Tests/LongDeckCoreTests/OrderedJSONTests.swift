import Foundation
import Testing
@testable import LongDeckCore

let settingsFixture: String = {
    let events = ["Notification", "PermissionRequest", "PostToolUse", "PreToolUse", "SessionEnd",
                  "SessionStart", "Stop", "StopFailure", "SubagentStop", "UserPromptSubmit"]
    let hooks = events.map { name in
        [
            "    \"\(name)\": [",
            "      {",
            "        \"hooks\": [",
            "          {",
            "            \"type\": \"command\",",
            "            \"command\": \"/Users/dev/.config/iterm2/cc-status\"",
            "          }",
            "        ]",
            "      }",
            "    ]",
        ].joined(separator: "\n")
    }.joined(separator: ",\n")
    return """
    {
      "env": {
        "EXAMPLE_FLAG": "1"
      },
      "model": "opus",
      "hooks": {
    \(hooks)
      },
      "statusLine": {
        "type": "command",
        "command": "ccstatusline",
        "padding": 0,
        "refreshInterval": 10
      },
      "theme": "dark",
      "label": "ทดสอบ \\"q\\" \\\\ /x",
      "ratio": 0.25,
      "flags": [],
      "nested": {}
    }

    """
}()

@Suite struct OrderedJSONTests {
    @Test func roundTripsFixtureByteForByte() throws {
        let v = try JSONText.parse(Data(settingsFixture.utf8))
        #expect(JSONText.pretty(v) == settingsFixture)
    }

    @Test func compactMatchesJSONStringify() throws {
        let s = "{\"b\":1,\"a\":[true,null,\"x\\ny\"]}"
        #expect(JSONText.compact(try JSONText.parse(Data(s.utf8))) == s)
    }

    @Test func escapesLikeJSONStringify() {
        #expect(JSONText.compact(.string("\u{01}")) == "\"\\u0001\"")
        #expect(JSONText.compact(.string("a/b")) == "\"a/b\"")
        #expect(JSONText.compact(.string("é")) == "\"é\"")
        #expect(JSONText.compact(.string("\u{08}\u{0C}\t\r\"\\")) == "\"\\b\\f\\t\\r\\\"\\\\\"")
    }

    @Test func decodesSurrogatePairs() throws {
        let v = try JSONText.parse(Data("\"\\ud83d\\ude00\"".utf8))
        #expect(v == .string("😀"))
    }

    @Test func rejectsMalformed() {
        for bad in ["{", "{\"a\":1}x", "[1,]"] {
            #expect(throws: (any Error).self) { try JSONText.parse(Data(bad.utf8)) }
        }
    }

    @Test func settingAndRemovingKeepOrder() throws {
        let v = try JSONText.parse(Data("{\"a\":1,\"b\":2,\"c\":3}".utf8))
        #expect(JSONText.compact(v.setting("b", .number("9"))) == "{\"a\":1,\"b\":9,\"c\":3}")
        #expect(JSONText.compact(v.setting("d", .bool(true))) == "{\"a\":1,\"b\":2,\"c\":3,\"d\":true}")
        #expect(JSONText.compact(v.removing("b")) == "{\"a\":1,\"c\":3}")
        #expect(v["c"] == .number("3"))
        #expect(v["zz"] == nil)
    }
}

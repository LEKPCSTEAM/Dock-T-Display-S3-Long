import Foundation
import Testing
@testable import LongDeckCore

@Suite struct ClaudeTextTests {
    @Test func cappedKeepsShortStrings() {
        #expect(ClaudeText.capped("caltera", bytes: 23) == "caltera")
    }

    @Test func cappedCutsAtGraphemeWithEllipsis() {
        let out = ClaudeText.capped("โปรเจกต์ทดสอบยาวมาก", bytes: 23)
        #expect(out == "โปรเจก…")
        #expect(out.utf8.count == 21)
    }

    @Test func cappedReplacesControlChars() {
        #expect(ClaudeText.capped("a\tb\u{7}", bytes: 23) == "a b ")
    }

    @Test func cappedLeftKeepsTail() {
        let path = "/" + String(repeating: "d/", count: 55) + "main.cpp"
        #expect(path.utf8.count >= 118)
        let out = ClaudeText.cappedLeft(path, bytes: 80)
        #expect(out.hasPrefix("…"))
        #expect(out.hasSuffix("main.cpp"))
        #expect(out.utf8.count <= 80)
    }

    @Test func toolLabelStripsMcpPrefix() {
        #expect(ClaudeText.toolLabel("mcp__claude_ai_Notion__notion-search") == "notion-search")
        #expect(ClaudeText.toolLabel("Bash") == "Bash")
        #expect(ClaudeText.toolLabel("A_very_long_tool_name_here").utf8.count <= 15)
    }

    @Test func summaryPerTool() {
        let cwd = "/tmp/work/p"
        let cases: [(String, String, String)] = [
            ("Bash", #"{"command":"echo hi\nsecond"}"#, "echo hi"),
            ("Edit", #"{"file_path":"/tmp/work/p/src/main.cpp"}"#, "src/main.cpp"),
            ("Write", #"{"file_path":"/etc/hosts"}"#, "/etc/hosts"),
            ("WebFetch", #"{"url":"https://example.com/a"}"#, "https://example.com/a"),
            ("Grep", #"{"pattern":"foo.*bar"}"#, "foo.*bar"),
            ("Foo", #"{"a":1}"#, #"{"a":1}"#),
        ]
        for (tool, input, expected) in cases {
            #expect(ClaudeText.summary(toolName: tool, toolInputJSON: input, cwd: cwd) == expected)
        }
    }

    @Test func projectFromPath() {
        #expect(ClaudeText.project("/a/b/caltera/") == "caltera")
        #expect(ClaudeText.project(nil) == "?")
        #expect(ClaudeText.project("") == "?")
    }
}

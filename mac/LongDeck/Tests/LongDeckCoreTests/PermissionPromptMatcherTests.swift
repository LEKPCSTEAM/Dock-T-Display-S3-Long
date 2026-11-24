import Foundation
import Testing
@testable import LongDeckCore

func promptScreen(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

let promptRule = String(repeating: "─", count: 80)
let hk1Input = #"{"command":"pio run -e ntp_clock","description":"Build firmware"}"#
let curlInput = #"{"command":"curl https://example.com"}"#
let commitInput = #"{"command":"git commit -m \"feat(longdeck): add the permission overlay and the claude sessions widget to the deck board\"","description":"Commit"}"#
let denyRow = "   3. No, and tell Claude what to do differently (esc)"

let promptF1 = promptScreen([
    "⏺ Bash(pio run -e ntp_clock)",
    "  ⎿  Running…",
    "",
    promptRule,
    " Bash command",
    "",
    "   pio run -e ntp_clock",
    "   Build firmware",
    "",
    " Do you want to proceed?",
    " ❯ 1. Yes",
    "   2. Yes, and don't ask again for pio run commands in /tmp/work/T-Display-S3-Long",
    denyRow,
    "",
])

let promptF2 = promptScreen([
    "⏺ Bash(pio run -e ntp_clock)",
    "  ⎿  Running…",
    "",
    promptRule,
    " Bash command",
    "",
    "   pio run -e ntp_clock",
    "   Build firmware",
    "",
    " Do you want to proceed?",
    " ❯ 1. Yes",
    "  2. No, and tell Claude what to do differently (esc)",
    "",
])

let promptF3 = promptScreen([
    promptRule,
    " Edit file",
    " src/main.cpp",
    String(repeating: "╌", count: 40),
    "  12 -  int x = 1;",
    "  12 +  int x = 2;",
    String(repeating: "╌", count: 40),
    " Do you want to make this edit to main.cpp?",
    " ❯ 1. Yes",
    "   2. Yes, allow all edits during this session (shift+tab)",
    denyRow,
])

let promptF4 = promptScreen([
    " Bash command",
    "   pio run -e ntp_clock",
    " This terminal is too short. Make it taller to choose Yes, or choose No.",
    " ❯ Yes",
    "   No, and tell Claude what to do differently (esc)",
])

let promptF5 = promptScreen([
    "⏺ Done. The firmware builds.",
    "",
    promptRule,
    "> ",
    promptRule,
    "  ? for shortcuts",
])

let promptF6 = promptScreen([
    "⏺ Bash(rm -rf build)",
    "  ⎿  Running…",
    "",
    promptRule,
    " Bash command",
    "",
    "   rm -rf build",
    "   Clean",
    "",
    " Do you want to proceed?",
    " ❯ 1. Yes",
    "   2. Yes, and don't ask again for rm commands in /tmp/work/T-Display-S3-Long",
    denyRow,
    "",
])

let promptF7 = promptScreen([
    "⏺ Bash(git commit -m \"feat(longdeck): add the permission overlay and…)",
    "  ⎿  Running…",
    "",
    promptRule,
    " Bash command",
    "",
    "   git commit -m \"feat(longdeck): add the permission overlay a",
    "   nd the claude sessions widget to the deck board\"",
    "   Commit",
    "",
    " Do you want to proceed?",
    " ❯ 1. Yes",
    "   2. Yes, and don't ask again for git commit commands in /tmp/work/T-Display-S3-Long",
    denyRow,
    "",
])

let promptF8 = promptScreen([
    " Bash command",
    "   curl https://example.com",
    " Do you want to proceed?",
    " ❯ 1. No, and tell Claude what to do differently (esc)",
    "   2. Yes",
])

private func boxed(_ s: String) -> String { "│" + s.padding(toLength: 46, withPad: " ", startingAt: 0) + "│" }

let promptF9 = promptScreen([
    "╭" + String(repeating: "─", count: 46) + "╮",
    boxed(" Bash command"),
    boxed(""),
    boxed("   pio run -e ntp_clock"),
    boxed("   Build firmware"),
    boxed(""),
    boxed(" Do you want to proceed?"),
    boxed(" ❯ 1. Yes"),
    boxed("   2. Yes, and don't ask again for pio run"),
    boxed("   commands in /tmp/work/T-Display-S3-Long"),
    boxed("   3. No, and tell Claude what to do"),
    boxed("   differently (esc)"),
    "╰" + String(repeating: "─", count: 46) + "╯",
])

let promptF10 = promptF1 + promptScreen(
    (1...20).map { "Compiling .pio/build/ntp_clock/src/unit\($0).cpp.o" } + [promptRule, "> ", promptRule])

let promptAfterOtherCommand = promptScreen([
    "⏺ Bash(pio run -e ntp_clock)",
    "  ⎿  Build complete",
    "⏺ Bash(rm -rf build)",
    "  ⎿  Running…",
    promptRule,
    " Bash command",
    "",
    "   rm -rf build",
    "   Clean",
    "",
    " Do you want to proceed?",
    " ❯ 1. Yes",
    "   2. Yes, and don't ask again for rm commands in /tmp/work/T-Display-S3-Long",
    denyRow,
])

let promptCutWithNumberedPreview = promptScreen([
    " Bash command",
    "   cat <<EOF",
    "   1. Yes",
    "   2. No, thanks",
    "   EOF",
    " This terminal is too short. Make it taller to choose Yes, or choose No.",
    " ❯ Yes",
    "   No, and tell Claude what to do differently (esc)",
])

func hints(_ tool: String, _ input: String) -> PromptHints? {
    PromptHints.from(toolName: tool, toolInputJSON: input, cwd: claudeCwd)
}

let hk1Hints = hints("Bash", hk1Input)!

@Suite struct PermissionPromptMatcherTests {
    @Test func readsBashPrompt() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF1))
        #expect(s.yes == "1")
        #expect(s.always == "2")
        #expect(s.no == "3")
        #expect(PermissionPromptMatcher.matches(s, hk1Hints))
    }

    @Test func promptWithoutAlwaysRow() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF2))
        #expect(s.yes == "1")
        #expect(s.always == nil)
        #expect(s.no == "2")
    }

    @Test func readsEditPrompt() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF3))
        let h = try #require(hints("Edit", #"{"file_path":"/tmp/work/T-Display-S3-Long/src/main.cpp","new_string":"b","old_string":"a"}"#))
        #expect(PermissionPromptMatcher.matches(s, h))
        #expect(s.always == "2")
        #expect(s.no == "3")
    }

    @Test func refusesCutPrompt() {
        #expect(PermissionPromptMatcher.parse(promptF4) == nil)
    }

    @Test func refusesIdleScreen() {
        #expect(PermissionPromptMatcher.parse(promptF5) == nil)
    }

    @Test func refusesOtherCommand() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF6))
        #expect(!PermissionPromptMatcher.matches(s, hk1Hints))
    }

    @Test func handlesWrappedCommand() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF7))
        let h = try #require(hints("Bash", commitInput))
        #expect(h.needle == #"gitcommit-m"feat(longdeck):addth"#)
        #expect(PermissionPromptMatcher.matches(s, h))
    }

    @Test func readsNoFirstVariant() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF8))
        #expect(s.no == "1")
        #expect(s.yes == "2")
        #expect(s.always == nil)
        #expect(PermissionPromptMatcher.matches(s, try #require(hints("Bash", curlInput))))
    }

    @Test func stripsBoxBorders() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF9))
        #expect(PermissionPromptMatcher.matches(s, hk1Hints))
        #expect(s.always == "2")
        #expect(s.no == "3")
    }

    @Test func ignoresStaleOptionsHigherUp() {
        #expect(PermissionPromptMatcher.parse(promptF10) == nil)
    }

    @Test func hintsPerTool() throws {
        #expect(hk1Hints.needle == "piorun-entp_clock")
        #expect(hk1Hints.titles == ["Bash command"])
        let edit = try #require(hints("Edit", #"{"file_path":"/tmp/work/T-Display-S3-Long/src/main.cpp"}"#))
        #expect(edit.needle == "main.cpp")
        #expect(edit.titles == ["Edit file", "Create file", "Overwrite file", "Write file"])
        #expect(hints("Bash", #"{"command":""}"#) == nil)
        #expect(hints("mcp__x__do it", "{}")?.needle == "doit")
        #expect(hints("mcp__x__do it", "{}")?.titles == [])
    }

    @Test func hintsForFilesUrlsAndBadInput() {
        #expect(hints("Read", #"{"file_path":"/a/b/my notes.txt"}"#) == PromptHints(titles: ["Read file"], needle: "mynotes.txt"))
        #expect(hints("NotebookEdit", #"{"notebook_path":"/a/x.ipynb"}"#) == PromptHints(titles: [], needle: "x.ipynb"))
        #expect(hints("WebFetch", #"{"url":"https://docs.example.com/a?b=1"}"#) == PromptHints(titles: [], needle: "docs.example.com"))
        #expect(hints("Bash", #"{"command":"echo 1\necho 2"}"#)?.needle == "echo1")
        #expect(hints("Bash", "not json") == nil)
        #expect(hints("Bash", #"{"command":7}"#) == nil)
        #expect(hints("Edit", #"{"file_path":"/"}"#) == nil)
        #expect(hints("WebFetch", #"{"url":"nonsense"}"#) == nil)
        #expect(hints("", "{}") == nil)
        #expect(hints("mcp__srv__a_really_long_tool_name", "{}")?.needle.contains("…") == false)
    }

    @Test func needleMustSitInTheDialogNotInHistoryAbove() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptAfterOtherCommand))
        #expect(s.regionLines.contains("⏺ Bash(pio run -e ntp_clock)"))
        #expect(!PermissionPromptMatcher.matches(s, hk1Hints))
        #expect(PermissionPromptMatcher.matches(s, try #require(hints("Bash", #"{"command":"rm -rf build"}"#))))
    }

    @Test func refusesCutDialogEvenWithNumberedPreview() {
        #expect(PermissionPromptMatcher.parse(promptCutWithNumberedPreview) == nil)
        let otherPointer = promptCutWithNumberedPreview.replacingOccurrences(of: "❯ Yes", with: "› Yes")
        #expect(PermissionPromptMatcher.parse(otherPointer) == nil)
    }

    @Test func ignoresTrailingBlankRows() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF1 + String(repeating: "\n", count: 30)))
        #expect(PermissionPromptMatcher.matches(s, hk1Hints))
    }

    @Test func refusesBrokenOptionBlocks() {
        let head = [" Bash command", "   pio run -e ntp_clock"]
        let yes = " ❯ 1. Yes"
        let no = "   2. No, and tell Claude what to do differently (esc)"
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [yes, "a", "b", "c", no])) == nil)
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [yes])) == nil)
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [" ❯ 1. Yes", "   2. Yes", denyRow])) == nil)
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [yes, "   3. No"])) == nil)
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [" ❯ 1. Yes, please", no])) == nil)
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [yes, "   2. Maybe"])) == nil)
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [yes, no, "❯ "])) == nil)
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [yes, no] + Array(repeating: "x", count: 15))) == nil)
        #expect(PermissionPromptMatcher.parse(promptScreen(head + [yes, no] + Array(repeating: "x", count: 14))) != nil)
    }

    @Test func regionIsThirtyRowsAboveFirstOption() throws {
        let filler = (1...35).map { "line \($0)" }
        let s = try #require(PermissionPromptMatcher.parse(promptScreen(filler + [" ❯ 1. Yes", "   2. No"])))
        #expect(s.regionLines.count == 30)
        #expect(s.regionLines.first == "line 6")
        #expect(s.regionLines.last == "line 35")
    }
}

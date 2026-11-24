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

let promptF7WordWrap = promptF7
    .replacingOccurrences(of: "permission overlay a\n", with: "permission overlay\n")
    .replacingOccurrences(of: "   nd the claude", with: "   and the claude")

let previewRule = String(repeating: "╌", count: 40)

func bashDialog(_ body: [String], history: [String] = [],
                always: String = "   2. Yes, and don't ask again for these commands in /tmp/work") -> String {
    promptScreen(history + [promptRule, " Bash command", ""] + body.map { "   " + $0 }
        + ["", " Do you want to proceed?", " ❯ 1. Yes", always, denyRow])
}

func fileDialog(_ title: String, _ path: String, _ preview: [String]) -> String {
    promptScreen([promptRule, " " + title, " " + path, previewRule] + preview
        + [previewRule, " Do you want to make this edit to main.cpp?", " ❯ 1. Yes",
           "   2. Yes, allow all edits during this session (shift+tab)", denyRow])
}

func bashInput(_ command: String, _ description: String? = nil) -> String {
    var object: [String: Any] = ["command": command]
    if let description { object["description"] = description }
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

func hints(_ tool: String, _ input: String) -> PromptHints? {
    PromptHints.from(toolName: tool, toolInputJSON: input, cwd: claudeCwd)
}

private func screenOf(_ s: String) throws -> PromptScreen { try #require(PermissionPromptMatcher.parse(s)) }

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
        let h = try #require(hints("Bash", commitInput))
        let words = try screenOf(promptF7WordWrap)
        #expect(PermissionPromptMatcher.matches(words, h, paneWidth: 61))
        #expect(!PermissionPromptMatcher.matches(words, h, paneWidth: 62))
        #expect(!PermissionPromptMatcher.matches(words, h))
        #expect(!PermissionPromptMatcher.matches(try screenOf(promptF7), h, paneWidth: 63))
    }

    @Test func midWordWrapIsAmbiguous() throws {
        let s = try screenOf(bashDialog(["rm -rf /tmp", "/x"]))
        #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("rm -rf /tmp/x"))), paneWidth: 15))
        #expect(PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("rm -rf /tmp /x"))), paneWidth: 15))
    }

    @Test func fullRowCannotEndALine() throws {
        let s = try screenOf(bashDialog(["echo", "rm"]))
        let twoLines = try #require(hints("Bash", bashInput("echo\nrm")))
        let oneLine = try #require(hints("Bash", bashInput("echo rm")))
        #expect(PermissionPromptMatcher.matches(s, twoLines))
        #expect(!PermissionPromptMatcher.matches(s, oneLine))
        #expect(PermissionPromptMatcher.matches(s, oneLine, paneWidth: 8))
        #expect(!PermissionPromptMatcher.matches(s, twoLines, paneWidth: 8))
    }

    @Test func ambiguousWidthNearEdgeIsRefused() throws {
        let s = try screenOf(bashDialog(["echo 🖥", "rm"]))
        let oneLine = try #require(hints("Bash", bashInput("echo 🖥 rm")))
        let twoLines = try #require(hints("Bash", bashInput("echo 🖥\nrm")))
        #expect(!PermissionPromptMatcher.matches(s, oneLine, paneWidth: 11))
        #expect(!PermissionPromptMatcher.matches(s, twoLines, paneWidth: 11))
        #expect(PermissionPromptMatcher.matches(s, twoLines, paneWidth: 20))
        #expect(PermissionPromptMatcher.matches(s, oneLine, paneWidth: 10))
        for glyph in ["🌡", "🗑", "⚠️", "…"] {
            let row = try screenOf(bashDialog(["echo \(glyph)", "rm"]))
            #expect(!PermissionPromptMatcher.matches(row, try #require(hints("Bash", bashInput("echo \(glyph) rm"))), paneWidth: 11),
                    "\(glyph)")
        }
    }

    @Test func tmuxWideGapsAreUncertain() throws {
        for glyph in ["ꥠ", "🈐", "\u{1B001}", "\u{FE10}", "\u{1F900}", "㉈"] {
            let w = PermissionPromptMatcher.displayWidth(glyph)
            let pair: [Int] = [w.min, w.max]
            #expect(pair == [1, 2], "\(glyph)")
            let s = try screenOf(bashDialog(["echo \(glyph)", "rm"]))
            #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("echo \(glyph)\nrm"))), paneWidth: 11),
                    "\(glyph)")
        }
    }

    @Test func displayWidthCountsWideCharacters() {
        func width(_ s: String) -> [Int] {
            let w = PermissionPromptMatcher.displayWidth(s)
            return [w.min, w.max]
        }
        #expect(width("abc") == [3, 3])
        #expect(width("日本") == [4, 4])
        #expect(width("กิน") == [2, 2])
        #expect(width("🚀") == [2, 2])
        #expect(width("❯ ⏺ …") == [5, 8])
        #expect(width("🖥🌡🗑") == [3, 6])
        #expect(width("⚠️") == [1, 2])
    }

    @Test func readsNoFirstVariant() throws {
        let s = try #require(PermissionPromptMatcher.parse(promptF8))
        #expect(s.no == "1")
        #expect(s.yes == "2")
        #expect(s.always == nil)
        let framed = try screenOf(promptScreen([promptRule]) + promptF8)
        #expect(PermissionPromptMatcher.matches(framed, try #require(hints("Bash", curlInput))))
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
        #expect(hk1Hints == PromptHints(titles: ["Bash command"], bodies: [["pio run -e ntp_clock"]],
                                        detail: ["Build firmware"], question: "Do you want to proceed?",
                                        alwaysPrefixes: ["Yes, and don't ask again for "]))
        let edit = try #require(hints("Edit", #"{"file_path":"/tmp/work/T-Display-S3-Long/src/main.cpp"}"#))
        #expect(edit.bodies == [["src/main.cpp"], ["/tmp/work/T-Display-S3-Long/src/main.cpp"]])
        #expect(edit.titles == ["Edit file", "Create file", "Overwrite file", "Write file"])
        #expect(edit.alwaysPrefixes == [])
        #expect(edit.question == nil)
        #expect(hints("Bash", #"{"command":""}"#) == nil)
        #expect(hints("Bash", #"{"command":"  \n \n"}"#) == nil)
        #expect(hints("Bash", #"{"command":"ls","description":7}"#) == nil)
        #expect(hints("mcp__x__do it", "{}") == nil)
        #expect(hints("Bash", #"{"command":"\n  echo   1 \n\n  echo 2\n"}"#)?.bodies == [["echo   1", "", "echo 2"]])
    }

    @Test func hintsForFilesAndBadInput() {
        #expect(hints("Read", #"{"file_path":"/a/b/my  notes.txt"}"#)
            == PromptHints(titles: ["Read file"], bodies: [["/a/b/my  notes.txt"]]))
        #expect(hints("Write", #"{"file_path":"/tmp/work/T-Display-S3-Long/a.txt"}"#)?.bodies
            == [["a.txt"], ["/tmp/work/T-Display-S3-Long/a.txt"]])
        let edit = #"{"file_path":"/x/a.c"}"#
        #expect(PromptHints.from(toolName: "Edit", toolInputJSON: edit, cwd: "/x/")?.bodies == [["a.c"], ["/x/a.c"]])
        #expect(PromptHints.from(toolName: "Edit", toolInputJSON: edit, cwd: nil)?.bodies == [["/x/a.c"]])
        #expect(PromptHints.from(toolName: "Edit", toolInputJSON: edit, cwd: "/")?.bodies == [["/x/a.c"]])
        #expect(PromptHints.from(toolName: "Edit", toolInputJSON: edit, cwd: "/x/a")?.bodies == [["/x/a.c"]])
        #expect(hints("Bash", "not json") == nil)
        #expect(hints("Bash", #"{"command":7}"#) == nil)
        #expect(hints("Edit", #"{"file_path":""}"#) == nil)
        #expect(hints("Edit", #"{"notebook_path":"/a/x.ipynb"}"#) == nil)
        #expect(hints("Edit", #"{"file_path":"/a\nb"}"#) == nil)
        #expect(hints("", "{}") == nil)
    }

    @Test func toolsWithoutKnownTitleAreUnverifiable() {
        for (tool, input) in [("WebFetch", #"{"url":"https://docs.example.com/a"}"#),
                              ("NotebookEdit", #"{"notebook_path":"/a/x.ipynb"}"#),
                              ("mcp__x__do it", "{}"), ("Grep", #"{"pattern":"x"}"#), ("Glob", #"{"pattern":"*"}"#),
                              ("WebSearch", #"{"query":"x"}"#), ("Task", #"{"description":"x"}"#)] {
            #expect(hints(tool, input) == nil, "\(tool)")
        }
    }

    @Test func historyAboveDialogDoesNotCount() throws {
        let s = try screenOf(promptAfterOtherCommand)
        #expect(s.regionLines.contains("⏺ Bash(pio run -e ntp_clock)"))
        #expect(!PermissionPromptMatcher.matches(s, hk1Hints))
        #expect(PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("rm -rf build", "Clean")))))
    }

    @Test func sharedPrefixCommandsDoNotMatch() throws {
        let prefix = "cd /Users/lek/WORK/MY_PROJECT/T-Display-S3-Long && "
        let s = try screenOf(bashDialog([prefix + "rm -rf build", "Clean"]))
        #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput(prefix + "ls", "Clean")))))
        #expect(PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput(prefix + "rm -rf build", "Clean")))))
    }

    @Test func commandMustSitRightUnderTitle() throws {
        let make = try #require(hints("Bash", bashInput("make")))
        #expect(!PermissionPromptMatcher.matches(try screenOf(bashDialog(["rm -rf build", "make"])), make))
        #expect(!PermissionPromptMatcher.matches(try screenOf(bashDialog(["", "", "make"])), make))
        #expect(PermissionPromptMatcher.matches(try screenOf(bashDialog(["", "make"])), make))
    }

    @Test func longerOnScreenCommandDoesNotMatch() throws {
        let rm = try #require(hints("Bash", bashInput("rm -rf build")))
        let rmClean = try #require(hints("Bash", bashInput("rm -rf build", "Clean")))
        #expect(!PermissionPromptMatcher.matches(try screenOf(bashDialog(["rm -rf build /"])), rm))
        #expect(!PermissionPromptMatcher.matches(try screenOf(bashDialog(["rm -rf build", "/ --no-preserve-root"])), rm))
        #expect(!PermissionPromptMatcher.matches(
            try screenOf(bashDialog(["rm -rf build", "/ --no-preserve-root", "Clean"])), rmClean))
        #expect(PermissionPromptMatcher.matches(try screenOf(bashDialog(["rm -rf build"])), rm))
        #expect(PermissionPromptMatcher.matches(try screenOf(bashDialog(["rm -rf build", "Clean"])), rmClean))
    }

    @Test func truncatedCommandDoesNotMatch() throws {
        let s = try screenOf(bashDialog(["git commit -m \"feat(longdeck): add the permission overlay…", "Commit"]))
        #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", commitInput))))
    }

    @Test func wholeMultiLineCommandMustMatch() throws {
        let h = try #require(hints("Bash", bashInput("python3 - <<'EOF'\nprint(1)\nEOF", "Run script")))
        let same = try screenOf(bashDialog(["python3 - <<'EOF'", "print(1)", "EOF", "Run script"]))
        let other = try screenOf(bashDialog(["python3 - <<'EOF'", "import shutil; shutil.rmtree('/tmp/work')", "EOF", "Run script"]))
        let cut = try screenOf(bashDialog(["python3 - <<'EOF'", "…", "Run script"]))
        #expect(PermissionPromptMatcher.matches(same, h))
        #expect(!PermissionPromptMatcher.matches(other, h))
        #expect(!PermissionPromptMatcher.matches(cut, h))
    }

    @Test func filesMatchFullPathNotBaseName() throws {
        let h = try #require(hints("Edit", #"{"file_path":"/tmp/work/T-Display-S3-Long/src/main.cpp"}"#))
        let diff = ["  1 -  int a;", "  1 +  int b;"]
        let cmake = ["  3 -  add_executable(app main.cpp)", "  3 +  add_executable(app src/main.cpp)"]
        #expect(PermissionPromptMatcher.matches(try screenOf(fileDialog("Edit file", "src/main.cpp", diff)), h))
        #expect(PermissionPromptMatcher.matches(
            try screenOf(fileDialog("Edit file", "/tmp/work/T-Display-S3-Long/src/main.cpp", diff)), h))
        #expect(!PermissionPromptMatcher.matches(try screenOf(fileDialog("Edit file", "test/main.cpp", diff)), h))
        #expect(!PermissionPromptMatcher.matches(try screenOf(fileDialog("Edit file", "main.cpp", diff)), h))
        #expect(!PermissionPromptMatcher.matches(try screenOf(fileDialog("Edit file", "CMakeLists.txt", cmake)), h))
        #expect(!PermissionPromptMatcher.matches(try screenOf(fileDialog("Read file", "src/main.cpp", diff)), h))
    }

    @Test func titleRowMustBeExactAndUnique() throws {
        let diff = fileDialog("Edit file", "mac/LongDeck/Tests/LongDeckCoreTests/PermissionPromptMatcherTests.swift",
                              ["  12 -      \" Bash command\",", "  12 +      \" Bash command\",",
                               "  13 +      \"   pio run -e ntp_clock\","])
        #expect(!PermissionPromptMatcher.matches(try screenOf(diff), hk1Hints))
        let preview = fileDialog("Create file", "notes.txt",
                                 [" Bash command", "", "   pio run -e ntp_clock", "   Build firmware", ""])
        #expect(!PermissionPromptMatcher.matches(try screenOf(preview), hk1Hints))
        let plural = promptScreen([promptRule, " Bash commands", "", "   pio run -e ntp_clock", "   Build firmware", "",
                                   " ❯ 1. Yes", "   2. No, and tell Claude what to do differently (esc)"])
        #expect(!PermissionPromptMatcher.matches(try screenOf(plural), hk1Hints))
    }

    @Test func boxCharsInsideTextStaySignificant() throws {
        let s = try screenOf(bashDialog(["echo a│b"]))
        #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("echo ab")))))
        #expect(PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("echo a│b")))))
    }

    @Test func alwaysNeedsSingleYesCommaRow() throws {
        let f1 = try screenOf(promptF1)
        #expect(f1.alwaysLabel == "Yes, and don't ask again for pio run commands in /tmp/work/T-Display-S3-Long")
        let s = try screenOf(promptScreen([
            " Bash command", "   pio run -e ntp_clock", " ❯ 1. Yes",
            "   2. Yes, and don't ask again for pio run commands in /tmp/work/T-Display-S3-Long",
            "   3. Yes, and always allow access to /tmp/work from this project",
            "   4. No, and tell Claude what to do differently (esc)",
        ]))
        #expect(s.yes == "1")
        #expect(s.always == nil)
        #expect(s.alwaysLabel == nil)
        #expect(s.no == "4")
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

    @Test func blankRowInsideCommandIsNotTheEnd() throws {
        let s = try screenOf(bashDialog(["npm test", "", "rm -rf ~", "Run tests"]))
        #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("npm test")))))
        #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("npm test", "Run tests")))))
    }

    @Test func lineBreakIsNotAWrap() throws {
        let s = try screenOf(bashDialog(["echo", "rm -rf ~"]))
        #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("echo rm -rf ~")))))
    }

    @Test func descriptionIsNotTheWrappedCommandEnd() throws {
        let h = try #require(hints("Bash", bashInput("pio run -e ntp_clock Build firmware")))
        #expect(!PermissionPromptMatcher.matches(try screenOf(promptF1), h))
    }

    @Test func secondCommandLineIsNotTheDescription() throws {
        let s = try screenOf(bashDialog(["npm test", "rm -rf ~", "Run tests"]))
        #expect(!PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("npm test", "rm -rf ~")))))
        #expect(PermissionPromptMatcher.matches(s, try #require(hints("Bash", bashInput("npm test\nrm -rf ~", "Run tests")))))
    }

    @Test func descriptionMustMatchExactly() throws {
        #expect(!PermissionPromptMatcher.matches(try screenOf(bashDialog(["pio run -e ntp_clock"])), hk1Hints))
        #expect(!PermissionPromptMatcher.matches(try screenOf(bashDialog(["pio run -e ntp_clock", "Build firmware!"])), hk1Hints))
        let bare = try #require(hints("Bash", bashInput("pio run -e ntp_clock")))
        #expect(!PermissionPromptMatcher.matches(try screenOf(promptF1), bare))
    }

    @Test func onlyBlankRowsThenExactQuestion() throws {
        func dialog(_ tail: [String]) -> String {
            promptScreen([promptRule, " Bash command", "", "   pio run -e ntp_clock", "   Build firmware"] + tail
                + [" ❯ 1. Yes", "   2. No, and tell Claude what to do differently (esc)"])
        }
        #expect(!PermissionPromptMatcher.matches(try screenOf(dialog(["", " Note: runs in /tmp", " Do you want to proceed?"])), hk1Hints))
        #expect(!PermissionPromptMatcher.matches(try screenOf(dialog(["", " Do you want to proceed with this?"])), hk1Hints))
        #expect(!PermissionPromptMatcher.matches(try screenOf(dialog([""])), hk1Hints))
        #expect(!PermissionPromptMatcher.matches(try screenOf(dialog(["", " Do you want to proceed?", " (esc to cancel)"])), hk1Hints))
        #expect(PermissionPromptMatcher.matches(try screenOf(dialog(["", "", " Do you want to proceed?", ""])), hk1Hints))
    }

    @Test func titleMustSitBelowDialogTopBorder() throws {
        #expect(!PermissionPromptMatcher.matches(try screenOf(promptF8), try #require(hints("Bash", curlInput))))
        let body = ["", "   pio run -e ntp_clock", "   Build firmware", "", " Do you want to proceed?", " ❯ 1. Yes",
                    "   2. No, and tell Claude what to do differently (esc)"]
        let tall = (1...6).map { "   line \($0)" } + ["    Bash command"] + body
        #expect(!PermissionPromptMatcher.matches(try screenOf(promptScreen(tall)), hk1Hints))
        let indentedRule = ["   " + String(repeating: "─", count: 60), " Bash command"] + body
        #expect(!PermissionPromptMatcher.matches(try screenOf(promptScreen(indentedRule)), hk1Hints))
        let dashedRule = [String(repeating: "╌", count: 60), " Bash command"] + body
        #expect(!PermissionPromptMatcher.matches(try screenOf(promptScreen(dashedRule)), hk1Hints))
        #expect(PermissionPromptMatcher.matches(try screenOf(promptScreen([promptRule, " Bash command"] + body)), hk1Hints))
    }

    @Test func pathsCompareExactly() throws {
        let h = try #require(hints("Edit", #"{"file_path":"/tmp/work/T-Display-S3-Long/my  docs/a.txt"}"#))
        let diff = ["  1 -  a", "  1 +  b"]
        #expect(!PermissionPromptMatcher.matches(try screenOf(fileDialog("Edit file", "my docs/a.txt", diff)), h))
        #expect(PermissionPromptMatcher.matches(try screenOf(fileDialog("Edit file", "my  docs/a.txt", diff)), h))
    }

    @Test func regionIsThirtyRowsAboveFirstOption() throws {
        let filler = (1...35).map { "line \($0)" }
        let s = try #require(PermissionPromptMatcher.parse(promptScreen(filler + [" ❯ 1. Yes", "   2. No"])))
        #expect(s.regionLines.count == 30)
        #expect(s.regionLines.first == "line 6")
        #expect(s.regionLines.last == "line 35")
    }
}

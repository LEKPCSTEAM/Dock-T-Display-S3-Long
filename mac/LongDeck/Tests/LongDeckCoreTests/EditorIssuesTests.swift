import Testing
@testable import LongDeckCore

@Suite struct EditorIssuesTests {
    private let env = IssueEnvironment.permissive

    private func key(_ id: String, col: Int = 0, row: Int = 0, w: Int = 1, h: Int = 1,
                     label: String = "L", icon: IconRef? = nil, background: String = "#2B2B2B",
                     action: DeckAction = .shell("ls"), longAction: DeckAction? = nil,
                     foreground: String? = nil) -> KeyConfig {
        KeyConfig(id: id, col: col, row: row, w: w, h: h, label: label, icon: icon,
                  background: background, action: action, longAction: longAction, foreground: foreground)
    }

    private func config(_ keys: [KeyConfig], live: [LiveWidgetConfig] = [], name: String = "A") -> DeckConfig {
        DeckConfig(version: 1, pages: [PageConfig(name: name, keys: keys, live: live)])
    }

    private func messages(_ c: DeckConfig, _ e: IssueEnvironment? = nil) -> [String] {
        EditorIssues.check(c, e ?? env).map(\.message)
    }

    private func digits(_ n: Int, width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: width - s.count) + s
    }

    private func fullStatPages(_ n: Int) -> DeckConfig {
        var pages: [PageConfig] = []
        for p in 0..<n {
            var live: [LiveWidgetConfig] = []
            for i in 0..<16 {
                live.append(LiveWidgetConfig(
                    id: "s" + digits(p * 16 + i, width: 14), col: i % 8, row: i / 8, w: 1, h: 1,
                    kind: .stat(.diskFree, .sparkline)))
            }
            pages.append(PageConfig(name: "P" + digits(p, width: 22), keys: [], live: live))
        }
        return DeckConfig(version: 1, pages: pages)
    }

    @Test func sampleHasNoIssues() {
        #expect(EditorIssues.check(SampleConfig.dev, env).isEmpty)
    }

    @Test func newKeyNeedsAnApp() {
        var m = EditorModel(document: config([]), saved: nil)
        m.add(.key)
        #expect(m.issues(env) == [EditorIssue(severity: .error, page: 0, widget: "key", message: "Choose an app")])
        #expect(m.hasErrors(env))
    }

    @Test func actionValueErrors() {
        let cases: [(DeckAction, String)] = [
            (.openApp(path: ""), "Choose an app"),
            (.openURL("  "), "Enter a URL"),
            (.openURL("github.com"), "URL is not valid, include a scheme like https://"),
            (.hotkey(keyCode: 65535, modifiers: []), "Record a hotkey"),
            (.typeText(""), "Enter text to type"),
            (.shell(" "), "Enter a shell command"),
            (.shortcut(""), "Enter a Shortcut name"),
        ]
        for (action, message) in cases {
            #expect(messages(config([key("k", action: action)])) == [message])
            #expect(messages(config([key("k", longAction: action)])) == ["Long press: " + message])
        }
        #expect(messages(config([key("k", action: .openURL("https://github.com"))])).isEmpty)
    }

    @Test func colourErrors() {
        #expect(messages(config([key("k", background: "#12345")])) == ["Background must be #RRGGBB"])
        #expect(messages(config([key("k", foreground: "red")])) == ["Text colour must be #RRGGBB"])
        #expect(messages(config([key("k", background: "#a1b2c3", foreground: "#a1b2c3")])).isEmpty)
    }

    private func layoutFixtures() -> [DeckConfig] {
        let sessions1 = LiveWidgetConfig(id: "s", col: 0, row: 0, w: 1, h: 1, kind: .claudeSessions)
        let many = (0..<17).map { LiveWidgetConfig(id: "c\($0)", col: $0 % 8, row: ($0 / 8) % 2, w: 1, h: 1, kind: .clock) }
        return [
            config([key("a"), key("a", col: 1)]),
            config([key("a"), key("b")]),
            config([key("a", col: 7, w: 2)]),
            config([], live: [sessions1]),
            config([], live: many),
            config([key("a")], name: String(repeating: "n", count: 24)),
            DeckConfig(version: 1, pages: (0..<9).map { PageConfig(name: "P\($0)", keys: []) }),
            config([key("")]),
            config([key(String(repeating: "i", count: 16))]),
        ]
    }

    @Test func layoutRuleErrorsPerWidget() {
        let dup = EditorIssues.check(layoutFixtures()[0], env)
        #expect(dup == [EditorIssue(severity: .error, page: 0, widget: "a", message: "Widget id a is used twice")])
        let overlap = EditorIssues.check(layoutFixtures()[1], env)
        #expect(overlap == [EditorIssue(severity: .error, page: 0, widget: "b", message: "Overlaps a")])
        #expect(messages(layoutFixtures()[2]) == ["Outside the 8x2 grid"])
        #expect(messages(layoutFixtures()[3]) == ["Claude sessions needs at least 2 columns"])
        #expect(messages(layoutFixtures()[4]).contains("17 widgets, at most 16 per page"))
        #expect(messages(layoutFixtures()[5]) == ["Page name is 24 bytes, at most 23"])
        let pages = EditorIssues.check(layoutFixtures()[6], env)
        #expect(pages.first == EditorIssue(severity: .error, page: nil, widget: nil,
                                           message: "9 pages, the board takes at most 8"))
        #expect(messages(layoutFixtures()[7]) == ["Widget id is empty"])
        #expect(messages(layoutFixtures()[8]) == ["Widget id is 16 bytes, at most 15"])
    }

    @Test func warningsUseEnvironment() {
        let noFiles = IssueEnvironment(fileExists: { _ in false }, symbolExists: { _ in true })
        let c = config([key("k", icon: .app(path: "/x/Y.app"), action: .openApp(path: "/x/Y.app"))])
        let found = EditorIssues.check(c, noFiles)
        #expect(found.map(\.message) == ["App not found: /x/Y.app", "Icon app not found: /x/Y.app"])
        #expect(found.allSatisfy { $0.severity == .warning })

        let noSymbols = IssueEnvironment(fileExists: { _ in true }, symbolExists: { _ in false })
        let s = EditorIssues.check(config([key("k", icon: .symbol(name: "star"))]), noSymbols)
        #expect(s.map(\.message) == ["Unknown SF Symbol star"])

        let empty = EditorIssues.check(config([key("k", label: " ")]), env)
        #expect(empty.map(\.message) == ["Key shows nothing: add a label or an icon"])
        #expect(!EditorModel(document: config([key("k", label: " ")]), saved: nil).hasErrors(env))
    }

    @Test func tooLargeLayoutIsError() {
        let found = EditorIssues.check(fullStatPages(7), env)
        #expect(found.count == 1)
        #expect(found[0].page == nil)
        #expect(found[0].message.hasPrefix("Layout is"))
        #expect(found[0].message.contains("15360"))
    }

    @Test func errorsCoverValidate() {
        let fixtures = layoutFixtures() + [SampleConfig.dev]
        for c in fixtures {
            let hasLayoutError = EditorIssues.check(c, env).contains {
                $0.severity == .error && !$0.message.hasPrefix("Layout is")
            }
            #expect(((try? c.validate()) == nil) == hasLayoutError)
        }
    }
}

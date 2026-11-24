import Foundation

public struct PromptScreen: Equatable, Sendable {
    public var yes: Character
    public var always: Character?
    public var no: Character
    public var regionLines: [String]

    public init(yes: Character, always: Character?, no: Character, regionLines: [String]) {
        self.yes = yes
        self.always = always
        self.no = no
        self.regionLines = regionLines
    }
}

public struct PromptHints: Equatable, Sendable {
    public var titles: [String]
    public var needle: String

    public init(titles: [String], needle: String) {
        self.titles = titles
        self.needle = needle
    }

    private static let needleChars = 32
    private static let fileTitles = ["Edit file", "Create file", "Overwrite file", "Write file"]

    public static func from(toolName: String, toolInputJSON: String, cwd: String?) -> PromptHints? {
        guard let input = (try? JSONSerialization.jsonObject(with: Data(toolInputJSON.utf8))) as? [String: Any]
        else { return nil }
        func fileName() -> String {
            let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? ""
            return path.split(separator: "/").last.map(String.init) ?? ""
        }
        let titles: [String]
        let raw: String
        switch toolName {
        case "Bash":
            guard let command = input["command"] as? String else { return nil }
            titles = ["Bash command"]
            raw = command.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first.map(String.init) ?? ""
        case "Edit", "MultiEdit", "Write":
            titles = fileTitles
            raw = fileName()
        case "Read":
            titles = ["Read file"]
            raw = fileName()
        case "NotebookEdit":
            titles = []
            raw = fileName()
        case "WebFetch":
            titles = []
            raw = (input["url"] as? String).flatMap { URLComponents(string: $0)?.host } ?? ""
        default:
            titles = []
            var label = ClaudeText.toolLabel(toolName)
            if label.hasSuffix("…") { label.removeLast() }
            raw = label
        }
        let needle = String(PermissionPromptMatcher.squeezed(raw).prefix(needleChars))
        return needle.isEmpty ? nil : PromptHints(titles: titles, needle: needle)
    }
}

public enum PermissionPromptMatcher {
    private static let keptLines = 40
    private static let bottomWindow = 15
    private static let regionSize = 30
    private static let maxGap = 2
    static let cutDialogNotice = "This terminal is too short"

    public static func parse(_ screen: String) -> PromptScreen? {
        var lines = screen.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(normalised)
        // capture-pane pads short content with blank rows.
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines = Array(lines.suffix(keptLines))
        guard !lines.contains(where: { $0.contains(cutDialogNotice) }),
              let last = lines.lastIndex(where: { option($0) != nil }),
              let bottom = option(lines[last]), (2...5).contains(bottom.number),
              last >= lines.count - bottomWindow,
              !lines[(last + 1)...].contains(where: isInputPrompt)
        else { return nil }
        var options = [bottom]
        var first = last
        for expected in stride(from: bottom.number - 1, through: 1, by: -1) {
            guard let above = (max(0, first - maxGap - 1)..<first).last(where: { option(lines[$0]) != nil }),
                  let o = option(lines[above]), o.number == expected
            else { return nil }
            options.append(o)
            first = above
        }
        options.reverse()
        let yesRows = options.filter { $0.label == "Yes" }
        guard yesRows.count == 1, let no = options.first(where: { $0.label.hasPrefix("No") }) else { return nil }
        let always = options.first { $0.label.hasPrefix("Yes, ") }
        return PromptScreen(yes: yesRows[0].digit, always: always?.digit, no: no.digit,
                            regionLines: Array(lines[max(0, first - regionSize)..<first]))
    }

    public static func matches(_ screen: PromptScreen, _ hints: PromptHints) -> Bool {
        guard !hints.needle.isEmpty else { return false }
        var dialog = screen.regionLines[...]
        if !hints.titles.isEmpty {
            // Needle must sit under the newest title, not in history.
            guard let title = dialog.lastIndex(where: { line in hints.titles.contains { line.contains($0) } })
            else { return false }
            dialog = dialog[title...]
        }
        return squeezed(dialog.joined()).contains(hints.needle)
    }

    static func squeezed(_ s: String) -> String {
        String(s.filter { !$0.isWhitespace })
    }

    private static func normalised(_ line: Substring) -> String {
        var scalars = String.UnicodeScalarView()
        for u in line.unicodeScalars where !(0x2500...0x257F).contains(u.value) {
            scalars.append(u)
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func option(_ line: String) -> (digit: Character, number: Int, label: String)? {
        var rest = line[...]
        if let f = rest.first, f == "❯" || f == ">" || f == "›" {
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        guard let d = rest.first, let ascii = d.asciiValue, (0x31...0x39).contains(ascii) else { return nil }
        rest = rest.dropFirst()
        guard rest.first == ".", let gap = rest.dropFirst().first, gap.isWhitespace else { return nil }
        let label = rest.dropFirst().drop(while: \.isWhitespace)
        guard !label.isEmpty else { return nil }
        return (d, Int(ascii - 0x30), String(label))
    }

    private static func isInputPrompt(_ line: String) -> Bool {
        guard let f = line.first, f == ">" || f == "❯" else { return false }
        return line.dropFirst().first.map(\.isWhitespace) ?? true
    }
}

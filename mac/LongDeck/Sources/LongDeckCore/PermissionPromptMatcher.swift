import Foundation

public struct PromptScreen: Equatable, Sendable {
    public var yes: Character
    public var always: Character?
    public var alwaysLabel: String?
    public var no: Character
    public var regionLines: [String]

    public init(yes: Character, always: Character?, alwaysLabel: String?, no: Character, regionLines: [String]) {
        self.yes = yes
        self.always = always
        self.alwaysLabel = alwaysLabel
        self.no = no
        self.regionLines = regionLines
    }
}

public struct PromptHints: Equatable, Sendable {
    public var titles: [String]
    public var bodies: [[String]]
    public var detail: [String]
    public var alwaysPrefixes: [String]

    public init(titles: [String], bodies: [[String]], detail: [String] = [], alwaysPrefixes: [String] = []) {
        self.titles = titles
        self.bodies = bodies
        self.detail = detail
        self.alwaysPrefixes = alwaysPrefixes
    }

    static let fileTitles = ["Edit file", "Create file", "Overwrite file", "Write file"]

    public static func from(toolName: String, toolInputJSON: String, cwd: String?) -> PromptHints? {
        guard let input = (try? JSONSerialization.jsonObject(with: Data(toolInputJSON.utf8))) as? [String: Any]
        else { return nil }
        switch toolName {
        case "Bash":
            guard let command = input["command"] as? String else { return nil }
            let body = PermissionPromptMatcher.textLines(command)
            guard !body.isEmpty else { return nil }
            return PromptHints(titles: ["Bash command"], bodies: [body],
                               detail: PermissionPromptMatcher.textLines(input["description"] as? String ?? ""),
                               alwaysPrefixes: ["Yes, and don't ask again for "])
        case "Edit", "MultiEdit", "Write":
            return fileHints(input, cwd, titles: fileTitles, always: "Yes, allow all edits ")
        case "Read":
            return fileHints(input, cwd, titles: ["Read file"], always: "Yes, allow reading from ")
        default:
            // Other dialogs' titles are unverified until live check L2.
            return nil
        }
    }

    private static func fileHints(_ input: [String: Any], _ cwd: String?, titles: [String], always: String) -> PromptHints? {
        guard let path = input["file_path"] as? String, !path.contains(where: \.isNewline) else { return nil }
        let absolute = PermissionPromptMatcher.collapsed(path)
        guard !absolute.isEmpty else { return nil }
        var bodies = [[absolute]]
        var base = cwd ?? ""
        while base.count > 1, base.hasSuffix("/") { base.removeLast() }
        if base.hasPrefix("/"), base.count > 1, path.hasPrefix(base + "/") {
            let relative = PermissionPromptMatcher.collapsed(String(path.dropFirst(base.count + 1)))
            if !relative.isEmpty { bodies.insert([relative], at: 0) }
        }
        return PromptHints(titles: titles, bodies: bodies, alwaysPrefixes: [always])
    }
}

public enum PermissionPromptMatcher {
    private static let keptLines = 40
    private static let bottomWindow = 15
    private static let regionSize = 30
    private static let maxGap = 2
    private static let maxTitleGap = 2
    private static let interruptWindow = 12
    private static let knownTitles: Set<String> = Set(PromptHints.fileTitles + ["Bash command", "Read file"])
    private static let questionPrefix = "Do you want to "
    private static let interruptHint = "esc to interrupt"
    private static let spinnerGlyphs: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽", "*"]
    static let cutDialogNotice = "This terminal is too short"

    public static func parse(_ screen: String) -> PromptScreen? {
        var lines = rows(screen)
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
        let alwaysRows = options.filter { $0.label.hasPrefix("Yes, ") }
        let always = alwaysRows.count == 1 ? alwaysRows[0] : nil
        return PromptScreen(yes: yesRows[0].digit, always: always?.digit, alwaysLabel: always?.label, no: no.digit,
                            regionLines: Array(lines[max(0, first - regionSize)..<first]))
    }

    public static func matches(_ screen: PromptScreen, _ hints: PromptHints) -> Bool {
        let rows = screen.regionLines.map(collapsed)
        let titled = rows.indices.filter { knownTitles.contains(rows[$0]) }
        guard titled.count == 1, hints.titles.contains(rows[titled[0]]) else { return false }
        var start = titled[0] + 1
        var skipped = 0
        while start < rows.count, rows[start].isEmpty, skipped < maxTitleGap {
            start += 1
            skipped += 1
        }
        return hints.bodies.contains { body in
            guard var next = spelled(body, in: rows, from: start) else { return false }
            if !hints.detail.isEmpty, let after = spelled(hints.detail, in: rows, from: next) { next = after }
            // A longer on-screen command would continue on this row.
            return next == rows.count || rows[next].isEmpty || rows[next].hasPrefix(questionPrefix)
        }
    }

    static func interruptHintVisible(_ screen: String) -> Bool {
        let tail = Array(rows(screen).filter { !$0.isEmpty }.suffix(interruptWindow))
        let input = tail.lastIndex(where: isInputPrompt)
        return tail.indices.contains { i in
            if let input, i > input { return hasHintToken(tail[i], inParens: false) }
            guard let glyph = tail[i].first, spinnerGlyphs.contains(glyph), tail[i].dropFirst().first == " "
            else { return false }
            return hasHintToken(tail[i], inParens: true)
        }
    }

    static func textLines(_ text: String) -> [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { collapsed(String($0)) }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    static func collapsed(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func spelled(_ lines: [String], in rows: [String], from start: Int) -> Int? {
        var r = start
        for line in lines {
            if line.isEmpty {
                guard r < rows.count, rows[r].isEmpty else { return nil }
                r += 1
                continue
            }
            var rest = Substring(line)
            while true {
                guard r < rows.count, !rows[r].isEmpty, rest.hasPrefix(rows[r]) else { return nil }
                rest = rest.dropFirst(rows[r].count)
                r += 1
                if rest.isEmpty { break }
                // Only word wraps; a mid-word break hides a possible space.
                guard rest.first == " " else { return nil }
                rest = rest.dropFirst()
            }
        }
        return r
    }

    private static func hasHintToken(_ row: String, inParens: Bool) -> Bool {
        var from = row.startIndex
        while let r = row.range(of: interruptHint, options: .caseInsensitive, range: from..<row.endIndex) {
            let before = row[..<r.lowerBound]
            let after = row[r.upperBound...]
            let opened = before.lastIndex(of: "(").map { !before[$0...].contains(")") } ?? false
            if before.isEmpty || before.hasSuffix("(") || before.hasSuffix("· "),
               after.isEmpty || after.hasPrefix(")") || after.hasPrefix(" ·"),
               !inParens || opened {
                return true
            }
            from = r.upperBound
        }
        return false
    }

    private static func rows(_ screen: String) -> [String] {
        screen.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(normalised)
    }

    private static func normalised(_ line: Substring) -> String {
        var s = line.drop(while: isEdge)
        while let c = s.last, isEdge(c) { s = s.dropLast() }
        return String(s)
    }

    // Box drawing only frames rows; inside text it stays significant.
    private static func isEdge(_ c: Character) -> Bool {
        c.isWhitespace || c.unicodeScalars.allSatisfy { (0x2500...0x257F).contains($0.value) }
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

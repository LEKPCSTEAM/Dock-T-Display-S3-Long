import Foundation

public struct PromptScreen: Equatable, Sendable {
    public var yes: Character
    public var always: Character?
    public var alwaysLabel: String?
    public var no: Character
    public var regionLines: [String]
    public var regionRows: [String]

    public init(yes: Character, always: Character?, alwaysLabel: String?, no: Character,
                regionLines: [String], regionRows: [String]) {
        self.yes = yes
        self.always = always
        self.alwaysLabel = alwaysLabel
        self.no = no
        self.regionLines = regionLines
        self.regionRows = regionRows
    }
}

public struct PromptHints: Equatable, Sendable {
    public var titles: [String]
    public var bodies: [[String]]
    public var detail: [String]
    public var question: String?
    public var alwaysPrefixes: [String]

    public init(titles: [String], bodies: [[String]], detail: [String] = [], question: String? = nil,
                alwaysPrefixes: [String] = []) {
        self.titles = titles
        self.bodies = bodies
        self.detail = detail
        self.question = question
        self.alwaysPrefixes = alwaysPrefixes
    }

    static let fileTitles = ["Edit file", "Create file", "Overwrite file", "Write file"]
    static let bashQuestion = "Do you want to proceed?"

    var renderings: [String] { bodies.map { ($0 + detail).joined(separator: "\n") } }

    public static func from(toolName: String, toolInputJSON: String, cwd: String?) -> PromptHints? {
        guard let input = (try? JSONSerialization.jsonObject(with: Data(toolInputJSON.utf8))) as? [String: Any]
        else { return nil }
        switch toolName {
        case "Bash":
            guard let command = input["command"] as? String else { return nil }
            let description = input["description"]
            guard description == nil || description is String else { return nil }
            let body = PermissionPromptMatcher.textLines(command)
            guard !body.isEmpty else { return nil }
            return PromptHints(titles: ["Bash command"], bodies: [body],
                               detail: PermissionPromptMatcher.textLines(description as? String ?? ""),
                               question: bashQuestion, alwaysPrefixes: ["Yes, and don't ask again for "])
        case "Edit", "MultiEdit", "Write":
            return fileHints(input, cwd, titles: fileTitles)
        case "Read":
            return fileHints(input, cwd, titles: ["Read file"])
        default:
            // Other dialogs' titles are unverified until live check L2.
            return nil
        }
    }

    // Always is never offered for files: its scope is not shown on the board.
    private static func fileHints(_ input: [String: Any], _ cwd: String?, titles: [String]) -> PromptHints? {
        guard let path = input["file_path"] as? String, !path.isEmpty, !path.contains(where: \.isNewline)
        else { return nil }
        var bodies = [[path]]
        var base = cwd ?? ""
        while base.count > 1, base.hasSuffix("/") { base.removeLast() }
        if base.hasPrefix("/"), base.count > 1, path.hasPrefix(base + "/") {
            let relative = String(path.dropFirst(base.count + 1))
            if !relative.isEmpty { bodies.insert([relative], at: 0) }
        }
        return PromptHints(titles: titles, bodies: bodies)
    }
}

public enum PermissionPromptMatcher {
    private static let keptLines = 40
    private static let bottomWindow = 15
    private static let regionSize = 30
    private static let maxGap = 2
    private static let maxTitleGap = 2
    private static let minBorder = 10
    private static let interruptWindow = 12
    private static let knownTitles: Set<String> = Set(PromptHints.fileTitles + ["Bash command", "Read file"])
    private static let interruptHint = "esc to interrupt"
    private static let spinnerGlyphs: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽", "*"]
    static let cutDialogNotice = "This terminal is too short"

    private struct DialogRow {
        var text: String
        var end: Int
        var isSeparator: Bool
    }

    public static func parse(_ screen: String) -> PromptScreen? {
        var raw = screen.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(rightTrimmed)
        // capture-pane pads short content with blank rows.
        while let last = raw.last, normalised(last).isEmpty { raw.removeLast() }
        raw = Array(raw.suffix(keptLines))
        let lines = raw.map(normalised)
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
        let top = max(0, first - regionSize)
        return PromptScreen(yes: yesRows[0].digit, always: always?.digit, alwaysLabel: always?.label, no: no.digit,
                            regionLines: Array(lines[top..<first]), regionRows: Array(raw[top..<first]))
    }

    public static func matches(_ screen: PromptScreen, _ hints: PromptHints, paneWidth: Int? = nil) -> Bool {
        let lines = screen.regionLines
        let titled = lines.indices.filter { knownTitles.contains(lines[$0]) }
        guard titled.count == 1, let t = titled.first, t >= 1, hints.titles.contains(lines[t]),
              screen.regionRows.count == lines.count,
              let boxed = topBorder(screen.regionRows[t - 1]),
              let rows = dialogRows(screen.regionRows[(t + 1)...], boxed: boxed)
        else { return false }
        var start = 0
        while start < rows.count, start < maxTitleGap, rows[start].text.isEmpty { start += 1 }
        return hints.bodies.contains { body in
            guard var r = spelled(body, rows, from: start, paneWidth) else { return false }
            guard let question = hints.question else {
                return r == rows.count || rows[r].isSeparator
            }
            if !hints.detail.isEmpty {
                guard let after = spelled(hints.detail, rows, from: r, paneWidth) else { return false }
                r = after
            }
            while r < rows.count, rows[r].text.isEmpty { r += 1 }
            guard r < rows.count, rows[r].text == question else { return false }
            return rows[(r + 1)...].allSatisfy { $0.text.isEmpty }
        }
    }

    static func interruptHintVisible(_ screen: String) -> Bool {
        let tail = Array(screen.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { normalised(rightTrimmed($0)) }.filter { !$0.isEmpty }.suffix(interruptWindow))
        let input = tail.lastIndex(where: isInputPrompt)
        return tail.indices.contains { i in
            if let input, i > input { return hasHintToken(tail[i], inParens: false) }
            guard let glyph = tail[i].first, spinnerGlyphs.contains(glyph), tail[i].dropFirst().first == " "
            else { return false }
            return hasHintToken(tail[i], inParens: true)
        }
    }

    static func textLines(_ text: String) -> [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    static func displayWidth<S: StringProtocol>(_ s: S) -> Int {
        s.reduce(0) { $0 + columns($1) }
    }

    // Plain rule or round box top at column 0; true when boxed.
    private static func topBorder(_ row: String) -> Bool? {
        let chars = Array(row)
        guard chars.count >= minBorder else { return nil }
        if chars.first == "╭" {
            return chars.last == "╮" && chars.dropFirst().dropLast().allSatisfy { $0 == "─" } ? true : nil
        }
        return chars.allSatisfy { $0 == "─" } ? false : nil
    }

    private static func dialogRows(_ raw: ArraySlice<String>, boxed: Bool) -> [DialogRow]? {
        var rows: [DialogRow] = []
        for row in raw {
            var content = Substring(row)
            var offset = 0
            if boxed {
                guard content.count >= 2, content.first == "│", content.last == "│" else { return nil }
                content = content.dropFirst().dropLast()
                offset = 1
            }
            let text = content.trimmingCharacters(in: .whitespaces)
            rows.append(DialogRow(text: text, end: offset + displayWidth(rightTrimmed(content)),
                                  isSeparator: text.allSatisfy(isBoxDrawing)))
        }
        return rows
    }

    private static func spelled(_ lines: [String], _ rows: [DialogRow], from start: Int, _ paneWidth: Int?) -> Int? {
        var r = start
        for line in lines {
            if line.isEmpty {
                guard r < rows.count, rows[r].text.isEmpty else { return nil }
                r += 1
                continue
            }
            var rest = Substring(line)
            while true {
                guard r < rows.count, !rows[r].text.isEmpty, rest.hasPrefix(rows[r].text) else { return nil }
                // Only a row filling the pane can be a soft wrap.
                let full = paneWidth.map { rows[r].end >= $0 - 1 } ?? false
                rest = rest.dropFirst(rows[r].text.count)
                r += 1
                if rest.isEmpty {
                    guard !full else { return nil }
                    break
                }
                guard full, rest.first == " ", let next = rest.dropFirst().first, !next.isWhitespace
                else { return nil }
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

    private static func rightTrimmed<S: StringProtocol>(_ s: S) -> String {
        var t = s[...]
        while let c = t.last, c.isWhitespace { t = t.dropLast() }
        return String(t)
    }

    private static func normalised(_ line: String) -> String {
        var s = line.drop(while: isEdge)
        while let c = s.last, isEdge(c) { s = s.dropLast() }
        return String(s)
    }

    // Box drawing only frames rows; inside text it stays significant.
    private static func isEdge(_ c: Character) -> Bool {
        c.isWhitespace || isBoxDrawing(c)
    }

    private static func isBoxDrawing(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0x2500...0x257F).contains($0.value) }
    }

    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
        0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
        0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD,
    ]

    private static func columns(_ c: Character) -> Int {
        guard let u = c.unicodeScalars.first else { return 0 }
        if u.value < 0x20 || (0x7F..<0xA0).contains(u.value) { return 0 }
        switch u.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format: return 0
        default: break
        }
        if c.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation })
            || wideRanges.contains(where: { $0.contains(u.value) }) {
            return 2
        }
        return 1
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

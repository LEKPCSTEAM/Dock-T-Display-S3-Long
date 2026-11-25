import Foundation

public enum ClaudeText {
    public static func capped(_ s: String, bytes: Int) -> String {
        let clean = clean(s)
        guard clean.utf8.count > bytes else { return clean }
        var out = ""
        var used = 0
        for ch in clean {
            let n = String(ch).utf8.count
            if used + n > bytes - 3 { break }
            out.append(ch)
            used += n
        }
        return out + "…"
    }

    public static func prefix(_ s: String, bytes: Int) -> String {
        var out = ""
        var used = 0
        for ch in clean(s) {
            let n = String(ch).utf8.count
            if used + n > bytes { break }
            out.append(ch)
            used += n
        }
        return out
    }

    public static func cappedLeft(_ s: String, bytes: Int) -> String {
        let clean = clean(s)
        guard clean.utf8.count > bytes else { return clean }
        var kept: [Character] = []
        var used = 0
        for ch in clean.reversed() {
            let n = String(ch).utf8.count
            if used + n > bytes - 3 { break }
            kept.append(ch)
            used += n
        }
        return "…" + String(kept.reversed())
    }

    public static func toolLabel(_ toolName: String) -> String {
        var name = toolName
        if name.hasPrefix("mcp__") {
            let parts = name.components(separatedBy: "__")
            if parts.count >= 3, let last = parts.last, !last.isEmpty { name = last }
        }
        return capped(name, bytes: 15)
    }

    public static func summary(toolName: String, toolInputJSON: String, cwd: String?) -> String {
        let input = (try? JSONSerialization.jsonObject(with: Data(toolInputJSON.utf8))) as? [String: Any] ?? [:]
        func text(_ key: String) -> String? { input[key] as? String }
        func path(_ key: String) -> String? {
            guard var p = text(key) else { return nil }
            if let cwd, !cwd.isEmpty, p.hasPrefix(cwd + "/") { p.removeFirst(cwd.count + 1) }
            return cappedLeft(p, bytes: 80)
        }
        var picked: String?
        switch toolName {
        case "Bash": picked = text("command")?.split(separator: "\n", maxSplits: 1,
                                                       omittingEmptySubsequences: false).first.map(String.init)
        case "Edit", "MultiEdit", "Write", "Read": if let p = path("file_path") { return p }
        case "NotebookEdit": if let p = path("notebook_path") { return p }
        case "WebFetch": picked = text("url")
        case "WebSearch": picked = text("query")
        case "Grep", "Glob": picked = text("pattern")
        case "Task", "Agent": picked = text("description")
        default: break
        }
        return capped(picked ?? toolInputJSON, bytes: 80)
    }

    public static func project(_ path: String?) -> String {
        let last = (path ?? "").split(separator: "/").last.map(String.init) ?? ""
        return last.isEmpty ? "?" : capped(last, bytes: 23)
    }

    private static func clean(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            scalars.append(u.value < 0x20 || u.value == 0x7F ? " " : u)
        }
        return String(scalars)
    }
}

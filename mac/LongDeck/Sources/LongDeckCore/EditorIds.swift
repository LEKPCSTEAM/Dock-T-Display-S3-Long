public enum EditorText {
    public static func prefix(_ s: String, maxBytes: Int) -> String {
        var result = ""
        var bytes = 0
        for ch in s {
            let n = String(ch).utf8.count
            guard bytes + n <= maxBytes else { break }
            result.append(ch)
            bytes += n
        }
        return result
    }
}

public enum EditorIds {
    public static func make(base: String, taken: Set<String>) -> String {
        let kept = base.lowercased().unicodeScalars.filter {
            ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39)
        }
        var slug = String(String.UnicodeScalarView(kept).prefix(12))
        if slug.isEmpty { slug = "w" }
        if !taken.contains(slug) { return slug }
        var n = 2
        while true {
            let candidate = String(slug.prefix(15 - String(n).count)) + String(n)
            if !taken.contains(candidate) { return candidate }
            n += 1
        }
    }
}

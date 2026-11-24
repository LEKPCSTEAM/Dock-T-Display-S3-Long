import Foundation

public enum StatusLineWrapper {
    public static func script(previousCommand: String?, url: String, token: String, curl: String = "/usr/bin/curl") -> String {
        var lines = [
            "#!/bin/sh",
            "in=$(cat)",
            "printf '%s' \"$in\" | \(shellQuote(curl)) -s -o /dev/null --max-time 0.2 -X POST -H 'Content-Type: application/json' -H 'Expect:' -H @/dev/fd/3 -H \"X-Tmux-Pane: ${TMUX_PANE:-}\" --data-binary @- \(shellQuote(url)) >/dev/null 2>&1 \(tokenRedirect) &",
        ] + tokenHereDoc(token)
        if let previousCommand {
            lines.append("printf '%s' \"$in\" | /bin/sh -c \(shellQuote(previousCommand))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Token reaches curl on fd 3 (`-H @/dev/fd/3`), never in argv.
    static let tokenRedirect = "3<<'LONGDECK_TOKEN'"

    static func tokenHereDoc(_ token: String) -> [String] {
        ["X-LongDeck-Token: " + token.filter { !$0.isNewline }, "LONGDECK_TOKEN"]
    }
}

import Foundation

public enum StatusLineWrapper {
    public static func script(previousCommand: String?, url: String, token: String, curl: String = "/usr/bin/curl") -> String {
        var lines = [
            "#!/bin/sh",
            "in=$(cat)",
            "printf '%s' \"$in\" | \(shellQuote(curl)) -s -o /dev/null --max-time 0.2 -X POST -H 'Content-Type: application/json' -H \(shellQuote("X-LongDeck-Token: \(token)")) -H \"X-Tmux-Pane: ${TMUX_PANE:-}\" --data-binary @- \(shellQuote(url)) >/dev/null 2>&1 &",
        ]
        if let previousCommand {
            lines.append("printf '%s' \"$in\" | /bin/sh -c \(shellQuote(previousCommand))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

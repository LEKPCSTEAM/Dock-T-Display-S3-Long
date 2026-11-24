import Foundation

public enum ClaudeHookScript {
    public static func script(url: String, token: String, curl: String = "/usr/bin/curl") -> String {
        let q = StatusLineWrapper.shellQuote
        return [
            "#!/bin/sh",
            "in=$(cat)",
            "set -- -H \(q("X-LongDeck-Token: \(token)"))",
            "case ${TMUX_PANE:-} in",
            "%*[!0-9]* | %) ;;",
            "%*) set -- \"$@\" -H \"X-Tmux-Pane: $TMUX_PANE\" ;;",
            "esac",
            "{ printf '%s' \"$in\" | \(q(curl)) -s -o /dev/null --max-time 1 -X POST -H 'Content-Type: application/json' \"$@\" --data-binary @- \(q(url)); } </dev/null >/dev/null 2>&1 &",
            "exit 0",
        ].joined(separator: "\n") + "\n"
    }
}

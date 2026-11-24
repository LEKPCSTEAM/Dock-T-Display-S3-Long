import Foundation

public enum ClaudeHookScript {
    public static func script(url: String, token: String, curl: String = "/usr/bin/curl") -> String {
        let q = StatusLineWrapper.shellQuote
        // Foreground: a killed process group cannot drop the POST.
        let lines = [
            "#!/bin/sh",
            "in=$(cat)",
            "set --",
            "case ${TMUX_PANE:-} in",
            "%*[!0-9]* | %) ;;",
            "%*) set -- -H \"X-Tmux-Pane: $TMUX_PANE\" ;;",
            "esac",
            "{ printf '%s' \"$in\" | \(q(curl)) -s -o /dev/null --connect-timeout 0.2 --max-time 0.5 -X POST -H 'Content-Type: application/json' -H 'Expect:' -H @/dev/fd/3 \"$@\" --data-binary @- \(q(url)); } </dev/null >/dev/null 2>&1 \(StatusLineWrapper.tokenRedirect)",
        ] + StatusLineWrapper.tokenHereDoc(token) + ["exit 0"]
        return lines.joined(separator: "\n") + "\n"
    }
}

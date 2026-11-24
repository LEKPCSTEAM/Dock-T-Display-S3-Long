# LongDeck

Menu-bar app that pairs with the deck board over Bonjour (`_longdeck._tcp`), pushes key layouts and faces, and runs actions on the Mac when keys are pressed.

## Build

    cd mac/LongDeck
    swift test
    ./scripts/bundle.sh
    open build/LongDeck.app

`bundle.sh` signs ad-hoc by default. Set `LONGDECK_SIGN_ID` to use a named identity.

## Keep the Accessibility grant across rebuilds

Ad-hoc signatures change on every build, so macOS forgets the Accessibility grant. Sign with a stable self-signed certificate instead:

1. Open Keychain Access, then Certificate Assistant, then Create a Certificate.
2. Name it `LongDeck Dev`, set Identity Type to Self Signed Root and Certificate Type to Code Signing, then create it.
3. Build with `LONGDECK_SIGN_ID="LongDeck Dev" ./scripts/bundle.sh`.
4. Choose "Grant Accessibility…" in the menu and enable LongDeck once.

## Config

`~/Library/Application Support/LongDeck/config.json`. Changes are picked up automatically. An invalid file is not pushed and the error shows in the menu. Use "Open config folder" to create a sample.

### Live widgets

`pages[].live[]` holds live widgets next to `keys`; it is optional. Each entry is flat: `id`, `type` (`stat`, `volume` or `clock`), `col`, `row`, `w`, `h`, plus `metric` and `style` for `stat`. Metrics: `cpu`, `ram`, `gpu`, `temp`, `net_down`, `net_up`, `disk_free`, `disk_io`, `battery`. Styles: `bar`, `number`, `sparkline`. Keys and live widgets share the 8x2 grid and a cap of 16 widgets per page. The first-run sample includes a `Mac` page with these widgets.

    {"id":"cpu","type":"stat","metric":"cpu","style":"sparkline","col":0,"row":0,"w":2,"h":1}

Temperature reads SMC key `TCMz` without root; values outside 10-130 °C are dropped. `battery` shows `--` on a Mac without a battery.

## Claude Code integration

Menu "Install Claude Code integration…" (and "Uninstall…") is the only way to change `~/.claude/settings.json`. Install first writes an owner-only backup `settings.json.longdeck-<UTC yyyyMMdd-HHmmss>.bak` and shows its path. It then adds 9 `command` hooks (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `SessionEnd`) that run `~/Library/Application Support/LongDeck/hook.sh`, and wraps `statusLine` with `statusline.sh` in the same folder (the previous command still runs, its output is unchanged). Install state is in `claude-install.json` next to them. Uninstall restores `settings.json` exactly, also removes the `http` hooks that earlier LongDeck builds added, and deletes both scripts and the state file.

`hook.sh` (owner-only, mode 0700) reads the hook input once and POSTs it in the background to `http://127.0.0.1:47821/hook` with `curl --max-time 1`, an `X-LongDeck-Token` header and `X-Tmux-Pane` (sent only when `TMUX_PANE` is `%` plus digits). It prints nothing and always exits 0, so Claude Code never acts on the listener's reply, and a stopped LongDeck causes no hook error or warning. `PostToolUseFailure` clears a pending prompt the same way `PostToolUse` does.

The listener binds loopback only (port 47821). The token is 32 random bytes in hex, written into `hook.sh` and the wrapper, not into `settings.json`. Restart running Claude Code sessions after install so they load the hooks, and after uninstall too: until then they keep calling the removed `hook.sh` and may show hook errors. Until the integration is installed and the listener is running, the board's Claude widgets show `--`; after an uninstall or a listener failure they show "No sessions" until the board reconnects. Sessions must run inside tmux (`TMUX_PANE`); sessions outside tmux are read-only. Focus uses iTerm2 AppleScript, so macOS asks for Automation permission the first time.

Board answers (Approve, Always, Deny, interrupt) are refused, and the board shows "Answer at the keyboard", unless the dialog is verified in the pane:

- Only Bash, Edit, MultiEdit, Write and Read prompts; title, full command or path, and the Bash description must match exactly.
- The pane must be a Claude Code pane and not synchronized, in copy mode or input-off (reason `pane_busy`). Look-alike queued prompts are refused; prompts are answered oldest first.
- Always: Bash only, single line, at most 55 bytes, no shell operators, redirections or surrounding whitespace, and the rule Claude Code would save must equal the whole command. Edit, Write and Read Always is never sent.
- Interrupt sends Escape only when the spinner row shows `esc to interrupt`.

Refusal codes (logged, not shown): `unknown_session`, `no_pane`, `stale`, `unverifiable`, `tmux`, `not_claude`, `pane_busy`, `no_prompt`, `mismatch`, `no_always`, `not_working`, `no_client`; `ClaudeController` also returns `proto` (unparsable request that has a request id) and `busy` (duplicate request id, or the pane already has an action in flight). Known limits: the prompt layout is matched against fixtures and still needs live checks, and long wrapped commands are usually refused. The overlay stays up while the pane shows a dialog with the prompt's tool title (checked once a second), even when the dialog cannot be verified for an answer.

Config entries (the first-run sample has a `Claude` page; `claude_sessions` needs w of at least 2):

    {"id":"ccs","type":"claude_sessions","col":0,"row":0,"w":4,"h":2}
    {"id":"ccu","type":"claude_usage","col":4,"row":0,"w":4,"h":1}

## Pairing

Choose "Pair with board…", pick the board, then type the 6-digit code shown on its screen. The key is stored in the login Keychain (service `dev.longdeck.LongDeck`).

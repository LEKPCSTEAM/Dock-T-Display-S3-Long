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

Menu "Install Claude Code integration…" (and "Uninstall…") is the only way to change `~/.claude/settings.json`. Install first writes an owner-only backup `settings.json.longdeck-<UTC yyyyMMdd-HHmmss>.bak` and shows its path. It then adds 8 `http` hooks (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification`, `Stop`, `SessionEnd`) to `http://127.0.0.1:47821/hook` with an `X-LongDeck-Token` header, and wraps `statusLine` with `~/Library/Application Support/LongDeck/statusline.sh` (the previous command still runs, its output is unchanged). Install state is in `claude-install.json` next to it. Uninstall restores `settings.json` exactly and removes the wrapper and state file.

The listener binds loopback only (port 47821). The token is 32 random bytes in hex, stored in the hooks and the wrapper. Restart running Claude Code sessions after install so they load the hooks. Sessions must run inside tmux (`TMUX_PANE`); sessions outside tmux are read-only. Focus uses iTerm2 AppleScript, so macOS asks for Automation permission the first time.

Board answers (Approve, Always, Deny, interrupt) are refused, and the board shows "Answer at the keyboard", unless the dialog is verified in the pane:

- Only Bash, Edit, MultiEdit, Write and Read prompts; title, full command or path, and the Bash description must match exactly.
- The pane must be a Claude Code pane and not synchronized, in copy mode or input-off (reason `pane_busy`). Look-alike queued prompts are refused; prompts are answered oldest first.
- Always: Bash only, single line, at most 55 bytes, no shell operators, redirections or surrounding whitespace, and the rule Claude Code would save must equal the whole command. Edit, Write and Read Always is never sent.
- Interrupt sends Escape only when the spinner row shows `esc to interrupt`.

Refusal codes (logged, not shown): `unknown_session`, `no_pane`, `stale`, `unverifiable`, `tmux`, `not_claude`, `pane_busy`, `no_prompt`, `mismatch`, `no_always`, `not_working`, `no_client`; `busy` and `proto` come from the board protocol. Known limits: the prompt layout is matched against fixtures and still needs live checks, and long wrapped commands are usually refused.

Config entries (the first-run sample has a `Claude` page; `claude_sessions` needs w of at least 2):

    {"id":"ccs","type":"claude_sessions","col":0,"row":0,"w":4,"h":2}
    {"id":"ccu","type":"claude_usage","col":4,"row":0,"w":4,"h":1}

## Pairing

Choose "Pair with board…", pick the board, then type the 6-digit code shown on its screen. The key is stored in the login Keychain (service `dev.longdeck.LongDeck`).

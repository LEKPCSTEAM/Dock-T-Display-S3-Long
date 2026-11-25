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

`~/Library/Application Support/LongDeck/config.json`. The layout editor writes this file (indented, sorted keys, unescaped paths). Hand edits still work and are picked up automatically. An invalid file is not pushed and the error shows in the menu. Use "Open config folder" to create a sample.

## Editor

Menu "Edit layout…" opens the editor window; the Dock icon shows while it is open. The pages list has + − ↑ ↓ (at most 8 pages, name up to 23 bytes, renamed in the inspector's Page section). Drag a palette tile onto the grid, or click it to add at the first free spot; a full page refuses with "No room there". Drag a widget to move it, use the three handles to resize, and press ⌘⌫ to delete. A page holds up to 16 widgets on the 8x2 grid; `claude_sessions` needs w of at least 2; ids are at most 15 bytes.

The inspector edits the label, icon (none, app or SF Symbol), background, optional text colour (it also tints SF Symbols), action and long-press action. The app picker lists `/Applications`, `/System/Applications`, `~/Applications` and `Other…`, and choosing an app sets the key icon. The hotkey recorder: click the field, press the combo, Esc cancels. ⌘Z / ⇧⌘Z undo and redo.

⌘S saves. Errors (empty action values, bad colours, more than 8 pages, a layout over 15360 bytes) show as issue rows and block saving; widget errors also outline the widget in red (click a row to select it), while page-count and layout-size errors appear only in the issue list. A saved layout goes to the board now, or on its next connect if it is offline. Closing the window or quitting with unsaved changes asks Save / Don't Save / Cancel.

If `config.json` changes on disk and the editor has no unsaved edits, it reloads silently. With unsaved edits, a banner says the file changed, with a Reload button (discards your edits and loads the file). While the banner is up the first ⌘S asks you to save again to overwrite; the second overwrites. The close and quit prompt then adds "config.json changed on disk — Save will overwrite it", and its Save overwrites in one step.

`foreground` is an optional key field (text colour, `#RRGGBB`); it is omitted when unset, so older configs are unchanged:

    {"id":"term","col":0,"row":0,"w":1,"h":1,"label":"Term","background":"#1E1E1E","foreground":"#FFD54A","icon":{"symbol":{"name":"terminal"}},"action":{"openApp":{"path":"/System/Applications/Utilities/Terminal.app"}}}

### Live widgets

`pages[].live[]` holds live widgets next to `keys`; it is optional. Each entry is flat: `id`, `type` (`stat`, `volume` or `clock`), `col`, `row`, `w`, `h`, plus `metric` and `style` for `stat`. Metrics: `cpu`, `ram`, `gpu`, `temp`, `net_down`, `net_up`, `disk_free`, `disk_io`, `battery`. Styles: `bar`, `number`, `sparkline`. Keys and live widgets share the 8x2 grid and a cap of 16 widgets per page. The first-run sample includes a `Mac` page with these widgets.

    {"id":"cpu","type":"stat","metric":"cpu","style":"sparkline","col":0,"row":0,"w":2,"h":1}

Temperature reads SMC key `TCMz` without root; values outside 10-130 °C are dropped. `battery` shows `--` on a Mac without a battery.

## Claude Code integration

Menu "Install Claude Code integration…" (and "Uninstall…") is the only way to change `~/.claude/settings.json`. Install first writes an owner-only backup `settings.json.longdeck-<UTC yyyyMMdd-HHmmss>.bak` and shows its path. It then adds 9 `command` hooks (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `SessionEnd`) that run `~/Library/Application Support/LongDeck/hook.sh`, and wraps `statusLine` with `statusline.sh` in the same folder (the previous command still runs, its output is unchanged). Install state is in `claude-install.json` next to them. Uninstall restores `settings.json` exactly, also removes the `http` hooks that earlier LongDeck builds added, and deletes both scripts and the state file.

`hook.sh` (owner-only, mode 0700) reads the hook input once and POSTs it to `http://127.0.0.1:47821/hook` with `curl --connect-timeout 0.2 --max-time 0.5`, an `X-LongDeck-Token` header and `X-Tmux-Pane` (sent only when `TMUX_PANE` is `%` plus digits). curl runs in the foreground so the POST survives Claude Code ending the hook's process group; a stopped LongDeck costs almost nothing (connection refused), a hung one at most 0.5 s. It prints nothing and always exits 0, so Claude Code never acts on the listener's reply, and a stopped LongDeck causes no hook error or warning. Both scripts send `Expect:` empty (the listener never answers `100-continue`, which curl would otherwise wait for on bodies over 1 MiB). `PostToolUseFailure` clears a pending prompt the same way `PostToolUse` does.

The listener binds loopback only (port 47821). The token is 32 random bytes in hex, written into `hook.sh` and the wrapper, not into `settings.json`; the scripts hand it to curl on file descriptor 3 (`-H @/dev/fd/3`), so it never appears in `ps` output. Restart running Claude Code sessions after install so they load the hooks, and after uninstall too: until then they keep calling the removed `hook.sh` and may show hook errors. Until the integration is installed and the listener is running, the board's Claude widgets show `--`; after an uninstall or a listener failure they show "No sessions" until the board reconnects. Sessions must run inside tmux (`TMUX_PANE`); sessions outside tmux are read-only. Focus uses iTerm2 AppleScript, so macOS asks for Automation permission the first time.

Board answers (Approve, Always, Deny, interrupt) are refused, and the board shows "Answer at the keyboard", unless the dialog is verified in the pane:

- Only Bash, Edit, MultiEdit, Write and Read prompts; title, full command or path, and the Bash description must match exactly.
- The pane must be a Claude Code pane and not synchronized, in copy mode or input-off (reason `pane_busy`). Look-alike queued prompts are refused; prompts are answered oldest first.
- Always: Bash only, single line, at most 55 bytes, no shell operators, redirections or surrounding whitespace, and the rule Claude Code would save must equal the whole command. Edit, Write and Read Always is never sent.
- Interrupt sends Escape only when the spinner row shows `esc to interrupt`.

Refusal codes (logged, not shown): `unknown_session`, `no_pane`, `stale`, `unverifiable`, `tmux`, `not_claude`, `pane_busy`, `no_prompt`, `mismatch`, `no_always`, `not_working`, `no_client`; `ClaudeController` also returns `proto` (unparsable request that has a request id) and `busy` (duplicate request id, or the pane already has an action in flight). Known limits: the prompt layout is matched against fixtures and still needs live checks, and long wrapped commands are usually refused. The overlay stays up while the pane shows a dialog with the prompt's tool title (checked once a second), even when the dialog cannot be verified for an answer.

Config entries (the first-run sample has a `Claude` page; `claude_sessions` needs w of at least 2):

    {"id":"ccs","type":"claude_sessions","col":0,"row":0,"w":4,"h":2}
    {"id":"ccu","type":"claude_usage","col":4,"row":0,"w":4,"h":1}

### Claude agents widget

`claude_agents` (ขั้นต่ำ 2x1) แสดง tile ละ session เป็นตัวละคร pixel ใส่หมวกสีประจำชื่อ ใน editor จะเห็นเป็น tile ตัวอย่าง 4 state (working, permission, waiting, done) ชื่อ session มาจาก tmux session name (`tmux display-message -p '#S'`, cache 30 วินาที) ถ้าไม่มีจะใช้ชื่อโฟลเดอร์ของ project

- History: session ที่จบแล้วเก็บไว้ 7 วันใน `~/Library/Application Support/LongDeck/claude-history.json` (owner-only) เพื่อให้ tile ยังอยู่หลัง quit แล้วเปิด LongDeck ใหม่ ลบไฟล์นี้ได้ถ้าอยากล้าง tile ที่จบแล้ว
- Subagent count: ต้องมี hook `SubagentStart` / `SubagentStop` ถ้า hook ที่ติดตั้งไว้เป็นรุ่นเก่า เมนูจะขึ้น "Reinstall Claude hooks (adds subagent count)" กดแล้ว restart Claude Code session
- Sprites override: วางไฟล์ `claude-agent.png/.json` และ `claude-hats.png/.json` ใน `~/Library/Application Support/LongDeck/sprites/` แอปจะใช้แทนของที่มากับตัวแอป (ต้องมีครบ 4 ไฟล์ ไม่งั้นใช้ของเดิม) และ push ให้บอร์ดอัตโนมัติเมื่อไฟล์เปลี่ยน ขนาด layout ที่ Save ถูกตรวจด้วย sprites ชุดเดียวกัน
- วาดใหม่: แก้ `Art/claude-agent.aseprite` หรือ `Art/claude-hats.aseprite` แล้วรัน `Art/export.sh` (ค่าเริ่มต้นเขียนลง `Sources/LongDeckCore/Resources/sprites/`, ใส่ absolute out-dir เป็น argument เพื่อส่งออกไปที่อื่น เช่น โฟลเดอร์ override ด้านบน) แล้ว `./scripts/bundle.sh` เพื่อใส่ใน app bundle

## Pairing

Choose "Pair with board…", pick the board, then type the 6-digit code shown on its screen. The key is stored in the login Keychain (service `dev.longdeck.LongDeck`).

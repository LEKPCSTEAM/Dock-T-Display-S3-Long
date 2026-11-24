# LongDeck Milestone 3 (Claude) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The board shows every Claude Code session on the Mac (state, project, context %), the 5-hour and weekly usage, and a permission overlay on every page, the clock pages included. A permission prompt can be answered from the board (Approve / Always / Deny), a working session can be interrupted, and any session can be brought to the front in iTerm2. The terminal prompt keeps working as before, and Claude Code is never slowed or broken when the Mac app is not running.

**Architecture:**

- The Mac app installs, on the user's click only, HTTP hooks and a statusLine wrapper into `~/.claude/settings.json`. Everything LongDeck adds sits next to the user's own hooks and `ccstatusline`. A backup is written before any change, and uninstall restores the file.
- Hooks and the wrapper POST to a listener on `127.0.0.1:47821` that only accepts requests carrying a random install token. The listener only records events and always answers at once with an empty `200`. Hooks never return a decision.
- A pure `ClaudeStore` in `LongDeckCore` keeps per-session state, the pending permission prompt with a fresh request id, and usage. It renders a capped `claude` body that the app sends to the board on every change.
- Answers go through tmux. The board's `claude_action` must carry the pane's current request id. The app then reads the pane with `capture-pane`, checks that a Claude Code permission prompt for the same tool and command is on screen, and only then sends the option key. In every other case it sends nothing and replies `claude_ack` with `ok:false`, and the board says "Answer at the keyboard".
- The board parses `claude` in a pure, native-tested module (`deck_claude`). `net_task` keeps the snapshot under the existing mutex. The LVGL thread draws two new live widgets (`claude_sessions`, `claude_usage`) and a permission overlay on `lv_layer_top()`.

**Tech Stack:**

- Firmware: as M2 (Arduino-ESP32 2.0.17, LVGL 8.4, `links2004/WebSockets@2.6.1`, `bblanchon/ArduinoJson@7.2.1`, Unity on PlatformIO `native`).
- Mac: the Swift 6 package from M1/M2, CommandLineTools toolchain, Swift Testing. New: Network.framework `NWListener` (loopback HTTP), `Process` for `/opt/homebrew/bin/tmux` and `/usr/bin/osascript` (iTerm2), `/usr/bin/curl` inside the statusLine wrapper.

**Spec:** `docs/superpowers/specs/2026-11-24-clock-deck-design.md`. This plan covers milestone 3: installer, hook listener, statusLine wrapper, the `claude_*` widgets, the permission overlay, and answers through tmux/iTerm2. The editor (milestone 4) is out of scope.

## Global Constraints

- Firmware code lives in `examples/ntp_clock/`. The Mac app lives in `mac/LongDeck/`. Do not modify `lib/`, `eez/`, or any file a task does not list.
- Edit files only with the Edit and Write tools. Never edit through Bash (`sed -i`, heredoc redirects, scripts).
- Comments: English, one line, at most about 10 words, only what the code cannot say. No file or class overview blocks. Do not add comments to code you did not change.
- **The board is not connected.** Verify firmware only with `pio run -e ntp_clock` and `pio test -e native_deck`. Every check that needs the device goes in the Hardware and live checklist at the end, which the owner runs later.
- **Never launch LongDeck.app** (`open build/LongDeck.app` or similar). Do not run `bundle.sh`.
- **Never touch the real `~/.claude/settings.json`.** No code under test reads or writes it. `ClaudeInstallPaths` has no default value. Only `ClaudeController` (app target) builds the live paths, and only inside the menu click handlers. Every installer test works in its own temp directory (`FileManager.default.temporaryDirectory/longdeck-tests-<UUID>`), and its helper asserts that every path it passes starts with that directory.
- **Never send keys to a real tmux pane.** No test or development step runs `tmux send-keys`, `switch-client`, `select-window` or `select-pane` against the real server. Tests use a `FakeTmux` runner. `ProcessTmuxRunner` tests run `/bin/echo` and `/bin/sleep` only. Read-only `tmux capture-pane -p`, `list-panes` and `display-message -p` of real panes is allowed during development to learn the prompt shape.
- Tests never bind port 47821 (they use port 0), never run `osascript`, and never start a Claude Code session.
- Swift uses the CommandLineTools toolchain only. In this plan, `$SWIFT_TEST` means, run in `mac/LongDeck`:
  `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
  Add `--filter <Suite>` to run one suite. `swift build` checks the app target.
- No SwiftUI macros: no `@State`, `@Observable` or `#Preview`. Use `ObservableObject` and `@Published` as M1 does.
- `LongDeckCore` builds in Swift 6 language mode (strict concurrency). The app target stays in Swift 5 mode.
- Grid, caps and frame limits are unchanged from M2: 8x2 cells, widget at `(col*80+3, row*90+3)` sized `(w*80-6) x (h*90-6)`, 8 pages, 16 widgets per page, ids at most 15 bytes and unique across pages, every WebSocket frame at most 15 360 bytes.
- Board colours come from the palette in `ui_internal.h`, and fonts only from `fonts.h`. No new fonts. Board UI strings are ASCII unless a task says otherwise.

## Protocol additions (both sides implement exactly this)

Every new message is a sealed text frame under the M1 session rules. There are no new binary frames. `DECK_PROTO_VERSION` stays 1.

| Dir | Type | Body | When |
| --- | --- | --- | --- |
| app→board | `claude` | claude object, below | Right after Ready (after `volume`), then on every change. An identical body is not sent twice in a row. During a layout push the newest body is held and sent when the push finishes. |
| app→board | `claude_ack` | `{"ok":<bool>,"reason":"<code or empty>","request":"<request id or empty>"}` | Once for every `claude_action` the app could parse. Never deduped. Queued (in order, at most 8) during a layout push. |
| board→app | `claude_action` | `{"action":"approve"\|"always"\|"deny"\|"interrupt"\|"focus","request":"<id or empty>","session":"<session id>"}` | On an overlay button or a session row press, only while Ready. `request` is the prompt's id for approve/always/deny and `""` for interrupt/focus. |

`claude` body. Keys are written sorted (`JSONSerialization` with `[.sortedKeys, .withoutEscapingSlashes]`):

| Field | Meaning |
| --- | --- |
| `sessions` | Array of at most 8 sessions, ordered permission, waiting, done, working, then newest state change first, then id. |
| `sessions[].id` | Claude `session_id` (a 36-char UUID). Sessions whose id is over 39 bytes are not sent. |
| `sessions[].project` | Last path component of `workspace.project_dir`, else of the hook `cwd`, else `?`. At most 23 bytes. |
| `sessions[].model` | `model.display_name` from the statusLine, at most 15 bytes, `""` when unknown. |
| `sessions[].state` | `working`, `permission`, `waiting` or `done`. |
| `sessions[].ctx` | `context_window.used_percentage` rounded, 0–100, `-1` when unknown. |
| `sessions[].cost_cents` | `cost.total_cost_usd * 100` rounded, `-1` when unknown. |
| `sessions[].tmux` | `true` when the session's hooks carried a valid `X-Tmux-Pane`. `false` sessions are read-only on the board. |
| `usage.five_hour`, `usage.seven_day` | `{"pct":<0–100>,"resets_at":<epoch s>}` from the latest statusLine `rate_limits`, or `null` when never seen or when `resets_at` has passed. A window missing from a newer statusLine keeps its previous value. |
| `prompt` | `null`, or the oldest pending permission prompt: `{"pending":<number of sessions with a pending prompt>,"project":"…","request":"…","session":"…","summary":"<≤ 80 bytes>","tmux":<bool>,"tool":"<≤ 15 bytes>"}`. |

String caps are UTF-8 byte caps. The app cuts at a grapheme boundary and ends a cut string with `…` (3 bytes) inside the cap. Control characters (U+0000–U+001F, U+007F) become spaces. Request ids are `<runTag>-<n>`: a 4-lowercase-hex tag picked when the app starts plus a counter from 1, at most 15 bytes. The board rejects a `claude` body over 4096 bytes (`DECK_CLAUDE_BODY_MAX`). With the caps and the control-character rule, the worst case stays under 2.5 KB.

`claude_ack.reason` codes, each at most 15 bytes: `""` (ok), `stale`, `no_prompt`, `mismatch`, `no_always`, `no_pane`, `not_claude`, `not_working`, `no_client`, `unverifiable`, `tmux`, `unknown_session`. The board shows one toast for any `ok:false`: `Answer at the keyboard`, and logs the reason to serial.

Layout JSON additions (M1/M2 keys unchanged):

- `"type":"claude_sessions"` and `"type":"claude_usage"` add nothing. Like every live widget they carry `"face":0` and no `"long"`.
- A `claude_sessions` narrower than 2 columns becomes a `DW_UNKNOWN` placeholder on the board, and the Mac config rejects it before sending.

Shared JSON examples. Both sides' tests use these strings byte for byte:

| Name | JSON |
| --- | --- |
| L2 | `{"hash":"0123456789abcdef","pages":[{"name":"Claude","widgets":[{"col":0,"face":0,"h":2,"id":"ccs","row":0,"type":"claude_sessions","w":4},{"col":4,"face":0,"h":1,"id":"ccu","row":0,"type":"claude_usage","w":4}]}]}` |
| C1 | `{"prompt":{"pending":1,"project":"T-Display-S3-Long","request":"a3f9-1","session":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42","summary":"pio run -e ntp_clock","tmux":true,"tool":"Bash"},"sessions":[{"cost_cents":142,"ctx":37,"id":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42","model":"Opus 5.5","project":"T-Display-S3-Long","state":"permission","tmux":true},{"cost_cents":-1,"ctx":-1,"id":"9b2d7e00-1111-4222-8333-444455556666","model":"","project":"caltera","state":"working","tmux":false}],"usage":{"five_hour":{"pct":42,"resets_at":1795530000},"seven_day":{"pct":13,"resets_at":1795900000}}}` |
| C2 | `{"prompt":null,"sessions":[],"usage":{"five_hour":null,"seven_day":null}}` |
| A1 | `{"action":"approve","request":"a3f9-1","session":"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42"}` |
| A2 | `{"action":"focus","request":"","session":"9b2d7e00-1111-4222-8333-444455556666"}` |
| K1 | `{"ok":false,"reason":"mismatch","request":"a3f9-1"}` |
| K2 | `{"ok":true,"reason":"","request":"a3f9-1"}` |

L2 is what `LayoutBuilder` produces for one page `Claude` with live `ccs` (`.claudeSessions`, col 0, row 0, 4x2) and `ccu` (`.claudeUsage`, col 4, row 0, 4x1), hash replaced by `0123456789abcdef`.

Mac-only fixtures (hook and statusLine stdin, as Claude Code sends them; `A` = `5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42`, `B` = `9b2d7e00-1111-4222-8333-444455556666`):

| Name | JSON |
| --- | --- |
| HK0 | `{"session_id":"A","transcript_path":"/tmp/work/t.jsonl","cwd":"/tmp/work/T-Display-S3-Long","hook_event_name":"SessionStart","source":"startup"}` |
| HKB | `{"session_id":"B","transcript_path":"/tmp/work/u.jsonl","cwd":"/tmp/work/caltera","hook_event_name":"UserPromptSubmit","prompt":"hi"}` |
| HK1 | `{"session_id":"A","transcript_path":"/tmp/work/t.jsonl","cwd":"/tmp/work/T-Display-S3-Long","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"pio run -e ntp_clock","description":"Build firmware"}}` |
| HK2 | HK1 with `"hook_event_name":"PostToolUse"` and `"tool_response":{"stdout":"ok"}` added |
| HK3 | `{"session_id":"A","cwd":"/tmp/work/T-Display-S3-Long","hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"}` |
| HK4 | HK3 with `"notification_type":"permission_prompt"` and `"message":"Claude needs your permission to use Bash"` |
| SL1 | `{"session_id":"A","transcript_path":"/tmp/work/t.jsonl","cwd":"/tmp/work/T-Display-S3-Long","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"workspace":{"current_dir":"/tmp/work/T-Display-S3-Long","project_dir":"/tmp/work/T-Display-S3-Long"},"cost":{"total_cost_usd":1.4249},"context_window":{"used_percentage":37.4},"rate_limits":{"five_hour":{"used_percentage":42.2,"resets_at":1795530000},"seven_day":{"used_percentage":12.6,"resets_at":1795900000}}}` |
| SL2 | SL1 without `rate_limits` |

(`"A"` and `"B"` stand for the full ids in the test source.)

C1 is what `ClaudeStore(runTag: "a3f9")` renders at `now = 1795520000` after: HK0 with pane `%37` at `t0 = 1795519000`, SL1 at `t0+10`, HKB with no pane at `t0+20`, and HK1 with pane `%37` at `t0+30`.

### Claude Code facts this milestone relies on

From the docs (as given) and the installed CLI 2.1.331:

- Hook stdin always has `session_id`, `cwd`, `transcript_path`, `hook_event_name`. `PermissionRequest`, `PreToolUse` and `PostToolUse` add `tool_name` and `tool_input`. `Notification` adds `notification_type` (`permission_prompt`, `idle_prompt`) and `message`.
- `"type":"http"` hooks POST the event JSON. `headers` values expand `$VAR` only for names in `allowedEnvVars` (regex `[A-Z_][A-Z0-9_]*`). Unlisted names become empty. A credential-looking variable is never interpolated; `TMUX_PANE` is not one. If a policy sets `allowedHttpHookUrls`, the LongDeck URL must be listed there (the owner's settings have none).
- An HTTP hook answered with an empty `2xx` body is a success with no decision.
- Claude Code captures hooks when a session starts, so sessions already running need a restart (or a review in `/hooks`) before they report. The statusLine change applies on the next refresh.
- The statusLine runs through a shell (`~` expands in it), so a command path with spaces must be quoted.
- Each Claude pane reports its Claude Code version as `pane_current_command` (seen on this Mac: `2.1.331`, `2.1.327`, …). A plain shell reports `zsh`.
- tmux 3.6b at `/opt/homebrew/bin/tmux`, `escape-time 10` in `~/.tmux.conf`, 5 clients attached, every pane 173x48 or smaller.

### Permission prompt shape (read from the installed binary; live check L2)

No pane showed a permission prompt on 2026-11-24, and no scrollback held one, so there is **no live capture yet**. The shape below comes from the UI strings and render code inside `~/.local/share/claude/versions/2.1.331` (read with `strings`). Hardware and live check L2 captures the real thing; if it differs, update fixtures F1–F10 and the matcher before using the board answers.

- An option row renders as `<pointer> <n>. <label>`. The focused row starts with `❯`, the others with spaces. The index is `` `${n}.` `` padded and dimmed.
- When the dialog does not fit, indexes are hidden, digit keys are disabled, and the text `This terminal is too short. Make it taller to choose Yes, or choose No.` shows. The matcher must refuse then.
- Labels:
  - Approve is exactly `Yes`.
  - "Always" rows start with `Yes, `: `Yes, and don't ask again for <cmd> commands in <dir>`, `Yes, allow all edits during this session (shift+tab)`, `Yes, and always allow access to <dir> from this project`, `Yes, allow reading from <dir> from this project`.
  - Deny is `No, and tell Claude what to do differently (esc)`.
  - Some asks have no "always" row. Some (`inPlaceOfClassifier`) put `No` first and `Yes` second. A disabled "always" row keeps its place, so No keeps its digit.
- Titles: `Bash command`; for files `Edit file`, `Create file`, `Overwrite file`, `Write file`, `Read file`. The question is `Do you want to proceed?` or, for files, `Do you want to make this edit to|create|overwrite|write to <name>?`. The question line is left out when the dialog is framed to fit, so the matcher does not require it.
- A working session's status line shows `esc to interrupt`.
- Digit keys choose an option directly. The board sends only the digit, never Enter. Live check L3 confirms this.

Matcher fixtures (Swift test literals, lines exactly as shown; leading spaces matter):

F1, Bash with an always row:

```
⏺ Bash(pio run -e ntp_clock)
  ⎿  Running…

────────────────────────────────────────────────────────────────────────────────
 Bash command

   pio run -e ntp_clock
   Build firmware

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for pio run commands in /tmp/work/T-Display-S3-Long
   3. No, and tell Claude what to do differently (esc)

```

- F2 is F1 with the options replaced by `❯ 1. Yes` and `  2. No, and tell Claude what to do differently (esc)`.
- F3 is an Edit prompt:

```
────────────────────────────────────────────────────────────────────────────────
 Edit file
 src/main.cpp
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
  12 -  int x = 1;
  12 +  int x = 2;
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Do you want to make this edit to main.cpp?
 ❯ 1. Yes
   2. Yes, allow all edits during this session (shift+tab)
   3. No, and tell Claude what to do differently (esc)
```

- F4 is a cut dialog: ` Bash command`, `   pio run -e ntp_clock`, ` This terminal is too short. Make it taller to choose Yes, or choose No.`, ` ❯ Yes`, `   No, and tell Claude what to do differently (esc)`.
- F5 is an idle screen: `⏺ Done. The firmware builds.`, blank, a `────` rule, `> `, a `────` rule, `  ? for shortcuts`.
- F6 is F1 with every `pio run -e ntp_clock` replaced by `rm -rf build`, `Build firmware` replaced by `Clean`, and the always row reading `2. Yes, and don't ask again for rm commands in /tmp/work/T-Display-S3-Long`.
- F7 is F1 whose command is `git commit -m "feat(longdeck): add the permission overlay and the claude sessions widget to the deck board"`, wrapped as `   git commit -m "feat(longdeck): add the permission overlay a` / `   nd the claude sessions widget to the deck board"`, with description `Commit`.
- F8 is a classifier-style prompt: ` Bash command`, `   curl https://example.com`, ` Do you want to proceed?`, ` ❯ 1. No, and tell Claude what to do differently (esc)`, `   2. Yes`.
- F9 is F1's dialog drawn inside `╭─╮ │ │ ╰─╯` borders, 48 columns wide, so option 2 wraps to `│   commands in /tmp/work/T-Display-S3-Long    │` and option 3 to `│   differently (esc)                          │`.
- F10 is F1 followed by 20 lines of build output, then a `────` rule, `> `, and a `────` rule.

## Review Focus

1. **Never approve the wrong prompt.** Approve, Always and Deny each need all of these:
   - the request id equals the pane's current pending request
   - the pane runs Claude Code
   - a numbered prompt sits near the bottom of the capture, with no input line below it
   - the tool title and the visible start of the command or the file name appear above it
   - for Always, an "always" row exists

   Anything else sends nothing. Tests: Task 4 `eachPermissionRequestGetsNewId`; Task 6 matcher F1–F10, `staleRequestRefusedWithoutCapture`, `mismatchRefused`, `alwaysWithoutRowRefused`, `notClaudePaneRefused`, `neverSendsKeysWithoutMatchingCapture`. Live checks L2, L3, L6.
2. **Claude Code is never slowed or broken.**
   - Hooks have `timeout` 2 and `onFailure` `continue`. The listener answers before any tmux work.
   - The wrapper posts in the background with `--max-time 0.2` and passes the previous command's output through unchanged.

   Tests: Task 3 `wrapperPassesOutputThrough`, `wrapperDoesNotWaitForListener`; Task 5 `acceptsHookWithToken`. Live check L9.
3. **settings.json safety.**
   - The installer merges and never replaces. It writes a backup first.
   - Uninstall restores the file byte for byte when nothing else changed, and keeps the user's later edits when something did.
   - Tests touch temp copies only.

   Tests: Task 3 installer suite. Live checks L1, L11.
4. **Frame order during a layout push.** `claude` and `claude_ack` are held while a push is in flight, exactly like M2's `volume`. Tests: Task 2 `claudeDeferredDuringPushKeepsNewest`, `acksQueuedDuringPushInOrder`.
5. **The overlay closes when the prompt is answered anywhere.**
   - A board answer resolves the prompt at once.
   - A keyboard answer is caught by a 1 Hz read-only `capture-pane` poll, or by `PostToolUse`, `UserPromptSubmit`, `Stop` or `idle_prompt`.

   Tests: Task 4 `promptCheck*`. Live check L5.
6. **Offline never shows stale Claude data.** Link loss clears the board's Claude snapshot. Widgets show `--` and the overlay hides. Live check L12.
7. **Only the owner's processes can feed the listener.** It binds loopback only and requires the token. Tests: Task 5 `rejectsMissingOrWrongToken`, `notReachableFromLanAddress`.

---

### Task 1: Board Claude logic (pure, native-tested)

**Files:**
- Modify: `examples/ntp_clock/deck_layout.h`, `examples/ntp_clock/deck_layout.cpp`
- Create: `examples/ntp_clock/deck_claude.h`, `examples/ntp_clock/deck_claude.cpp` (no Arduino or LVGL includes)
- Modify: `platformio.ini`. In `[env:native_deck]`, add `+<deck_claude.cpp>` to `build_src_filter`.
- Test: `examples/ntp_clock/test/test_layout/test_main.cpp` (extend), `examples/ntp_clock/test/test_claude/test_main.cpp` (new)

**Interfaces:**
- Produces in `deck_layout.h`: `DeckWidgetType` gains `DW_CLAUDE_SESSIONS = 4` and `DW_CLAUDE_USAGE = 5`. Nothing else changes.
- Produces in `deck_claude.h` (includes `<stddef.h>`, `<stdint.h>`):

```cpp
#define DECK_CLAUDE_MAX_SESSIONS 8
#define DECK_CLAUDE_BODY_MAX     4096
#define DECK_CLAUDE_ID_MAX       40
#define DECK_CLAUDE_REQ_MAX      16
#define DECK_CLAUDE_PROJECT_MAX  24
#define DECK_CLAUDE_TOOL_MAX     16
#define DECK_CLAUDE_MODEL_MAX    16
#define DECK_CLAUDE_SUMMARY_MAX  84
#define DECK_CLAUDE_REASON_MAX   16

enum DeckClaudeState : uint8_t { DCS_WORKING = 0, DCS_PERMISSION, DCS_WAITING, DCS_DONE, DCS_COUNT };
enum DeckClaudeAction : uint8_t { DCA_APPROVE = 0, DCA_ALWAYS, DCA_DENY, DCA_INTERRUPT, DCA_FOCUS, DCA_COUNT };

struct DeckClaudeSession {
  char id[DECK_CLAUDE_ID_MAX];
  char project[DECK_CLAUDE_PROJECT_MAX];
  char model[DECK_CLAUDE_MODEL_MAX];
  uint8_t state;
  int8_t ctx;          // -1 unknown
  int32_t cost_cents;  // -1 unknown
  bool tmux;
};
struct DeckClaudeWindow { bool known; uint8_t pct; uint32_t resets_at; };
struct DeckClaudePrompt {
  bool present, tmux;
  uint8_t pending;
  char session[DECK_CLAUDE_ID_MAX];
  char request[DECK_CLAUDE_REQ_MAX];
  char project[DECK_CLAUDE_PROJECT_MAX];
  char tool[DECK_CLAUDE_TOOL_MAX];
  char summary[DECK_CLAUDE_SUMMARY_MAX];
};
struct DeckClaude {
  uint8_t count;
  DeckClaudeSession s[DECK_CLAUDE_MAX_SESSIONS];
  DeckClaudeWindow five_hour, seven_day;
  DeckClaudePrompt prompt;
};
struct DeckClaudeAck { bool ok; char request[DECK_CLAUDE_REQ_MAX]; char reason[DECK_CLAUDE_REASON_MAX]; };

bool        deck_claude_parse(const char *json, size_t len, DeckClaude *out);         // out untouched on false
bool        deck_claude_ack_parse(const char *json, size_t len, DeckClaudeAck *out);  // out untouched on false
bool        deck_claude_action_body(const char *session, const char *request, uint8_t action, char *out, size_t out_len);
int         deck_claude_state_from_name(const char *name);  // -1 if unknown
const char *deck_claude_action_name(uint8_t action);        // "" if out of range
void        deck_claude_copy(char *dst, size_t dst_len, const char *src);
void        deck_claude_format_reset(uint32_t resets_at, uint32_t now, char *out, size_t len);
void        deck_claude_format_cost(int32_t cents, char *out, size_t len);
bool        deck_claude_prompt_same(const DeckClaudePrompt *a, const DeckClaudePrompt *b);
```

  Behaviour required:
  - Layout parse: `claude_sessions` maps to `DW_CLAUDE_SESSIONS`, except that `w < 2` gives `DW_UNKNOWN`. `claude_usage` maps to `DW_CLAUDE_USAGE` at any width. Both get `face = 0` and `has_long = false` whatever the JSON says, and both take part in the grid, overlap, id and cap checks like every widget.
  - `deck_claude_parse`:
    - Returns false for a null pointer, a body over `DECK_CLAUDE_BODY_MAX`, malformed JSON, a non-object, `sessions` missing or not an array, or `usage` missing or not an object. It builds into a local `DeckClaude` and copies to `out` only on success.
    - Sessions: keep the first 8 valid entries in order. An entry needs a non-empty string `id` and a known `state` name, otherwise it is skipped.
      - `project` and `model` default to `""`.
      - `ctx` is a number rounded and clamped to 0..100, and a negative value or a non-number gives -1.
      - `cost_cents` is a number rounded, and a negative value, a non-number or a missing field gives -1.
      - `tmux` defaults to false.
    - A window is `known` only when it is an object with numeric `pct` (rounded, clamped 0..100) and numeric `resets_at` ≥ 0 (stored as `uint32_t`). `null`, missing or malformed gives `known = false`.
    - `prompt` is `present` only when it is an object with non-empty string `session` and `request`. `tool`, `project` and `summary` default to `""`, `tmux` to false, and `pending` (rounded) is clamped to 1..99, default 1.
    - Every string goes through `deck_claude_copy`.
  - `deck_claude_copy` copies at most `dst_len - 1` bytes, never splits a UTF-8 sequence (it backs off over continuation bytes `10xxxxxx`), and always NUL-terminates. A null `src` gives `""`.
  - `deck_claude_ack_parse` needs an object with a boolean `ok` and a string `request`. `reason` is optional (`""`).
  - `deck_claude_action_body`:
    - Uses ArduinoJson with keys inserted in the order `action`, `request`, `session`, so the output equals A1 and A2.
    - Returns false for an empty or null session, an action ≥ `DCA_COUNT`, an empty request with approve/always/deny, or a buffer that is too small (`measureJson(doc) >= out_len`).
  - `deck_claude_state_from_name`: `working`, `permission`, `waiting`, `done` map to their `DCS_*` values.
  - `deck_claude_action_name`: `approve`, `always`, `deny`, `interrupt`, `focus`.
  - `deck_claude_format_reset(resets_at, now)`:
    - `"--"` when either argument is 0.
    - Otherwise `d = resets_at - now` as a signed 64-bit value. `d ≤ 0` gives `"0m"`, `d < 60` gives `"<1m"`, below 3600 `"%um"`, below 86400 `"%uh %um"`, and from there `"%ud %uh"`, all with floor division.
  - `deck_claude_format_cost`: a negative value gives `"--"`, below 10000 `"$%d.%02d"`, and from there `"$%d"` (whole dollars).
  - `deck_claude_prompt_same` is true when both are absent, or both are present with equal `session` and `request`.

- [ ] **Step 1: Write the failing tests**

  In `test_layout/test_main.cpp` (keep every M1 and M2 test):
  - `test_parse_claude_example`: L2 parses. [0] is `DW_CLAUDE_SESSIONS` 4x2, [1] is `DW_CLAUDE_USAGE` 4x1, both with face 0 and `has_long == false`.
  - `test_claude_sessions_needs_two_columns`: a 1x1 `claude_sessions` parses as `DW_UNKNOWN`. Overlapping it with a key is still rejected.
  - `test_claude_face_and_long_ignored`: a `claude_usage` with `"face":9,"long":true` gives face 0 and no long.

  In `test_claude/test_main.cpp`:
  - `test_parse_c1`:
    - `count == 2`.
    - `s[0]` has the C1 id, project `T-Display-S3-Long`, model `Opus 5.5`, `DCS_PERMISSION`, ctx 37, cost 142 and tmux true.
    - `s[1]` has `DCS_WORKING`, ctx -1, cost -1, model `""` and tmux false.
    - The windows are `{true,42,1795530000}` and `{true,13,1795900000}`.
    - The prompt is present with pending 1, request `a3f9-1`, tool `Bash`, summary `pio run -e ntp_clock`, tmux true and the C1 session id.
  - `test_parse_c2`: count 0, both windows unknown, prompt absent.
  - `test_parse_rejects_and_keeps_out`: `{`, `[]`, a 4097-byte body, `{"sessions":[]}` and `{"usage":{}}` each return false, and a sentinel-filled `out` is unchanged (`memcmp`).
  - `test_parse_skips_bad_sessions`: entries with state `sleeping`, a missing id and `"id":""` are skipped, and the valid ones keep their order.
  - `test_parse_caps_sessions_at_8`: 10 valid entries give count 8, the first 8.
  - `test_parse_truncates_utf8_safely`:
    - A project of 30 × `ก` (3 bytes each) is stored as 21 bytes, 7 whole characters.
    - A 40-char ASCII id is stored as 39 bytes.
    - A summary of 100 ASCII bytes is stored as 83.
  - `test_parse_clamps_numbers`: ctx 150 → 100, ctx -5 → -1, ctx 12.6 → 13, pct 101 → 100, pct -3 → 0, pending 0 → 1, `cost_cents` -7 → -1.
  - `test_parse_prompt_requires_ids`: a prompt with `"session":""` or a missing `request` is absent.
  - `test_state_names`: the 4 names map, and `"x"` and `NULL` give -1.
  - `test_ack_parse_k1_k2`: K1 gives `{false,"a3f9-1","mismatch"}`, and K2 gives ok with reason `""`.
  - `test_ack_rejects`: a missing `ok`, `"ok":"false"`, a missing `request`, `[]` and `{` each return false with `out` unchanged.
  - `test_action_body_a1_a2`: the bodies equal A1 and A2. Approve with `""` request gives false. Interrupt with `""` request gives true. Action 9, an empty session and a 16-byte buffer each give false.
  - `test_action_names`: all 5 names, and `""` for 5.
  - `test_format_reset_vectors`: `now = 1795520000`, and `resets_at - now` → text:

    | Δ | Text |
    | --- | --- |
    | -10 | `0m` |
    | 0 | `0m` |
    | 59 | `<1m` |
    | 60 | `1m` |
    | 3599 | `59m` |
    | 3600 | `1h 0m` |
    | 15179 | `4h 12m` |
    | 86399 | `23h 59m` |
    | 86400 | `1d 0h` |
    | 190801 | `2d 5h` |

    Also `resets_at = 0` gives `--`, and `now = 0` gives `--`.
  - `test_format_cost_vectors`: -1 → `--`, 0 → `$0.00`, 5 → `$0.05`, 142 → `$1.42`, 9999 → `$99.99`, 10000 → `$100`, 12345 → `$123`.
  - `test_prompt_same`: both absent gives true. The same session and request gives true. A different request gives false. One present and one absent gives false.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `pio test -e native_deck -f test_claude -f test_layout`. Expected: compile errors for the missing symbols.

- [ ] **Step 3: Implement**

  Parse with ArduinoJson `JsonDocument`. Use `is<float>()` for numbers and `is<const char *>()` for strings. Round with `floorf(x + 0.5f)`.

- [ ] **Step 4: Run the tests and confirm they pass, then confirm the firmware still builds**

  Run: `pio test -e native_deck`. Expected: `test_crypto`, `test_proto`, `test_layout`, `test_live` and `test_claude` all PASS.
  Run: `pio run -e ntp_clock`. Expected: SUCCESS.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): parse claude sessions and usage on the board`

### Task 2: Mac Claude widgets in the config, and Claude frames in LiveLink

**Files:**
- Modify: `mac/LongDeck/Sources/LongDeckCore/DeckConfig.swift`, `LayoutBuilder.swift`, `SampleConfig.swift`, `LiveLink.swift`
- Modify: `mac/LongDeck/Sources/LongDeckApp/DeckConnection.swift`, **only** the one `pushFinished()` call site, so the app target keeps building. Task 10 owns the rest of this file and runs later in the same lane.
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/DeckConfigTests.swift`, `LayoutBuilderTests.swift`, `LiveLinkTests.swift` (extend)

**Interfaces:**
- Produces in `DeckConfig.swift`:
  - `LiveKind` gains `case claudeSessions, claudeUsage`. Their JSON `type` strings are `claude_sessions` and `claude_usage`. They have no extra keys.
  - `validate()` also throws `DeckConfigError.invalid("widget <id>: claude_sessions needs at least 2 columns")` for a `.claudeSessions` with `w < 2`.
- Produces in `LayoutBuilder.swift`: the two kinds emit `"type":"claude_sessions"` and `"type":"claude_usage"` with the M2 live widget keys and `"face":0`.
- Produces in `SampleConfig.swift`: `SampleConfig.dev` gains a third page `PageConfig(name: "Claude", keys: [], live: …)`:
  - `ccsessions`: `.claudeSessions` at col 0, row 0, 4x2.
  - `ccusage`: `.claudeUsage` at col 4, row 0, 4x1.
  - `ccclock`: `.clock` at col 4, row 1, 2x1.
  - The `Dev` and `Mac` pages are unchanged.
- Produces in `LiveLink.swift`:

```swift
public mutating func claudeFrame(body: String) -> OutFrame?  // deduped against the last sent body; newest held while pushing
public mutating func ackFrame(body: String) -> OutFrame?     // never deduped; queued while pushing, max 8, oldest dropped
public mutating func pushFinished() -> [OutFrame]            // held volume, then held claude, then queued acks
```

  - `reset()` also forgets the last claude body, the held claude body and the queued acks.
  - `isLiveWidget` and `command` are unchanged. Claude widget ids already count as live widgets, so a `press` for them never reaches `ActionRunner`.
- In `DeckConnection.swift`, replace `if let held = self.link.pushFinished() { self.sendFrame(held) }` with a loop that sends every returned frame in order.

- [ ] **Step 1: Write the failing tests**

  - In `DeckConfigTests`, keep every M1 and M2 test. Give the switch in `sampleMacPageHasEveryLiveKind` the two new cases, ignored. Then add:
    - `claudeWidgetJSONIsFlat`: with `.sortedKeys`, `LiveWidgetConfig(id:"ccs",col:0,row:0,w:4,h:2,kind:.claudeSessions)` encodes to `{"col":0,"h":2,"id":"ccs","row":0,"type":"claude_sessions","w":4}` and decodes back equal. The same holds for `.claudeUsage`.
    - `claudeSessionsNeedsTwoColumns`: a 1x1 `.claudeSessions` fails `validate()`. A 1x1 `.claudeUsage` passes.
    - `sampleClaudePage`: the `Claude` page has exactly the three widgets above, and `validate()` passes.
  - In `LayoutBuilderTests`, add `claudeLayoutMatchesSharedExample`: build the L2 config with `stubRender`, replace the hash with `0123456789abcdef`, and expect L2. `built.faces` is empty. `sampleLayoutFrameFitsBoard` must still pass with three pages.
  - In `LiveLinkTests`:
    - Change `volumeDeferredDuringPush` to expect `[OutFrame(type: "volume", body: V2)]`.
    - Add `claudeDedupes`: C1 gives a frame, C1 again gives `nil`, and C2 gives a frame. After `reset()`, C2 gives a frame.
    - Add `claudeDeferredDuringPushKeepsNewest`: `pushStarted()`, then C1 and C2 both give `nil`. `pushFinished()` gives `[claude C2]`.
    - Add `acksQueuedDuringPushInOrder`: during a push, K1 then K2 give `nil`. `pushFinished()` gives `[claude_ack K1, claude_ack K2]`. Ten acks keep the last 8.
    - Add `pushFinishedOrder`: a held V1, C1 and K1 come back as `[volume, claude, claude_ack]`.
    - Add `acksNeverDeduped`: K1 twice outside a push gives two frames.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST`. Expected: compile errors.

- [ ] **Step 3: Implement the changes above**

- [ ] **Step 4: Run the tests and confirm they pass, and that the app builds**

  Run: `$SWIFT_TEST`. Expected: all suites pass.
  Run: `cd mac/LongDeck && swift build`. Expected: SUCCESS.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add claude widgets to the mac config and live link`

### Task 3: Mac settings JSON, installer and statusLine wrapper

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `OrderedJSON.swift`, `StatusLineWrapper.swift`, `ClaudeInstaller.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/OrderedJSONTests.swift`, `StatusLineWrapperTests.swift`, `ClaudeInstallerTests.swift`

**Interfaces:**
- Produces:

```swift
public indirect enum JSONValue: Equatable, Sendable {
    case null, bool(Bool), number(String), string(String), array([JSONValue]), object([JSONMember])
    public subscript(key: String) -> JSONValue? { get }          // objects only
    public func setting(_ key: String, _ value: JSONValue) -> JSONValue   // replaces in place, else appends
    public func removing(_ key: String) -> JSONValue
}
public struct JSONMember: Equatable, Sendable { public var key: String; public var value: JSONValue }
public enum JSONText {
    public static func parse(_ data: Data) throws -> JSONValue
    public static func pretty(_ value: JSONValue) -> String   // JSON.stringify(v, null, 2) + "\n"
    public static func compact(_ value: JSONValue) -> String  // JSON.stringify(v)
}

public enum StatusLineWrapper {
    public static func script(previousCommand: String?, url: String, token: String, curl: String = "/usr/bin/curl") -> String
    public static func shellQuote(_ s: String) -> String      // POSIX single quotes
}

public struct ClaudeInstallPaths: Sendable {
    public let settings: URL     // a settings.json path, never defaulted
    public let supportDir: URL   // holds statusline.sh and claude-install.json
    public init(settings: URL, supportDir: URL)
}
public struct ClaudeInstallState: Codable, Equatable, Sendable {
    public var token: String
    public var port: Int
    public var statusLineCommand: String          // the exact command string written
    public var previousStatusLine: String?        // compact JSON of the original value, nil = key absent
    public var createdEvents: [String]
    public var createdHooksKey: Bool
    public var createdSettingsFile: Bool
    public var backupPath: String?
    public var installedAt: String                // ISO 8601 UTC
}
public enum ClaudeInstallError: Error, Equatable {
    case alreadyInstalled, notInstalled, settingsUnreadable(String), settingsNotObject,
         wrapperWithoutState, writeFailed(String)
}
public enum ClaudeInstaller {
    public static let port = 47821
    public static let hookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                    "PermissionRequest", "Notification", "Stop", "SessionEnd"]
    public static func loadState(_ paths: ClaudeInstallPaths) -> ClaudeInstallState?
    @discardableResult
    public static func install(_ paths: ClaudeInstallPaths, token: String, now: Date) throws -> ClaudeInstallState
    public static func uninstall(_ paths: ClaudeInstallPaths, now: Date) throws
}
```

  Behaviour required:
  - `JSONText`:
    - `parse` keeps object key order and keeps each number as its source text. It decodes `\uXXXX` escapes, surrogate pairs included. It throws on malformed input or trailing garbage.
    - `pretty` matches `JSON.stringify(v, null, 2)` plus `"\n"`: 2-space indent, `"key": value`, and one array element per line. Empty objects and arrays print as `{}` and `[]`.
    - String escaping matches `JSON.stringify`: `\"`, `\\`, `\b`, `\f`, `\n`, `\r`, `\t`, other code points below 0x20 as lowercase `\u00xx`. `/` and non-ASCII are written as is.
  - `StatusLineWrapper.script` is exactly these lines, with every `<…>` produced by `shellQuote`:

    ```
    #!/bin/sh
    in=$(cat)
    printf '%s' "$in" | <curl> -s -o /dev/null --max-time 0.2 -X POST -H 'Content-Type: application/json' -H <'X-LongDeck-Token: TOKEN'> -H "X-Tmux-Pane: ${TMUX_PANE:-}" --data-binary @- <url> >/dev/null 2>&1 &
    printf '%s' "$in" | /bin/sh -c <previousCommand>
    ```

    The last line is left out when `previousCommand` is nil. The script ends with `"\n"`. `shellQuote` wraps a string in `'` and turns each `'` into `'\''`.
  - `ClaudeInstaller.install(paths, token, now)`:
    1. Throw `.alreadyInstalled` if `supportDir/claude-install.json` exists.
    2. Resolve symlinks in `paths.settings`. Read it. A missing file counts as `{}` with `createdSettingsFile = true`. A parse error throws `.settingsUnreadable(message)`, and a non-object throws `.settingsNotObject`. Neither error writes anything.
    3. If `statusLine.command` already equals the quoted wrapper path, throw `.wrapperWithoutState`.
    4. If the file existed, write the backup **before any other write**. The backup is the exact original bytes, at `<settings>.longdeck-<yyyyMMdd-HHmmss>.bak` with `now` in UTC (add `-2`, `-3`, … if the name is taken), file mode 0600.
    5. Remove stale LongDeck groups (rule below) from every event array.
    6. For each name in `hookEvents`, append one group to `hooks.<name>`, creating `hooks` and the array when they are missing and recording them in `createdHooksKey` and `createdEvents`. Each group is, in this key order:

       ```json
       {"hooks":[{"type":"http","url":"http://127.0.0.1:47821/hook","headers":{"X-LongDeck-Token":"<token>","X-Tmux-Pane":"$TMUX_PANE"},"allowedEnvVars":["TMUX_PANE"],"timeout":2,"onFailure":"continue"}]}
       ```

    7. The statusLine:
       - Set `statusLineCommand = shellQuote(<supportDir>/statusline.sh)`.
       - If a `statusLine` object exists, store `JSONText.compact` of it in `previousStatusLine` and change only its `command`.
       - Otherwise add `{"type":"command","command":<statusLineCommand>,"padding":0}`, and `previousStatusLine` stays nil.
    8. Write `supportDir/statusline.sh` with mode 0700. It uses `previousCommand` = the old `statusLine.command` (nil when there was none) and `url` = `http://127.0.0.1:47821/statusline`.
    9. Write settings with `JSONText.pretty`: to a temp file in the same directory, with the original file mode (0600 when new), then `rename` over the original.
    10. Write the state file `claude-install.json` (sorted keys, pretty, mode 0600) and return the state.
  - A LongDeck group is an element of an event array whose `hooks` array has at least one object with `"type":"http"`, a `url` starting with `http://127.0.0.1:47821/`, and a `headers` object holding `X-LongDeck-Token`.
  - `ClaudeInstaller.uninstall(paths, now)`:
    1. Throw `.notInstalled` without a state file.
    2. Read the settings. If the file is gone, just delete the wrapper and the state file.
    3. Write a backup first, named as above.
    4. Remove every LongDeck group. Delete an event key that is now empty **and** listed in `createdEvents`. Delete `hooks` when it is now empty and `createdHooksKey` is true.
    5. If `statusLine.command` still equals `statusLineCommand`: when `previousStatusLine` is nil, remove `statusLine`; otherwise replace it with `JSONText.parse(previousStatusLine)`. A statusLine the user changed since install is left alone.
    6. If `createdSettingsFile` is true and the result is `{}`, delete the settings file. Otherwise write it as in install step 9.
    7. Delete `statusline.sh` and `claude-install.json`.

- [ ] **Step 1: Write the failing tests**

  The installer fixture `SETTINGS` is this text with a trailing newline. The `"Notification"` group is repeated with the same body, in this order, for `PermissionRequest`, `PostToolUse`, `PreToolUse`, `SessionEnd`, `SessionStart`, `Stop`, `StopFailure`, `SubagentStop` and `UserPromptSubmit`:

  ```json
  {
    "env": {
      "EXAMPLE_FLAG": "1"
    },
    "model": "opus",
    "hooks": {
      "Notification": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/Users/dev/.config/iterm2/cc-status"
            }
          ]
        }
      ]
    },
    "statusLine": {
      "type": "command",
      "command": "ccstatusline",
      "padding": 0,
      "refreshInterval": 10
    },
    "theme": "dark",
    "label": "ทดสอบ \"q\" \\ /x",
    "ratio": 0.25,
    "flags": [],
    "nested": {}
  }
  ```

  - `OrderedJSONTests`:
    - `roundTripsFixtureByteForByte`: `pretty(parse(SETTINGS)) == SETTINGS`.
    - `compactMatchesJSONStringify`: `{"b":1,"a":[true,null,"x\ny"]}` stays the same.
    - `escapesLikeJSONStringify`: U+0001 gives `"\u0001"`, `/` stays `/`, and `é` stays raw.
    - `decodesSurrogatePairs`: `"😀"` gives 😀.
    - `rejectsMalformed`: `{`, `{"a":1}x`, `[1,]`.
    - `settingAndRemovingKeepOrder`: `setting` replaces in place, adds at the end, and `removing` keeps the rest in order.
  - `StatusLineWrapperTests` (each test writes the script into its temp dir and runs `/bin/sh <script>` through `Process`; the URL is `http://127.0.0.1:9/statusline`, which refuses):
    - `wrapperPassesOutputThrough`: with previous command `cat` and stdin `{"a":1}`, stdout is `{"a":1}`.
    - `quotesPreviousCommandSafely`: previous command `printf '%s' "it's"` gives `it's`.
    - `noPreviousCommandPrintsNothing`: stdout is empty and the exit status is 0.
    - `wrapperDoesNotWaitForListener`: with previous command `cat`, the run takes under 1 s.
    - `postsHeadersAndBody`:
      - Use `curl:` = a fake script in the temp dir that writes `"$@"` and its stdin to files. Run with `TMUX_PANE=%99` in the environment.
      - Within 2 s, the args contain `--max-time 0.2`, `X-LongDeck-Token: <token>`, `X-Tmux-Pane: %99` and the URL, and the recorded stdin equals the input.
  - `ClaudeInstallerTests` (temp dirs only; `now` = 2026-11-24 15:30:00 UTC; token = 64 × `a`):
    - `installAddsHttpHooksBesideExisting`:
      - Every one of the 8 events holds the original cc-status group first, unchanged, and the LongDeck group last, equal to the group above.
      - `StopFailure` and `SubagentStop` are unchanged.
      - Every other top-level key has the same `compact` text as before, and the key order is unchanged.
      - `statusLine` is `{"type":"command","command":"'<supportDir>/statusline.sh'","padding":0,"refreshInterval":10}`.
    - `installWritesBackupFirst`: the backup `settings.json.longdeck-20261124-153000.bak` holds the original bytes. A second backup in the same second gets `-2`.
    - `wrapperRunsPreviousCommand`: `statusline.sh` exists with mode 0700 and contains `/bin/sh -c 'ccstatusline'`.
    - `stateRecordsOriginal`: `previousStatusLine == {"type":"command","command":"ccstatusline","padding":0,"refreshInterval":10}`, `createdEvents` is empty, and the token is stored.
    - `uninstallRestoresExactly`: install then uninstall gives settings bytes equal to `SETTINGS`. The wrapper and the state file are gone.
    - `uninstallKeepsLaterUserEdits`:
      - After install, the test adds a command hook to `Stop`, sets `theme` to `light`, and adds a key `newKey`.
      - Uninstall leaves those three edits, removes every LongDeck group, and restores the `statusLine`.
    - `uninstallLeavesChangedStatusLine`: after install, the test sets `statusLine.command` to `other`. Uninstall keeps `other`.
    - `installIntoEmptyAndMissingFiles`:
      - `{}\n` round-trips: install creates `hooks` and all 8 events plus a `statusLine` with `padding` 0, and uninstall gives back `{}\n` exactly.
      - A missing file is created and then deleted on uninstall.
    - `installTwiceRefused`: the second install throws `.alreadyInstalled` and changes nothing.
    - `staleGroupsReplaced`: settings that already hold a LongDeck group in `Stop` (no state file) end up with exactly one LongDeck group per event.
    - `invalidSettingsRefused`: `{` throws `.settingsUnreadable`, and `[]` throws `.settingsNotObject`. In both cases the file bytes are unchanged and no backup, wrapper or state file exists.
    - `wrapperWithoutStateRefused`.
    - `settingsSymlinkFollowed`: when settings is a symlink to `real.json`, the symlink stays a symlink and `real.json` changes.
    - `fileModeKept`: a 0600 settings file is still 0600 after install.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter "OrderedJSON|StatusLineWrapper|ClaudeInstaller"`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass. `git status` shows no change outside `mac/LongDeck`, and `~/.claude/settings.json` has the same modification time as before.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add the claude code installer and statusline wrapper`

### Task 4: Mac Claude events, session store and board body

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `ClaudeEvents.swift`, `ClaudeText.swift`, `ClaudeStore.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/ClaudeEventsTests.swift`, `ClaudeTextTests.swift`, `ClaudeStoreTests.swift`

**Interfaces:**
- Produces:

```swift
public struct ClaudeHookEvent: Equatable, Sendable {
    public var sessionId: String
    public var event: String
    public var cwd: String?
    public var toolName: String?
    public var toolInputJSON: String?      // sorted keys, slashes unescaped
    public var notificationType: String?
    public static func decode(_ body: Data) -> ClaudeHookEvent?   // nil without session_id or hook_event_name
}
public struct UsageWindow: Equatable, Sendable { public var pct: Double; public var resetsAt: TimeInterval }
public struct ClaudeStatusUpdate: Equatable, Sendable {
    public var sessionId: String
    public var model: String?
    public var costUSD: Double?
    public var contextPct: Double?
    public var projectDir: String?          // workspace.project_dir, else workspace.current_dir, else cwd
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
    public static func decode(_ body: Data) -> ClaudeStatusUpdate?
}

public enum ClaudeText {
    public static func capped(_ s: String, bytes: Int) -> String       // grapheme-safe, "…" when cut
    public static func cappedLeft(_ s: String, bytes: Int) -> String   // keeps the tail, "…" first
    public static func toolLabel(_ toolName: String) -> String          // ≤ 15 bytes
    public static func summary(toolName: String, toolInputJSON: String, cwd: String?) -> String  // ≤ 80 bytes
    public static func project(_ path: String?) -> String               // ≤ 23 bytes, "?" when empty
}

public enum ClaudeState: String, Sendable { case working, permission, waiting, done }
public struct ClaudePending: Equatable, Sendable {
    public var request: String
    public var toolName: String
    public var toolInputJSON: String
    public var createdAt: Date
    public var seenOnScreen: Bool
    public var misses: Int
}
public struct ClaudeSession: Equatable, Sendable {
    public var id: String
    public var cwd: String?
    public var projectDir: String?
    public var pane: String?
    public var state: ClaudeState
    public var stateSince: Date
    public var lastSeen: Date
    public var model: String?
    public var costUSD: Double?
    public var contextPct: Double?
    public var pending: ClaudePending?
}
public struct ClaudeStore: Sendable {
    public static let silentLimit: TimeInterval = 1800
    public static let unseenGrace: TimeInterval = 5
    public init(runTag: String)
    public private(set) var sessions: [String: ClaudeSession]
    public private(set) var fiveHour: UsageWindow?
    public private(set) var sevenDay: UsageWindow?
    public mutating func apply(_ e: ClaudeHookEvent, pane: String?, now: Date)
    public mutating func apply(_ s: ClaudeStatusUpdate, pane: String?, now: Date)
    public mutating func expire(now: Date)
    public mutating func resolve(session: String, request: String, state: ClaudeState, now: Date)
    @discardableResult
    public mutating func promptCheck(session: String, request: String, visible: Bool, now: Date) -> Bool  // true = cleared
    public func pendingPrompts() -> [(session: ClaudeSession, pending: ClaudePending)]   // oldest first
    public func body(now: Date) -> String
}
```

  Behaviour required:
  - Decoding:
    - Both decoders use `JSONSerialization` and return nil for non-JSON or a missing id.
    - `toolInputJSON` is re-serialised with `[.sortedKeys, .withoutEscapingSlashes]`.
    - Statusline numbers accept Int or Double. `resets_at` must be a number.
  - `ClaudeText.capped`:
    - Replace control characters with spaces.
    - If the string fits `bytes`, return it.
    - Otherwise add `Character`s while the UTF-8 count stays ≤ `bytes - 3`, then append `…`.
    - `cappedLeft` does the same from the end and puts `…` first.
  - `toolLabel`: `mcp__<server>__<tool>` gives `<tool>`. Anything else stays the name. Then `capped(…, 15)`.
  - `summary`, from `tool_input`:
    - `Bash`: the first line of `command`.
    - `Edit`, `MultiEdit`, `Write`, `Read`: `file_path`. `NotebookEdit`: `notebook_path`. Paths under `cwd + "/"` lose that prefix, and long paths use `cappedLeft`.
    - `WebFetch`: `url`. `WebSearch`: `query`. `Grep` and `Glob`: `pattern`. `Task` and `Agent`: `description`.
    - Any other tool: the compact `toolInputJSON`.
    - Everything except paths goes through `capped(…, 80)`.
  - `project`: the last path component, `capped(…, 23)`.
  - Store rules. Every event creates the session if needed, sets `lastSeen = now`, updates `cwd` when present, and sets `pane` when the given pane is non-nil (a nil pane keeps the old one). A state change sets `stateSince = now`.
    - `SessionStart` → `waiting`.
    - `UserPromptSubmit` → `working`, pending cleared.
    - `PreToolUse` → `working` only when nothing is pending.
    - `PermissionRequest` → `permission`, with a new `ClaudePending`: request `"<runTag>-<n>"`, where `n` counts every PermissionRequest from 1 across the store; `createdAt = now`; not seen; 0 misses. It replaces any older pending prompt of that session.
    - `PostToolUse`:
      - If a prompt is pending with the same `toolName` and `toolInputJSON`, clear it and set `working`.
      - If nothing is pending, set `working`.
      - Otherwise change nothing.
    - `Notification` with `permission_prompt` → `permission`, and no pending prompt is created. With `idle_prompt` → `waiting`, pending cleared. Other types only touch `lastSeen`.
    - `Stop` → `done`, pending cleared.
    - `SessionEnd` → the session is removed.
    - Unknown event names only touch `lastSeen`.
  - Status updates create the session in `waiting` if it is unknown. They set `model`, `costUSD`, `contextPct` and `projectDir` when present, and `lastSeen`. A window present in the update replaces the stored window, and an absent one keeps it.
  - `expire(now)` removes sessions with `now - lastSeen > silentLimit`, and drops a usage window once `now ≥ resetsAt`.
  - `resolve` clears the pending prompt and sets `state`, only if the session's pending request equals `request`.
  - `promptCheck` ignores a request that is not the session's current one.
    - `visible == true` sets `seenOnScreen` and resets `misses`.
    - Otherwise `misses += 1`. The prompt is cleared and the state set to `working` once `misses ≥ 2` and either `seenOnScreen` or `now - createdAt ≥ unseenGrace`.
  - `body(now)` follows the Protocol section:
    - Sort the sessions: permission, waiting, done, working; then `stateSince` descending; then id ascending. Drop ids over 39 bytes and keep the first 8.
    - `ctx` is `Int(contextPct.rounded())` clamped to 0...100, else -1. `cost_cents` is `Int((costUSD * 100).rounded())`, else -1. `model` is `capped(…, 15)` or `""`.
    - `prompt` is the oldest pending by `createdAt`, with `pending` = the number of sessions with a pending prompt. `summary` uses that session's `cwd`.
    - Windows use `Int(pct.rounded())` clamped to 0...100 and `Int(resetsAt)`, and `NSNull` when nil or when `now ≥ resetsAt`.
    - Serialise with `[.sortedKeys, .withoutEscapingSlashes]`.

- [ ] **Step 1: Write the failing tests**

  - `ClaudeEventsTests`:
    - `hookDecodeReadsHK1`: tool `Bash`, `toolInputJSON == {"command":"pio run -e ntp_clock","description":"Build firmware"}`, cwd set.
    - `hookDecodeReadsNotificationType` (HK3).
    - `hookDecodeRejects`: a missing `session_id`, a missing `hook_event_name`, `[]` and `x`.
    - `statusDecodeReadsSL1`: model `Opus 5.5`, cost 1.4249, ctx 37.4, `projectDir` `/tmp/work/T-Display-S3-Long`, windows `(42.2, 1795530000)` and `(12.6, 1795900000)`.
    - `statusDecodeToleratesMissingRateLimits`: SL2 gives both windows nil. SL1 with only `five_hour` gives `sevenDay == nil`.
  - `ClaudeTextTests`:
    - `cappedKeepsShortStrings`.
    - `cappedCutsAtGraphemeWithEllipsis`: `capped("โปรเจกต์ทดสอบยาวมาก", bytes: 23) == "โปรเจก…"` (21 bytes).
    - `cappedReplacesControlChars`: `"a\tb\u{7}"` gives `"a b "`.
    - `cappedLeftKeepsTail`: a 120-byte path keeps its file name and starts with `…`.
    - `toolLabelStripsMcpPrefix`: `mcp__claude_ai_Notion__notion-search` → `notion-search`.
    - `summaryPerTool`, a table:
      - Bash with a two-line command → first line.
      - Edit under cwd → `src/main.cpp`.
      - Write outside cwd → the absolute path.
      - WebFetch → url.
      - Grep → pattern.
      - `Foo` → compact JSON.
    - `projectFromPath`: `/a/b/caltera/` → `caltera`, nil → `?`.
  - `ClaudeStoreTests` (`runTag: "a3f9"`, explicit `now` values):
    - `bodyMatchesC1`: the sequence in the Protocol section gives exactly C1.
    - `bodyMatchesC2`: an empty store gives exactly C2.
    - `stateTransitionsFollowSpec`, a table from a fresh session:
      - HK0 → waiting.
      - HKB-style UserPromptSubmit → working.
      - PreToolUse → working.
      - HK1 → permission, with pending `a3f9-1`.
      - HK2 → working, nothing pending.
      - HK4 → permission, nothing pending.
      - HK3 → waiting.
      - Stop → done.
      - SessionEnd → gone.
    - `preToolUseKeepsPendingPrompt`: HK1, then a PreToolUse for another command, keeps `permission` and `a3f9-1`.
    - `postToolUseForOtherCallKeepsPrompt`.
    - `eachPermissionRequestGetsNewId`: two HK1s give `a3f9-1`, then `a3f9-2`, and only `a3f9-2` stays pending.
    - `promptClearedByPromptStopAndIdle`: UserPromptSubmit, Stop and HK3 each clear it.
    - `paneKeptWhenLaterEventHasNone`.
    - `silentSessionsDropped`: `lastSeen` at t; `expire(t+1800)` keeps it, `expire(t+1801)` removes it.
    - `statusLineCreatesSessionAndKeepsUsage`: SL1 for an unknown session gives `waiting` plus usage. Then SL2 keeps the usage.
    - `usageWindowDroppedAfterReset`: `expire(now: 1795530000)` drops `fiveHour` and keeps `sevenDay`.
    - `bodySortsAndCapsSessions`: 10 sessions in mixed states give 8 entries in the rule's order.
    - `bodyWorstCaseFitsBoard`:
      - 8 sessions with 39-byte ids, 60-char projects full of `"` and `\`, and 30-char models.
      - A pending Bash prompt whose command is 300 × `"\`.
      - The body is at most 4096 bytes and parses back as JSON.
    - `promptIsOldestPendingWithCount`: two pending sessions give the older prompt and `pending == 2`.
    - `promptCheckClearsAfterTwoMissesWhenSeen`: visible, then miss, miss → cleared and `working`.
    - `promptCheckGraceBeforeFirstSeen`: misses at +1 s and +2 s keep it. Misses at +6 s and +7 s clear it.
    - `promptCheckIgnoresOtherRequest`.
    - `resolveNeedsCurrentRequest`: `resolve(request: "a3f9-0")` changes nothing. `resolve("a3f9-1", .waiting)` clears it and sets `waiting`.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter Claude`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): track claude sessions and render the board body`

### Task 5: Mac local hook listener

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `HTTPRequestParser.swift`, `ClaudeListener.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/HTTPRequestParserTests.swift`, `ClaudeListenerTests.swift`

**Interfaces:**
- Produces:

```swift
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]   // keys lowercased
    public var body: Data
}
public enum HTTPParseResult: Equatable, Sendable { case needMore, request(HTTPRequest), failure(status: Int) }
public enum HTTPRequestParser {
    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 4 * 1024 * 1024
    public static func parse(_ buffer: Data) -> HTTPParseResult
}

public enum ClaudeChannel: String, Sendable { case hook, statusLine }
public struct ClaudeInbound: Sendable { public let channel: ClaudeChannel; public let pane: String?; public let body: Data }

@MainActor public final class ClaudeListener {
    public init(port: UInt16, token: String, onInbound: @escaping @MainActor (ClaudeInbound) -> Void)
    public func start(onReady: @escaping @MainActor (Result<UInt16, Error>) -> Void)   // bound port; 0 = ephemeral
    public func stop()
    public static func validPane(_ value: String?) -> String?   // "%<digits>" or nil
}
```

  Behaviour required:
  - Parser:
    - No `\r\n\r\n` yet gives `.needMore`, or 431 once the buffer exceeds `maxHeaderBytes`.
    - A bad request line (not `METHOD SP PATH SP HTTP/1.x`) gives 400.
    - Any `Transfer-Encoding` gives 501. A POST without `Content-Length` gives 411.
    - A `Content-Length` over `maxBodyBytes` gives 413. A short body gives `.needMore`.
  - Listener:
    - `NWParameters.tcp` with `acceptLocalOnly = true` and `requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: …)`, on `DispatchQueue.main`.
    - Per connection, it accumulates up to the parser's verdict, with a 5 s idle timeout.
    - It responds with `HTTP/1.1 <code> <reason>\r\nContent-Length: 0\r\nConnection: close\r\n\r\n` and cancels the connection after the send completes.
    - Routing:
      - `POST /hook` and `POST /statusline` with a correct `x-longdeck-token` (constant-time compare) call `onInbound` first, then answer 200.
      - A missing or wrong token gives 403. Any other path gives 404, and another method on a known path gives 405. A parser failure gives its status.
    - `pane` = `validPane(headers["x-tmux-pane"])`.

- [ ] **Step 1: Write the failing tests**

  - `HTTPRequestParserTests`:
    - `parsesCompleteRequest`.
    - `needsMoreForPartialHeaderAndBody`.
    - `headerKeysLowercased`.
    - `rejects`: 400, 411, 413, 431 and 501 cases.
    - `ignoresBytesAfterBody`.
  - `ClaudeListenerTests` (`@MainActor`, `port: 0`, token `t0k`, requests through `URLSession` to `http://127.0.0.1:<bound>`):
    - `acceptsHookWithToken`: POST `/hook` with the token and `X-Tmux-Pane: %37` gives 200 with an empty body. `onInbound` fired once with `.hook`, `%37` and the exact body.
    - `statusLineChannel`.
    - `rejectsMissingOrWrongToken`: 403, and `onInbound` never fires.
    - `unknownPathIs404`, `getIs405`.
    - `validPaneRules`: `%37` → `%37`; `""`, `"%"`, `"%3a"`, `"37"` and nil → nil.
    - `notReachableFromLanAddress`: find the first up IPv4 address on an `en*` interface (`getifaddrs`). A TCP connect from `NWConnection` to it on the bound port must not reach `ready` within 1 s. Skip the test when there is no such address.
    - `stopReleasesPort`: after `stop()`, a request fails to connect.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter "HTTPRequestParser|ClaudeListener"`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add the loopback claude hook listener`

### Task 6: Mac answers through tmux

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `TmuxRunner.swift`, `PermissionPromptMatcher.swift`, `ClaudeResponder.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/PermissionPromptMatcherTests.swift`, `ClaudeResponderTests.swift`, `TmuxRunnerTests.swift`

**Interfaces:**
- Produces:

```swift
public protocol TmuxRunner: Sendable { func run(_ args: [String]) throws -> String }   // stdout
public enum TmuxError: Error, Equatable { case notFound, timeout, failed(Int32, String) }
public struct ProcessTmuxRunner: TmuxRunner {
    public static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
    public init(path: String? = nil, timeout: TimeInterval = 2)
}

public enum ClaudeActionKind: String, Sendable { case approve, always, deny, interrupt, focus }
public struct ClaudeActionRequest: Equatable, Sendable {
    public var session: String
    public var request: String
    public var action: ClaudeActionKind
    public static func parse(_ body: String) -> ClaudeActionRequest?
}
public struct ClaudeAck: Equatable, Sendable {
    public var request: String
    public var ok: Bool
    public var reason: String
    public var body: String { get }        // sorted keys
}

public struct PromptScreen: Equatable, Sendable {
    public var yes: Character
    public var always: Character?
    public var no: Character
    public var regionLines: [String]       // normalised lines above the options
}
public struct PromptHints: Equatable, Sendable {
    public var titles: [String]            // any one must appear; empty = no title check
    public var needle: String              // whitespace-free, non-empty
    public static func from(toolName: String, toolInputJSON: String, cwd: String?) -> PromptHints?
}
public enum PermissionPromptMatcher {
    public static func parse(_ screen: String) -> PromptScreen?
    public static func matches(_ screen: PromptScreen, _ hints: PromptHints) -> Bool
}

public struct TmuxClient: Equatable, Sendable { public var tty: String; public var session: String; public var activity: Int }
public enum TmuxFocus {
    public static func chooseClient(_ clients: [TmuxClient], paneSession: String, frontTTY: String?) -> TmuxClient?
}

public struct ClaudeTarget: Sendable {
    public var pane: String?
    public var pendingRequest: String?
    public var toolName: String?
    public var toolInputJSON: String?
    public var cwd: String?
}
public struct ClaudeResponder: Sendable {
    public init(runner: TmuxRunner, frontTTY: @escaping @Sendable () -> String?,
                activateTerminal: @escaping @Sendable (String?) -> Void)
    public func handle(_ req: ClaudeActionRequest, target: ClaudeTarget?) -> ClaudeAck
    public func promptVisible(pane: String) -> Bool   // capture + parse, false on any error
}
```

  Behaviour required:
  - `ClaudeActionRequest.parse` needs:
    - a JSON object with a known `action`
    - a non-empty `session` of at most 64 bytes
    - a string `request`, non-empty for approve/always/deny

    Anything else gives nil, and the app then sends no ack.
  - `PermissionPromptMatcher.parse(screen)`:
    1. Split into lines and keep the last 40. Normalise each line: delete U+2500–U+257F (box drawing), then trim whitespace.
    2. An option line matches `^(?:[❯>›]\s*)?([1-9])\.\s+(.+)$`. Scan up from the bottom for the last option line with digit `n` (2...5), then collect `n-1` … `1` upwards. At most 2 non-option lines may sit between consecutive options. Anything else gives nil.
    3. The last option line must be within the last 15 lines. No line below it may match the input prompt `^[>❯](\s.*)?$` without a digit.
    4. `yes` is the option whose label is exactly `Yes`. `no` is the first label starting with `No`. `always` is the first label starting with `Yes, `. A missing `yes` or `no` gives nil.
    5. `regionLines` holds the normalised lines from 30 above the first option up to just above it.
  - `matches`:
    - With non-empty `titles`, at least one title is a substring of some region line.
    - `needle` is a substring of the region lines joined with every whitespace character removed.
  - `PromptHints.from`:
    - Bash: titles `["Bash command"]`. The needle is the first 32 characters of the command's first line with whitespace removed.
    - Edit, MultiEdit, Write: titles `["Edit file", "Create file", "Overwrite file", "Write file"]`. Read: `["Read file"]`. NotebookEdit: `[]`. For all of them the needle is the whitespace-free last path component of `file_path` (or `notebook_path`), first 32 characters.
    - WebFetch: titles `[]`, the needle is the URL host.
    - Any other tool: titles `[]`, the needle is `ClaudeText.toolLabel(toolName)` with whitespace removed.
    - An empty needle or undecodable input gives nil.
  - `TmuxFocus.chooseClient`:
    1. Among clients already on `paneSession`, the highest `activity`.
    2. Otherwise the client whose `tty == frontTTY`.
    3. Otherwise the highest `activity`.
    4. nil when the list is empty.
  - `ClaudeResponder.handle`, in this order. Every refusal is `ok: false` with the reason given, and sends no keys.
    1. `target == nil` → `unknown_session`. `target.pane == nil` → `no_pane`. For approve, always and deny, `pendingRequest != req.request` → `stale`. All three checks run before any tmux call.
    2. `display-message -p -t <pane> "#{pane_current_command}\t#{session_name}"` (a real tab). If it throws → `tmux`.
    3. Approve, always, deny:
       - If the pane command does not match `^[0-9]+\.[0-9]+\.[0-9]+$` and is not `claude` → `not_claude`.
       - If `PromptHints.from` gives nil → `unverifiable`.
       - Run `capture-pane -p -t <pane>`. If it throws → `tmux`. If `parse` gives nil → `no_prompt`. If `matches` is false → `mismatch`.
       - The key is `yes`, `always` or `no`. A missing `always` → `no_always`.
       - Run `send-keys -t <pane> -l <digit>`. If it throws → `tmux`. Otherwise ok.
    4. Interrupt:
       - The pane must run Claude Code (`not_claude`).
       - The capture's last 12 non-empty lines must contain `esc to interrupt` (case-insensitive), and `parse` must give nil. Otherwise → `not_working`.
       - Then run `send-keys -t <pane> Escape`.
    5. Focus:
       - Run `list-clients -F "#{client_tty}\t#{client_session}\t#{client_activity}"` and choose a client (none → `no_client`).
       - If the client's session differs from the pane's, run `switch-client -c <tty> -t <pane>`.
       - Then run `select-window -t <pane>` and `select-pane -t <pane>`, then `activateTerminal(tty)`. Ok.
  - `ProcessTmuxRunner`:
    - Runs the first existing candidate (or `path`) with the args, and no shell.
    - Collects stdout. A non-zero exit throws `.failed(status, stderr)`.
    - Kills the process and throws `.timeout` after `timeout`.

- [ ] **Step 1: Write the failing tests**

  - `PermissionPromptMatcherTests`, using F1–F10 from the Protocol section:
    - `readsBashPrompt` (F1): yes `1`, always `2`, no `3`. With hints from HK1's input, `matches` is true.
    - `promptWithoutAlwaysRow` (F2): `always == nil`, no `2`.
    - `readsEditPrompt` (F3): with hints for `Edit` with `file_path` `/tmp/work/T-Display-S3-Long/src/main.cpp`, `matches` is true. Always is `2`.
    - `refusesCutPrompt` (F4): nil.
    - `refusesIdleScreen` (F5): nil.
    - `refusesOtherCommand` (F6): parse succeeds, but `matches` with HK1's hints is false.
    - `handlesWrappedCommand` (F7): Bash hints for the full commit command match.
    - `readsNoFirstVariant` (F8): no `1`, yes `2`, always nil.
    - `stripsBoxBorders` (F9): it matches HK1's hints, and always is `2`.
    - `ignoresStaleOptionsHigherUp` (F10): nil.
    - `hintsPerTool`:
      - Bash gives the needle `piorun-entp_clock` and titles `["Bash command"]`.
      - Edit gives the needle `main.cpp`.
      - Bash with `"command":""` gives nil.
      - `mcp__x__do it` gives the needle `doit`.
  - `ClaudeResponderTests`, with `final class FakeTmux: TmuxRunner, @unchecked Sendable`:
    - The fake records every args array and returns scripted output keyed by `args[0]`.
    - The default `display-message` output is `"2.1.331\tT-Display-S3-Long"`.
    - The target is pane `%37`, pending `a3f9-1`, with HK1's tool.

    The tests:
    - `actionParseA1A2` and `actionParseRejects`: unknown action, missing session, approve with `""` request, non-JSON.
    - `ackBodiesMatchK1K2`.
    - `approveSendsYesKey` (F1): the calls are `display-message …`, `capture-pane -p -t %37`, `send-keys -t %37 -l 1`, and the ack is ok.
    - `alwaysSendsAlwaysKey` → `2`. `denySendsNoKey` → `3`. `noFirstVariantDenySendsOne` (F8 with curl hints) → `1`.
    - `alwaysWithoutRowRefused` (F2): `no_always`, and no `send-keys`.
    - `staleRequestRefusedWithoutCapture`: request `a3f9-0` gives `stale`, and the fake recorded no tmux call at all.
    - `notClaudePaneRefused`: a `display-message` output of `zsh\tx` gives `not_claude`.
    - `noPaneRefused`, `unknownSessionRefused`.
    - `mismatchRefused` (F6), `noPromptRefused` (F5), `cutPromptRefused` (F4).
    - `tmuxFailureRefused`: `capture-pane` throws, giving `tmux`.
    - `interruptNeedsWorkingScreen`:
      - A capture whose last line is `✻ Building… (12s · esc to interrupt)` sends `send-keys -t %37 Escape`.
      - F5 gives `not_working`, and so does F1, because a prompt is open.
    - `focusSwitchesChosenClient`:
      - `list-clients` returns `/dev/ttys028\tcaltera\t100`, `/dev/ttys011\thome\t300` and `/dev/ttys031\tq-calling\t200`, and `frontTTY` returns `/dev/ttys011`.
      - The calls are `switch-client -c /dev/ttys011 -t %37`, `select-window -t %37` and `select-pane -t %37`, and `activateTerminal("/dev/ttys011")` ran once.
    - `focusSkipsSwitchWhenClientOnSession`: a client on `T-Display-S3-Long` means no `switch-client` call.
    - `chooseClientRules`: the three rules and the empty list.
    - `neverSendsKeysWithoutMatchingCapture`: for each of F2–F10 with HK1's hints and action approve, `send-keys` is called for exactly F2 and F9, and for no other fixture.
    - `promptVisibleUsesParse`: F1 gives true. F5 and a throwing capture give false.
  - `TmuxRunnerTests`:
    - `ProcessTmuxRunner(path: "/bin/echo").run(["a", "b"]) == "a b\n"`.
    - `/bin/sleep` with `["5"]` and timeout 0.5 throws `.timeout` within 2 s.
    - `/usr/bin/false` throws `.failed(1, _)`.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter "PermissionPromptMatcher|ClaudeResponder|TmuxRunner"`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

  `ClaudeResponder` may use `ClaudeText.toolLabel` from Task 4.

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass. No test spawned `tmux`, which you can confirm by searching the test sources for `ProcessTmuxRunner(` with no `path:`.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): answer claude prompts through tmux after verifying the pane`

### Task 7: Board link carries Claude frames and actions

**Files:**
- Modify: `examples/ntp_clock/deck_net.h`, `examples/ntp_clock/deck_net.cpp`

**Interfaces:**
- Consumes: Task 1 (`deck_claude.h`).
- Produces in `deck_net.h` (which now includes `deck_claude.h`):

```cpp
uint32_t deck_net_claude_version();                     // bumps on claude, claude_ack and link loss
bool     deck_net_claude(DeckClaude *out);               // false while offline or before the first frame
bool     deck_net_take_claude_ack(DeckClaudeAck *out);   // one-shot
void     deck_net_claude_action(const char *session, const char *request, uint8_t action);  // dropped when not ready
```

  Behaviour required:
  - `on_message` handles `claude`:
    - Parse into a static `DeckClaude` (not on the `net_task` stack) with `deck_claude_parse`.
    - On success, take the lock, store the snapshot, mark it valid and bump the Claude version.
    - On failure, log `[deck] claude ignored` and keep the socket.
    - When the prompt's request changes (`!deck_claude_prompt_same`), log `[deck] claude prompt <request>`, or `[deck] claude prompt cleared`.
  - `claude_ack`: on `deck_claude_ack_parse` success, store it as the waiting ack, overwriting an untaken one, and bump the version. Log `[deck] claude ack <request> ok` or `[deck] claude ack <request> <reason>`.
  - When `deck_net_loop` sees no Ready client after having one, it also clears the Claude snapshot validity and the waiting ack, and bumps the Claude version.
  - `OutMsg` gains `kind == 3` (claude_action) with `char session[DECK_CLAUDE_ID_MAX]`, `char request[DECK_CLAUDE_REQ_MAX]` and `uint8_t action`. `drain_queue` builds the body with `deck_claude_action_body` into a 160-byte buffer and sends it as type `claude_action`. A false return is dropped and logged.
  - Everything from M1 and M2 stays as it is.

- [ ] **Step 1: Implement the changes above**

- [ ] **Step 2: Build and run the native tests**

  Run: `pio run -e ntp_clock`. Expected: SUCCESS, and the app stays under the app partition size.
  Run: `pio test -e native_deck`. Expected: all five suites PASS.

- [ ] **Step 3: Commit**

  Message: `feat(longdeck): carry claude state and actions over the deck link`

### Task 8: Board `claude_sessions` and `claude_usage` widgets

**Files:**
- Create: `examples/ntp_clock/ui_deck_claude.cpp`
- Modify: `examples/ntp_clock/ui_page_deck.cpp`, `examples/ntp_clock/ui_internal.h`

**Interfaces:**
- Consumes: Task 1 (`deck_claude.h`, `DW_CLAUDE_*`) and Task 7 (`deck_net_claude*`).
- Produces in `ui_internal.h`:

```cpp
void ui_claude_reset();                                       // before deck tiles are cleaned
bool ui_claude_create(lv_obj_t *tile, const DeckWidget *w);   // false for non-claude types
void ui_claude_update(const UiTick *t, bool ready);           // every UI tick
void ui_claude_overlay_update(const UiTick *t);               // ui_claude_overlay.cpp, Task 9
```

  Hooks in `ui_page_deck.cpp`:
  - `deck_rebuild` calls `ui_claude_reset()` next to `ui_live_reset()`.
  - `key_create` starts with `if (ui_live_create(tile, w) || ui_claude_create(tile, w)) return;`.
  - `page_deck_update` calls `ui_claude_update(t, ready)` right after `ui_live_update`.

  Behaviour required. Both widgets:
  - The box is built like M2's `box_create`: `COLOR_PANEL`, radius 8, not clickable, `LV_OBJ_FLAG_GESTURE_BUBBLE`. Its opacity is `OFFLINE_OPA` (102) while not ready.
  - At most 16 Claude widgets (`MAX_CLAUDE 16`) live in a static array. Extra ones still get an empty box.
  - Refresh when `deck_net_claude_version()`, `ready` or `t->accent` changes, and on `t->new_minute` for the usage countdown. Copy the snapshot once per refresh into a static `DeckClaude` with `deck_net_claude`. When it returns false, or while `!ready`, show the offline look.

  `claude_sessions` (box `bw x bh`):
  - `rows = (bh - 4) / 40`, so 2 rows at h 1 and 4 rows at h 2. Row `i` is a clickable `lv_obj` at `(4, 2 + 40*i)`, size `(bw - 8) x 40`, transparent. It gets `COLOR_PANEL_HI` in `LV_STATE_PRESSED`, radius 6 and `LV_OBJ_FLAG_GESTURE_BUBBLE`. Its children are not clickable.
  - Each row holds:
    - A 10x10 circle at left-middle `(8, 0)`. Its colour by state: working `t->accent`, permission `COLOR_WARN`, waiting `COLOR_OK`, done `COLOR_TEXT_DIM`.
    - The project in `ui_font_th_16` `COLOR_TEXT` at `x = 26`, `LV_LABEL_LONG_DOT`, with the width that is left.
    - A right label in `ui_font_th_16` `COLOR_TEXT_DIM`, aligned right at -8. It shows `ctx%` (or `--`). From w ≥ 4 it shows `<model>  <ctx>%`. From w ≥ 6 it shows `<model>  <cost>  <ctx>%`, with cost from `deck_claude_format_cost`.
  - When `count > rows`, the last row shows `+<count - rows + 1> more` in `COLOR_TEXT_DIM`, not clickable. `count == 0` shows `No sessions` centred in `COLOR_TEXT_DIM`. Offline hides the rows and shows `--` centred.
  - Row events, only while ready:
    - `LV_EVENT_SHORT_CLICKED` on a session with `tmux` calls `deck_net_claude_action(id, "", DCA_FOCUS)`.
    - `LV_EVENT_LONG_PRESSED` on a `working` session with `tmux` calls `deck_net_claude_action(id, "", DCA_INTERRUPT)`.
    - A row for a `tmux == false` session ignores both.

  `claude_usage`:
  - Two sections, `5h` (five_hour) and `7d` (seven_day), each `bh / 2` high. In each section:
    - The name in `ui_font_th_16` `COLOR_TEXT_DIM` sits top-left at (6, 2).
    - The percentage in `ui_font_th_16` `COLOR_TEXT` sits top-right at (-6, 2): `42%`, or `--`.
    - When `w ≥ 2`, the reset countdown in `ui_font_th_16` `COLOR_TEXT_DIM` sits top-middle. It is `deck_claude_format_reset(resets_at, now)` with `now = t->time_valid ? (uint32_t)time(NULL) : 0`.
    - An `lv_bar` 0..100, 8 px high, `bw - 12` wide, sits at the section bottom (-4). Its background is `COLOR_PANEL_HI`. The indicator is `t->accent`, `COLOR_WARN` from 80 %, and `COLOR_ERR` from 95 %.
  - An unknown window or offline shows `--`, no countdown and bar 0.

- [ ] **Step 1: Implement the files above**

- [ ] **Step 2: Build and run the native tests**

  Run: `pio run -e ntp_clock`. Expected: SUCCESS. Note RAM and flash use in the commit body.
  Run: `pio test -e native_deck`. Expected: PASS.

- [ ] **Step 3: Commit**

  Message: `feat(longdeck): render claude sessions and usage widgets`

### Task 9: Board permission overlay

**Files:**
- Create: `examples/ntp_clock/ui_claude_overlay.cpp`
- Modify: `examples/ntp_clock/ui.cpp`. In `tick_cb`, call `ui_claude_overlay_update(&t);` right after `page_deck_update(&t);` and before `ui_pair_update(&t);`. Nothing else changes in this file.

**Interfaces:**
- Consumes: Task 1, Task 7 (`deck_net_claude`, `deck_net_take_claude_ack`, `deck_net_claude_action`, `deck_net_ready`), and the Task 8 declaration of `ui_claude_overlay_update`.

  Behaviour required:
  - State: a static `DeckClaude` copy refreshed when `deck_net_claude_version()` changes, plus:
    - `shown` (the `DeckClaudePrompt` on screen)
    - `hidden_for` (a prompt the user hid with ✕)
    - `armed_at` (an `lv_tick_get()` value)
    - `sent_at` (0 when not sending)
  - Show when the copy is valid, `prompt.present` is true, and the prompt is not `hidden_for`. Hide otherwise, which includes offline, since the snapshot is cleared on link loss.
  - Layout: create once, then show and hide with `LV_OBJ_FLAG_HIDDEN`.
    - The root is a `lv_layer_top()` child, 640x180, `COLOR_BG` covering, **clickable**, so touches never reach the tileview below.
    - Top row at y 6, a flex row:
      - `LV_SYMBOL_WARNING` in `ui_font_th_22` `COLOR_WARN`
      - the project in `ui_font_th_22` `COLOR_TEXT`, `LONG_DOT`, at most 300 px
      - the tool in `ui_font_th_22` `t->accent`
    - At the top right, `+<pending-1>` in `ui_font_th_16` `COLOR_TEXT_DIM` when `pending > 1`, then a ✕ button (`LV_SYMBOL_CLOSE`, `ui_font_th_22`, 44x36, `lv_obj_set_ext_click_area` 10).
    - The summary in `ui_font_th_22` `COLOR_TEXT`, single line, `LV_LABEL_LONG_DOT`, 624 px wide, at (8, 48).
    - Four buttons at y 94, each 150x80, x = 8, 166, 324 and 482, radius 10, labels in `ui_font_th_22`:

      | Button | Background | Text |
      | --- | --- | --- |
      | `Approve` | `COLOR_OK` | `COLOR_BG` |
      | `Always` | `COLOR_PANEL_HI` | `COLOR_OK` |
      | `Deny` | `COLOR_ERR` | `COLOR_BG` |
      | `Open` | `COLOR_PANEL_HI` | `COLOR_TEXT` |

      `LV_STATE_DISABLED` sets the opacity to 40 %.
    - When `prompt.tmux` is false, the four buttons are hidden, and a centred `Answer at the keyboard` in `ui_font_th_22` `COLOR_TEXT_DIM` shows at y 110.
  - A new prompt (`!deck_claude_prompt_same(&shown, &prompt)`):
    - Update the texts and set `armed_at = lv_tick_get()`. Enable the buttons and clear `sent_at`.
    - Call `lv_obj_move_foreground(root)` once and `ui_flash_screen(COLOR_WARN)`.
    - A re-show of the same prompt neither flashes nor moves to the foreground.
  - Button clicks (`LV_EVENT_SHORT_CLICKED`) are ignored while `lv_tick_elaps(armed_at) < 600` or `!deck_net_ready()`.
    - Approve, Always and Deny send `deck_net_claude_action(prompt.session, prompt.request, DCA_APPROVE | DCA_ALWAYS | DCA_DENY)`, disable those three buttons, and set `sent_at`.
    - Open sends `DCA_FOCUS` with request `""` and stays enabled.
    - ✕ sets `hidden_for = shown` and hides the overlay.
  - Every tick:
    - If `sent_at` is set and 4000 ms have passed, re-enable the buttons.
    - Take an ack with `deck_net_take_claude_ack`. On `ok == false`, call `ui_toast("Answer at the keyboard")`, and if the ack's request equals the shown request, re-enable the buttons. This runs even while the overlay is hidden, so focus and interrupt refusals from the sessions widget also toast.
  - Do not call `lv_obj_move_foreground` every tick. The pairing overlay (`ui_pair_update`) runs later and stays on top. Toasts and flashes are created later, so they draw above this overlay.

- [ ] **Step 1: Implement the files above**

- [ ] **Step 2: Build and run the native tests**

  Run: `pio run -e ntp_clock`. Expected: SUCCESS. Note RAM and flash use in the commit body.
  Run: `pio test -e native_deck`. Expected: PASS.

- [ ] **Step 3: Commit**

  Message: `feat(longdeck): show claude permission prompts on every page`

### Task 10: Mac app wiring

**Files:**
- Create: `mac/LongDeck/Sources/LongDeckApp/ClaudeController.swift`
- Modify: `mac/LongDeck/Sources/LongDeckApp/DeckConnection.swift`, `AppModel.swift`, `MenuView.swift`, `LongDeckApp.swift` (only to pass `model.claude` into `MenuView`)
- Modify: `mac/LongDeck/Resources/Info.plist`. Add `NSAppleEventsUsageDescription` = `LongDeck brings the iTerm2 window of a Claude Code session to the front.`

**Interfaces:**
- Consumes: Tasks 2–6.
- Produces:
  - `DeckConnection`:
    - The init gains `claudeBody: @escaping () -> String?` and `onClaudeAction: @escaping (String) -> Void`.
    - `func sendClaude(_ body: String)` goes through `link.claudeFrame`. `func sendClaudeAck(_ body: String)` goes through `link.ackFrame`. Both use the M2 `sendFrame`.
    - On `.ready`, after `sendVolume`, call `sendClaude(claudeBody())` when it is non-nil.
    - The frame type `claude_action` forwards the raw body to `onClaudeAction`.
  - `@MainActor final class ClaudeController: ObservableObject`:
    - `@Published private(set) var installed: Bool` and `@Published private(set) var statusText: String`.
    - `var onBody: ((String) -> Void)?` and `var currentBody: String`.
    - `func start()`, `func install()`, `func uninstall()`, and `func handleAction(_ body: String, reply: @escaping (String) -> Void)`.
  - `AppModel` owns `let claude = ClaudeController()`. In `start()` it sets `claude.onBody = { [weak self] in self?.connection?.sendClaude($0) }`, then calls `claude.start()`. It passes `{ [weak self] in self?.claude.currentBody }` and an action closure that calls `claude.handleAction(body) { [weak self] ack in self?.connection?.sendClaudeAck(ack) }` into every `DeckConnection`.
  - `MenuView` adds a `Claude` section after the existing items:
    - A `Text(model.claude.statusText)`.
    - `Install Claude Code integration…` when `!installed`, or `Uninstall Claude Code integration…` when installed.

    `MenuView` takes `@ObservedObject var claude: ClaudeController` as a second property, and `LongDeckApp` passes `model.claude`.

  Behaviour required:
  - Paths. `ClaudeInstallPaths(settings: home/.claude/settings.json, supportDir: ~/Library/Application Support/LongDeck)` is built **only** inside `install()`, `uninstall()` and `start()` (where `start()` only calls `loadState`).
  - `start()`:
    - If `ClaudeInstaller.loadState` returns a state, start `ClaudeListener(port: 47821, token: state.token)`. A start failure sets `statusText` to `Claude: listener failed (port 47821 busy?)`.
    - Start one 1 s `Timer` on `RunLoop.main` in `.common` mode.
  - `install()`:
    - Show an `NSAlert`: "LongDeck will add HTTP hooks to ~/.claude/settings.json next to your existing hooks, and run your status line (`<current command>`) through a small wrapper. A backup is saved next to the file. Restart running Claude Code sessions afterwards." Buttons: `Install`, `Cancel`.
    - On Install, generate the token with `SecRandomCopyBytes` (32 bytes, lowercase hex), call `ClaudeInstaller.install(paths, token:, now: Date())`, and start the listener.
    - Errors show in an `NSAlert` with the error text.
  - `uninstall()`: confirm with an `NSAlert`, stop the listener, call `ClaudeInstaller.uninstall`, reset the store, and publish.
  - Inbound events: `.hook` goes through `ClaudeHookEvent.decode` and `store.apply(_, pane:, now: Date())`. `.statusLine` goes through `ClaudeStatusUpdate.decode`. Undecodable bodies are dropped. Then publish.
  - Publish: `currentBody = store.body(now: Date())`, and call `onBody` only when the body differs from the last one published.
  - Timer tick:
    - `store.expire(now:)`.
    - For each `store.pendingPrompts()` entry with a pane, at most one in flight per request, run `responder.promptVisible(pane:)` in `Task.detached`. Back on the main actor, call `store.promptCheck(session:, request:, visible:, now:)`.
    - Publish.
  - `handleAction(body, reply)`:
    - `ClaudeActionRequest.parse`; nil means log and return without a reply.
    - Build `ClaudeTarget` from `store.sessions[req.session]`: pane, `pending?.request`, `pending?.toolName`, `pending?.toolInputJSON`, `cwd`.
    - Run `responder.handle` in `Task.detached`. Back on the main actor, when `ack.ok`: approve and always call `store.resolve(…, state: .working)`, and deny calls `store.resolve(…, state: .waiting)`. Publish, then `reply(ack.body)`.
  - `responder = ClaudeResponder(runner: ProcessTmuxRunner(), frontTTY:, activateTerminal:)`:
    - `frontTTY` runs `/usr/bin/osascript -e 'tell application "iTerm2" to get tty of current session of current window'` with a 2 s timeout, and returns nil on any failure.
    - `activateTerminal(tty)` runs `osascript` with a script that loops `windows` / `tabs` / `sessions` of iTerm2, `select`s the window, tab and session whose `tty` equals the given one, then `activate`s. On failure it falls back to `NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first?.activate()`.
  - `statusText`: `Claude: not installed`, `Claude: N sessions`, or the listener error.

- [ ] **Step 1: Implement the changes above**

- [ ] **Step 2: Build and test**

  Run: `cd mac/LongDeck && swift build`. Expected: SUCCESS with no new warnings in the edited files.
  Run: `$SWIFT_TEST`. Expected: all pass.
  Do not run `bundle.sh`, open the app, or click the menu items.

- [ ] **Step 3: Commit**

  Message: `feat(longdeck): wire the claude listener, store and answers into the app`

### Task 11: Docs

**Files:**
- Modify: `examples/ntp_clock/README.md`. In the LongDeck section, add `### Claude Code`, written in Thai like the rest of the file, with technical terms in English. Cover:
  - the two widgets and what each colour means
  - the overlay on every page, its buttons, ✕, and the toast "Answer at the keyboard"
  - tap a row to focus, long-press to interrupt
  - `--` while the Mac is offline
- Modify: `mac/LongDeck/README.md`. Add `## Claude Code integration` covering:
  - what Install changes: 8 http hooks, the statusLine wrapper, the backup name, the state file
  - that Uninstall restores the file
  - port 47821 on loopback, and the token
  - restarting running sessions after install
  - the tmux requirement (`TMUX_PANE`), and that sessions outside tmux are read-only
  - when the app refuses an answer
  - the iTerm2 Automation prompt
  - the `claude_sessions` and `claude_usage` config entries, for example `{"id":"ccs","type":"claude_sessions","col":0,"row":0,"w":4,"h":2}`

- [ ] **Step 1: Write the sections above.** Keep each to two short paragraphs plus the example.

- [ ] **Step 2: Commit**

  Message: `docs(longdeck): document the claude code integration`

## Hardware and live checklist (owner, after all tasks)

Agents do not run this. The board must be on USB (find the port by serial `74:4D:BD:88:D5:C0`) and powered as in M1. Use a **scratch** tmux window and a throwaway directory for every prompt test, never a pane with real work.

- [ ] **H1 Flash.** `pio run -e ntp_clock -t upload`. The clock pages look and behave as before: Thai text, swipe, night mode, Wi-Fi portal, web settings.
- [ ] **H2 Config.** Move the config aside so the app writes the new sample (`mv ~/Library/Application\ Support/LongDeck/config.json{,.m2}`), or add the two widgets by hand. Build with `LONGDECK_SIGN_ID="LongDeck Dev" ./scripts/bundle.sh` and open the app. The board gets a `Claude` page with `--` widgets until install.
- [ ] **L1 Install.**
  - Run `cp ~/.claude/settings.json /tmp/settings.before.json`, then choose "Install Claude Code integration…".
  - `diff <(jq -S . /tmp/settings.before.json) <(jq -S . ~/.claude/settings.json)` shows only the 8 added http groups and the new `statusLine.command`.
  - `ccstatusline` output looks the same in a new Claude Code session.
  - iTerm2's `cc-status` badges still update.
- [ ] **L2 Prompt capture (the spec's spike).**
  - In the scratch window, start `claude` in an empty temp dir and ask it to run `echo longdeck-test`.
  - While the prompt shows, run `tmux capture-pane -p -t <pane> > /tmp/ld-bash.txt` from another pane. Repeat for an Edit prompt (`/tmp/ld-edit.txt`).
  - Compare with F1 and F3. Check: option rows `❯ 1. Yes`, the `Bash command` and `Edit file` titles, and the command text visible above the options.
  - If anything differs, update the fixtures and the matcher first (Task 6) and re-run `$SWIFT_TEST`.
- [ ] **L3 Approve from the board.**
  - Trigger the same prompt. The overlay appears within 1 s on whatever page is showing, the clock page included, and the screen flashes.
  - Approve: the command runs, no Enter is needed, and the overlay closes within 2 s.
  - Repeat with Deny: Claude stops, and the session row shows waiting.
  - Repeat with Always: the "don't ask again" rule is saved.
- [ ] **L4 Narrow window.** Shrink the scratch pane until Claude Code says "This terminal is too short". Approve on the board shows the toast "Answer at the keyboard", and nothing is typed.
- [ ] **L5 Keyboard answer closes the overlay.** Answer a prompt at the keyboard, once Yes and once No. The overlay closes within about 2 s each time.
- [ ] **L6 Stale press.** Answer at the keyboard, then press Approve on the board within a second. The toast shows, and nothing is typed into the pane.
- [ ] **L7 Interrupt.**
  - Long-press the row of a working scratch session: Claude stops (Esc), and with `escape-time 10` nothing else is typed.
  - Long-press an idle row: the toast shows, and nothing is typed.
- [ ] **L8 Focus.** With several iTerm2 windows attached to the tmux server, tap a session row or Open. The right window comes to the front, showing the right tmux session, window and pane. Allow the Automation prompt the first time.
- [ ] **L9 App not running.** Quit LongDeck, start a Claude Code session, and use tools. No hook error lines and no visible delay. The statusLine looks as usual. Relaunch the app: sessions appear within 10 s.
- [ ] **L10 Usage.** The `claude_usage` widget shows 5h and 7d percentages close to ccstatusline's, and the countdown drops by one each minute.
- [ ] **L11 Uninstall.**
  - Choose "Uninstall Claude Code integration…".
  - `cmp /tmp/settings.before.json ~/.claude/settings.json` is identical when nothing else changed the file in between. `~/Library/Application Support/LongDeck/statusline.sh` and `claude-install.json` are gone, and both backups exist next to `settings.json`.
- [ ] **L12 Offline.** Quit the app while a prompt is open. Within 15 s the overlay closes, and both Claude widgets show `--`.
- [ ] **L13 Many sessions.** With about 18 tmux sessions running Claude Code, the 4x2 sessions widget shows 3 rows plus `+N more`, with permission and waiting sessions first.

## Execution order

- **Firmware lane:** Task 1 → Task 7 → Task 8 → Task 9, one after another. Each needs the previous task's symbols, and all of them share the PlatformIO build directory.
- **Mac lane:** Task 2 → Task 3 → Task 4 → Task 5 → Task 6 → Task 10, one after another. All of them build the same `LongDeckCore` target, so a half-written file in one breaks `swift test` for the others, and SwiftPM locks `.build`. Task 2 touches one line of `DeckConnection.swift`, and Task 10 owns the rest of it later in this lane.
- The two lanes run in parallel. They share no files and use different toolchains.
- Then Task 11.
- Then the owner runs the Hardware and live checklist, starting with L2.

Notes:
- No two concurrently running tasks share a file. `platformio.ini` belongs to Task 1 only, `ui_internal.h` to Task 8 only, and `ui.cpp` to Task 9 only.
- Tasks 3, 4, 5 and 6 are independent in content, apart from Task 6 using `ClaudeText.toolLabel`. They run in sequence only because they share the `LongDeckCore` target. With `isolation: worktree` they could run in parallel and merge in the listed order.

## Decisions made while planning

- **Port 47821**, loopback only. The token is 32 random bytes in hex, written literally into the hooks and the wrapper.
- **`PostToolUse` is installed too.** The spec's install list leaves it out, but its state model needs it.
- **Action name `always`**, not the spec's `approve_always`, as instructed.
- **A third frame type, `claude_ack`.** The app needs a way to tell the board "answer at the keyboard". The board shows one fixed toast and logs the reason code.
- **`Notification(permission_prompt)` without a `PermissionRequest`** only turns the row amber. No overlay shows, because there would be nothing the app could verify.
- **Keyboard answers are detected** by a 1 Hz read-only `capture-pane` poll of panes with a pending prompt (two misses), plus `PostToolUse`, `UserPromptSubmit`, `Stop` and `idle_prompt`.
- **Approve/Always/Deny also need `pane_current_command`** to look like a Claude Code version, so digits never go into a plain shell.
- **Interrupt** needs `esc to interrupt` on screen. It lives on a long-press of a session row.
- **Settings are edited through an order-preserving JSON model** (`OrderedJSON`). The output matches Claude Code's own 2-space format, so the user's key order survives and uninstall can restore the file byte for byte.
- **If there is no statusLine,** install adds one with the wrapper alone, and uninstall removes it.
- **The overlay has a ✕** that hides it until the next prompt, as a safety valve if prompt-gone detection ever fails. It also ignores taps for 600 ms after it appears.
- **`claude_sessions` needs at least 2 columns.** `claude_usage` works at 1x1 without the countdown.
- **The sample config gains a third page, `Claude`.** The `Dev` page stays unchanged, so the M1 and M2 tests keep their meaning.

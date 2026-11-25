# LongDeck Claude agents page — Design

Date: 2026-11-25 · Branch: `claude-agents` (from `T-Display-S3-Long-cst3530` at `0eef291`)
Builds on: `docs/superpowers/specs/2026-11-24-clock-deck-design.md` (LongDeck M1–M4).

## Intent

The owner runs many Claude Code sessions at once (about 18 named tmux sessions). They want a board
page that shows every session at a glance: one animated pixel character per session, like a row of
pets. The page answers three questions: which sessions are working, which are waiting for the
owner, and how many agents are running right now (main sessions plus their subagents). The owner
showed a reference photo: a grid of dark tiles, each with a small grey pixel creature wearing a
per-project hat, orange when busy, sleeping "zz" when done, a striped "hungry · feed me" tile when
waiting, and the session name with a status line under it.

Success: the page sits on the board next to the keyboard. A glance tells the owner which session
needs them and how much is running. Tapping a tile jumps to that session's tmux pane. The
characters are drawn in Aseprite and can be redrawn later without reflashing.

## Decisions taken with the owner

| Topic | Decision |
| --- | --- |
| Layout | Tiles in a 4x2 grid on a full 640x180 page (8 visible). More sessions scroll **vertically**; horizontal swipe still changes pages. |
| Agent count | Each tile shows a badge with the number of subagents running in that session. A page total shows how many agents are working in all. |
| Total placement | A pill with the total number sits at the top of a thin scrollbar on the right edge. No header bar; tiles keep the full height. |
| Which sessions | Live sessions plus recently finished ones ("done · 3d ago"), going back 7 days. |
| Character | A Claude-style orange pixel critter. Busy = orange and moving; waiting = orange with "feed me"; done = grey and asleep with "zz". Each project gets its own hat design and hat colour. |
| Tile name | The tmux session name. If the session is not in tmux, the project folder name. |
| Art tool | Sprites are drawn in Aseprite through the `aseprite-ai-artist` MCP (installed 2026-11-25, pinned `@0.8.4`, local scope). |

## My calls (the owner can overrule)

- Tap a live tile → focus its tmux pane. Long-press a working tile → interrupt. These match the
  existing `claude_sessions` widget. History tiles ignore taps. The permission overlay is unchanged.
- `claude_agents` is a new widget kind placed in the editor like any other. It is at least 2x1
  cells (one tile, 160x90). A full 8x2 page shows 4x2 tiles. The old `claude_sessions` widget stays.
- Sprites are sent from the Mac and cached on the board. Redrawing the art in Aseprite updates the
  board on the next layout push, with no reflash.
- Subagents are counted from the `SubagentStart` and `SubagentStop` hooks. The installer adds both,
  so the owner must press Install again once.
- The Mac keeps a session history file so "done · 3d ago" survives an app restart.
- Total = sessions in the working state + running subagents in all sessions.

## Goals

1. A `claude_agents` widget that shows one tile per session: sprite, name, status line, agent badge.
2. Four animated states with distinct looks: working, permission, waiting, done.
3. A per-project hat (design + colour) that stays the same for the same name every day.
4. Vertical scrolling with the total pill on the scrollbar.
5. Sprites authored in Aseprite, stored in the repo, and replaceable by the owner.

## Non-goals

- No new Claude actions. Approve, Deny and Always stay on the permission overlay.
- No per-subagent tiles. Subagents show only as a count.
- No sound, no notifications on the Mac.
- No editing of hats or names on the board. The board is a display.

## Anti-goals (a failure even if it works)

- The page must never hide a session that needs the owner. Permission and waiting tiles sort first,
  always.
- Animation must not make the board stutter, starve the heartbeat, or slow the clock pages.
- The page must not show stale "working" forever. A session or subagent that stops reporting
  falls back to a calm state.
- No art copied from the reference photo. The critter and hats are original drawings in the
  Claude-mascot spirit.

## Constraints

- Board: ESP32-S3, 640x180, LVGL 8.4 with 16-bit colour (`LV_COLOR_16_SWAP=1`), PSRAM available, the
  LittleFS `spiffs` partition at about 13.4 MB.
- Images on the board are `LV_IMG_CF_TRUE_COLOR_ALPHA` (RGB565 big-endian + A8, 3 bytes per pixel),
  delivered as face chunks of at most 12288 bytes including the 10-byte header.
- WebSocket text frames are at most 15360 bytes (`LayoutPushPolicy.maxWebSocketFrame`).
- The page root is an LVGL tileview that scrolls left/right. The widget may scroll only vertically.
- Mac: Swift package `mac/LongDeck`, CommandLineTools toolchain, no SwiftUI macros, LongDeckCore in
  Swift 6 strict concurrency. The hard rules of the M4 plan apply (no window on screen from tests,
  never touch the real config or `~/.claude`).
- Comments: English, one line, about 10 words.

## Approaches considered

| Approach | Trade-off | Verdict |
| --- | --- | --- |
| A. Mac renders sprite frames from the Aseprite export and sends them as cached images. The board animates them and lays the hat on top, tinted per project. | New sprite references in the layout. Art changes need no reflash. Small storage: one body sheet plus a few hat images. | **Chosen** |
| B. Compile the sprites into the firmware as C arrays. | Least protocol work, but every art change needs a reflash, and the Mac cannot preview the real art. | Rejected: the owner wants to redraw freely. |
| C. Mac renders whole tiles (sprite + text) and streams them as frames. | About 1.3 MB/s for 8 tiles at 8 fps. Too heavy for the link and the heartbeat. | Rejected |

## Design

### Session model (Mac, `ClaudeStore`)

Each session gains:

- `name`: tmux session name. Read once per pane with `tmux display-message -p -t <pane> '#S'`, and
  refreshed when tmux renames it. Falls back to the project folder name.
- `tool`: the last `PreToolUse` tool name while working, lower-case (`bash`, `edit`, `agent`).
- `subagents`: ids started by `SubagentStart` and not yet stopped by `SubagentStop`. Cleared on
  `SessionEnd`. An id older than 2 hours with no matching stop is dropped.
- `endedAt`: set when the session ends or goes stale.

History: when a session ends, a record `{name, project, endedAt, hat}` goes into
`~/Library/Application Support/LongDeck/claude-history.json`. There is one record per name, the
newest wins, and records older than 7 days are pruned. A live session hides the history record
with the same name. Two live sessions that share a tmux session name show as `name`, `name·2`.

Sort order: permission → waiting → working → done (newest first). The wire carries at most 24
tiles. The rest are dropped from the end.

Hat: `hat` (design 0–7) and `tint` (colour 0–7) come from a stable hash of `name` (FNV-1a), so the
same name always wears the same hat.

### Wire

The existing `claude` frame keeps every current field. Each `sessions[]` row adds:

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string ≤ 23 bytes | Tile name (tmux session or project) |
| `tool` | string ≤ 15 bytes | Current tool while working, else "" |
| `agents` | int ≥ 0 | Running subagents |
| `since` | int (unix seconds) | When the current state began; for done, when it ended |
| `hat`, `tint` | int 0–7 | Hat design and colour |
| `live` | bool | false for history rows |

The top level adds `agents_total` (int). The board's session cap rises from 8 to 24. Old boards
ignore the new fields. A new board fed by an old Mac shows the project as the name and no badge.
A 24-row frame is about 4 KB, well under 15360 bytes.

### Sprites

Source files in the repo:

- `mac/LongDeck/Resources/sprites/claude-agent.aseprite`: the critter, with tags `working`,
  `permission`, `waiting`, `done`. Each tag has 2–6 frames with their own durations. The done frames
  are grey and include the rising "zz". There is no hat on this layer.
- `mac/LongDeck/Resources/sprites/claude-hats.aseprite`: 8 hat designs drawn in light greys so a
  tint can colour them. Each hat sits on a fixed anchor above the critter's head.
- The exported `*.png` sprite sheets and `*.json` (Aseprite json-array with frame tags and
  durations) are committed next to the sources. The app reads only the exports.

Art size: drawn at native pixel size, at most 20x20 for the critter and 20x10 for a hat. The Mac
scales by a whole number (3x) with nearest-neighbour, so the board never zooms. The tint palette
is 8 colours that read on the dark tile.

Owner override: if `~/Library/Application Support/LongDeck/sprites/` holds the same export file
names, the app uses those instead and watches them for changes.

Transport: each sprite frame and hat image is sent as a face over the existing face channel, in an
id range of its own that cannot collide with key faces. The `claude_agents` widget's layout entry
lists the ids per tag, the per-frame durations, the hat ids, and the hat offset for each frame (so
the hat bobs with the body). The layout hash covers the sprite pixels, so new art triggers a normal
re-push, and the board deletes unused ids as it already does for faces.

### Board widget

- Tiles are about 157x90 (the scrollbar takes about 12 px). Each tile has:
  - a dark panel;
  - the sprite on the left, with the hat image tinted with `img_recolor`;
  - the name (bold white when live, dim when done);
  - the status line;
  - the agent badge (`×3`) when `agents > 0`.
- Status line:

  | State | Status line | Tile style |
  | --- | --- | --- |
  | working | `bash · 98% ctx` | |
  | permission | `permission · Bash` | orange accent |
  | waiting | `hungry · feed me` | orange text, striped panel |
  | done | `done · 3d ago` | |

- The relative time is computed on the board from `since` and the NTP clock, and refreshed each
  minute.
- Busy tiles get the orange corner accent from the reference style. Waiting tiles get diagonal
  stripes.
- Vertical scroll snaps to whole rows. The right edge shows the total pill on top and the scroll
  thumb below it.
- One LVGL timer per widget advances the frames of the visible tiles only, and only while the page is
  shown. Frame swaps change the image source. Nothing is redrawn while the page is hidden.
- When the Mac is offline, the widget shows `--` like the other Claude widgets.
- Tap and long-press behave as in "My calls".

### Editor

`claude_agents` appears in the widget palette. Minimum size 2x1. Its canvas placeholder shows sample
tiles drawn with the real sprite sheets, so the owner sees the actual art. EditorIssues gains the
size rule, and the frame-size check counts the sprite images.

### Hooks

`ClaudeInstaller.hookEvents` adds `SubagentStart` and `SubagentStop`. `ClaudeHookEvent` reads
`agent_id` (and `agent_type` if present). The menu shows "Reinstall to count subagents" when the
installed hooks lack them.

## Testing

- Swift:
  - store rules: subagent counting, stale drop, history merge, prune, name collision suffix, sort
    order, hat hash stability;
  - wire encoding: fields and the 24-row cap;
  - sprite loader: Aseprite JSON tags, durations, the scale and pixel format;
  - editor placeholder snapshot PNG.
- Board native tests: parse of the new session fields and the `claude_agents` layout entry with
  sprite tables; the sprite id range never collides with key faces.
- `ntp_clock` build, RAM and flash within budget.
- Hardware and live checks:
  - all four animations play smoothly;
  - vertical scroll does not steal page swipes;
  - the total pill counts subagents while a real multi-agent session runs;
  - tap focuses the right pane;
  - redrawing a hat in Aseprite reaches the board after a re-export;
  - 24 tiles keep the heartbeat healthy.

## Calls settled after the builder check

1. **Sprite ids:** `DECK_MAX_FACES` rises from 128 to 192. Key faces keep ids 1–128. Sprite frames and
   hats use 129–192. When the widget is created, the board loads its sprite images from LittleFS into
   PSRAM once (about 32 images × 60x60x3 ≈ 350 KB).
2. **Layout size:** the sprite table is compact. Each tag's frames are a contiguous id range
   `{first, count}`, followed by one duration per frame (ms) and one hat y-offset per frame. Hats are
   one contiguous range. That comes to well under 1 KB, so a full layout still fits in 15360 bytes.
   EditorIssues counts it.
3. **24 rows:** `DECK_CLAUDE_MAX_SESSIONS` rises to 24.
   - The old `claude_sessions` widget skips rows with `live:false`, then shows its first rows in
     the new sort order.
   - The permission overlay only ever uses live rows with a pending prompt.
4. **Stale:** the existing rule stays as it is: a session silent for 30 minutes is ended. It then
   becomes a done history row with `endedAt` = its last event. There is no shorter timeout.
5. **Names:** the `name·2` suffix applies only between live sessions. A history record is written
   under the name the session had when it ended. A rename mid-session simply moves the live tile.
6. **Total:** `agents_total` = live sessions in the working state + every running subagent, including
   subagents of a session whose main turn has stopped. The tile keeps the main session's state and
   shows the badge.
7. **Widget sizes:** visible tiles = `floor(w/2)` columns × `h` rows. Vertical scroll applies
   whenever there are more rows than visible tiles. For example, 2x1 shows one tile, 4x1 shows two
   side by side, 2x2 shows two stacked, and 8x2 shows 4x2.

## Left to the builder

- Exact pixel layout of the tile text and badge within the 157x90 tile.
- Hat anchor coordinates and the tint palette values, checked on the board.
- How sprite ids are numbered within their range.
- How the board formats ages: `now`, `5m`, `3h`, `2d`.

## To verify live

- The field names in the `SubagentStart`/`SubagentStop` hook input (expected `agent_id`, `agent_type`).
- Whether background subagents can outlive the main session's `Stop`. The count must stay right.

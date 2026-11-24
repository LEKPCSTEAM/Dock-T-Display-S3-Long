# ThaiClock Deck — Design

Date: 2026-11-24 · Branch: `clock-deck` (from `ntp-clock`)

## Intent

Turn the ThaiClock desk clock (`examples/ntp_clock`, T-Display-S3-Long, 640x180 touch) into a
Stream-Deck-like control surface for the owner's Mac, without losing the clock. The owner is a
developer. Daily use is coding plus watching and answering Claude Code sessions. From the board
they want to: fire hotkeys, open apps, control media and system volume, see how the Mac is doing
(CPU, RAM, GPU, disk, network, temperature), and see/answer Claude Code (session state, usage
limits, context/cost, approve/deny/interrupt).

Success: the board sits next to the keyboard, the custom pages are laid out in a Mac app the
owner designed, a Claude permission prompt can be answered from the board, and the clock pages
behave exactly as today.

## Decisions taken with the owner

| Topic | Decision |
| --- | --- |
| Host | macOS only. Target machine: Mac mini M4 Pro (Mac16,11), macOS 26, no battery. |
| Link | Wi-Fi. The board never acts as USB or BLE HID. A companion Mac app performs every action. |
| Audio | Media keys (play/pause, next, previous) and system volume/mute. No soundboard. |
| Mac stats | CPU, RAM, GPU, disk, network, temperature. Battery is shown only when the Mac has one, so it is hidden on the Mac mini. |
| Layout | Every custom page is designed freely in the Mac app by placing widgets on a grid. |
| Config | A GUI program (the Mac app). No hand-edited files required, no web UI on the board. |
| Firmware home | Inside ThaiClock. The existing pages Clock → Calendar → Focus → System stay as they are. Custom pages are appended after System in the swipe order. |
| Claude | Session state, usage limits (5 h / weekly), context and cost, and Approve / Deny / Interrupt / jump-to-session buttons. |
| Permission prompts | Shown in both places at once. The terminal prompt works as usual. Pressing Approve/Deny on the board types the answer into that session's tmux pane. |
| Deny on the board | Same as "No" at the terminal. Claude stops the turn and waits for keyboard input. The board then shows "waiting for you". |
| Mac app stack | Native SwiftUI app (menu bar + editor window). |

## Goals

1. Custom pages on the board, designed in the Mac app and pushed over Wi-Fi.
2. Actions: open app, open URL, hotkey (modifier combo), media key, volume up/down/mute, type
   text, run shell command, run a macOS Shortcut.
3. Live widgets: Mac stats, volume slider, Claude sessions, Claude usage, small clock.
4. Claude Code integration through hooks and the status line, with answers routed to iTerm2.
5. Pairing so that only the owner's Mac and board talk to each other.

## Non-goals

- Windows or Linux hosts. USB HID or Bluetooth HID.
- Soundboard or audio playback on the board (it has no speaker).
- Now-playing track info (macOS 15.4+ blocks the MediaRemote API for third-party apps).
- Per-app volume. More than one paired Mac per board.
- Editing the four existing ThaiClock pages from the Mac app.

## Anti-goals (a failure even if it "works")

- Any device on the LAN can make the Mac do something without being paired.
- Claude Code becomes slower or breaks when the Mac app is not running. Hooks must fail fast and
  never block a prompt.
- `ccstatusline` output changes, or the existing `~/.config/iterm2/cc-status` hooks stop working.
- A board press approves the wrong permission prompt.
- The clock pages regress: look, Thai text rendering, swipe, night mode, Wi-Fi portal, web settings.

## Constraints

**Hardware and firmware**

- ESP32-S3, 16 MB flash, 8 MB PSRAM. Arduino-ESP32 2.0.17 (`espressif32@6.13.0`), LVGL 8.4 in
  `lib/lvgl` with `lib/lv_conf.h` (16-bit colour with byte swap, no PNG decoder, no LVGL file system,
  QR code enabled).
- The panel is 640x180 px but only about 83x23 mm. Single touch. A finger needs about 10 mm, so the
  custom-page grid is **8 columns x 2 rows** (80x90 px cells, about 10x12 mm). Widgets span whole
  cells.
- Threads today: LVGL runs in `loop()` on core 1. `net_task` on core 0 owns Wi-Fi, the sync
  `WebServer` on port 80, mDNS (`thaiclock.local`, `_http._tcp`), NTP and weather. Data crosses
  threads through mutex-guarded snapshots (`net_get_status`). New code follows the same pattern.
- The dev board has no battery. The PMU (SY6970) is already set to 1500 mA / 3.7 V so Wi-Fi bursts
  do not brown it out. Keep that.
- Partition table today is `huge_app.csv`: 3 MB app plus an 896 KB `spiffs` data partition at
  `0x310000`, unused so far.
- The existing pages come from EEZ Studio (`eez/thaiclock.eez-project`). Custom pages cannot,
  because their content is only known at runtime.
- Thai labels need the repo's tone-stacking fonts (`thai_fonts.c`). Those fonts cover Thai, Latin
  and a FontAwesome subset only.
- Code comments follow the owner's rules: English, one line, about 10 words, only what the code
  cannot say.

**Mac**

- Swift 6.4, Xcode installed, macOS 26, Apple Silicon M4 Pro.
- Every Claude Code session runs **inside tmux**. One tmux server holds about 18 named sessions,
  and plain tmux (not `-CC`) runs in iTerm2. All panes inherit the same stale `ITERM_SESSION_ID`,
  so a Claude session can only be addressed by its `TMUX_PANE` (`%N`). Sessions outside tmux (an
  IDE terminal, say) are shown read-only.
- Audio output is the built-in "Mac mini Speakers", and CoreAudio volume works on it. If the
  default output has no volume control (some HDMI or USB devices), the volume widget shows
  "unavailable".
- There is **no code-signing identity** on the machine. An ad-hoc signed app loses its
  Accessibility permission (needed for CGEvent hotkeys) on every rebuild. The build must use a
  stable identity: a free "Apple Development" certificate via Xcode, or a self-signed code-signing
  certificate in the login keychain.
- Claude Code 2.1.331. Hook type `http` exists. `onFailure: "continue"` needs 2.1.295+ (met).
- The owner already has `statusLine: ccstatusline` (refresh 10 s) and command hooks for
  `Notification`, `PermissionRequest`, `Stop` and others pointing at `~/.config/iterm2/cc-status`.

**Claude Code facts this design relies on** (docs: hooks.md, statusline.md)

- Hook stdin fields include `session_id`, `cwd`, `transcript_path`, `hook_event_name`. Relevant
  events are `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`
  (`tool_name`, `tool_input`), `Notification` (`notification_type`: `permission_prompt` or
  `idle_prompt`, `message`), `Stop`, and `SessionEnd`.
- `http` hooks POST the event JSON. They take `headers` with `$VAR` expansion limited to
  `allowedEnvVars`, plus `timeout` and `onFailure`.
- The statusLine stdin carries `model`, `cost.total_cost_usd`, `context_window.used_percentage`,
  `workspace`, and `rate_limits.five_hour|seven_day.{used_percentage,resets_at}`. `rate_limits` is
  the **only** supported source of plan usage. It appears only for subscription plans and only
  after the session's first API response.
- No hook can interrupt a running turn. Interrupt is therefore done by sending Esc to the session's
  terminal.

## Approaches considered

**Link: USB HID vs Wi-Fi vs BLE HID.** USB HID would make hotkeys and media keys work with no Mac
software, but switching to TinyUSB changes upload and serial behaviour, and stats and Claude would
still need a Mac app. BLE HID has the same need for a Mac app plus pairing friction. The owner chose
**Wi-Fi**: one channel carries everything, the board can sit anywhere, and all actions live in the
Mac app.

**Mac app: SwiftUI vs Python + web page vs Tauri.** Python would iterate fastest, but permissions
attach to the interpreter, packaging is awkward, temperature and GPU readings need ctypes or helper
tools, and the UI is split between the menu bar and a browser. Tauri gives a web editor and a later
Windows path, but every native part (CGEvent, IOKit, iTerm2) would be written in Rust anyway. The
owner chose **SwiftUI native**: every API needed is first-party, it ships as one `.app` with one
Accessibility grant, and the editor feels like a Mac app.

**Firmware home: new example vs inside ThaiClock.** The owner chose **inside ThaiClock**. It reuses
Wi-Fi provisioning, NVS settings, mDNS, the tileview and fonts, and the board stays a clock when the
Mac is off.

**Permission answers: hook decision vs keystrokes.** A `PermissionRequest` hook that returns a
decision is exact, but while it waits the terminal prompt may not be shown. The owner wants **both
places at once**, so the hook only reports, and the board's answer is typed into the session's tmux
pane with `tmux send-keys`. To meet the "never approve the wrong prompt" anti-goal, each answer
carries a request id, and the app reads the pane with `tmux capture-pane` before sending (see
"Answers through tmux").

## Design

### System overview

```
 Claude Code ──http hooks──▶┐
 statusLine wrapper ──POST─▶│  ThaiDeck.app (menu bar, SwiftUI)        ThaiClock board
                            │  - config + editor                       - tileview: Clock, Calendar,
 macOS APIs ◀──actions──────│  - actions (CGEvent, NSWorkspace, ...)     Focus, System, Deck 1..N
 tmux / iTerm2 ◀─send-keys──│  - stats sampler (1 Hz)   ◀── WebSocket ─▶ - deck renderer + cache
                            └  - key-face renderer           (LAN, paired)  - permission overlay
```

The board is the WebSocket **server**. The app is the **client**: it finds the board over mDNS, so
the Mac's IP can change freely.

### Board ↔ app protocol

- Transport: WebSocket on port 81, served from `net_task` (for example `links2004/WebSockets`). The
  existing port-80 `WebServer` is untouched. mDNS adds `_thaideck._tcp` port 81 with the TXT
  record `id=<board MAC>`.
- Text frames carry JSON. Binary frames carry key-face bitmaps.
- **Pairing**: the user picks the board in the app and taps "Pair". The board shows a 6-digit PIN on
  a `lv_layer_top` overlay for 60 s. The user types the PIN in the app. Both sides then derive and
  store a 256-bit key (board: NVS; Mac: Keychain). Re-pairing replaces the key. "Forget Mac" goes
  on the System page or in web settings.
- **Session auth**: on connect, each side proves it holds the key with a challenge and response
  (HMAC-SHA256 over the other side's nonce). Every later frame in **both** directions carries a
  sequence number and an HMAC. Frames that fail the check are dropped and the socket is closed.
  Traffic is not encrypted. The data is not secret; the HMAC is there to stop forged button
  presses.
- **App → board**: `layout` (pages, widgets, grid positions, widget config, face image ids),
  `face` (binary: id, w, h, RGB565 + A8 pixels), `stats` (1 Hz), `volume` (on change), `claude`
  (sessions and usage, on change), `time_hint` (optional).
- **Board → app**: `press` (widget id, `tap` or `long`), `slider` (widget id, value 0..100,
  rate-limited to 10 Hz), `claude_action` (session id, request id, `approve` / `approve_always` /
  `deny` / `interrupt` / `focus`), `page` (visible page index; the app may skip `stats` while no deck page is
  shown).
- The layout carries a version hash. The board answers with the hash it has cached, and the app
  resends only on mismatch.

### Firmware (inside `examples/ntp_clock`)

- New tiles are appended to the tileview after `PAGE_SYSTEM`, one per custom page (cap: 8 pages).
  The page dots grow to match. `ui_next_page` (BOOT button) cycles through all of them.
- **Deck renderer**: builds LVGL objects from the cached layout at runtime. This is not EEZ; EEZ
  stays for the four fixed pages.
  - `key` (1x1 up to 8x2): shows the face bitmap from the app. Tap and long-press give visual
    feedback and send `press`.
  - `stat` (metric + style): `bar`, `number` or `sparkline` (last 60 s). Metrics: `cpu`, `ram`,
    `gpu`, `temp`, `net_down`, `net_up`, `disk_free`, `disk_io`, `battery`.
  - `volume`: horizontal slider plus a mute toggle. It must keep the drag from turning into a page
    swipe.
  - `claude_sessions`: one row per live session showing project name, a state colour (working,
    waiting for you, needs permission, done), and context %. Tapping a row sends `focus`.
  - `claude_usage`: 5 h and weekly bars with reset times.
  - `clock`: small time label driven by the board's own NTP time.
- **Permission overlay**: when any session enters "needs permission", a `lv_layer_top` overlay
  shows on every page, the clock pages included. It shows the project, the tool, a one-line
  summary of `tool_input` (the command, or the file path), and buttons Approve / Always / Deny /
  Open. It closes when the app reports the prompt is gone, whoever answered it. The existing
  `ui_flash_screen` draws attention.
- **Cache**: layout JSON and face bitmaps are stored in LittleFS on the existing 896 KB `spiffs`
  partition, so deck pages render at boot before the Mac connects. Faces are RGB565 + A8,
  80x90 px per cell. An 8x2 page of 1x1 keys is about 345 KB, so the cache must bound itself
  (LRU by page, or a bigger partition; see "Left to the builder").
- **Offline**: when the app is not connected, deck pages keep the cached layout, keys are dimmed,
  live widgets show `--`, and a small "Mac offline" badge appears. Presses are ignored, never
  queued.
- **Threading**: WebSocket I/O runs in `net_task`. Parsed layout, stats and Claude state reach the
  LVGL thread through mutex-guarded snapshots with version counters, like `net_get_status`.
  Outgoing events go through a small FreeRTOS queue from the LVGL thread to `net_task`.

### Mac app (`ThaiDeck.app`)

Location: `mac/ThaiDeck/` at the repo root (Xcode project). It is kept out of
`examples/ntp_clock/` because `build_src_filter = +<*>` would compile any C shim found there. It is a
menu-bar app (`MenuBarExtra`) with an editor window.

- **Connection**: Bonjour browse for `_thaideck._tcp`, `URLSessionWebSocketTask`, auto-reconnect.
  The menu bar shows the state (paired / connecting / offline).
- **Editor**:
  - A pages list. Each page has a canvas drawn at the device's aspect ratio with the 8x2 grid.
  - A widget palette. Drag a widget onto the grid and resize it in whole cells.
  - An inspector for the selected widget: label, icon, colours, action. For a key there is also an
    optional long-press action.
  - App picker: choose from /Applications. The app's icon is used automatically.
  - Hotkey recorder for the hotkey action.
  - Live preview. Save pushes the layout to the board.
  - Config file: `~/Library/Application Support/ThaiDeck/config.json`, human-readable, written
    only by the app.
- **Key-face rendering**: the app renders each key face (icon, label in any font or emoji, colours)
  to a bitmap at the cell size and sends it. The board only blits it. This side-steps the board's
  font coverage and makes the editor preview pixel-exact. Live widgets are drawn on the board,
  because their values change every second.
- **Actions**:
  - Open app: `NSWorkspace.openApplication`.
  - Open URL.
  - Hotkey: `CGEvent` with modifiers. Needs Accessibility.
  - Media keys: `NSEvent` system-defined `NX_KEYTYPE_*`.
  - Volume and mute: CoreAudio on the default output device. Volume changes are pushed back so the
    slider stays in sync.
  - Type text.
  - Shell command: `/bin/zsh -lc`, with output discarded.
  - macOS Shortcut: `shortcuts run`.
- **Stats sampler (1 Hz)**:
  - CPU: `host_processor_info` deltas.
  - RAM: `host_statistics64`; used = active + wired + compressed.
  - GPU: IOAccelerator `PerformanceStatistics` "Device Utilization %".
  - Temperature: SMC keys read through IOKit, no sudo. The exact keys for M4 Pro are found
    empirically.
  - Network: `getifaddrs` byte deltas.
  - Disk: free space, plus IOBlockStorageDriver statistics for I/O.
  - Battery: IOPowerSources, sent only when present.
- **Claude integration**: a local HTTP listener on `127.0.0.1:<port>`.
  - Hooks: the app's settings screen offers "Install Claude Code integration". It **adds** `http`
    hooks to `~/.claude/settings.json` next to the existing ones, never replacing them, for
    `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `Notification`, `Stop`
    and `SessionEnd`. Each hook has a short `timeout` (2 s), `onFailure: "continue"`, and the
    header `X-Tmux-Pane: $TMUX_PANE` (listed in `allowedEnvVars`). The hooks only report; they
    never return a decision.
  - Status line: the installer swaps `statusLine.command` to a tiny wrapper. The wrapper reads
    stdin, POSTs it to the app with a timeout of at most 200 ms, ignoring failures, then pipes the
    same stdin to the previous command (`ccstatusline`) and passes its output through unchanged.
    The previous command is stored so "Uninstall" restores it.
  - State model per `session_id`:
    - `UserPromptSubmit` / `PreToolUse` → working.
    - `PermissionRequest` or `Notification(permission_prompt)` → needs permission, keeping
      `tool_name` and `tool_input`.
    - `PostToolUse` after a permission request → working.
    - `Stop` → done.
    - `Notification(idle_prompt)` → waiting for you.
    - `SessionEnd` → removed.
    - Sessions silent for 30 min are dropped.
    - The status line adds model, cost, context % and the global `rate_limits`.
  - Answers through tmux. The target is the `TMUX_PANE` from the hook header.
    - Every `PermissionRequest` gets a new request id. The board's answer must carry the id of the
      pane's **current** pending request, otherwise the app rejects it. The hook fires before the
      prompt is drawn, so a prompt that replaced the old one always has a new id first.
    - Approve, Always, Deny: run `tmux capture-pane -p -t %N` and check two things. First, a
      Claude Code permission prompt is on screen. Second, it names the same tool and shows the
      start of the same command or file path. Long commands may be cut off on screen; the visible
      prefix is enough. If both checks pass, `send-keys` the option key the prompt shows. If not,
      send nothing and tell the board "answer at the keyboard". *(Builder call: refuse when
      unsure.)*
    - Interrupt: `send-keys Escape`.
    - Focus: `switch-client` to the pane's session, then `select-window` and `select-pane`, then
      bring iTerm2 to the front.

### Milestones (each ends usable)

1. **Link and keys**: pairing, auth, protocol, layout cache, custom pages from a built-in sample
   layout, and all key actions. Config is the JSON file the app will later edit.
2. **Live widgets**: stats sampler, the `stat`, `volume` and `clock` widgets, offline state.
3. **Claude**: installer, hook listener, statusLine wrapper, the `claude_*` widgets, the permission
   overlay, answers through iTerm2.
4. **Editor**: the full SwiftUI editor, app picker, hotkey recorder, preview, push.

## Risks to verify early

- How Claude Code's permission prompt looks today (option keys and visible text) for the
  `capture-pane` check. Spike before milestone 3.
- `send-keys Escape` versus the owner's tmux `escape-time` (`~/.tmux.conf`). A slow Escape can merge
  with the next key.
- With several tmux clients attached, which client `switch-client` should move. Pick the one on
  iTerm2's front window.
- SMC temperature keys on M4 Pro without root.
- WebSocket library behaviour inside `net_task` next to the sync `WebServer`, and heap or PSRAM use
  while receiving face bitmaps.
- Brownout margin on the battery-less dev board under sustained Wi-Fi traffic.

## Left to the builder

- WebSocket library choice. Exact JSON field names and the binary face frame layout.
- Whether to enlarge the data partition (16 MB flash allows it) or bound the face cache by LRU.
- Key press visuals, the dimmed-offline style, and overlay styling (the ThaiClock palette in
  `ui_internal.h`).
- Swift project structure, test layout, and how to provision the stable signing identity.
- Default sample layout for milestone 1. Suggested Dev page: VS Code, iTerm2, Chrome, Claude
  sessions (4x1), volume, and play/pause.

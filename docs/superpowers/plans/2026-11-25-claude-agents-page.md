# Claude Agents Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `claude_agents` board widget. It shows one animated pixel critter per Claude Code session (live plus the last 7 days), with the tmux session name, a status line, a subagent badge and a total pill on a vertical scrollbar.

**Architecture:** The Mac `ClaudeStore` gains names, tools, subagents and history, and sends them as new fields in the existing `claude` frame. Sprite sheets exported from Aseprite are loaded by the Mac, scaled 3x, and sent as faces in a new id range (129–192), described by a compact `agent_sprites` table in the layout JSON. The board parses both, caches the sprite images, and animates the visible tiles in a new `ui_deck_agents.cpp`.

**Tech Stack:**
- Mac: Swift package `mac/LongDeck` (LongDeckCore Swift 6, LongDeckEditor, LongDeckApp).
- Board: ESP32-S3 Arduino + LVGL 8.4 in `examples/ntp_clock`, with PlatformIO envs `native_deck` (Unity) and `ntp_clock`.
- Art: Aseprite 1.3.18 through the `aseprite` MCP (`@pebbly/aseprite-ai-artist@0.8.4`).

**Spec:** `docs/superpowers/specs/2026-11-25-claude-agents-page-design.md`. Read its "Calls settled after the builder check" section; those calls bind.

## Global Constraints

- Edit files only with the Edit and Write tools. Never edit through Bash (`sed -i`, heredoc redirects, scripts).
- Comments: English, one line, about 10 words at most, only what the code cannot say. Never add comments to code you did not change.
- Swift: CommandLineTools toolchain only. `$SWIFT_TEST` means, run in `mac/LongDeck`:
  `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
  (add `--filter <Suite>`). `swift build` checks the app target.
- **No SwiftUI macros:** no `@State`, `@Observable`, `@FocusState`, `@GestureState`, `#Preview`. Use `ObservableObject` + `@Published` + `@StateObject`.
- LongDeckCore builds in Swift 6 strict concurrency, so new core types are `Sendable`.
- **Never launch LongDeck.app. Never put a window on screen from a test.** No test constructs `AppModel` or `EditorWindowController`. Never touch the real `~/Library/Application Support/LongDeck/` or anything under `~/.claude`. File tests use `FileManager.default.temporaryDirectory/longdeck-tests-<UUID>`.
- Board: `$NATIVE` = `pio test -e native_deck` (baseline 102/102). `$BUILD` = `pio run -e ntp_clock` (baseline RAM 29.2%, flash 52.3%). Never flash.
- Fixed values:
  - The tag order is `working, permission, waiting, done`, the same as `DeckClaudeState` `DCS_*`.
  - Face ids 1–128 are key faces. Ids 129–192 are sprites (`DECK_SPRITE_FIRST_ID 129`, `DECK_MAX_FACES 192`).
  - Sprites are scaled 3x with nearest-neighbour. Pixels are RGB565 big-endian + A8, 3 bytes per pixel, made with `FaceRenderer.pack`.
  - The wire carries at most 24 session rows, and the board cap is `DECK_CLAUDE_MAX_SESSIONS 24`. Names are at most 23 UTF-8 bytes and tools at most 15, cut at grapheme boundaries.
  - History lasts 7 days (604800 s). A subagent with no stop is dropped after 2 h (7200 s). A silent session is ended after 30 min, as today.
  - Hat: FNV-1a 32-bit over the UTF-8 name. `hat = h % 8`, `tint = (h / 8) % 8`.
  - Hat tints, in board order: `#4ADE80 #60A5FA #F472B6 #FBBF24 #A78BFA #F87171 #2DD4BF #F2F4F7`.
  - Widget: minimum 2x1. Visible tiles = `floor(w/2)` columns × `h` rows.

## Review Focus

1. **A session that needs the owner is never cut.** Permission and waiting rows sort before working and done, and before history, so they survive the 24-row cap. Test: Task 1 `needyRowsSurviveCap`.
2. **Mixed versions keep working.** A board fed an old frame (no new fields) shows the project as the name with no badge. A config with no `claude_agents` widget builds a byte-identical layout and hash. Tests: Task 2 `test_old_frame_defaults`, Task 6 `layoutUnchangedWithoutAgentsWidget`.
3. **Subagent counts never go negative or stick.** A stop with no start is ignored, `SessionEnd` clears, and a start older than 2 h is dropped. Test: Task 1 `subagentCountingRules`.
4. **Thai, emoji and long names fit.** The name is cut at a grapheme boundary to 23 bytes on the Mac, and the board copies it safely. Tests: Task 1 `namesCutAtGraphemes`, Task 2 `test_name_truncates_safely`.
5. **Missing or broken art never breaks the deck.** Bad sprite exports load as `nil`. The layout then has no `agent_sprites`, and the board widget draws tiles without a critter. A malformed table on the board gives `present=false` and does not reject the layout. Tests: Task 6 `brokenSpritesLoadNil`, Task 2 `test_bad_sprite_table_is_absent`.
6. **No clock means no fake age.** With no NTP time, or `since` in the future, the age text is empty. Test: Task 2 `test_age_without_clock`.

## Execution waves

The Swift tasks share one package, so they run one at a time. The board tasks share the pio build dirs, so they run one at a time too. Swift and board run side by side:

`(T1 ‖ T2) → (T3 ‖ T5) → T4 → T6 → T7 → T8`

T7 needs a session with the `aseprite` MCP loaded. If the controller has no such tools, it asks the owner to start one (or run `/mcp`) before T7.

---

### Task 1: Session model and wire fields (Mac)

**Files:**
- Modify: `mac/LongDeck/Sources/LongDeckCore/ClaudeEvents.swift`, `ClaudeStore.swift`, `ClaudeInstaller.swift`
- Create: `mac/LongDeck/Sources/LongDeckCore/AgentHat.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/ClaudeAgentsStoreTests.swift`, extend `ClaudeInstallerTests.swift`

**Interfaces:**
- Produces:
  - `ClaudeHookEvent.agentId: String?` and `agentType: String?`, read from `agent_id` and `agent_type`.
  - `ClaudeSession` gains `name: String?`, `lastTool: String?` and `subagents: [String: TimeInterval]` (agent id → start time).
  - `ClaudeStore.setName(_ name: String, forSession id: String)`.
  - `ClaudeStore.agentsTotal: Int`.
  - `AgentHat.of(_ name: String) -> (hat: Int, tint: Int)`.
  - `ClaudeInstaller.isCurrent(_ paths: ClaudeInstallPaths) -> Bool`.
- Wire, in each `sessions[]` row of `ClaudeStore.body(now:)`:

  | Field | Value |
  | --- | --- |
  | `name` | name, else project; at most 23 bytes |
  | `tool` | pending tool if permission, else `lastTool` while working, else `""`; lower-case, at most 15 bytes |
  | `agents` | running subagents |
  | `since` | unix seconds when the state began |
  | `hat`, `tint` | from `AgentHat.of` |
  | `live` | `true` for every row this task makes |

  The top level adds `agents_total`. The row cap becomes 24.

- [ ] **Step 1: Write the failing tests** in `ClaudeAgentsStoreTests` (Swift Testing, a fixed `Date`):
  - `rowCarriesAgentFields`: a session with `setName("CMM iOS")`, a `PreToolUse` with `Bash`, and ctx 98. Row has `name == "CMM iOS"`, `tool == "bash"`, `agents == 0`, `since == <unix of state change>`, `live == true`, and `hat`/`tint` equal to `AgentHat.of("CMM iOS")`.
  - `nameFallsBackToProject`: no name set → `name == project`.
  - `subagentCountingRules`:
    - two `SubagentStart` (ids a, b) then `SubagentStop` a → `agents == 1`;
    - `SubagentStop` c (never started) → still 1;
    - `SessionEnd` → the session is gone and `agents_total` drops;
    - a start older than 7200 s at the next `body(now:)` → dropped.
  - `agentsTotalCountsWorkingAndSubagents`: 2 working sessions, 1 done session holding 2 subagents → `agents_total == 4`.
  - `needyRowsSurviveCap`: 30 working sessions plus 1 permission and 1 waiting added last → 24 rows; row 0 is the permission one and row 1 the waiting one.
  - `namesCutAtGraphemes`: `setName("โปรเจกต์ทดสอบภาษาไทย👍🏽")` → `name.utf8.count <= 23`, it is a prefix of the original, and it does not end inside a grapheme.
  - `permissionRowShowsPendingTool`: permission for `Edit` → `tool == "edit"`.
  - `hatIsStable`: `AgentHat.of("Agents Deck")` is the same on every call. Pin the exact pair you compute once in the test, as a regression guard, and check both values are in `0..<8`.
  - In `ClaudeInstallerTests`, `isCurrentNeedsSubagentHooks`:
    - a settings file installed by the old event list (without `SubagentStart`/`SubagentStop`) → `false`;
    - after `install` → `true`;
    - `hookEvents` contains both new events.
- [ ] **Step 2:** `$SWIFT_TEST --filter ClaudeAgentsStoreTests` → fails to compile (missing members).
- [ ] **Step 3: Implement.**
  - Decode the two fields.
  - Store `SubagentStart`/`SubagentStop` per session.
  - Set `lastTool` on `PreToolUse`.
  - Add the row fields. Reuse `ClaudeText.capped` for the byte cuts, or add a grapheme-safe variant beside it if it is not grapheme-safe.
  - `since` must be wall-clock unix seconds. If `stateSince` is not wall-clock, keep a wall-clock copy beside it.
  - Set `maxSessions = 24`.
  - Append `"SubagentStart", "SubagentStop"` to `hookEvents`.
  - `isCurrent` is true only when every `hookEvents` entry has a LongDeck group.
- [ ] **Step 4:** `$SWIFT_TEST` → all pass (core count grows from 392).
- [ ] **Step 5: Commit** `feat(longdeck): add names, tools and subagent counts to Claude rows`.

### Task 2: Board parsing, sprite table and face range (firmware)

**Files:**
- Modify: `examples/ntp_clock/deck_claude.h/.cpp`, `deck_layout.h/.cpp`, `deck_net.cpp`, `deck_store.cpp`, `ui_deck_claude.cpp` (only the change that skips non-live rows)
- Test: `examples/ntp_clock/test/test_claude/test_main.cpp`, `test/test_layout/test_main.cpp`

**Interfaces:**
- Produces, in `deck_claude.h`:
  - `DECK_CLAUDE_MAX_SESSIONS 24`.
  - `DECK_CLAUDE_BODY_MAX`: raise it so a 24-row frame fits. Use 8192, and check where the buffer lives (PSRAM or static) and keep it out of internal RAM if it is static.
  - `DeckClaudeSession` adds `char name[24]; char tool[16]; uint8_t agents; uint32_t since; uint8_t hat, tint; bool live;`.
  - `DeckClaude` adds `uint8_t agents_total`.
  - `size_t deck_claude_age(char *out, size_t n, uint32_t since, uint32_t now)` returns `"now"` (< 60 s), `"5m ago"`, `"3h ago"` or `"2d ago"`. It writes `""` and returns 0 when `now == 0`, `since == 0` or `since > now + 60`.
- Produces, in `deck_layout.h`:
  - `DW_CLAUDE_AGENTS = 6` with type string `"claude_agents"`, minimum `w ≥ 2`.
  - `DECK_MAX_FACES 192`, `DECK_SPRITE_FIRST_ID 129`, `DECK_AGENT_TAGS 4`, `DECK_SPRITE_MAX_FRAMES 32`.
  - The sprite table:
    ```c
    struct DeckAgentSprites {
      bool present;
      uint8_t w, h, hat_w, hat_h, frames, hat_count;
      uint16_t first_id, hat_first;
      uint8_t tag_first[DECK_AGENT_TAGS], tag_count[DECK_AGENT_TAGS];  // frame indexes
      uint16_t ms[DECK_SPRITE_MAX_FRAMES];
      uint8_t hat_x[DECK_SPRITE_MAX_FRAMES], hat_y[DECK_SPRITE_MAX_FRAMES];
    };
    ```
    `DeckLayout` gains `DeckAgentSprites sprites`.
- Layout JSON, top level, present only when the Mac has a `claude_agents` widget and sprites:
  ```json
  "agent_sprites":{"w":60,"h":72,"first":129,"tags":[[0,4],[4,2],[6,4],[10,4]],
    "ms":[150,...],"hx":[0,...],"hy":[0,...],"hats":[143,8],"hw":60,"hh":30}
  ```
  `tags` holds `[frame index, count]` in tag order. `ms`, `hx` and `hy` each have exactly `frames` entries, where `frames = sum(count)`. Frame `i` is face `first + i`.
- `face_referenced` and `deck_store_invalidate_faces` treat present sprite frame ids and hat ids as used.
- The old `claude_sessions` widget skips rows with `live == false`.

- [ ] **Step 1: Write the failing tests.**

  In `test_claude`:
  - `test_agent_fields_parse`: a row with all new fields → each field equal; `agents_total` equal.
  - `test_old_frame_defaults`: a row without the new fields → `name` equals `project`, `agents == 0`, `live == true`, `since == 0`.
  - `test_cap_24`: 30 rows → `count == 24`.
  - `test_name_truncates_safely`: a 40-byte UTF-8 Thai name → stored NUL-terminated at ≤ 23 bytes and never splits a UTF-8 sequence.
  - `test_age_strings`: `since = 1000` with `now` of 1030, 1000+300, 1000+3*3600 and 1000+2*86400 → `"now"`, `"5m ago"`, `"3h ago"`, `"2d ago"`.
  - `test_age_without_clock`: `now = 0` → `""`; `since = now + 120` → `""`.

  In `test_layout`:
  - `test_agents_widget_type`: `claude_agents` with w 2 parses as `DW_CLAUDE_AGENTS`; w 1 fails.
  - `test_sprite_table_parse`: the example above, with 14 frames and 8 hats → every field equal.
  - `test_bad_sprite_table_is_absent`: each of these → layout still parses with `sprites.present == false`:
    - `ms` length ≠ frames;
    - a tag count of 0;
    - `first + frames - 1 > 192`;
    - the hat range overlaps the frames;
    - `first < 129`.
  - `test_face_range_192`: a key with face 129 is rejected (key faces stay at 1–128). The sprite frame id 192 is accepted.
- [ ] **Step 2:** `$NATIVE` → the new tests fail.
- [ ] **Step 3: Implement.**
  - Parse in the existing style.
  - Truncate with a UTF-8-safe copy (back off continuation bytes).
  - Key faces keep the `1..128` check. Sprites use `129..DECK_MAX_FACES`.
  - In `deck_net.cpp`, change `face_referenced` and the face id range check at line ~141. In `deck_store.cpp`, change the sweep (`used[]`).
- [ ] **Step 4:** `$NATIVE` all pass. `$BUILD` succeeds; note RAM and flash.
- [ ] **Step 5: Commit** `feat(longdeck): parse agent rows and the agent sprite table on the board`.

### Task 3: History and tmux names (Mac)

**Files:**
- Create: `mac/LongDeck/Sources/LongDeckCore/ClaudeHistory.swift`, `ClaudeNames.swift`
- Modify: `mac/LongDeck/Sources/LongDeckCore/ClaudeStore.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/ClaudeHistoryTests.swift`

**Interfaces:**
- Consumes: Task 1 `ClaudeSession.name`, `AgentHat.of`, and the row fields.
- Produces:
  - `struct ClaudeHistoryRecord: Codable, Sendable, Equatable { name, project: String; endedAt: TimeInterval }`.
  - `struct ClaudeHistory: Sendable, Equatable` with:
    - `records: [ClaudeHistoryRecord]`;
    - `mutating func record(name:project:endedAt:)`, which replaces a record with the same name only when the new one is newer;
    - `mutating func prune(now: TimeInterval)`, which drops records older than 604800 s;
    - `static func load(from: URL) -> ClaudeHistory`, which returns empty on a missing or corrupt file;
    - `func save(to: URL) throws`, an atomic write with mode 0600.
  - `ClaudeStore.history: ClaudeHistory` (public get and set) and `ClaudeStore.historyChanged: Bool`. The controller saves the history and clears the flag.
  - `final class ClaudeNames: @unchecked Sendable` or an actor, initialized as `init(runner: TmuxRunner)`. Its `func name(forPane pane: String, now: TimeInterval) -> String?` runs `tmux display-message -p -t <pane> '#S'`, trims the output, caches it for 30 s, and returns `nil` on error or empty output.
- Store behaviour:
  - When a session ends (`SessionEnd`) or is dropped as silent (30 min), the store records `{name ?? project, project, endedAt: last event}` into `history`.
  - `body(now:)` appends one history row per record whose name is not used by a live row:
    - `id = "h:" + name`, `state = "done"`, `live = false`, `since = endedAt`;
    - `hat`/`tint` from the name, `tool = ""`, `agents = 0`, `ctx = -1`, `cost_cents = -1`, `tmux = false`.
  - History rows sort after every live row, newest first. All rows together are capped at 24.
  - Two live sessions with the same name: the newer one gets `name·2` (then `·3`, and so on), still within 23 bytes.

- [ ] **Step 1: Write the failing tests** in `ClaudeHistoryTests`:
  - `recordKeepsNewestPerName`;
  - `pruneDropsOlderThanSevenDays`, which keeps 604799 s and drops 604801 s;
  - `saveLoadRoundTrip` in a temp dir, with mode 0600;
  - `corruptFileLoadsEmpty`;
  - `endedSessionBecomesHistoryRow`: `SessionEnd` → the next body has a row with `live == false`, `state == "done"` and `since == endedAt`;
  - `staleSessionBecomesHistoryRow` (31 min silent);
  - `liveHidesHistoryWithSameName`;
  - `historySortsAfterLive`;
  - `duplicateLiveNamesGetSuffix` (`"CMM"`, `"CMM·2"`);
  - `namesCacheAndFallback`: a fake `TmuxRunner` returns `"Agents Deck\n"` and is called once in 30 s and again after; a throwing runner gives `nil`.
- [ ] **Step 2:** `$SWIFT_TEST --filter ClaudeHistoryTests` fails.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `$SWIFT_TEST` all pass.
- [ ] **Step 5: Commit** `feat(longdeck): keep a 7-day Claude session history and tmux names`.

### Task 4: Register the `claude_agents` widget kind (Mac)

**Files:**
- Modify the `mac/LongDeck/Sources/LongDeckCore/` files that register `claudeSessions`:
  - `DeckConfig.swift` (lines ~68, 103, 125, 189);
  - `WidgetPalette.swift` (~29–100);
  - `EditorGrid.swift:71`;
  - `EditorIssues.swift:78`;
  - `LayoutBuilder.swift:38`.
- Modify every exhaustive `switch` over `LiveKind` or the palette kind in `LongDeckEditor` and `LongDeckApp` that stops compiling, at minimum `LivePlaceholderView.swift:61`.
- Test: extend `DeckConfigTests`, `WidgetPaletteTests`, `EditorIssuesTests`.

**Interfaces:**
- Produces:
  - `LiveKind.claudeAgents` with JSON type `"claude_agents"`.
  - Palette entry: title "Claude agents", SF Symbol `"person.3.sequence"`, default size 8x2, minimum 2x1, id base `"ccagents"`.
  - Validation and EditorIssues error: "claude_agents needs at least 2 columns".
  - LayoutBuilder writes `"type":"claude_agents"`.
  - The placeholder for now: text "Claude agents" in the box. Task 8 draws the real one.

- [ ] **Step 1: Failing tests:**
  - `claudeAgentsRoundTrips`, which decodes and re-encodes the same JSON;
  - `claudeAgentsNeedsTwoColumns` (validate throws for w 1);
  - palette `claudeAgentsDefaults` (8x2, minimum 2x1);
  - an issues test for a 1-wide widget;
  - `layoutWritesClaudeAgentsType`.
- [ ] **Step 2:** fails. **Step 3:** implement. **Step 4:** `$SWIFT_TEST` and `swift build` pass.
- [ ] **Step 5: Commit** `feat(longdeck): add the claude_agents widget kind`.

### Task 5: Board `claude_agents` widget (firmware)

**Files:**
- Create: `examples/ntp_clock/ui_deck_agents.h`, `ui_deck_agents.cpp`
- Modify: `examples/ntp_clock/ui_page_deck.cpp`, which creates, resets, updates and routes dirty faces to the widget
- Docs: `examples/ntp_clock/README.md` (Thai). Add one short entry for the widget in the existing widget list.

**Interfaces:**
- Consumes: Task 2 `DeckClaude` fields, `deck_claude_age`, `DeckLayout.sprites`, `DW_CLAUDE_AGENTS`, and the existing `deck_store_load_face(id, lv_img_dsc_t*)`, `deck_net_claude_action` and `UiTick`.
- Produces:
  - `void ui_agents_reset();`
  - `bool ui_agents_create(lv_obj_t *tile, const DeckWidget *w, const DeckAgentSprites *sprites);`, which returns false if `w->type != DW_CLAUDE_AGENTS`;
  - `void ui_agents_update(const UiTick *t, bool ready, bool visible);`
  - `void ui_agents_face_changed(uint16_t id);`
- Behaviour, as the spec's "Board widget" section says, with these exact rules:
  - Layout:
    - Box = the widget rect. A 12 px column on the right holds the total pill (`agents_total`, on top) and a scroll thumb under it.
    - The tile grid has `cols = w/2` and `rows = h` visible. Tile size is `((box_w-12)/cols) × (box_h/rows)`.
    - The container scrolls `LV_DIR_VER` only, with snap to tile rows and the LVGL scrollbar off. Horizontal drags must still chain to the page tileview.
  - Tile content:
    - Sprite on the left, vertically centred. The hat image sits at `(hat_x[f], hat_y[f])` inside the frame, with `img_recolor` = tint `HAT_TINTS[tint]` and `img_recolor_opa` ≈ `LV_OPA_60`.
    - Name: bold `COLOR_TEXT` when live, `COLOR_TEXT_DIM` when not.
    - Status line:

      | State | Text | Colour / panel |
      | --- | --- | --- |
      | working | `tool · NN% ctx`, or `tool`, or `working` | |
      | permission | `permission · Tool` | orange |
      | waiting | `hungry · feed me` | orange |
      | done | `done · <age>`, or `done` if the age is empty | |

    - Badge `×N` when `agents > 0`.
    - Working and permission tiles get an orange corner accent. Waiting tiles get a diagonal-stripe panel.
  - Animation:
    - Each tile keeps a frame index and the time it entered that frame.
    - On each `ui_agents_update`, while `visible` (the deck page holding this widget is the active tile), advance tiles whose frame time ≥ `ms[f]` within the tag for their state. Swap the image source only, and do no other redraw.
    - Restart the tag when the state changes.
    - Sprite images load once per layout into PSRAM through `deck_store_load_face`, and are reloaded on `ui_agents_face_changed`. If `sprites->present` is false or an image is missing, draw the tile without a sprite.
  - Input:
    - Tap a live tile with `tmux` → `DCA_FOCUS`.
    - Long-press a working live tile with `tmux` → `DCA_INTERRUPT`.
    - History tiles ignore input.
  - Offline: when `!ready` or there is no Claude snapshot, show a single `--` label like the other Claude widgets.
  - Tile objects are created once, up to 24, and shown or hidden per frame, not rebuilt on every frame.

- [ ] **Step 1:** If you add pure helpers (for example the tile geometry `agents_grid(w, h, box_w, box_h, &cols, &rows, &tw, &th)`), put them in `deck_claude.cpp` with native tests in `test_claude` (`test_agents_grid` for 2x1, 4x1, 2x2 and 8x2 → 1, 2, 2 and 8 tiles).
- [ ] **Step 2:** `$NATIVE` passes, and `$BUILD` succeeds within budget (RAM must stay under 35%).
- [ ] **Step 3:** In the report, list the hardware checks for the owner:
  - animations run smoothly;
  - a vertical drag scrolls tiles while a horizontal swipe changes pages;
  - tap focuses the pane;
  - the pill shows the right total.
- [ ] **Step 4: Commit** `feat(longdeck): draw the animated Claude agents widget`.

### Task 6: Sprite loader and sprite faces in the layout (Mac)

**Files:**
- Create: `mac/LongDeck/Sources/LongDeckCore/AgentSprites.swift`, plus `mac/LongDeck/Sources/LongDeckCore/Resources/sprites/ABOUT.txt` (one line saying the exports live here).
- Modify:
  - `mac/LongDeck/Package.swift`: LongDeckCore gets `resources: [.copy("Resources/sprites")]`.
  - `LayoutBuilder.swift`.
  - `EditorIssues.swift` and the editor environment type it reads, so the frame-size check builds with the same sprites.
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/AgentSpritesTests.swift`. It builds fixture PNG and JSON in code with CoreGraphics and writes nothing to the repo.

**Interfaces:**
- Consumes: Task 4 `LiveKind.claudeAgents`; `FaceRenderer.pack`.
- Produces:
  ```swift
  public struct AgentSprites: Sendable, Equatable {
      public static let tagNames = ["working", "permission", "waiting", "done"]
      public static let scale = 3
      public var frameW: Int, frameH: Int, hatW: Int, hatH: Int   // display px
      public var frames: [Data]          // tag order, RGB565BE+A8
      public var tagRanges: [Range<Int>] // one per tag, indexes into frames
      public var durationsMs: [Int]
      public var hatX: [Int], hatY: [Int] // per frame, display px inside the frame
      public var hats: [Data]            // exactly 8
      public static func load(agentJSON: Data, agentPNG: Data, hatsJSON: Data, hatsPNG: Data) throws -> AgentSprites
      public static func loadFiles(in dir: URL) -> AgentSprites?
      public static func bundled() -> AgentSprites?
  }
  ```
  `loadFiles` reads `claude-agent.json/.png` and `claude-hats.json/.png`, and returns `nil` on any error. `bundled()` uses `Bundle.module`.
  `LayoutBuilder.build(_:render:sprites:)` gains `sprites: AgentSprites? = nil`.
- Aseprite export contract, which Task 7 must meet:
  - `--format json-array` with `meta.frameTags` and `meta.slices`.
  - The agent sheet:
    - every frame is the same size, at most 24x24 native;
    - each of the 4 tags exists with 1–8 frames;
    - total frames + 8 ≤ 64;
    - a slice named `hat` has keys that give the hat's top-left per frame (a key holds until the next key).
  - The hats sheet: exactly 8 frames, all the same size, at most 24x12 native.
  - Frame `duration` is in ms.
- Layout rules:
  - Only when some page has a `claudeAgents` widget and `sprites != nil`:
    - frames get ids 129… in tag order, then the 8 hats;
    - the top-level `agent_sprites` table is written exactly as in Task 2;
    - the face pixels go into `faces`, so the hash covers them.
  - Otherwise the output is byte-identical to today.

- [ ] **Step 1: Failing tests:**
  - `loadsFixtureSheet`: tags → ranges, durations, `hatX`/`hatY` scaled 3x, frame bytes = w*h*3, and one known pixel's packed bytes equal `FaceRenderer.pack` of that colour.
  - `nearestNeighbourScale`: a 2x1 native checker gives 6x3 blocks.
  - `brokenSpritesLoadNil`:
    - each of a missing tag, an extra hat count (7 or 9), frames of different sizes, a frame over 24 px, and corrupt JSON → `load` throws;
    - `loadFiles` on an empty dir → `nil`.
  - `layoutUnchangedWithoutAgentsWidget`: the sample config with fixture sprites → JSON and hash equal to the build without sprites.
  - `layoutAddsSpriteFacesAndTable`: a config with a `claude_agents` widget → faces 129..(129+frames+7) exist, the `agent_sprites` JSON matches the Task 2 shape, and the hash differs from the build without sprites.
  - `spriteTableFitsFrame`: the full sample config plus an 8x2 agents page → sealed layout ≤ `LayoutPushPolicy.maxWebSocketFrame`.
  - `issuesCountSprites`: EditorIssues with sprites in the environment reports the same frame size the builder produces.
- [ ] **Step 2:** fails. **Step 3:** implement. **Step 4:** `$SWIFT_TEST` and `swift build` pass.
- [ ] **Step 5: Commit** `feat(longdeck): load Aseprite agent sprites and send them as faces`.

### Task 7: Draw the critter and hats in Aseprite (art)

Run this task in a session where the `aseprite` MCP tools are loaded. Aseprite must have been restarted once after the extension install.

**Files:**
- Create:
  - `mac/LongDeck/Art/claude-agent.aseprite`, `mac/LongDeck/Art/claude-hats.aseprite`;
  - `mac/LongDeck/Art/export.sh`, which runs `/Applications/Aseprite.app/Contents/MacOS/aseprite -b <src> --sheet <png> --data <json> --format json-array --list-tags --list-slices --sheet-type horizontal` for both files into `Sources/LongDeckCore/Resources/sprites/`;
  - the four export files.
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/AgentSpritesTests.swift` gains `bundledSpritesLoad` (`AgentSprites.bundled()` is non-nil, 4 tags, 8 hats).

**Art direction** (original work; do not copy the reference photo):
- **The critter:** a Claude-style orange pixel critter (body around `#D97757`, darker outline, small dark eyes), about 16x14 inside a 20x24 canvas, with headroom above it for the hat and the "zz".
- **working** (4–6 frames, about 120–160 ms): a bob plus a busy arm or typing motion.
- **permission** (2–4 frames, about 300 ms): a raised arm and a blinking "!" above it.
- **waiting** (4 frames, about 200 ms): a hungry bounce with the mouth open.
- **done** (4 frames, about 400 ms): the same pose, recoloured grey (`#8A8F98` family), eyes closed, a small "z" rising in the headroom.
- **The `hat` slice:** keys follow the head as it bobs.
- **Hats:** 8 designs in light greys (`#F2F4F7`, `#C9CED6`, `#8A8F98`) so a tint can colour them: cap, beanie, top hat, crown, headband, bucket hat, propeller cap, beret.
- Use the MCP's preview and onion-skin tools to check the motion. Export through `export.sh`.

- [ ] **Step 1:** Draw both files through the MCP, and save them.
- [ ] **Step 2:** Run `bash mac/LongDeck/Art/export.sh` → four files written.
- [ ] **Step 3:** Add `bundledSpritesLoad`. `$SWIFT_TEST` passes.
- [ ] **Step 4:** Write a contact-sheet PNG (every frame scaled 3x, with hats in their 8 tints) to `/Users/lek/.claude/jobs/1fd8bef7/tmp/agents-sprites.png` for the controller to show the owner. The owner approves the art before Task 8.
- [ ] **Step 5: Commit** `feat(longdeck): draw the Claude agent critter and hats`.

### Task 8: App wiring, editor placeholder and docs (Mac)

**Files:**
- Modify:
  - `mac/LongDeck/Sources/LongDeckApp/ClaudeController.swift`: name lookup through `ClaudeNames` for each event with a pane; load history at start from `<support>/claude-history.json`; prune and save when `historyChanged`.
  - `AppModel.swift`: sprites = `AgentSprites.loadFiles(in: <support>/sprites)` ?? `AgentSprites.bundled()`; watch `<support>/sprites` with the existing watcher style; pass the sprites into `LayoutBuilder.build` and into the editor environment; rebuild and push when they change.
  - `MenuView.swift`: when Claude hooks are installed but `!ClaudeInstaller.isCurrent`, show "Reinstall Claude hooks (adds subagent count)".
  - `scripts/bundle.sh`: copy `LongDeck_LongDeckCore.bundle` into `Contents/Resources`.
  - `mac/LongDeck/Sources/LongDeckEditor/LivePlaceholderView.swift`: the `claudeAgents` case draws sample tiles (4 states, names "Agents Deck", "CMM iOS", "Heritage" and "Wall Panel") with the real first frames and hats, scaled for the canvas.
  - `mac/LongDeck/README.md` and `examples/ntp_clock/README.md` (Thai): the widget, the history file, the sprites override folder, reinstalling the hooks, and how to redraw (`Art/*.aseprite` → `export.sh`).
- Test: `mac/LongDeck/Tests/LongDeckEditorTests/EditorSnapshotTests.swift` gains `claudeAgentsPlaceholder`, which writes a PNG to `$LONGDECK_SNAPSHOT_DIR` when set.

**Interfaces:**
- Consumes everything above. No new public API beyond what the wiring needs.

- [ ] **Step 1:** Write the snapshot test; it fails.
- [ ] **Step 2:** Implement the wiring, the placeholder and the bundle step.
- [ ] **Step 3:** `$SWIFT_TEST`, `swift build` and `./scripts/bundle.sh` succeed, and the built app contains `Contents/Resources/LongDeck_LongDeckCore.bundle/sprites/claude-agent.png`. Do not open the app.
- [ ] **Step 4:** Run the snapshot with `LONGDECK_SNAPSHOT_DIR=/Users/lek/.claude/jobs/1fd8bef7/tmp/agents-snapshots` and name the PNG in the report.
- [ ] **Step 5: Commit** `feat(longdeck): wire agent sprites, history and names into the app`.

## Hardware and live checklist (owner, after all tasks)

- A1 Flash `pio run -e ntp_clock -t upload`. Place an 8x2 `claude_agents` widget on a new page in the editor and Save.
- A2 All four animations play smoothly. The clock pages are no slower.
- A3 A vertical drag scrolls the tiles. A horizontal swipe still changes pages.
- A4 Reinstall the hooks from the menu. In a session that launches subagents, the badge and the pill count up and back down.
- A5 A tap focuses the right tmux pane. A long-press on a working tile interrupts it.
- A6 End a session: its tile turns grey and asleep with "done · now". It is still there after quitting and relaunching LongDeck.
- A7 Redraw a hat in Aseprite and run `export.sh` into `~/Library/Application Support/LongDeck/sprites/`. The board updates after the push.
- A8 With 18+ sessions (24 tiles) the heartbeat stays healthy for 10 minutes.

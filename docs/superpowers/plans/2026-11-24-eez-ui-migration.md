# ThaiClock EEZ Studio UI Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the static layout of every ThaiClock screen into an EEZ Studio project so it can be edited visually, while all behaviour stays identical.

**Architecture:** One EEZ project (`type lvgl`, LVGL 8.4.0, 640x180, no Flow) holds six pages. At runtime `ui.cpp` calls each generated `create_screen_<name>_page()`, then moves the page's children into a real `lv_tileview_add_tile` tile (or a `lv_layer_top` overlay) and deletes the empty EEZ screen. The existing C++ keeps all logic: binding events, updating text, animations, QR payloads, the meter, toast/flash and brightness.

**Tech Stack:** EEZ Studio CLI via the `eez-studio` MCP, LVGL 8.3.0-dev (LilyGO-patched, in `lib/lvgl`), Arduino-ESP32 2.0.17, PlatformIO `espressif32@6.13.0`.

**Spec:** The agreed hybrid design from the 2026-11-24 conversation: EEZ owns layout and style, C++ owns behaviour. Behaviour baseline = commit `a0b33f9`. The visual baseline is the framebuffer screenshots in the session scratchpad (`shots/*.png`).

## Global Constraints

- Do not modify `lib/lvgl`, `lib/lv_conf.h`, `net.cpp`, `settings.cpp`, `web_pages.h` or `app_state.h`.
- EEZ project: `examples/ntp_clock/eez/thaiclock.eez-project`, `--type lvgl --lvgl 8.4.0 --size 640x180`, build destination folder `gen`.
- Never hand-edit `.eez-project` JSON or anything in `examples/ntp_clock/eez/gen/`. Change the project through EEZ CLI/MCP only, then `build`.
- Never call the generated `create_screens()` or `ui_init()` from `gen/`. They install a light Montserrat theme.
- Do not use the EEZ `TileView` widget. Its children are not `lv_tileview_tile_t`, and LVGL 8.3 reads `tile->dir` on them (UB).
- At runtime the fonts must be the repo's fonts, with `ui_font_th_*` being the tone-stacking wrappers in `thai_fonts.c`. The generated `gen/ui_font_*.c` and `gen/ui.c` are excluded from the build.
- EEZ naming convention (enforced): widgets `<type>_<page>_<role>`, pages `<name>_page`.
- Comments: English, one line, at most about 10 words, only what the code cannot say.
- UI text, colours, sizes and behaviour stay as at `a0b33f9`. The 24 h-only change is kept.

## Review Focus

1. Dangling `objects.<x>_page` pointers after a mount. Expected: each is set to NULL right after `ui_mount_screen`, and no code reads it again.
2. Thai tone marks on the device. Expected: "ที่", "หรี่จอ" and "ปีนี้" show stacked marks, which proves the EEZ font files are not linked.
3. Theme. Expected: dark background, Thai-capable default font, no white flash at boot.
4. Swipe between pages. Expected: tiles snap and `lv_tileview_get_tile_act` works, including the page indicator and `ui_next_page`.
5. Regeneration safety. Expected: after re-running `eez build`, the firmware builds unchanged, with no hand edits lost.

---

### Task 1: Foundation (orchestrator, sequential)

**Files:**
- Modify: `examples/ntp_clock/fonts/gen_fonts.sh` (output `ui_font_digits_128.c`, `ui_font_digits_56.c`)
- Rename (regenerate): `fonts/font_digits_*.c` → `fonts/ui_font_digits_*.c`
- Modify: `examples/ntp_clock/thai_fonts.c` (wrappers named `ui_font_th_16/22/32`)
- Modify: `examples/ntp_clock/fonts.h` (declare `ui_font_*`)
- Modify: every `examples/ntp_clock/ui*.cpp` (rename `font_*` references to `ui_font_*`)
- Modify: `examples/ntp_clock/ui_internal.h`, `examples/ntp_clock/ui_common.cpp` (add the mount helper)
- Modify: `platformio.ini` (`[env:ntp_clock]` `build_src_filter`)
- Create: `examples/ntp_clock/eez/thaiclock.eez-project`, `eez/.gitignore`, `eez/fonts/OFL.txt`
- Modify: the scratchpad `compile_one.sh` (also compiles `.c` files)

**Interfaces:**
- Produces: `void ui_mount_screen(lv_obj_t *eez_screen, lv_obj_t *dst);`, which moves every child of `eez_screen` into `dst` (keeping x/y) and then deletes `eez_screen`.
- Produces: fonts `ui_font_digits_128`, `ui_font_digits_56`, `ui_font_th_16`, `ui_font_th_22`, `ui_font_th_32` (the same names inside EEZ: `digits_128`, `digits_56`, `th_16`, `th_22`, `th_32`).
- Produces: EEZ named colours `bg #05070A`, `panel #121820`, `panel_hi #1C2530`, `text #F2F4F7`, `text_dim #7D8794`, `ok #4ADE80`, `warn #FBBF24`, `err #F87171`, `night #C2341F`.

- [ ] Step 1: Run `gen_fonts.sh` with the new names. Expected: the five font files are regenerated and `font_th_*_base.c` is unchanged.
- [ ] Step 2: Rename the font references across `ui*.cpp`, `fonts.h` and `thai_fonts.c`, then run `pio run -e ntp_clock`. Expected: SUCCESS.
- [ ] Step 3: Create the EEZ project. Add the five fonts from Kanit TTF (`th_*` ranges `32-126,0x0E01-0x0E5B`, symbols `°·•–—…`; digits as in `gen_fonts.sh`), the colours, `obj set settings/build destinationFolder=gen`, and empty pages `clock_page calendar_page focus_page system_page portal_page splash_page`, each `$screen` with `bg_color=bg`. Then `build`. Expected: 0 errors.
- [ ] Step 4: Add `build_src_filter = +<*> -<eez/gen/ui.c> -<eez/gen/ui_font_*.c>` and the mount helper, then run `pio run -e ntp_clock`. Expected: SUCCESS.
- [ ] Step 5: Commit `build(ntp_clock): add EEZ project skeleton and font aliases`.

### Task 2: EEZ page designs (one implementer: the single project file cannot be edited in parallel)

**Files:**
- Modify: `examples/ntp_clock/eez/thaiclock.eez-project` (through EEZ MCP only)
- Generated: `examples/ntp_clock/eez/gen/*`

**Interfaces:**
- Consumes: Task 1 fonts and colours.
- Produces: in `gen/screens.h`, these `objects.*` names (positions and styles copied from the create functions at `a0b33f9`):
  - clock_page: `cont_clock_time`; `cont_clock_d0`..`cont_clock_d3`, each holding `label_clock_d<n>_a` and `label_clock_d<n>_b`; `label_clock_colon`, `label_clock_sec`, `label_clock_placeholder`, `label_clock_hint`; `panel_clock_info` holding `cont_clock_stripe`, `label_clock_wifi`, `label_clock_sat`, `label_clock_day`, `label_clock_date`, `label_clock_wx_icon`, `label_clock_wx_temp`, `label_clock_wx_text`; `bar_clock_seconds`
  - calendar_page: `cont_calendar_meter` (168x168 placeholder, meter stays in code), `label_calendar_date`, `label_calendar_years`, `label_calendar_doy`, `bar_calendar_year`, `label_calendar_year_pct`, `label_calendar_gift`, `label_calendar_holiday`
  - focus_page: `arc_focus_ring`, `label_focus_icon`, `label_focus_time`, `label_focus_mode`, `cont_focus_dot0`..`cont_focus_dot3`, `label_focus_hint`
  - system_page: `label_system_<row>_icon` and `label_system_<row>_text` for row in `wifi ip sync uptime battery city`; `cont_system_bar0`..`cont_system_bar3`; `label_system_dbm`; `label_system_sun`; `slider_system_brightness`; `label_system_night`; `switch_system_night`; `btn_system_wifi`; `btn_system_sync` (each button keeps its generated child label)
  - portal_page: `qrcode_portal_wifi` (150 px), `label_portal_title`, `label_portal_step1`..`label_portal_step3`, `label_portal_status`, `qrcode_portal_url` (100 px), `label_portal_url_caption`, `btn_portal_close`
  - splash_page: `label_splash_title`, `label_splash_subtitle`, `cont_splash_underline`, `spinner_splash`, `label_splash_status`

- [ ] Step 1: For each page, read its `*_create` function at `a0b33f9` and recreate the widgets with absolute positions (`git show a0b33f9:examples/ntp_clock/<file>`). Widgets the code moves or animates get `-SCROLLABLE`, and anything that clips gets the right `clip_corner`/overflow settings.
- [ ] Step 2: `eez_render` each page and compare it with the baseline screenshot. Expected: same geometry, and no `outside-screen` or `overflows-parent` issues except intended ones.
- [ ] Step 3: `eez_check` (0 errors), then `eez_build`. Compile `gen/screens.c` and `gen/styles.c` with `compile_one.sh`. Expected: 0 errors.
- [ ] Step 4: Commit `feat(ntp_clock): design all screens in EEZ Studio`.

### Task 3: Bind the pages to the EEZ objects (four parallel implementers, disjoint files)

**Files (one implementer each):**
- 3a: `ui.cpp` (theme, tileview, mount all pages, overlay containers on `lv_layer_top`), `ui_splash.cpp`, `ui_portal.cpp`
- 3b: `ui_page_clock.cpp`
- 3c: `ui_page_calendar.cpp`, `ui_page_focus.cpp`
- 3d: `ui_page_system.cpp`

**Interfaces:**
- Consumes: `objects.*` names from Task 2 and `ui_mount_screen` from Task 1.
- The `page_*_create(lv_obj_t *tile)` and `ui_portal_update` / `ui_splash_*` signatures in `ui_internal.h` are unchanged. `page_*_create` now runs after its page is mounted into `tile` and only binds: it attaches events, creates the code-only parts (the meter needles, toast and flash stay in code) and sets the initial state. The update functions keep their logic, swapping their static pointers for `objects.*`.
- 3a defines the order in `ui_init`: theme init → tileview and tiles → for each page `create_screen_X_page(); ui_mount_screen(objects.X_page, tile); objects.X_page = NULL; page_X_create(tile);`. Portal and splash are mounted into full-screen containers on `lv_layer_top`. The portal is shown and hidden instead of created and destroyed. The splash container is deleted when it closes, and the code then stops touching its objects.

- [ ] Step 1: Rewrite the create/bind code. The update logic is unchanged apart from the pointer source.
- [ ] Step 2: Run `compile_one.sh` on the owned files. Expected: 0 errors and 0 warnings from them.
- [ ] Step 3: Report the `file:line` of every behaviour change, which should be none, plus the overlay lifecycle changes (3a only).

### Task 4: Integrate, verify on hardware, ship (orchestrator)

- [ ] Step 1: Run `pio run -e ntp_clock -t upload`. Expected: SUCCESS.
- [ ] Step 2: Add a temporary framebuffer-dump hook, capture every page plus the portal, and compare against the baseline. Check each Review Focus item. Expected: visual parity, stacked Thai tone marks, dark theme, swipe works.
- [ ] Step 3: Remove the hook. Re-run `eez_build` and check `git diff --stat examples/ntp_clock/eez/gen` (Review Focus 5). Run a 3-minute serial stability check: one USB connection, no resets.
- [ ] Step 4: Update the README with a design-with-EEZ section, commit per task, and push the `eez-ui` branch to `dock` after confirmation.

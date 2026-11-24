# LongDeck Milestone 2 (Live Widgets) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deck pages show live Mac data. Stat widgets (CPU, RAM, GPU, temperature, network, disk, battery) update every second as a bar, a number or a sparkline. A volume widget moves and mutes the Mac's output volume and follows changes made on the Mac. A small clock shows the board's own time. When the Mac app is offline, every Mac-fed widget shows `--`.

**Architecture:**

- The Mac app samples stats at 1 Hz with a headless `StatsSampler` over a pluggable `StatsSource`. It sends a sealed `stats` frame only while the board reports a visible deck page.
- The app watches the default CoreAudio output device. It sends a `volume` frame on connect and on every change, and applies `slider` and mute `press` frames from the board.
- The layout JSON gains the widget types `stat`, `volume` and `clock`. They carry `"face":0` and get no face bitmap. The board draws them natively with LVGL and the repo fonts.
- The board parses stats and volume in a pure module (`deck_live`) that also keeps the 60-sample history, formats values and rate-limits the slider. It compiles in the `native_deck` test env.
- `net_task` keeps stats, history and volume in mutex-guarded snapshots with a version counter, like the M1 layout snapshot. The LVGL thread copies them when the version changes.

**Tech Stack:**

- Firmware: as M1 (Arduino-ESP32 2.0.17, LVGL 8.4, `links2004/WebSockets@2.6.1`, `bblanchon/ArduinoJson@7.2.1`, Unity on PlatformIO `native`). LVGL widgets used: `lv_bar`, `lv_slider`, `lv_chart` (all enabled in `lib/lv_conf.h`).
- Mac: Swift 6 package from M1, CommandLineTools toolchain, Swift Testing. New frameworks: IOKit (SMC, IOAccelerator, IOBlockStorageDriver, IOPowerSources), CoreAudio and AudioToolbox, Darwin `host_processor_info` / `host_statistics64` / `getifaddrs`.

**Spec:** `docs/superpowers/specs/2026-11-24-clock-deck-design.md`. This plan covers milestone 2. The Claude integration (`claude_*` widgets, permission overlay) and the editor are out of scope. `time_hint` is not used.

## Global Constraints

- Firmware code lives in `examples/ntp_clock/`. The Mac app lives in `mac/LongDeck/`. Do not modify `lib/`, `eez/`, or any file a task does not list.
- Edit files only with the Edit and Write tools. Never edit through Bash (`sed -i`, heredoc redirects, scripts).
- Comments: English, one line, at most about 10 words, only what the code cannot say. No file or class overview blocks. Do not add comments to code you did not change.
- **The board is not connected.** Verify firmware only with `pio run -e ntp_clock` and `pio test -e native_deck`. Every check that needs the device goes in the Hardware checklist at the end, which the owner runs later.
- **Never launch LongDeck.app** (`open build/LongDeck.app` or similar), and never set the system volume or mute from a test.
- Swift uses the CommandLineTools toolchain only. In this plan, `$SWIFT_TEST` means, run in `mac/LongDeck`:
  `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
  Add `--filter <Suite>` to run one suite. `swift build` checks the app target.
- No SwiftUI macros: no `@State`, `@Observable` or `#Preview`. Use `ObservableObject` and `@Published` as M1 does.
- `LongDeckCore` builds in Swift 6 language mode (strict concurrency). The app target stays in Swift 5 mode.
- The machine running the tests is the target Mac mini M4 Pro (Mac16,11, macOS 26.6, no battery). Tests may assert plausible live ranges on it.
- Grid and caps are unchanged and apply to every widget type: 8x2 cells of 80x90 px, widget at `(col*80+3, row*90+3)` sized `(w*80-6) x (h*90-6)`, 8 pages, 16 widgets per page (keys plus live widgets), ids at most 15 UTF-8 bytes and unique across all pages, page names at most 23 bytes, layout JSON at most 16 KB, and every WebSocket frame at most 15 360 bytes (`LayoutPushPolicy.maxWebSocketFrame`).
- Board colours come from the palette in `ui_internal.h`, and fonts only from `fonts.h`. No new fonts.

## Protocol additions (both sides implement exactly this)

Every new message is a sealed text frame under the M1 session rules. There are no new binary frames. `DECK_PROTO_VERSION` stays 1, because an M1 peer ignores message types it does not know.

| Dir | Type | Body | When |
| --- | --- | --- | --- |
| app→board | `stats` | stats object, below | Every 1 s while the board's last `page` index is ≥ 0 and no layout push is in flight |
| app→board | `volume` | `{"available":<bool>,"level":<0–100>,"muted":<bool>}` | Right after Ready, then on every change. An identical body is not sent twice in a row. |
| board→app | `slider` | `{"id":"<volume widget id>","value":<0–100>}` | While the volume slider is dragged, at most one per 100 ms (10 Hz). The last value of a drag is always sent. |
| board→app | `press` | `{"id":"<volume widget id>","kind":"tap"}` | The M1 press frame. On a volume widget it means "toggle mute". |
| board→app | `page` | `{"index":<n>}` | The M1 frame. The board now also sends it once right after `hello_state` on every Ready. |

Stats body fields:

| Field | Meaning | Range | Unknown |
| --- | --- | --- | --- |
| `cpu` | Busy share of all cores | 0–100 % | — |
| `ram` | (active + wired + compressed pages) / physical memory | 0–100 % | — |
| `gpu` | IOAccelerator `PerformanceStatistics` "Device Utilization %" | 0–100 % | — |
| `temp_c` | Hottest CPU die, SMC key `TCMz` | °C | `null` |
| `net_down_bps`, `net_up_bps` | Bytes per second, summed over up and running `en*` interfaces | ≥ 0 | — |
| `disk_free_pct` | Free share of `/` (important-usage capacity) | 0–100 % | — |
| `disk_io_bps` | Bytes read plus written per second, all `IOBlockStorageDriver`s | ≥ 0 | — |
| `battery` | Internal battery charge | 0–100 % | `-1` |

Encoding rules:

- The app sends integers. It rounds to nearest, clamps percentages to 0–100 and rates to ≥ 0, and writes keys sorted (`JSONSerialization` with `.sortedKeys`).
- The board accepts any JSON number, integer or float. It clamps percentages to 0–100 and rates to ≥ 0. `null`, a missing field or a non-number makes that metric unknown, and so does a negative `battery`. An unknown metric shows `--`.
- A stats or volume body that is not a JSON object, or is over 512 bytes, is ignored. The socket stays open and the previous values stay.

Layout JSON additions (M1 keys unchanged):

- `"type":"stat"` adds `"metric"` (`cpu`, `ram`, `gpu`, `temp`, `net_down`, `net_up`, `disk_free`, `disk_io`, `battery`) and `"style"` (`bar`, `number`, `sparkline`).
- `"type":"volume"` and `"type":"clock"` add nothing.
- Live widgets carry `"face":0` and no `"long"` key. The board ignores `face` and `long` on live widgets.
- On the board, a `stat` with a missing or unknown `metric` or `style` becomes a `DW_UNKNOWN` placeholder that still takes grid space, like any unknown type. The Mac config rejects it before it is ever sent.

Shared JSON examples. Both sides' tests use these strings byte for byte:

| Name | JSON |
| --- | --- |
| L1 | `{"hash":"0123456789abcdef","pages":[{"name":"Mac","widgets":[{"col":7,"face":1,"h":1,"id":"k1","long":false,"row":0,"type":"key","w":1},{"col":0,"face":0,"h":1,"id":"cpu","metric":"cpu","row":0,"style":"sparkline","type":"stat","w":2},{"col":2,"face":0,"h":1,"id":"vol","row":0,"type":"volume","w":3},{"col":5,"face":0,"h":1,"id":"clk","row":0,"type":"clock","w":2},{"col":0,"face":0,"h":1,"id":"tmp","metric":"temp","row":1,"style":"number","type":"stat","w":1}]}]}` |
| S1 | `{"battery":-1,"cpu":37,"disk_free_pct":58,"disk_io_bps":1048576,"gpu":12,"net_down_bps":125000,"net_up_bps":2048,"ram":62,"temp_c":67}` |
| S2 | `{"battery":-1,"cpu":0,"disk_free_pct":100,"disk_io_bps":0,"gpu":100,"net_down_bps":0,"net_up_bps":0,"ram":100,"temp_c":null}` |
| V1 | `{"available":true,"level":44,"muted":false}` |
| V2 | `{"available":false,"level":0,"muted":false}` |
| P1 | `{"id":"vol","value":55}` |
| P2 | `{"id":"vol","kind":"tap"}` |

L1 is what `LayoutBuilder` produces for the "L1 config" below, with the computed hash replaced by `0123456789abcdef`. The L1 config is one page named `Mac`:

- Key `k1` at col 7, row 0, 1x1, label `K`, background `#222222`, action `.shell("true")`, no long action.
- Live `cpu`: col 0, row 0, 2x1, `.stat(.cpu, .sparkline)`.
- Live `vol`: col 2, row 0, 3x1, `.volume`.
- Live `clk`: col 5, row 0, 2x1, `.clock`.
- Live `tmp`: col 0, row 1, 1x1, `.stat(.temp, .number)`.

Mac stats sources. Probed on this machine on 2026-11-24 with a throw-away C program, without root:

| Metric | Source | Finding on this Mac |
| --- | --- | --- |
| CPU | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` tick deltas; busy = user + system + nice | 12 CPUs |
| RAM | `host_statistics64(HOST_VM_INFO64)`; `active_count + wire_count + compressor_page_count` times the page size from `host_page_size(mach_host_self(), &size)`, over `ProcessInfo.physicalMemory` | 24 GB |
| GPU | First `IOAccelerator` service with `PerformanceStatistics` → `"Device Utilization %"` | Class `AGXAcceleratorG16X`, key present |
| Temp | `AppleSMC` user client, selector 2, key `TCMz`, type `flt ` (4-byte little-endian float) | 1734 keys. `TCMz` was 67.6 °C idle, equal to the hottest `Te0*` E-core sensor, and 74.1 °C under a 12-thread load, equal to the hottest `Tp0*` P-core sensor. `Tp0*` read a flat 40.0 while the P-cores idled, so do not average `Tp*` keys. `TCMb` ran about 4 °C lower. |
| Network | `getifaddrs`, `AF_LINK`, names starting `en`, `IFF_UP` and `IFF_RUNNING`, `if_data.ifi_ibytes` / `ifi_obytes` | Counters are 32-bit, so they wrap. Active: `en1`. `utun*` (VPN), `awdl0`, `bridge100` and `lo0` are excluded to avoid double counting. |
| Disk free | `URL(fileURLWithPath: "/")` resource values `volumeAvailableCapacityForImportantUsage` / `volumeTotalCapacity` | — |
| Disk I/O | Every `IOBlockStorageDriver` `Statistics` → `"Bytes (Read)"` + `"Bytes (Write)"` | 2 drivers, internal SSD plus external disk |
| Battery | `IOPSCopyPowerSourcesInfo`, type `kIOPSInternalBatteryType` | 0 power sources, so `battery` is -1 |
| Volume | Default output `kAudioHardwarePropertyDefaultOutputDevice`. Level: `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (output scope, main element). Mute: `kAudioDevicePropertyMute` (output scope, main element). | "Mac mini Speakers". Both properties present and settable. Volume 0.437 → level 44. |

## Review Focus

1. **Sequence order when live frames meet a layout push.** In M1, `DeckConnection` seals all chunks of a face, then awaits each send. A `stats` frame sealed in between gets a higher `s`, reaches the board first, and the board then closes the socket on the next lower `s`. Live frames must be skipped (stats) or held back (volume) while a push is in flight. Tests: Task 2 `statsSkippedDuringPush` and `volumeDeferredDuringPush`. Device check H7.
2. **Stats start after a reconnect without a swipe.** M1 drops `page` frames while not Ready, so after a reconnect the app would believe no deck page is visible and never send stats. The board re-sends `page` on Ready. Tests: Task 2 `statsOnlyWhileDeckPageVisible`. Device check H9.
3. **Slider drag never becomes a page swipe and never floods the link.** Tests: Task 1 `test_slider_rate_limit_vector`, `test_slider_at_most_10_per_second`, `test_slider_final_value_delivered`. Device check H5.
4. **Volume input is routed to the right widget.** A slider or tap for a volume widget id controls CoreAudio and never runs a key action. A slider for any other id is ignored. Tests: Task 2 `sliderOnVolumeWidgetSetsVolume`, `sliderForOtherIdsIgnored`, `tapOnVolumeWidgetTogglesMute`.
5. **Offline means `--`, never stale numbers.** When no client is Ready, the board drops the stats, history and volume snapshots, and every stat and volume widget shows `--`. A malformed body is ignored without closing the link. Tests: Task 1 `test_stats_malformed_keeps_out`. Device check H8.
6. **Sampler correctness on this Mac.** CPU, RAM, GPU, `TCMz`, network wrap and disk I/O give plausible values headless and without root. Tests: Task 3 `StatsSamplerTests` (fake source) and `MacStatsSourceTests` (live ranges).
7. **M1 configs keep working.** A `config.json` with only `pages[].keys[]` loads unchanged and builds the same widget JSON as before. Tests: Task 2 `m1ConfigLoadsUnchanged`.

---

### Task 1: Board live-widget logic (pure, native-tested)

**Files:**
- Modify: `examples/ntp_clock/deck_layout.h`, `examples/ntp_clock/deck_layout.cpp`
- Create: `examples/ntp_clock/deck_live.h`, `examples/ntp_clock/deck_live.cpp` (no Arduino or LVGL includes)
- Modify: `platformio.ini`. In `[env:native_deck]`, add `+<deck_live.cpp>` to `build_src_filter`.
- Test: `examples/ntp_clock/test/test_layout/test_main.cpp` (extend), `examples/ntp_clock/test/test_live/test_main.cpp` (new)

**Interfaces:**
- Produces in `deck_layout.h`:

```cpp
enum DeckWidgetType : uint8_t { DW_KEY = 0, DW_STAT = 1, DW_VOLUME = 2, DW_CLOCK = 3, DW_UNKNOWN = 255 };
enum DeckMetric : uint8_t { DM_CPU = 0, DM_RAM, DM_GPU, DM_TEMP, DM_NET_DOWN, DM_NET_UP, DM_DISK_FREE, DM_DISK_IO, DM_BATTERY, DM_COUNT };
enum DeckStatStyle : uint8_t { DS_BAR = 0, DS_NUMBER, DS_SPARKLINE, DS_COUNT };

struct DeckWidget {
  char id[16];
  uint8_t type, col, row, w, h;
  uint16_t face;
  bool has_long;
  uint8_t metric, style;  // DW_STAT only
};

int deck_metric_from_name(const char *name);  // -1 if unknown
int deck_style_from_name(const char *name);   // -1 if unknown
```

- Produces in `deck_live.h` (includes `deck_layout.h`):

```cpp
#define DECK_HISTORY_LEN     60
#define DECK_LIVE_BODY_MAX   512
#define DECK_SLIDER_MIN_MS   100
#define DECK_RATE_FLOOR_BPS  100000.0f

struct DeckStats      { float v[DM_COUNT]; uint16_t valid; };  // valid bit = 1 << metric
struct DeckVolume     { uint8_t level; bool muted; bool available; };
struct DeckHistory    { float v[DM_COUNT][DECK_HISTORY_LEN]; uint8_t head, count; };
struct DeckSliderGate { uint32_t last_ms; int16_t last_sent, pending; bool sent_once, has_pending; };

bool        deck_stats_parse(const char *json, size_t len, DeckStats *out);    // out untouched on false
bool        deck_volume_parse(const char *json, size_t len, DeckVolume *out);  // out untouched on false
void        deck_history_clear(DeckHistory *h);
void        deck_history_push(DeckHistory *h, const DeckStats *s);             // unknown values stored as NAN
uint8_t     deck_history_series(const DeckHistory *h, uint8_t metric, float out[DECK_HISTORY_LEN]);
float       deck_history_max(const DeckHistory *h, uint8_t metric);            // ignores NAN, 0 when empty
int         deck_live_level(uint8_t metric, float value, float rate_max);      // 0..100
void        deck_live_format(uint8_t metric, const DeckStats *s, char *val, size_t val_len, char *unit, size_t unit_len);
const char *deck_metric_label(uint8_t metric);
void        deck_slider_reset(DeckSliderGate *g);
bool        deck_slider_offer(DeckSliderGate *g, uint32_t now_ms, int value, int *out);
bool        deck_slider_poll(DeckSliderGate *g, uint32_t now_ms, int *out);
bool        deck_slider_body(const char *id, int value, char *out, size_t out_len);
```

  Behaviour required:
  - Layout parse: `stat`, `volume` and `clock` map to their `DW_*` values. A `stat` whose `metric` or `style` is missing or unknown becomes `DW_UNKNOWN`. Every live widget and every `DW_UNKNOWN` gets `face = 0` and `has_long = false`, whatever the JSON says. Geometry, overlap, id and cap checks stay as in M1 for every type.
  - `deck_history_series` writes up to 60 values, oldest first, and returns the count. `deck_history_push` with `count == 60` overwrites the oldest.
  - `deck_live_level`:
    - `cpu`, `ram`, `gpu`, `disk_free` and `battery`: the value rounded and clamped to 0..100.
    - `temp`: °C mapped 1:1, so 100 °C is a full bar.
    - `net_down`, `net_up` and `disk_io`: `value * 100 / max(rate_max, DECK_RATE_FLOOR_BPS)`, rounded and clamped.
    - NAN gives 0.
  - `deck_live_format`:
    - Unknown metric: `"--"` and an empty unit.
    - Percentages: `"%.0f"` with unit `"%"`. Temperature: `"%.0f"` with unit `"°C"`.
    - Rates: below 999.5 B/s use `B/s`, below 999 500 `KB/s`, below 999.5e6 `MB/s`, else `GB/s`, with base 1000. The scaled value uses `"%.1f"` below 9.95 and `"%.0f"` from there up. Bytes always use `"%.0f"`.
  - `deck_metric_label`: `CPU`, `RAM`, `GPU`, `TEMP`, `NET` + `"\xEF\x81\xB8"` (LV_SYMBOL_DOWN), `NET` + `"\xEF\x81\xB7"` (LV_SYMBOL_UP), `DISK`, `DISK I/O`, `BAT`. Join `NET` and the arrow with one space.
  - Slider gate:
    - `offer` sends at once if nothing was sent yet or at least `DECK_SLIDER_MIN_MS` have passed since the last send, and the value differs from the last sent one. Otherwise it stores the value as pending.
    - `poll` sends the pending value once `DECK_SLIDER_MIN_MS` have passed, unless it equals the last sent value.
  - `deck_slider_body` uses ArduinoJson (`id` first, then `value` clamped to 0..100). It returns false for an empty id or a buffer that is too small.

- [ ] **Step 1: Write the failing tests**

  In `test_layout/test_main.cpp` (keep every M1 test):
  - `test_parse_live_example`: L1 parses. There are 5 widgets. [0] is `DW_KEY` with face 1. [1] is `DW_STAT`, `DM_CPU`, `DS_SPARKLINE`, face 0. [2] is `DW_VOLUME`. [3] is `DW_CLOCK`. [4] is `DW_STAT`, `DM_TEMP`, `DS_NUMBER`.
  - `test_every_metric_and_style_name`: all 9 metric names and 3 style names map to their enum values, and `"fan"` and `""` give -1.
  - `test_stat_unknown_metric_is_placeholder`: `metric:"fan"` parses as `DW_UNKNOWN`. Overlapping it with another widget is still rejected.
  - `test_stat_missing_style_is_placeholder`.
  - `test_live_widget_face_and_long_ignored`: a `volume` with `"face":7,"long":true` gives face 0 and `has_long == false`.
  - `test_live_widgets_respect_grid`: a `volume` at col 7 with w 2 is rejected. A `clock` overlapping a key is rejected. A `stat` sharing an id with a key on another page is rejected.

  In `test_live/test_main.cpp`:
  - `test_stats_parse_s1`: every metric except battery is valid, with the S1 values. Battery is unknown.
  - `test_stats_parse_s2_null_temp`: temp is unknown. cpu is 0, gpu 100, disk_free 100.
  - `test_stats_accepts_float_and_clamps`: `{"cpu":12.5,"ram":150,"net_down_bps":-5}` gives cpu 12.5, ram 100 and net_down 0. Missing fields are unknown.
  - `test_stats_wrong_type_is_unknown`: `{"cpu":"x","gpu":true}` returns true with cpu and gpu unknown.
  - `test_stats_malformed_keeps_out`: `{"cpu":`, `[1,2]`, and a 513-byte body each return false, and a sentinel-filled `out` is unchanged (`memcmp`).
  - `test_volume_parse_v1_v2`: V1 gives `{44,false,true}`. V2 gives `available == false`.
  - `test_volume_missing_field_rejected`: `{"level":10,"muted":false}` and `{"level":"x","muted":false,"available":true}` return false. `level:150` gives 100.
  - `test_history_order_and_wrap`: push 65 samples with cpu = i. The series count is 60, `out[0] == 5`, `out[59] == 64`, and the max is 64.
  - `test_history_unknown_is_nan_and_ignored_by_max`: all-unknown temp samples give a max of 0, and every series value is NAN.
  - `test_history_clear`.
  - `test_level_percent_and_temp`: cpu 37→37, 120→100, -3→0. temp 67.4→67, 130→100.
  - `test_level_rates_use_floor_and_max`: net 50 000 with max 0 gives 50. With max 200 000 it gives 25. disk_io 1e6 with max 1e6 gives 100. NAN gives 0.
  - `test_format_vectors`, metric and value → value text and unit:

    | Metric | Value | Text | Unit |
    | --- | --- | --- | --- |
    | cpu | 37 | `37` | `%` |
    | temp | 67 | `67` | `°C` |
    | net_down | 0 | `0` | `B/s` |
    | net_down | 999 | `999` | `B/s` |
    | net_down | 999.6 | `1.0` | `KB/s` |
    | net_down | 2048 | `2.0` | `KB/s` |
    | net_down | 9960 | `10` | `KB/s` |
    | net_down | 125000 | `125` | `KB/s` |
    | net_down | 999999 | `1.0` | `MB/s` |
    | disk_io | 1048576 | `1.0` | `MB/s` |
    | net_up | 2.5e9 | `2.5` | `GB/s` |
    | battery | unknown | `--` | (empty) |
    | temp | unknown | `--` | (empty) |

  - `test_slider_rate_limit_vector`, as calls in order → result:
    - `offer(0,10)` → send 10
    - `offer(30,20)` → no
    - `offer(60,30)` → no
    - `poll(90)` → no
    - `poll(100)` → send 30
    - `offer(150,40)` → no
    - `poll(199)` → no
    - `poll(200)` → send 40
    - `poll(400)` → no
    - `offer(400,40)` → no
    - `offer(401,41)` → send 41
  - `test_slider_at_most_10_per_second`: offers at t = 0, 10, …, 990 with value = t/10, and polls every 30 ms. At most 10 sends happen in [0, 1000). A final `poll(1100)` sends 99.
  - `test_slider_final_value_delivered`: `offer(0,10)` sends. `offer(20,77)` does not. `poll(119)` does not. `poll(120)` sends 77.
  - `test_slider_body_p1`: `deck_slider_body("vol",55)` equals P1. 150 gives `"value":100`. An 8-byte buffer and an empty id return false.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `pio test -e native_deck -f test_live -f test_layout`. Expected: compile errors for the missing symbols.

- [ ] **Step 3: Implement**

  - Parse with ArduinoJson `JsonDocument`. `JsonVariantConst::is<float>()` is true for integer and float numbers.
  - Use `NAN` and `isnan` from `<math.h>`.
  - `deck_stats_parse` builds into a local `DeckStats` and copies it to `out` only on success.

- [ ] **Step 4: Run the tests and confirm they pass, then confirm the firmware still builds**

  Run: `pio test -e native_deck`. Expected: `test_crypto`, `test_proto`, `test_layout` and `test_live` all PASS.
  Run: `pio run -e ntp_clock`. Expected: SUCCESS.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): parse live widgets and stats on the board`

### Task 2: Mac live config, layout and link policy

**Files:**
- Modify: `mac/LongDeck/Sources/LongDeckCore/DeckConfig.swift`, `LayoutBuilder.swift`, `SampleConfig.swift`
- Create: `mac/LongDeck/Sources/LongDeckCore/LiveLink.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/DeckConfigTests.swift`, `LayoutBuilderTests.swift` (extend); `LiveLinkTests.swift` (new)

**Interfaces:**
- Produces in `DeckConfig.swift`:
  - `enum StatMetric: String, Codable, CaseIterable, Sendable { case cpu, ram, gpu, temp, netDown = "net_down", netUp = "net_up", diskFree = "disk_free", diskIO = "disk_io", battery }`
  - `enum StatStyle: String, Codable, CaseIterable, Sendable { case bar, number, sparkline }`
  - `enum LiveKind: Equatable, Sendable { case stat(StatMetric, StatStyle), volume, clock }`
  - `struct LiveWidgetConfig: Codable, Equatable, Sendable { var id: String; var col, row, w, h: Int; var kind: LiveKind }`, with `init(id:col:row:w:h:kind:)`.
    - Its JSON is flat: `{"id","type":"stat"|"volume"|"clock","metric"?,"style"?,"col","row","w","h"}`. `metric` and `style` are written only for `stat`.
    - Decoding an unknown `type`, or a `stat` without `metric` or `style`, throws `DecodingError`.
  - `PageConfig` gains `var live: [LiveWidgetConfig]`.
    - The init becomes `init(name: String, keys: [KeyConfig], live: [LiveWidgetConfig] = [])`, so every M1 call site compiles unchanged.
    - A custom `init(from:)` decodes a missing `live` as `[]`. Encoding stays synthesized.
  - Rename `maxKeysPerPage` to `maxWidgetsPerPage` (still 16). `validate()` applies the count, id rules, uniqueness, grid and overlap checks to keys and live widgets together. Messages say "widget".
- Produces in `LayoutBuilder.swift`:
  - Per page, keys come first, exactly as in M1, then live widgets in config order. A live widget is `["id","type","col","row","w","h","face":0]`, plus `metric` and `style` for `stat`, and no `long`.
  - Face ids and `faces` cover keys only.
  - The hash rule is unchanged: SHA-256 over the JSON without the hash, then the faces.
- Produces in `SampleConfig.swift`: `SampleConfig.dev` keeps the M1 `Dev` page and adds a second page `PageConfig(name: "Mac", keys: [], live: …)`:
  - Row 0: `cpu` `.stat(.cpu,.sparkline)` at col 0, w 2. `gpu` `.stat(.gpu,.sparkline)` at col 2, w 2. `ram` `.stat(.ram,.bar)` at col 4, w 2. `clock` `.clock` at col 6, w 2.
  - Row 1, all w 1 except volume: `temp` `.stat(.temp,.number)` at col 0. `netdown` `.stat(.netDown,.number)` at col 1. `netup` `.stat(.netUp,.number)` at col 2. `diskio` `.stat(.diskIO,.sparkline)` at col 3. `diskfree` `.stat(.diskFree,.bar)` at col 4. `volume` `.volume` at col 5, w 3.
  - No battery widget, because the Mac mini has none.
- Produces in `LiveLink.swift`:

```swift
public struct OutFrame: Equatable, Sendable { public let type: String; public let body: String }
public enum LiveCommand: Equatable, Sendable { case setVolume(Int), toggleMute }

public struct LiveLink: Sendable {
    public private(set) var page: Int          // -1 until the board reports a deck page
    public init()
    public mutating func reset()               // new connection: page -1, no push, no volume sent
    public mutating func pageChanged(_ index: Int)
    public mutating func pushStarted()
    public mutating func pushFinished() -> OutFrame?            // newest volume held back during the push
    public func statsFrame(body: String) -> OutFrame?           // nil unless page >= 0 and not pushing
    public mutating func volumeFrame(body: String) -> OutFrame? // nil if same as last sent; held while pushing
    public static func command(type: String, body: String, config: DeckConfig) -> LiveCommand?
}
```

  `command` rules:
  - `slider` with an `id` that names a `.volume` live widget and an integer `value` in 0...100 gives `.setVolume(value)`.
  - `press` with `kind == "tap"` on a `.volume` widget gives `.toggleMute`.
  - Anything else gives `nil`: a long press, another id, a key id, an out-of-range value, malformed JSON, or another type. The caller then falls through to `ActionRunner.handlePress` for `press` frames.

- [ ] **Step 1: Write the failing tests**

  - In `DeckConfigTests`, keep every M1 test and add:
    - `liveWidgetJSONIsFlat`: with `.sortedKeys`, `LiveWidgetConfig(id:"cpu",col:0,row:0,w:2,h:1,kind:.stat(.cpu,.sparkline))` encodes to `{"col":0,"h":1,"id":"cpu","metric":"cpu","row":0,"style":"sparkline","type":"stat","w":2}`. The `vol` widget from the L1 config encodes to `{"col":2,"h":1,"id":"vol","row":0,"type":"volume","w":3}`. Both decode back equal.
    - `liveWidgetDecodeRejectsBadInput`: `"type":"gauge"`, a `stat` without `style`, and `"metric":"fan"` each throw.
    - `m1ConfigLoadsUnchanged`: encode `SampleConfig.dev`, then delete every page's `live` key through `JSONSerialization`. Decoding gives `SampleConfig.dev` with every `live` emptied, and the `Dev` page builds the same widget dictionaries as before (all `type == "key"`, faces 1…16).
    - `validationCoversLiveWidgets`. Each of these is rejected:
      - a live widget outside the grid
      - a live widget overlapping a key
      - a live id equal to a key id on another page
      - a 16-byte live id
      - 10 keys plus 7 live widgets on one page

      16 mixed widgets pass.
    - `sampleMacPageHasEveryLiveKind`: the `Mac` page has `.volume`, `.clock`, all 3 styles, and every metric except `.battery`. `validate()` passes.
  - In `LayoutBuilderTests`, add:
    - `liveLayoutMatchesSharedExample`: build the L1 config with `stubRender`. `built.json` with `built.hash` replaced by `0123456789abcdef` equals L1. `built.faces.keys` is `[1]`.
    - `liveWidgetsChangeHash`: adding a clock to a config changes the hash.
    - `sampleLayoutFrameFitsBoard`: with `var sealer = FrameSealer(sessionKey: Data(count: 32))`, the byte count of `sealer.seal(type: "layout", body: LayoutBuilder.build(SampleConfig.dev, render: stubRender).json)` passes `LayoutPushPolicy.fits`.
  - In `LiveLinkTests` (new), use the L1 config:
    - `statsOnlyWhileDeckPageVisible`: a new link gives `nil`. After `pageChanged(0)` it gives `OutFrame(type: "stats", body: S1)`. After `pageChanged(-1)` it gives `nil`. `reset()` brings back `nil`.
    - `statsSkippedDuringPush`: page 0 and `pushStarted()` give `nil`. After `pushFinished()` it gives a frame.
    - `volumeDedupes`: V1 gives a frame. V1 again gives `nil`. V2 gives a frame. After `reset()`, V2 gives a frame.
    - `volumeDeferredDuringPush`: `pushStarted()`, then V1 and V2 both give `nil`. `pushFinished()` gives `OutFrame(type: "volume", body: V2)`. V2 afterwards gives `nil`.
    - `sliderOnVolumeWidgetSetsVolume`: `("slider", P1)` gives `.setVolume(55)`.
    - `sliderForOtherIdsIgnored`: id `cpu`, `k1` and `nope`, values 101 and -1, and the body `{` all give `nil`.
    - `tapOnVolumeWidgetTogglesMute`: P2 gives `.toggleMute`. `{"id":"vol","kind":"long"}` and `{"id":"k1","kind":"tap"}` give `nil`.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

  Keep `KeyConfig`, `DeckAction` and `FaceRenderer` unchanged.

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all suites pass, the 54 M1 tests included.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add live widgets to the mac config and layout`

### Task 3: Mac stats sampler

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `StatsSample.swift`, `StatsSampler.swift`, `MacStatsSource.swift`, `SMCReader.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/StatsSampleTests.swift`, `StatsSamplerTests.swift`, `MacStatsSourceTests.swift`

**Interfaces:**
- Produces:

```swift
public struct StatsSample: Equatable, Sendable {
    public var cpu, ram, gpu: Double            // 0...100
    public var tempC: Double?
    public var netDownBps, netUpBps: Double
    public var diskFreePct: Double
    public var diskIOBps: Double
    public var battery: Int                     // -1 = no battery
    public init(cpu:ram:gpu:tempC:netDownBps:netUpBps:diskFreePct:diskIOBps:battery:)
    public var jsonBody: String                 // integers, clamped, sorted keys, temp_c null when nil
}

public struct CPUTicks: Equatable, Sendable { public var busy: UInt64; public var total: UInt64 }
public struct NetCounters: Equatable, Sendable { public var rx: UInt32; public var tx: UInt32 }

public protocol StatsSource: AnyObject {
    func cpuTicks() -> CPUTicks?
    func memoryUsedPct() -> Double?
    func gpuUtilizationPct() -> Double?
    func temperatureC() -> Double?
    func netCounters() -> [String: NetCounters]   // per interface name
    func diskFreePct() -> Double?
    func diskIOBytes() -> UInt64?                 // cumulative read + write
    func batteryPct() -> Int?                     // nil = no battery
}

public struct StatsSampler {
    public init(source: StatsSource)
    public mutating func sample(now: TimeInterval) -> StatsSample   // now = monotonic seconds
}

public final class MacStatsSource: StatsSource {
    public static let temperatureKey = "TCMz"
    public init()
}

public final class SMCReader {
    public init?()                                // nil if AppleSMC cannot be opened
    public func readFloat(_ key: String) -> Double?   // "flt " keys only
}
```

  Behaviour required:
  - `StatsSampler`:
    - The first call returns cpu 0 and all rates 0.
    - `cpu = 100 * Δbusy / Δtotal`. When `Δtotal == 0`, it repeats the previous cpu value.
    - Network: for each interface name present in both readings, `Δ = cur &- prev` (UInt32 wrapping), summed over interfaces. An interface seen for the first time adds 0.
    - Disk I/O: `Δ = cur - prev` when `cur >= prev`, otherwise 0, because the driver set changed.
    - Rates divide by the elapsed `now` delta. A delta ≤ 0 gives rates of 0.
    - A `nil` level reading gives 0. `nil` temperature stays `nil`. A `nil` battery gives -1.
  - `jsonBody` rounds with `.rounded()`, clamps percentages to 0...100 and rates to ≥ 0, normalises any negative battery to -1, and uses `NSNull` for a missing temperature.
  - `SMCReader`:
    - Open `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))` with `IOServiceOpen(…, mach_task_self_, 0, &conn)`. Close it in `deinit`.
    - Talk to it with `IOConnectCallStructMethod(conn, 2, in, 80, out, &outSize)`, using an 80-byte `[UInt8]` buffer rather than a Swift struct. Offsets are in native byte order:
      - `key` UInt32 at 0
      - `keyInfo.dataSize` UInt32 at 28
      - `keyInfo.dataType` UInt32 at 32
      - `result` at 40
      - `data8` at 42
      - `data32` at 44
      - `bytes[32]` at 48
    - A key's four-character code is `c0<<24 | c1<<16 | c2<<8 | c3`.
    - First call with `data8 = 9` (get key info). Then call with `data8 = 5` (read) and `dataSize` set.
    - A non-zero `result`, or a type other than `flt `, gives `nil`. The value is `bytes[0..<4]` as a little-endian `Float32`.
  - `MacStatsSource` follows the "Mac stats sources" table in the Protocol section:
    - Free the `host_processor_info` array with `vm_deallocate(mach_task_self_, …)`.
    - Swift 6 mode rejects `vm_kernel_page_size` as shared mutable state, so use `host_page_size`. `HOST_VM_INFO64_COUNT` is a C macro, so compute it as `MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride`. Both were checked with `swiftc -swift-version 6`.
    - `temperatureC()` returns `TCMz` only inside 10...130, else `nil`.
    - `netCounters()` reads `ifa_data` as `if_data`.
    - Battery uses `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` / `IOPSGetPowerSourceDescription`, with `kIOPSCurrentCapacityKey * 100 / kIOPSMaxCapacityKey`.

- [ ] **Step 1: Write the failing tests**

  - `StatsSampleTests`:
    - `bodyMatchesS1`: `StatsSample(cpu: 36.6, ram: 62.4, gpu: 12.0, tempC: 67.4, netDownBps: 125_000.2, netUpBps: 2_048, diskFreePct: 57.5, diskIOBps: 1_048_576, battery: -1).jsonBody == S1`.
    - `bodyMatchesS2`: `(cpu: -0.2, ram: 100.4, gpu: 250, tempC: nil, netDownBps: 0, netUpBps: -1, diskFreePct: 100, diskIOBps: -3, battery: -7)` gives S2.
  - `StatsSamplerTests`, with a `FakeSource` class whose readings the test sets:
    - `firstSampleHasZeroRates`
    - `cpuPercentFromTickDeltas`: ticks `(100, 1000)` then `(350, 1500)` give cpu 50.
    - `netRateSumsInterfacesAndHandlesWrap`: `en0` rx goes from `UInt32.max - 999` to `1000` and `en1` rx from 0 to 1000, over 1 s. That gives 3000 B/s. Over 2 s it gives 1500.
    - `newInterfaceContributesZero`
    - `diskIORateAndCounterReset`: 1 000 000 → 3 000 000 over 2 s gives 1 000 000 B/s. A following drop to 500 gives 0.
    - `passesThroughLevelsAndBattery`: ram, gpu, temp and disk free pass through. Battery `nil` gives -1, and 80 gives 80.
  - `MacStatsSourceTests` (live, this Mac):
    - `smcReadsCpuTemperature`: `SMCReader()` is not nil, and `readFloat("TCMz")` is in 20...110.
    - `cpuTicksAdvance`: two reads 200 ms apart, and `total` grows.
    - `memoryUsedPlausible`: 5...100.
    - `gpuUtilizationReadable`: not nil, 0...100.
    - `netCountersListAnEnInterface`
    - `diskFreeAndIOReadable`: free in 1...100, and I/O bytes > 0.
    - `noBatteryOnThisMac`: `batteryPct() == nil`.
    - `samplerEndToEnd`: two samples 1 s apart (`try await Task.sleep(for: .seconds(1))`). Expect cpu in 0...100, ram in 5...100, tempC in 20...110, and battery -1. `jsonBody` parses to an object with exactly the 9 field names.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter Stats`. Expected: compile errors.

- [ ] **Step 3: Implement**

  `import IOKit`, `import IOKit.ps` and `Darwin`. Frameworks autolink, so do not modify `Package.swift`. If a live test fails on this machine, fix the source; do not widen the range.

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add mac stats sampler`

### Task 4: Mac volume control

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `VolumeState.swift`, `VolumeControl.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/VolumeTests.swift`

**Interfaces:**
- Produces:

```swift
public struct VolumeState: Equatable, Sendable {
    public var level: Int          // 0...100
    public var muted: Bool
    public var available: Bool
    public init(level: Int, muted: Bool, available: Bool)   // clamps level; available false stores (0, false, false)
    public static let unavailable: VolumeState              // (0, false, false), set field by field
    public var jsonBody: String                             // sorted keys
}

public enum VolumeError: Error, Equatable { case unavailable, status(Int32) }

@MainActor public protocol VolumeControl: AnyObject {
    func read() -> VolumeState
    func setLevel(_ level: Int) throws
    func setMuted(_ muted: Bool) throws
}

public extension VolumeControl {
    func toggleMute() throws                 // throws .unavailable when !available
    func setLevelUnmuting(_ level: Int) throws  // unmutes when level > 0, like the volume keys
}

@MainActor public final class CoreAudioVolume: VolumeControl {
    public init()
    public var onChange: (() -> Void)?       // main queue
    public func start()                      // installs listeners once
    public static func defaultOutputName() -> String?
}
```

  Behaviour required:
  - `read()` follows the Volume row of the "Mac stats sources" table. `available` is true only when `VirtualMainVolume` exists and is settable. `level = Int((scalar * 100).rounded())`. `muted` is false when the device has no mute property.
  - `setLevel` writes `Float32(level) / 100`, and `setMuted` writes `UInt32` 0 or 1. Each throws `.unavailable` when the property is missing or read-only, and `.status(err)` on an `OSStatus` failure.
  - `start()`:
    - Adds `AudioObjectAddPropertyListenerBlock` on `kAudioObjectSystemObject` for the default output device, plus listeners on the current device for `VirtualMainVolume` and `Mute`, all on `DispatchQueue.main`.
    - When the default device changes, it removes the old device's listeners (with the same block objects), attaches them to the new device, and calls `onChange`.
    - Block bodies hop with `MainActor.assumeIsolated`.
  - If the SDK lacks the `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` name, use the raw selector `0x766D7663` (`'vmvc'`).

- [ ] **Step 1: Write the failing tests**

  - `bodyMatchesV1AndV2`: `VolumeState(level: 44, muted: false, available: true).jsonBody == V1`, and `VolumeState.unavailable.jsonBody == V2`.
  - `stateClampsAndNormalises`: level 150 → 100 and -5 → 0. `(70, true, false)` equals `.unavailable`.
  - `toggleMuteFlips`: with a `@MainActor` `FakeVolume`, muted false → true → false.
  - `setLevelUnmuting`: when muted, `30` gives level 30 and unmuted. `0` keeps it muted.
  - `unavailableThrows`: a fake with `available == false` throws `.unavailable` from both helpers.
  - `coreAudioReadsDefaultOutput` (live, **read-only**): `read().level` is in 0...100. When `defaultOutputName() == "Mac mini Speakers"`, `available` is true. Never call `setLevel` or `setMuted` on `CoreAudioVolume` in any test.
  - Mark the suite `@MainActor`, because `VolumeControl` and `CoreAudioVolume` are main-actor isolated.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter VolumeTests`. Expected: compile errors.

- [ ] **Step 3: Implement with `import CoreAudio` and `import AudioToolbox`**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass, and the system volume is unchanged.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add coreaudio volume control`

### Task 5: Board link carries stats, volume and slider

**Files:**
- Modify: `examples/ntp_clock/deck_net.h`, `examples/ntp_clock/deck_net.cpp`

**Interfaces:**
- Consumes: Task 1 (`deck_live.h`).
- Produces in `deck_net.h` (which now includes `deck_live.h`):

```cpp
uint32_t deck_net_live_version();                              // bumps on stats, volume and link loss
bool     deck_net_stats(DeckStats *stats, DeckHistory *hist);  // false while offline or before first frame; hist may be NULL
bool     deck_net_volume(DeckVolume *out);                     // false while offline or before first frame
void     deck_net_slider(const char *id, uint8_t value);       // dropped when not ready
```

  Behaviour required:
  - `on_message` handles `stats`: on `deck_stats_parse` success, take the lock, store the stats, `deck_history_push`, mark stats valid and bump the live version. On failure, log `[deck] stats ignored` and keep the socket.
  - `volume` is handled the same way with `deck_volume_parse`.
  - Log `[deck] stats resumed` when a stats frame arrives after at least 3 s without one. Hardware check H9 relies on this line.
  - When `deck_net_loop` sees no Ready client after having one, it clears stats and volume validity, calls `deck_history_clear`, and bumps the live version.
  - `OutMsg` gains `kind == 2` (slider) with a `uint8_t value`. `drain_queue` builds its body with `deck_slider_body` and sends it as type `slider`.
  - `deck_net_page` now always stores the index in a locked `s_last_page` (initially -1). It still queues a frame only when Ready.
  - In `check_became_ready`, right after `hello_state`, send `page` with `{"index":s_last_page}`.
  - Everything else from M1 stays as it is.

- [ ] **Step 1: Implement the changes above**

- [ ] **Step 2: Build and run the native tests**

  Run: `pio run -e ntp_clock`. Expected: SUCCESS, and the app stays under 3 MB.
  Run: `pio test -e native_deck`. Expected: all four suites PASS.

- [ ] **Step 3: Commit**

  Message: `feat(longdeck): carry stats, volume and slider over the deck link`

### Task 6: Mac app streams stats and volume

**Files:**
- Modify: `mac/LongDeck/Sources/LongDeckApp/DeckConnection.swift`, `mac/LongDeck/Sources/LongDeckApp/AppModel.swift`

**Interfaces:**
- Consumes: `LiveLink`, `LiveCommand` and `OutFrame` (Task 2); `StatsSampler`, `MacStatsSource` and `StatsSample` (Task 3); `VolumeControl` and `CoreAudioVolume` (Task 4).
- Produces:
  - `DeckConnection`:
    - The init gains `volume: VolumeControl`.
    - `var isReady: Bool` (a sealer exists)
    - `func sendStats(_ sample: StatsSample)`
    - `func sendVolume(_ state: VolumeState)`
  - `AppModel` owns `let volume = CoreAudioVolume()` and a `StatsSampler(source: MacStatsSource())`.

  Behaviour required:
  - `DeckConnection` holds `private var link = LiveLink()`. Every live frame goes through one private `sendFrame(_ f: OutFrame)`, which seals and calls `task.send` with no `await` in between.
  - On `.ready`: `link.reset()`, then `sendVolume(volume.read())`.
  - `sendStats` sends `link.statsFrame(body: sample.jsonBody)` when it is non-nil. `sendVolume` does the same with `link.volumeFrame(body: state.jsonBody)`.
  - `page`: call `link.pageChanged(index)` and keep the M1 `onEvent(.pageChanged)`.
  - `slider` and `press`:
    - If `LiveLink.command(type:body:config:)` returns a command, run `.setVolume(n)` → `volume.setLevelUnmuting(n)` or `.toggleMute` → `volume.toggleMute()`. Report errors as `.actionFailed("Volume: …")`.
    - Otherwise, a `press` goes to `runner.handlePress` exactly as in M1.
  - Layout push:
    - Call `link.pushStarted()` once the sealed layout frame has passed `LayoutPushPolicy`, before it is sent. A refused frame never starts a push.
    - Number pushes with a generation counter. Only the current generation's task calls `link.pushFinished()` after its last face chunk, and sends the frame it returns.
  - `AppModel.start()`:
    - Set `volume.onChange` to send `volume.read()` through the current connection, then call `volume.start()`.
    - Start a 1 s repeating `Timer` that hops to the main actor. When `connection?.isReady == true` it takes one sample with `sampler.sample(now: ProcessInfo.processInfo.systemUptime)` and calls `sendStats`. When not Ready it does nothing.
  - Pass `volume` into every `DeckConnection`.
  - The CoreAudio echo of a slider change comes back through `onChange`, and `LiveLink` dedupes it.

- [ ] **Step 1: Implement the changes above**

- [ ] **Step 2: Build and test**

  Run: `cd mac/LongDeck && swift build`. Expected: SUCCESS with no new warnings in the edited files.
  Run: `$SWIFT_TEST`. Expected: all pass.
  Do not run `bundle.sh` or open the app.

- [ ] **Step 3: Commit**

  Message: `feat(longdeck): stream stats and volume from the mac app`

### Task 7: Board stat, volume and clock widgets

**Files:**
- Create: `examples/ntp_clock/ui_deck_live.cpp`
- Modify: `examples/ntp_clock/ui_page_deck.cpp`, `examples/ntp_clock/ui_internal.h`

**Interfaces:**
- Consumes: Task 1 (`deck_live.h`) and Task 5 (`deck_net_*`).
- Produces in `ui_internal.h`:

```cpp
void ui_live_reset();                                        // before deck tiles are cleaned
bool ui_live_create(lv_obj_t *tile, const DeckWidget *w);    // false for non-live types
void ui_live_update(const UiTick *t, bool ready);            // every UI tick
```

  Hooks in `ui_page_deck.cpp`:
  - `deck_rebuild` calls `ui_live_reset()` before the tiles are cleaned.
  - `key_create` starts with `if (ui_live_create(tile, w)) return;`. `DW_UNKNOWN` keeps the M1 placeholder rect.
  - `page_deck_update` calls `ui_live_update(t, ready)` after its ready handling.

  Behaviour required. All widgets:
  - The box is an `lv_obj` at the grid geometry, `COLOR_PANEL` with radius 8, like a key.
  - Every child except the slider and the mute button has `LV_OBJ_FLAG_CLICKABLE` cleared, so a swipe that starts on a widget still changes the page.
  - Up to `DECK_MAX_PAGES * DECK_MAX_WIDGETS` live widgets are kept in a static array.
  - Refresh stat and volume widgets when `deck_net_live_version()`, `ready` or `t->accent` changes. Copy the snapshot with `deck_net_stats(&stats, &hist)` and `deck_net_volume(&vol)` into static buffers.

  Stat widgets:
  - The metric label is `deck_metric_label`, in `ui_font_th_16` `COLOR_TEXT_DIM`, top-left at (6, 4).
  - Text is `deck_live_format`. Join value and unit with a space when the unit starts with a letter (`1.2 MB/s`), otherwise without one (`37%`, `67°C`).
  - When `!ready` or the metric is unknown, the text is `--`, a bar is 0, and a chart's points are all `LV_CHART_POINT_NONE`.
  - `number`:
    - The value is centred, 8 px below the middle, in `COLOR_TEXT`. The unit uses `ui_font_th_16` `COLOR_TEXT_DIM`: to the right of the value at its bottom when w ≥ 2, under it when w == 1.
    - The value font is fixed at build time. Pick the first of `ui_font_digits_56` (only when w ≥ 2), `ui_font_th_32` and `ui_font_th_22` whose `lv_txt_get_size` width of the widest value text fits in the box width minus 12. The widest text is `100` for percentages and temperature and `888` for rates. The unit is a separate label.
  - `bar`:
    - An `lv_bar` 0..100, 10 px high, as wide as the box minus 12, at the bottom (0, -8). The background is `COLOR_PANEL_HI` and the indicator `t->accent`. Its value is `deck_live_level(metric, value, deck_history_max(&hist, metric))`.
    - The text uses `ui_font_th_22`, top-right (-6, 2) when w ≥ 2 and centred when w == 1.
  - `sparkline`:
    - An `lv_chart` of type `LV_CHART_TYPE_LINE`, `DECK_HISTORY_LEN` points, y range 0..100, no division lines, point size 0, line width 2 in `t->accent`, transparent background.
    - It fills the box below the label: (box width - 12) x (box height - 34), bottom (0, -6).
    - Points come from `deck_history_series`, right-aligned. Missing or NAN points are `LV_CHART_POINT_NONE`. Each point is `deck_live_level` against the history max.
    - The text uses `ui_font_th_16`, top-right (-6, 4).

  Volume widget:
  - The mute button is a clickable `lv_obj`. Its square side is the smaller of (box height - 12) and 56. It holds a `ui_font_th_22` label with `LV_SYMBOL_MUTE` when muted, else `LV_SYMBOL_VOLUME_MAX`.
  - When w ≥ 2:
    - The button sits left-middle at (6, 0). The level label (`ui_font_th_16`) sits top-right.
    - An `lv_slider` 0..100, 12 px high, fills the rest of the width to the right of the button. Copy `ui_page_system.cpp:274-275`: `lv_obj_clear_flag(slider, LV_OBJ_FLAG_SCROLL_CHAIN)` and `lv_obj_set_ext_click_area(slider, 14)`. This stops a drag from scrolling the tileview.
  - When w == 1: there is no slider. The button sits top-middle and the level label bottom-middle.
  - Slider events:
    - `LV_EVENT_VALUE_CHANGED` and `LV_EVENT_RELEASED` call `deck_slider_offer(&gate, lv_tick_get(), value, &out)`. Every tick calls `deck_slider_poll`.
    - Each send goes out with `deck_net_slider(id, out)`. Call `deck_slider_reset` when the widget is created.
  - An incoming level is applied only while `!lv_slider_is_dragged(slider)`, like `ui_page_system.cpp:145`.
  - Mute button `LV_EVENT_SHORT_CLICKED` calls `deck_net_press(id, false)`, only when ready, the volume is known and it is available.
  - Display states:
    - Muted: the slider indicator is `COLOR_TEXT_DIM`, otherwise `t->accent`.
    - Offline or volume unknown: the slider gets `LV_STATE_DISABLED` and the label reads `--`.
    - `available == false`: the slider is hidden and the label reads `unavailable`.

  Clock widget:
  - `%02d:%02d` from `t->now.tm_hour` and `t->now.tm_min`, centred, in `t->accent`.
  - The font is chosen with the same rule as stat numbers, with widest text `88:88`.
  - It updates on `t->new_second`, on creation and on accent change. It shows `--:--` while `!t->time_valid`.
  - It ignores the Mac link: the time comes from the board's NTP clock, so the clock keeps working while the Mac is offline.

- [ ] **Step 1: Implement the files above**

- [ ] **Step 2: Build and run the native tests**

  Run: `pio run -e ntp_clock`. Expected: SUCCESS. Note RAM and flash use in the commit body.
  Run: `pio test -e native_deck`. Expected: PASS.

- [ ] **Step 3: Commit**

  Message: `feat(longdeck): render stat, volume and clock widgets`

### Task 8: Docs

**Files:**
- Modify: `examples/ntp_clock/README.md`. In the LongDeck section, add "Live widgets": the three widget types, `--` while the Mac is offline, the clock running on board time, the slider and the mute tap.
- Modify: `mac/LongDeck/README.md`. In the Config section, document `pages[].live[]` with the flat JSON shape, the metric and style names, the 16-widgets-per-page cap shared with keys, and the `Mac` sample page. Note that temperature reads SMC `TCMz` without root and that battery shows `--` on a Mac without one. Show one example:
  `{"id":"cpu","type":"stat","metric":"cpu","style":"sparkline","col":0,"row":0,"w":2,"h":1}`.

- [ ] **Step 1: Write the sections above.** Keep each to one short paragraph plus the example.

- [ ] **Step 2: Commit**

  Message: `docs(longdeck): document live widgets`

## Hardware checklist (owner, after all tasks)

Agents do not run this. The board must be on USB (find the port by serial `74:4D:BD:88:D5:C0`) and powered as in M1.

- [ ] **H1 Flash.** `pio run -e ntp_clock -t upload`. The clock pages look and behave as before: Thai text, swipe, night mode, Wi-Fi portal, web settings.
- [ ] **H2 Config.** Move the M1 config aside so the app writes the new sample: `mv ~/Library/Application\ Support/LongDeck/config.json{,.m1}`. Build with `LONGDECK_SIGN_ID="LongDeck Dev" ./scripts/bundle.sh` and open the app. Within 5 s the board has a second deck page, `Mac`.
- [ ] **H3 Values.** On the `Mac` page, all values appear within 2 s:
  - CPU is within about 10 points of Activity Monitor.
  - RAM is close to Activity Monitor's "Memory Used" share.
  - TEMP reads 40–90 °C and rises under `yes > /dev/null` ×12 (stop it with `pkill -x yes`).
  - Sparklines scroll every second.
- [ ] **H4 Rates.**
  - A large download raises NET ↓, and the unit steps KB/s → MB/s.
  - `dd if=/dev/zero of=/tmp/ld bs=1m count=2000 && rm /tmp/ld` raises DISK I/O.
- [ ] **H5 Volume.**
  - Dragging the slider changes the Mac volume (Control Centre).
  - A drag on the slider never swipes the page. A swipe that starts on the widget background does.
  - Changing the volume with the Mac keyboard moves the board slider within 1 s.
  - Tapping the speaker icon mutes and unmutes, and the icon follows.
- [ ] **H6 No volume control.** If an output without volume control (some HDMI or USB devices) is available, select it. The widget shows "unavailable". Switching back restores it.
- [ ] **H7 Push during stats.** With the `Mac` page visible, edit a key label in `config.json`. The face updates and the link stays up: the serial log shows no `dropped`, and the menu stays "Connected".
- [ ] **H8 Offline.**
  - Quit the app. Within 15 s the "Mac offline" badge shows, every stat and volume widget shows `--`, and the clock keeps ticking.
  - Relaunch. Values return without pairing, and the layout is not resent.
- [ ] **H9 Page gating.**
  - Swipe to the Clock page for 10 s, then back. The serial log shows `[deck] stats resumed` once.
  - Quit and relaunch the app while the `Mac` page stays visible. Values return without a swipe.
- [ ] **H10 Battery.** Add `{"id":"bat","type":"stat","metric":"battery","style":"number","col":7,"row":0,"w":1,"h":1}` to a free cell. It shows `--` on the Mac mini.
- [ ] **H11 Endurance.** Leave the `Mac` page visible for 30 min. There are no resets or brownouts in the serial log, and the values keep moving.

## Execution order

- Wave 1 (parallel): Task 1, Task 2, Task 3, Task 4.
- Wave 2 (parallel): Task 5, Task 6.
- Wave 3 (parallel): Task 7, Task 8.
- Then the owner runs the Hardware checklist.

Notes:
- Tasks 2, 3 and 4 add files to the same `LongDeckCore` target. A half-written file in one breaks `swift test` for the others, and SwiftPM locks `.build`. Run them in separate git worktrees (`isolation: worktree`) and merge each one after its tests pass. Their files do not overlap. Without worktrees, run them one after another.
- Task 5 and Task 7 are sequential because Task 7 needs Task 5's `deck_net.h` functions to link.
- No two tasks share a file. `platformio.ini` belongs to Task 1 only.

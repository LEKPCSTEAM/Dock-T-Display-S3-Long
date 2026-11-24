# LongDeck Milestone 4 (Editor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The owner designs every custom deck page in a SwiftUI editor window instead of hand-editing `config.json`. The editor has a pages list, a canvas at the board's aspect ratio with the 8x2 grid, a widget palette (drag onto the grid, or click to add), whole-cell move and resize, and an inspector for label, icon, colours, action and an optional long-press action. It also has an app picker that sets the key icon automatically, a hotkey recorder, a live preview that is pixel-identical to the board for key faces, undo/redo, and Save, which validates, writes `config.json` atomically and pushes to the board. Closing or quitting with unsaved changes asks Save / Don't Save / Cancel.

**Architecture:**

- All editing logic is a pure, value-type `EditorModel` in `LongDeckCore`. It holds the document (a `DeckConfig`), the current page and the selection. It also places, moves and resizes widgets in whole cells, checking bounds and collisions. It manages pages, generates ids that meet the byte limits, and keeps an undo/redo stack, a dirty flag and per-widget validation issues. Unit tests cover all of it.
- A new SwiftUI library target `LongDeckEditor` holds the views and one `ObservableObject` (`EditorStore`) that wraps `EditorModel`. The views stay thin: they read the store and call its methods. Because the views live in a library, tests can render them offscreen to PNG files for review.
- The app target only wires things up. `EditorWindowController` hosts `EditorView` in an AppKit `NSWindow`, because a SwiftUI `Window` scene cannot refuse to close. `AppModel` gains `saveFromEditor` and a write guard, so its own file watcher does not reload and push the file the editor just wrote. The menu gains "Edit layout…".
- Key faces in the canvas are made from the exact bytes the board receives (`FaceRenderer.render`, RGB565 + A8). They are decoded and blended over the board's key colour with LVGL's own mix formula. Live widgets get a simple placeholder drawing.

**Tech Stack:** The Swift 6 package from M1–M3 (`mac/LongDeck`), CommandLineTools toolchain (Swift 6.4, macOS 26 SDK), Swift Testing, SwiftUI hosted in AppKit (`NSHostingView`), AppKit (`NSEvent` local monitor, `NSWorkspace` icons, `NSOpenPanel`, `NSAlert`). There is no firmware change in this milestone.

**Spec:** `docs/superpowers/specs/2026-11-24-clock-deck-design.md`, the "Editor" bullets under "Mac app" and milestone 4. M1–M3 behaviour (protocol, board, actions, live widgets, Claude integration) does not change.

## Global Constraints

- The Mac app lives in `mac/LongDeck/`. Do not modify `examples/` (except the README in Task 11), `lib/`, `eez/`, or any file a task does not list.
- Edit files only with the Edit and Write tools. Never edit through Bash (`sed -i`, heredoc redirects, scripts).
- Comments: English, one line, at most about 10 words, only what the code cannot say. No file or class overview blocks. Do not add comments to code you did not change.
- **Never launch LongDeck.app** (`open build/LongDeck.app`, `swift run`, or similar). It pops Local Network, Accessibility and Automation prompts. Do not run `./scripts/bundle.sh`; the owner does that in the checklist.
- **Never put a window on screen from a test or a script.** No test calls `orderFront`, `makeKeyAndOrderFront`, `NSApp.activate`, `setActivationPolicy` or `runModal`. Snapshot tests use the offscreen harness below.
- **Never touch the real `~/Library/Application Support/LongDeck/config.json`.** No test constructs `AppModel` or `EditorWindowController`. Every file test works in `FileManager.default.temporaryDirectory/longdeck-tests-<UUID>`.
- Swift uses the CommandLineTools toolchain only. In this plan, `$SWIFT_TEST` means, run in `mac/LongDeck`:
  `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
  Add `--filter <Suite>` to run one suite. `swift build` checks the app target.
- **No SwiftUI macros**, because the toolchain cannot expand them (the Xcode license is not accepted): no `@State`, `@Observable`, `@Entry` or `#Preview`. Use `ObservableObject` + `@Published` with `@StateObject` / `@ObservedObject` (as `PairView` does with `CodeInput`). Plain property wrappers that typecheck with this toolchain (verified 2026-11-25): `@Published`, `@StateObject`, `@ObservedObject`, `@Binding`, `@Environment`, `@NSApplicationDelegateAdaptor`. Transient view state (drag ghosts, search text, sheet flags) goes in a small `ObservableObject` owned with `@StateObject`. Do not use `@GestureState` or `@FocusState`.
- `LongDeckCore` builds in Swift 6 language mode (strict concurrency), so every new core type is `Sendable`. `LongDeckEditor`, `LongDeckEditorTests` and the app target build in Swift 5 mode.
- Grid, caps and frame limits are unchanged:
  - 8x2 cells of 80x90 px. A widget sits at `(col*80+3, row*90+3)` with size `(w*80-6) x (h*90-6)`.
  - At most 8 pages and 16 widgets per page (keys plus live widgets).
  - Ids are non-empty, at most 15 UTF-8 bytes, and unique across all pages. Page names are at most 23 UTF-8 bytes.
  - `claude_sessions` needs `w ≥ 2`.
  - The sealed `layout` frame is at most 15 360 bytes (`LayoutPushPolicy.maxWebSocketFrame`).
- Board colours used by the editor (from `examples/ntp_clock/ui_internal.h`): `COLOR_BG #05070A`, `COLOR_PANEL #121820`, `COLOR_PANEL_HI #1C2530`, `COLOR_TEXT #F2F4F7`, `COLOR_TEXT_DIM #7D8794`, `COLOR_OK #4ADE80`, `COLOR_WARN #FBBF24`, `COLOR_ERR #F87171`. On the board a key is a `COLOR_PANEL` box with radius 8, and the face bitmap is centred on it at the same size.

## Offscreen snapshot harness (verified on this Mac, 2026-11-25)

Every view task proves itself with PNG files that a reviewer opens with the Read tool. The recipe was spiked with this exact toolchain in a scratch package under `/Users/lek/.claude/jobs/1fd8bef7/tmp/m4-spike`. It works inside `swift test` with Swift Testing, `@MainActor` tests and a Swift 5 library target.

1. Call `_ = NSApplication.shared`. The activation policy stays `.prohibited` (raw value 2), so no Dock icon and no prompt appears.
2. Build `NSHostingView(rootView:)` with the wanted frame. Put it in `NSWindow(contentRect:, styleMask: [.titled], backing: .buffered, defer: false)` and set `window.appearance = NSAppearance(named: .darkAqua)` and `window.contentView = host`. Never order the window front.
3. Call `host.layoutSubtreeIfNeeded()` and `window.displayIfNeeded()`, then `RunLoop.main.run(until: Date().addingTimeInterval(0.3))`.
4. Capture from the window's frame view, `host.superview!`. The rect is `host.convert(host.bounds, to: frameView)`. Use `bitmapImageRepForCachingDisplay(in:)` and then `cacheDisplay(in:to:)`. Capturing `host` itself leaves AppKit-backed controls (Toggle, Button, Picker, ColorPicker) blank. The frame view draws them.
5. Encode with `rep.representation(using: .png, properties: [:])`. Pixel size is twice the point size (Retina backing).

`ImageRenderer` cannot draw AppKit-backed controls, so do not use it. Snapshot suites are `@Suite(.serialized)` and every snapshot test is `@MainActor`.

`$SNAP_DIR` means `/Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots`. A snapshot test writes its PNG only when the environment variable `LONGDECK_SNAPSHOT_DIR` is set. Without it, the test still renders and runs its assertions.

## Config file changes

- `KeyConfig` gains an optional `foreground` (`"#RRGGBB"`). It sets the label colour and the SF Symbol tint. `nil` means white, exactly as today. Synthesized `Codable` omits it when `nil`, so M1–M3 files load unchanged and re-encode without the key.
- `config.json` is written with `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` plus a trailing newline. Paths read `"/Applications/iTerm.app"` instead of `"\/Applications\/iTerm.app"`. The decoded config is identical.
- A hotkey that has not been recorded yet uses `keyCode` `65535` (`ActionKind.unsetKeyCode`). The editor never saves it, because it is an error (see Task 5).
- Nothing else changes. The layout JSON sent to the board, the face format and the protocol are as in M3.

## Review Focus

1. **M1–M3 keep working byte for byte.** A config without `foreground` decodes and builds the same layout. `FaceRenderer` output for existing keys is unchanged, so the layout hash is unchanged and the board does not re-download faces after the upgrade. Tests: Task 1 `facesUnchangedForExistingKeys`, `layoutHashUnchangedForSample`, `foregroundIsOptionalInJSON`, and all existing suites.
2. **The editor can never save what the loader or the board rejects.** Editor errors cover every `DeckConfig.validate()` rule plus the sealed frame size, the action values and the colour format. `ConfigSaver.prepare` checks validation and frame size again before writing. Tests: Task 4 `sevenFullStatPagesTooLarge`, Task 5 `errorsCoverValidate`, `tooLargeLayoutIsError`.
3. **No double push, no lost edits.**
   - The watcher skips a file whose bytes equal the editor's last write (`ConfigWriteGuard`).
   - `DeckConnection.push` already skips a layout whose hash the board has.
   - An outside change replaces the editor document only when the editor is clean.

   Tests: Task 4 `writeGuardMatchesOwnBytes`, Task 5 `externalChangeRules`. Live check E8.
4. **Unsaved changes are never dropped silently.** Window close and app termination both ask Save / Don't Save / Cancel. Dirty means "differs from the saved baseline", so undoing back to the saved state is clean. Tests: Task 5 `dirtyFollowsSavedBaseline`. Live checks E9, E10.
5. **The hotkey recorder never leaks its key monitor and never eats keys when idle.** Tests: Task 8 `HotkeyRecorderFieldTests`.
6. **Byte limits hold for Thai and emoji.** Ids and page names are cut at grapheme boundaries. Tests: Task 2 `prefixIsGraphemeSafe`, `idsFitFifteenBytes`; Task 5 `pagesAddRemoveMoveRename`.
7. **Agents never show UI.** The snapshot harness never orders a window front. No test touches `AppModel`, the real config or the real Keychain.

---

### Task 1: Config foreground colour, readable file output, face preview

**Files:**
- Modify: `mac/LongDeck/Sources/LongDeckCore/DeckConfig.swift`, `mac/LongDeck/Sources/LongDeckCore/FaceRenderer.swift`
- Create: `mac/LongDeck/Sources/LongDeckCore/HexColor.swift`, `mac/LongDeck/Sources/LongDeckCore/FacePreview.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/DeckConfigTests.swift`, `FaceRendererTests.swift`, `LayoutBuilderTests.swift` (extend); `HexColorTests.swift`, `FacePreviewTests.swift` (new)

**Interfaces:**
- In `DeckConfig.swift`:
  - `KeyConfig` gains `public var foreground: String?`. Its public `init` gains a trailing parameter `foreground: String? = nil`, so every existing call site compiles unchanged. Keep synthesized `Codable`.
  - `DeckConfig` gains `public func fileData() throws -> Data`. It encodes with `JSONEncoder` and `outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`, then appends `"\n"`.
  - `save(to:)` becomes `@discardableResult public func save(to url: URL) throws -> Data`. It creates the folder as today, writes `fileData()` with `.atomic`, and returns the bytes written.
- `HexColor.swift`:

```swift
public enum HexColor {
    public static func parse(_ s: String) -> (r: UInt8, g: UInt8, b: UInt8)?  // exactly "#" + 6 hex digits, any case
    public static func format(r: UInt8, g: UInt8, b: UInt8) -> String         // "#RRGGBB", uppercase
    public static func from(_ color: NSColor) -> String?                       // via .sRGB, rounded; nil if not convertible
    public static func nsColor(_ s: String) -> NSColor?                        // sRGB, nil when parse fails
}
```

- `FacePreview.swift`:

```swift
public enum FacePreview {
    public static let panel565: UInt16 = 0x10C4   // COLOR_PANEL #121820 as RGB565
    public static func expand(_ rgb565: UInt16) -> (r: UInt8, g: UInt8, b: UInt8)
    public static func mix(_ fg: UInt16, _ bg: UInt16, alpha: UInt8) -> UInt16
    public static func composite(face: Data, width: Int, height: Int) -> [UInt8]   // RGBA8888, opaque, top row first
    public static func image(face: Data, width: Int, height: Int) -> CGImage?
    public static func image(for key: KeyConfig) -> CGImage?                       // render + composite
    public static func cacheKey(_ key: KeyConfig) -> String
}
```

Behaviour required:
- `FaceRenderer.draw` uses `HexColor.nsColor(foreground)` for the label colour and the symbol tint when `foreground` parses. Otherwise it keeps today's `NSColor.white` code path, unchanged. App icons are never tinted.
- `FacePreview.expand` uses bit replication: `r8 = r5<<3 | r5>>2`, `g8 = g6<<2 | g6>>4`, `b8 = b5<<3 | b5>>2`.
- `FacePreview.mix` mirrors LVGL 8.4's software blend for this build (16-bit colour, `LV_COLOR_MIX_ROUND_OFS` 128 from `lib/lv_conf.h`):
  - `alpha < 3` gives `bg`, and `alpha > 252` gives `fg`.
  - Otherwise, for each of the 5/6/5-bit channels, `c = ((fg_c * a + bg_c * (255 - a) + 128) * 0x8081) >> 23`.
- `composite` reads the face as `FaceRenderer.render` writes it: 3 bytes per pixel, `[rgb565 >> 8, rgb565 & 0xFF, alpha]`, rows top first. Each pixel becomes `expand(mix(face565, panel565, alpha))` with alpha byte 255.
- `image(face:…)` wraps `composite` in a `CGImage`: sRGB, 8 bits per component, `CGImageAlphaInfo.noneSkipLast`. `image(for:)` uses `FaceRenderer.faceSize` and `FaceRenderer.render(key)`.
- `cacheKey` is a string built from `w`, `h`, `label`, `icon`, `background` and `foreground` only. Use `JSONEncoder` with `.sortedKeys` on a private `Codable` struct of those fields. Two keys that differ only in `id`, `col`, `row`, `action` or `longAction` give the same key.

- [ ] **Step 1: Capture the regression goldens on the unmodified code**

  - In `FaceRendererTests`, add `facesUnchangedForExistingKeys`. It takes the `DeckCrypto.hex(DeckCrypto.sha256(FaceRenderer.render(k)))` of two keys:
    - `SampleConfig.dev` key `spotlight` (symbol `magnifyingglass`, `#444B6E`)
    - `KeyConfig(id: "g", col: 0, row: 0, w: 2, h: 1, label: "Golden ทดสอบ", icon: nil, background: "#222222", action: .shell("true"), longAction: nil)`
  - In `LayoutBuilderTests`, add `layoutHashUnchangedForSample`: `LayoutBuilder.build(SampleConfig.dev, render: stubRender).hash`.
  - Write each expectation with a placeholder string, run `$SWIFT_TEST --filter "FaceRendererTests|LayoutBuilderTests"` **before changing any source file**, and paste the actual values from the failure output into the tests. Re-run and see them pass. These three values must not change for the rest of the milestone.

- [ ] **Step 2: Write the failing tests**

  - `DeckConfigTests`:
    - `foregroundIsOptionalInJSON`:
      - With `.sortedKeys`, a key with `foreground: nil` encodes without a `"foreground"` key.
      - `foreground: "#FF0000"` round-trips.
      - The M3 key JSON `{"action":{"shell":{"_0":"true"}},"background":"#333333","col":0,"h":1,"id":"a","label":"a","row":0,"w":1}` decodes with `foreground == nil`.
    - `fileDataIsReadable`:
      - `SampleConfig.dev.fileData()` contains `"/Applications/iTerm.app"`, contains no `\/`, contains `"\n  "`, and ends with `"\n"`.
      - It decodes back equal to `SampleConfig.dev`.
    - `saveReturnsWrittenBytes`: in a temp dir, the returned `Data` equals the file contents.
  - `HexColorTests`:
    - `parse("#1F3A5F")` and `parse("#1f3a5f")` both give `(31, 58, 95)`.
    - `"1F3A5F"`, `"#12345"`, `"#GG0000"` and `"#1F3A5F0"` give nil.
    - `format(r: 31, g: 58, b: 95) == "#1F3A5F"`.
    - `from(NSColor(srgbRed: 31/255, green: 58/255, blue: 95/255, alpha: 1)) == "#1F3A5F"` and `from(NSColor.white) == "#FFFFFF"`.
    - `nsColor("#FF0000")` gives an sRGB red, and `nsColor("red")` gives nil.
  - `FaceRendererTests`:
    - `foregroundChangesLabelPixels`: the golden label key with `foreground: "#FF0000"` renders different bytes. Some pixel in the bottom 22 rows has red > 200 and green < 80 after `FacePreview.expand`.
    - `foregroundTintsSymbols`: the `spotlight` key with `foreground: "#00FF00"` differs from the golden.
  - `FacePreviewTests`:
    - `expandReplicatesBits`: `0xF800 → (255,0,0)`, `0x07E0 → (0,255,0)`, `0x001F → (0,0,255)`, `0x0000 → (0,0,0)`, `0xFFFF → (255,255,255)`, and `panel565 → (16,24,33)`.
    - `mixMatchesLvgl`: with `fg = 0xFFFF` and `bg = panel565`:

      | alpha | `expand(mix(...))` |
      | --- | --- |
      | 0, 2 | (16,24,33) |
      | 128 | (140,142,148) |
      | 253, 255 | (255,255,255) |

    - `imageSizeMatchesFace`: `image(for:)` of a 2x1 key is 154x84, and of a 1x1 key 74x84.
    - `previewPixelsMatchRenderedFace`: for the golden label key, every pixel of `composite(face: FaceRenderer.render(k), …)` equals the test's own recomputation from the face bytes with `expand(mix(...))`.
    - `cacheKeyIgnoresActionAndPlace`: changing `action`, `longAction`, `id`, `col` or `row` keeps `cacheKey`. Changing `label`, `w`, `background` or `foreground` changes it.

- [ ] **Step 3: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter "DeckConfigTests|HexColorTests|FaceRendererTests|FacePreviewTests"`. Expected: compile errors for the missing symbols.

- [ ] **Step 4: Implement the changes above**

- [ ] **Step 5: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: every suite passes, the three goldens from Step 1 included.
  Run: `cd mac/LongDeck && swift build`. Expected: SUCCESS. `AppModel`'s `try? SampleConfig.dev.save(to:)` still compiles thanks to `@discardableResult`.

- [ ] **Step 6: Commit**

  Message: `feat(longdeck): add key text colour and a board-exact face preview`

### Task 2: Editor primitives (grid, ids, palette, action kinds)

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `EditorGrid.swift`, `EditorIds.swift`, `WidgetPalette.swift`, `EditorActions.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/EditorGridTests.swift`, `EditorIdsTests.swift`, `WidgetPaletteTests.swift`, `EditorActionsTests.swift`

**Interfaces:**

```swift
// EditorGrid.swift
public struct CellSize: Equatable, Hashable, Sendable { public var w: Int; public var h: Int; public init(w: Int, h: Int) }
public struct CellRect: Equatable, Hashable, Sendable {
    public var col: Int, row: Int, w: Int, h: Int
    public init(col: Int, row: Int, w: Int, h: Int)
    public var size: CellSize { get }
    public var isInGrid: Bool { get }          // w,h ≥ 1, col,row ≥ 0, col+w ≤ 8, row+h ≤ 2
    public var cells: Set<Int> { get }         // row * 8 + col for every covered cell
    public func intersects(_ other: CellRect) -> Bool
    public func fitted() -> CellRect           // shifted left/up into the grid; size kept
}
public enum EditorWidget: Equatable, Sendable {
    case key(KeyConfig)
    case live(LiveWidgetConfig)
    public var id: String { get }
    public var frame: CellRect { get }
    public var minSize: CellSize { get }       // claude_sessions 2x1, everything else 1x1
    public var title: String { get }           // key: label, or "Key" when empty; live: LiveTitles.title
}
public enum EditorGrid {
    public static func widgets(of page: PageConfig) -> [EditorWidget]                  // keys first, then live
    public static func occupied(_ widgets: [EditorWidget], ignoring id: String?) -> Set<Int>
    public static func fits(_ rect: CellRect, occupied: Set<Int>) -> Bool              // isInGrid and no shared cell
    public static func firstFree(_ size: CellSize, occupied: Set<Int>) -> CellRect?    // row-major scan of top-left cells
}

// EditorIds.swift
public enum EditorText {
    public static func prefix(_ s: String, maxBytes: Int) -> String   // whole Characters only, no ellipsis
}
public enum EditorIds {
    public static func make(base: String, taken: Set<String>) -> String
}

// WidgetPalette.swift
public enum PaletteItem: String, CaseIterable, Sendable {
    case key, stat, volume, clock
    case claudeSessions = "claude_sessions"
    case claudeUsage = "claude_usage"
    public var title: String { get }
    public var symbol: String { get }
    public var defaultSize: CellSize { get }
    public var minSize: CellSize { get }
    public var idBase: String { get }
    public func makeWidget(id: String, rect: CellRect) -> EditorWidget
}
public enum LiveTitles {
    public static func metricName(_ m: StatMetric) -> String
    public static func styleName(_ s: StatStyle) -> String
    public static func title(_ kind: LiveKind) -> String
}

// EditorActions.swift
public enum ActionSlot: String, Sendable { case primary, long }
public enum ActionKind: String, CaseIterable, Sendable {
    case openApp, openURL, hotkey, media, volume, typeText, shell, shortcut
    public static let unsetKeyCode: UInt16 = 0xFFFF
    public init(_ action: DeckAction)
    public var title: String { get }
    public var defaultAction: DeckAction { get }
}
```

Behaviour required:
- `fitted()` sets `col = min(max(col, 0), 8 - w)` and `row = min(max(row, 0), 2 - h)`. Clamp `w` to 1...8 and `h` to 1...2 first.
- `firstFree` tries every top-left `(col, row)` with row 0 before row 1 and col ascending, and returns the first rect where `fits` is true.
- `EditorText.prefix` adds `Character`s while the running UTF-8 count stays ≤ `maxBytes`.
- `EditorIds.make`:
  1. Lowercase `base`, keep only ASCII `a`–`z` and `0`–`9`, and take the first 12 characters. If that is empty, use `w`.
  2. If the slug is not in `taken`, return it.
  3. Otherwise, for `n` from 2 upwards, try `String(slug.prefix(15 - String(n).count)) + String(n)` and return the first that is not taken.
  4. Results are always 1–15 bytes.
- `PaletteItem` table:

  | Item | `title` | `symbol` | `defaultSize` | `minSize` | `idBase` | `makeWidget` |
  | --- | --- | --- | --- | --- | --- | --- |
  | `key` | Key | `button.programmable` | 1x1 | 1x1 | `key` | `KeyConfig(label: "Key", icon: nil, background: "#2B2B2B", action: .openApp(path: ""), longAction: nil, foreground: nil)` |
  | `stat` | Stat | `chart.bar.fill` | 2x1 | 1x1 | `cpu` | `.stat(.cpu, .sparkline)` |
  | `volume` | Volume | `speaker.wave.2.fill` | 3x1 | 1x1 | `volume` | `.volume` |
  | `clock` | Clock | `clock` | 2x1 | 1x1 | `clock` | `.clock` |
  | `claudeSessions` | Claude sessions | `list.bullet.rectangle` | 4x2 | 2x1 | `ccsessions` | `.claudeSessions` |
  | `claudeUsage` | Claude usage | `gauge.with.dots.needle.33percent` | 4x1 | 1x1 | `ccusage` | `.claudeUsage` |

  `makeWidget` puts the given `id` and `rect` into the config.
- `LiveTitles`:
  - Metric names: cpu `CPU`, ram `RAM`, gpu `GPU`, temp `Temp`, netDown `Net down`, netUp `Net up`, diskFree `Disk free`, diskIO `Disk I/O`, battery `Battery`.
  - Style names: `Bar`, `Number`, `Sparkline`.
  - `title(.stat(.cpu, .sparkline)) == "CPU · sparkline"` (the style name lowercased). Otherwise `Volume`, `Clock`, `Claude sessions`, `Claude usage`.
- `ActionKind` table:

  | Kind | `title` | `defaultAction` |
  | --- | --- | --- |
  | `openApp` | Open app | `.openApp(path: "")` |
  | `openURL` | Open URL | `.openURL("")` |
  | `hotkey` | Hotkey | `.hotkey(keyCode: 0xFFFF, modifiers: [])` |
  | `media` | Media key | `.media(.playPause)` |
  | `volume` | Volume | `.volume(.mute)` |
  | `typeText` | Type text | `.typeText("")` |
  | `shell` | Shell command | `.shell("")` |
  | `shortcut` | Shortcut | `.shortcut("")` |

- [ ] **Step 1: Write the failing tests**

  - `EditorGridTests`:
    - `cellRectBasics`:
      - `(1,0,2,2).cells == [1,2,9,10]`.
      - `(0,0,2,1)` intersects `(1,0,1,1)`, and `(0,0,1,1)` does not intersect `(1,0,1,1)`.
      - `isInGrid` is false for `(7,0,2,1)`, `(0,1,1,2)`, `(-1,0,1,1)` and `(0,0,0,1)`, and true for `(0,0,8,2)`.
    - `fittedShiftsIntoGrid`: `(7,1,4,1) → (4,1,4,1)`, `(6,1,2,2) → (6,0,2,2)`, `(-1,0,1,1) → (0,0,1,1)`.
    - `firstFreeIsRowMajor`:

      | Size | Occupied | Result |
      | --- | --- | --- |
      | 2x1 | `{0}` | `(1,0,2,1)` |
      | 1x1 | `0...14` | `(7,1,1,1)` |
      | 4x2 | `{3}` | `(4,0,4,2)` |
      | 4x2 | `{3, 12}` | nil |
      | 8x1 | `{}` | `(0,0,8,1)` |

    - `widgetsKeysThenLive`: for `SampleConfig.dev` page `Claude`, the ids are `[ccsessions, ccusage, ccclock]`. `minSize` is 2x1 for `ccsessions` and 1x1 for the rest.
  - `EditorIdsTests`:
    - `prefixIsGraphemeSafe`: `("abc", 2) → "ab"`, `("ทดสอบ", 7) → "ทด"`, `("é", 1) → ""`, `("👍🏽x", 8) → "👍🏽"`, `("👍🏽x", 7) → ""`.
    - `makeVectors`:

      | `base` | `taken` | Result |
      | --- | --- | --- |
      | `key` | `[]` | `key` |
      | `key` | `[key]` | `key2` |
      | `key` | `[key, key2, key3]` | `key4` |
      | `VS Code` | `[]` | `vscode` |
      | `ทดสอบ` | `[]` | `w` |
      | `net_down` | `[]` | `netdown` |
      | `abcdefghijklmnop` | `[]` | `abcdefghijkl` |
      | `abcdefghijklmnop` | `[abcdefghijkl]` | `abcdefghijkl2` |

    - `idsFitFifteenBytes`: with `taken` = `abcdefghijkl` plus `abcdefghijkl2` … `abcdefghijkl999`, `make` gives `abcdefghijk1000` (15 bytes).
  - `WidgetPaletteTests`:
    - `paletteTable`: every row of the table above.
    - `paletteSymbolsExist`: every `symbol` resolves with `NSImage(systemSymbolName:accessibilityDescription:)`.
    - `makeWidgetUsesIdAndRect`.
    - `liveTitles`: four cases from the rules.
  - `EditorActionsTests`:
    - `kindRoundTrip`: `ActionKind(k.defaultAction) == k` for every kind, and `ActionKind` of each `SampleConfig.dev` key action is right.
    - `defaultsTable`.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter "EditorGridTests|EditorIdsTests|WidgetPaletteTests|EditorActionsTests"`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add editor grid, id and palette primitives`

### Task 3: App catalog, hotkey format, symbol catalog, canvas geometry

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `AppCatalog.swift`, `HotkeyFormat.swift`, `SymbolCatalog.swift`, `CanvasGeometry.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/AppCatalogTests.swift`, `HotkeyFormatTests.swift`, `SymbolCatalogTests.swift`, `CanvasGeometryTests.swift`

**Interfaces:**

```swift
// AppCatalog.swift
public struct AppRoot: Sendable { public var url: URL; public var label: String; public init(url: URL, label: String) }
public struct AppEntry: Equatable, Hashable, Identifiable, Sendable {
    public var name: String
    public var path: String       // as found in the scanned folder, symlinks not resolved
    public var folder: String     // root label, plus "/<subfolder>" for depth-2 apps
    public var id: String { path }
    public init(name: String, path: String, folder: String)
}
public enum AppCatalog {
    public static var standardRoots: [AppRoot] { get }
    public static func scan(_ roots: [AppRoot]) -> [AppEntry]
    public static func entry(forApp url: URL) -> AppEntry?       // NSOpenPanel picks; folder = parent folder name
    public static func name(forPath path: String) -> String
    public static func filter(_ apps: [AppEntry], query: String) -> [AppEntry]
}

// HotkeyFormat.swift
public enum HotkeyFormat {
    public static func modifiers(from flags: NSEvent.ModifierFlags) -> [KeyModifier]
    public static func action(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> DeckAction
    public static func keyName(_ keyCode: UInt16) -> String
    public static func display(keyCode: UInt16, modifiers: [KeyModifier]) -> String
    public static func isCancel(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool
}

// SymbolCatalog.swift
public enum SymbolCatalog {
    public static let common: [String]
    public static func exists(_ name: String) -> Bool
}

// CanvasGeometry.swift
public enum ResizeHandle: CaseIterable, Sendable { case right, bottom, bottomRight }
public struct CanvasGeometry: Equatable, Sendable {
    public static let boardSize = CGSize(width: 640, height: 180)
    public var scale: CGFloat
    public init(scale: CGFloat)
    public static func fitting(width: CGFloat) -> CanvasGeometry
    public var size: CGSize { get }
    public func rect(for cells: CellRect) -> CGRect                     // top-left origin, points
    public func cell(at point: CGPoint) -> (col: Int, row: Int)?
    public func moved(_ start: CellRect, by translation: CGSize) -> CellRect
    public func resized(_ start: CellRect, handle: ResizeHandle, by translation: CGSize, minSize: CellSize) -> CellRect
}
```

Behaviour required:
- `standardRoots`, in this order:
  - `/Applications` labelled `Applications`
  - `/System/Applications` labelled `System`
  - `FileManager.default.homeDirectoryForCurrentUser/Applications` labelled `Home`
- `scan`:
  - For each root, list the entries (`contentsOfDirectory(at:includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey], options: [.skipsHiddenFiles])`). Missing roots are skipped.
  - An entry whose name ends in `.app` and which resolves to a directory (follow symlinks; `/Applications/Safari.app` is a symlink on macOS 13+) is an app with `folder` = the root label.
  - A directory that does not end in `.app` is scanned one level deeper, and its apps get `folder` = `<label>/<dir name>` (for example `Applications/Utilities`). Nothing deeper is scanned, and nothing inside an `.app` is ever scanned.
  - Entries whose resolved paths are equal are deduplicated, keeping the first.
  - Sort by `name` with `localizedStandardCompare`, then by `path`.
- `name(forPath:)`, using `Bundle(url:)`, takes the first non-empty of:
  1. `localizedInfoDictionary["CFBundleDisplayName"]`
  2. `infoDictionary["CFBundleDisplayName"]`
  3. `localizedInfoDictionary["CFBundleName"]`
  4. `infoDictionary["CFBundleName"]`
  5. the file name without `.app`
- `filter`: a query that is empty after trimming returns all apps. Otherwise keep the entries whose `name` satisfies `localizedStandardContains(query)`.
- `HotkeyFormat`:
  - `modifiers` keeps command, shift, option, control, in that order (the `KeyModifier` declaration order). Every other flag (caps lock, function, numeric pad, help) is ignored.
  - `action` gives `.hotkey(keyCode:modifiers:)`.
  - `keyName` uses the US-ANSI virtual key codes from HIToolbox `Events.h`:
    - Letters and digits by `kVK_ANSI_*` code, upper case: A 0, S 1, D 2, F 3, H 4, G 5, Z 6, X 7, C 8, V 9, B 11, Q 12, W 13, E 14, R 15, Y 16, T 17, 1 18, 2 19, 3 20, 4 21, 6 22, 5 23, 9 25, 7 26, 8 28, 0 29, O 31, U 32, I 34, P 35, L 37, J 38, K 40, N 45, M 46.
    - Punctuation: `=` 24, `-` 27, `]` 30, `[` 33, `'` 39, `;` 41, `\` 42, `,` 43, `/` 44, `.` 47, `` ` `` 50.
    - Named keys: Return `↩` 36, Tab `⇥` 48, `Space` 49, Delete `⌫` 51, Escape `⎋` 53, Home `↖` 115, Page Up `⇞` 116, Forward Delete `⌦` 117, End `↘` 119, Page Down `⇟` 121, `←` 123, `→` 124, `↓` 125, `↑` 126.
    - F-keys: F1 122, F2 120, F3 99, F4 118, F5 96, F6 97, F7 98, F8 100, F9 101, F10 109, F11 103, F12 111, F13 105, F14 107, F15 113, F16 106, F17 64, F18 79, F19 80, F20 90.
    - Anything else gives `Key <code>`.
  - `display`:
    - `unsetKeyCode` gives `Not set`.
    - Otherwise the modifier glyphs in Apple's order `⌃⌥⇧⌘`, for the modifiers present, followed by `keyName`.
  - `isCancel` is true only for key code 53 with none of the four modifiers.
- `SymbolCatalog.common`, exactly these 30 names:
  `play.fill`, `pause.fill`, `playpause.fill`, `forward.fill`, `backward.fill`, `speaker.wave.1.fill`, `speaker.wave.3.fill`, `speaker.slash.fill`, `mic.fill`, `mic.slash.fill`, `camera.viewfinder`, `magnifyingglass`, `globe`, `link`, `terminal`, `folder`, `doc.text`, `text.cursor`, `keyboard`, `bolt.fill`, `star.fill`, `heart.fill`, `lock.fill`, `moon.fill`, `sun.max.fill`, `gearshape.fill`, `house.fill`, `bell.fill`, `hammer.fill`, `cup.and.saucer.fill`.
  All of them resolved on this Mac on 2026-11-25. `exists` is `NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil`.
- `CanvasGeometry`:
  - `fitting(width:)` gives the scale `min(2, max(1, floor(width / 640 * 4) / 4))`.
  - `size` is the board size × scale.
  - `rect(for:)` is `(col*80+3, row*90+3, w*80-6, h*90-6)` × scale.
  - `cell(at:)` is `(floor(x / (80*scale)), floor(y / (90*scale)))` for `0 ≤ x < size.width` and `0 ≤ y < size.height`, else nil.
  - `moved` offsets by `dc = Int((dx / (80*scale)).rounded())` and `dr = Int((dy / (90*scale)).rounded())` (`.toNearestOrAwayFromZero`) and keeps the size. Then `fitted()`.
  - `resized`:
    - `.right` sets `w = clamp(start.w + dc, minSize.w, 8 - col)`.
    - `.bottom` sets `h = clamp(start.h + dr, minSize.h, 2 - row)`.
    - `.bottomRight` does both.
    - `col` and `row` never change.

- [ ] **Step 1: Write the failing tests**

  - `AppCatalogTests` (temp dirs; each fake bundle is a folder with an optional `Contents/Info.plist` written with `PropertyListSerialization`):
    - `scanFindsAppsOneLevelDeep`. The root `T` (label `Test`) holds:
      - `A.app` with `CFBundleName` = `Alpha`
      - `b.app` with no Info.plist
      - `Utilities/C.app` with `CFBundleDisplayName` = `Cee`
      - `Nested.app/Contents/Plug.app`
      - `.Hidden.app`
      - `notes.txt`
      - `Deep/More/D.app`

      The result is exactly `[("Alpha", T/A.app, "Test"), ("b", T/b.app, "Test"), ("Cee", T/Utilities/C.app, "Test/Utilities"), ("Nested", T/Nested.app, "Test")]`. `Plug.app`, `.Hidden.app` and `D.app` are absent.
    - `scanFollowsAppSymlinksAndDedupes`:
      - A symlink `T2/Link.app → T/A.app` is listed as `T2/Link.app`, folder `Test2`, when `T2` is scanned alone.
      - When `[T, T2]` are scanned, it is dropped as a duplicate.
    - `missingRootIsSkipped`.
    - `filterByName`: `"al"` keeps `Alpha`, `"  "` keeps all, and `"zz"` keeps none.
    - `entryForOpenPanelPick`: `entry(forApp: T/Utilities/C.app)` gives name `Cee` and folder `Utilities`.
    - `systemAppsAreFound` (read-only on the real disk): `scan([AppRoot(url: /System/Applications, label: "System")])` contains path `/System/Applications/Calculator.app` with a non-empty name equal to `name(forPath:)` of that path. Do not assert the text: it may be localized.
  - `HotkeyFormatTests`:
    - `modifiersCanonicalOrder`: `[.shift, .command, .capsLock, .function]` gives `[.command, .shift]`.
    - `displayVectors`:

      | Key code | Modifiers | Text |
      | --- | --- | --- |
      | 21 | `[.command, .shift]` | `⇧⌘4` |
      | 49 | `[.command]` | `⌘Space` |
      | 0 | `[.control, .option, .shift, .command]` | `⌃⌥⇧⌘A` |
      | 122 | `[]` | `F1` |
      | 123 | `[.option]` | `⌥←` |
      | 200 | `[]` | `Key 200` |
      | 65535 | `[]` | `Not set` |

    - `actionFromEvent`: key code 21 with `[.command, .shift]` gives `.hotkey(keyCode: 21, modifiers: [.command, .shift])`, which equals `SampleConfig.dev` key `screenshot`.
    - `cancelOnlyBareEscape`: `(53, [])` is true; `(53, [.command])` and `(12, [])` are false.
  - `SymbolCatalogTests`:
    - `commonSymbolsExist`: all 30 exist, and there are no duplicates.
    - `sampleSymbolsAreCommon`: every `.symbol` name in `SampleConfig.dev` is in `common`.
    - `unknownSymbol`: `exists("no.such.symbol.x")` is false.
  - `CanvasGeometryTests`:
    - `fittingSteps`: width 500 → 1, 900 → 1.25, 1280 → 2, 2000 → 2.
    - `rectVectors`: at scale 2, `(1,1,2,1)` → `(166,186,308,168)`. At scale 1, `(0,0,1,1)` → `(3,3,74,84)`.
    - `cellAtVectors`: at scale 1, `(159.9,179.9)` → `(1,1)`, `(0,0)` → `(0,0)`, `(640,0)` → nil, `(-1,5)` → nil.
    - `movedRoundsToCells`: at scale 1:
      - `(0,0,2,1)` by `(119,0)` → col 1, and by `(121,0)` → col 2.
      - `(6,0,2,1)` by `(400,200)` → `(6,1,2,1)`.
    - `resizedClamps`: at scale 1:
      - `(2,0,1,1)` `.right` by `(250,0)` → w 4.
      - `(2,0,1,1)` `.bottom` by `(0,-90)` → h 1.
      - `(6,0,2,1)` `.bottomRight` by `(500,100)` with min 2x1 → `(6,0,2,2)`.
      - `(0,0,2,1)` `.right` by `(-200,0)` with min 2x1 → w 2.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter "AppCatalogTests|HotkeyFormatTests|SymbolCatalogTests|CanvasGeometryTests"`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add app catalog, hotkey names and canvas geometry`

### Task 4: Save path (frame size, atomic write, write guard)

**Files:**
- Create: `mac/LongDeck/Sources/LongDeckCore/ConfigSaver.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/ConfigSaverTests.swift`

**Interfaces:**

```swift
public enum SaveOutcome: Equatable, Sendable { case sent, savedOffline, failed(String) }
public enum ConfigSaveError: Error, Equatable, CustomStringConvertible {
    case layoutTooLarge(bytes: Int, max: Int)   // "Layout is <bytes> bytes, the board takes at most <max>"
}
public enum LayoutSize {
    public static let sequenceSlack = 9
    public static func sealedBytes(_ config: DeckConfig) -> Int
}
public enum ConfigSaver {
    public static func prepare(_ config: DeckConfig) throws -> Data   // validate, frame check, fileData
    public static func write(_ data: Data, to url: URL) throws        // mkdir -p, then atomic replace
}
public struct ConfigWriteGuard: Sendable {
    public init()
    public mutating func recordWrite(_ data: Data)
    public func matches(_ data: Data) -> Bool   // equals the last recorded bytes
}
```

Behaviour required:
- `sealedBytes` reproduces the frame `DeckConnection.send` checks:
  - Build `LayoutBuilder.build(config, render: { _ in Data() })`. The faces do not change the JSON, only the 16-char hash.
  - Seal it with `FrameSealer(sessionKey: Data(count: 32)).seal(type: "layout", body: json)` and take the UTF-8 byte count.
  - Add `sequenceSlack`, because a sequence number of `1` is 1 digit and a real one is up to 10.
- `prepare` calls `try config.validate()`, then throws `.layoutTooLarge` when `!LayoutPushPolicy.fits(frameBytes: sealedBytes(config))`, then returns `try config.fileData()`.
- `write` creates the parent folder with intermediate directories, then `data.write(to: url, options: .atomic)`.
- `ConfigWriteGuard.matches` is false before any write. It does not consume the record, because one atomic write can fire the watcher more than once.

- [ ] **Step 1: Write the failing tests**

  - `sampleFits`: `prepare(SampleConfig.dev) == SampleConfig.dev.fileData()`, and `sealedBytes(SampleConfig.dev) < 15360`.
  - `sealedBytesMatchesSealer`: for `SampleConfig.dev`, it equals the sealer computation done in the test + 9.
  - `fullStatPages(n)` helper:
    - `n` pages named `"P" + 22 digits`, 23 bytes each.
    - Each page holds 16 1x1 `.stat(.diskFree, .sparkline)` widgets with ids `"s" + 14 digits`, filling the grid.
    - The config is valid.

    Then:
    - `sixFullStatPagesFit`: `prepare(fullStatPages(6))` succeeds (about 14.2 KB sealed).
    - `sevenFullStatPagesTooLarge`: `prepare(fullStatPages(7))` throws `.layoutTooLarge(bytes: b, max: 15360)` with `b > 15360` (about 16.5 KB). The `description` contains both numbers.
  - `invalidConfigRejected`: two overlapping keys throw `DeckConfigError`.
  - `writeIsAtomicAndCreatesFolder`:
    - Write into `<tmp>/a/b/config.json`. The folder is created and the bytes are equal.
    - A second write replaces the content, and the folder then holds exactly one file.
  - `writeGuardMatchesOwnBytes`:
    - A fresh guard matches nothing.
    - After `recordWrite(A)`, `matches(A)` is true twice and `matches(B)` is false.
    - After `recordWrite(B)`, `matches(A)` is false.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter ConfigSaverTests`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add a checked atomic config save path`

### Task 5: EditorModel (document, placement, pages, undo, issues)

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `EditorModel.swift`, `EditorIssues.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/EditorModelTests.swift`, `EditorIssuesTests.swift`

**Interfaces:**

```swift
// EditorIssues.swift
public struct EditorIssue: Equatable, Sendable {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var page: Int?      // nil = whole layout
    public var widget: String? // nil = page or layout level
    public var message: String
    public init(severity: Severity, page: Int?, widget: String?, message: String)
}
public struct IssueEnvironment: Sendable {
    public var fileExists: @Sendable (String) -> Bool
    public var symbolExists: @Sendable (String) -> Bool
    public init(fileExists: @escaping @Sendable (String) -> Bool, symbolExists: @escaping @Sendable (String) -> Bool)
    public static let live: IssueEnvironment         // FileManager.default.fileExists, SymbolCatalog.exists
    public static let permissive: IssueEnvironment   // both always true
}
public enum EditorIssues {
    public static func check(_ config: DeckConfig, _ env: IssueEnvironment) -> [EditorIssue]
}

// EditorModel.swift
public struct EditorModel: Sendable {
    public static let undoLimit = 100
    public private(set) var document: DeckConfig
    public private(set) var pageIndex: Int
    public private(set) var selection: String?
    public init(document: DeckConfig, saved: DeckConfig?)   // saved nil = never saved, always dirty
    public var isDirty: Bool { get }
    public var canUndo: Bool { get }
    public var canRedo: Bool { get }
    public var page: PageConfig { get }
    public func widgets(onPage index: Int) -> [EditorWidget]
    public func widget(_ id: String) -> EditorWidget?                  // current page only
    public func canPlace(_ rect: CellRect, ignoring id: String?) -> Bool
    public func canAdd(_ item: PaletteItem) -> Bool
    public func issues(_ env: IssueEnvironment) -> [EditorIssue]
    public func hasErrors(_ env: IssueEnvironment) -> Bool

    public mutating func selectPage(_ index: Int)
    public mutating func select(_ id: String?)

    @discardableResult public mutating func addPage() -> Bool
    @discardableResult public mutating func removePage(at index: Int) -> Bool
    @discardableResult public mutating func movePage(from: Int, to: Int) -> Bool
    public mutating func renamePage(at index: Int, to name: String)

    @discardableResult public mutating func add(_ item: PaletteItem) -> String?
    @discardableResult public mutating func add(_ item: PaletteItem, col: Int, row: Int) -> String?
    @discardableResult public mutating func setFrame(_ id: String, _ rect: CellRect) -> Bool
    @discardableResult public mutating func remove(_ id: String) -> Bool
    public mutating func updateKey(_ id: String, coalesce: String? = nil, _ change: (inout KeyConfig) -> Void)
    @discardableResult public mutating func setStat(_ id: String, metric: StatMetric, style: StatStyle) -> Bool
    public mutating func setAction(_ action: DeckAction?, slot: ActionSlot, for id: String, coalesce: String? = nil)
    public mutating func chooseApp(_ app: AppEntry, slot: ActionSlot, for id: String)

    public mutating func undo()
    public mutating func redo()
    public mutating func load(_ config: DeckConfig)
    public mutating func markSaved()
    public mutating func externalChange(_ config: DeckConfig)
}
```

Behaviour required:

- **State.**
  - `init` keeps `saved` as the baseline. If `document.pages` is empty, the document gets one page `Page 1`, while the baseline stays as given.
  - `pageIndex` is always a valid index, and `selection` is nil or an id on the current page.
  - `isDirty` is `saved == nil || document != saved`.
- **Edits and undo.**
  - Every mutating method except `selectPage`, `select`, `undo`, `redo`, `load`, `markSaved` and `externalChange` is an edit. An edit that leaves `document` unchanged records nothing.
  - An edit pushes a snapshot `(document, pageIndex, selection)` of the state before it onto the undo stack, at most `undoLimit` entries (oldest dropped), and clears the redo stack.
  - Coalescing: if an edit has a non-nil `coalesce` equal to the previous edit's, and nothing else happened in between, no new snapshot is pushed. Typing into one field is then one undo step.
  - `selectPage`, `select`, `undo`, `redo` and any edit with a different or nil key reset the coalescing.
  - The inspector's coalesce keys are `label-<id>`, `symbol-<id>`, `background-<id>`, `foreground-<id>`, `action-primary-<id>`, `action-long-<id>` and `page-name-<index>`.
  - `undo` pushes the current snapshot onto redo and restores the popped one. `redo` does the reverse. A restored selection that is not on the restored page becomes nil.
- **Pages.**
  - `selectPage` clamps the index and clears the selection.
  - `addPage`:
    - Returns false at 8 pages.
    - Otherwise appends `PageConfig(name: "Page <n>", keys: [], live: [])`, where `n` starts at `pages.count + 1` and goes up while the name is taken.
    - Selects the new page.
  - `removePage`:
    - Returns false when it would remove the last page, or for a bad index.
    - If the removed page is before the current one, `pageIndex -= 1`. If it is the current one, `pageIndex = min(index, count - 1)`. The selection is cleared.
  - `movePage` works like `Array.remove(at: from)` then `insert(_, at: to)`, with `to` the final index. It returns false for equal or bad indexes. `pageIndex` follows the page that was current.
  - `renamePage` stores `EditorText.prefix(name, maxBytes: 23)` with coalesce key `page-name-<index>`.
- **Adding widgets** (current page):
  - `canAdd(item)` needs fewer than 16 widgets on the page and some free rect of `item.minSize`.
  - `add(item)` uses `firstFree(defaultSize)`, then `firstFree(minSize)`. It returns nil when neither exists.
  - `add(item, col:row:)` tries `CellRect(col, row, defaultSize).fitted()`, then `CellRect(col, row, minSize).fitted()`, and uses the first that fits. Otherwise it returns nil.
  - In both cases the 16-widget cap applies. The id is `EditorIds.make(base: item.idBase, taken: <all ids on all pages>)`. Keys are appended to `keys`, live widgets to `live`. The new widget is selected, and the method returns its id.
- **Changing widgets** (each acts on a widget of the current page only):
  - `setFrame`:
    - Returns false when the rect is smaller than `minSize` or `!canPlace(rect, ignoring: id)`.
    - Returns true with no undo entry when the rect equals the current frame. Otherwise it sets `col`, `row`, `w` and `h`.
  - `remove` deletes the widget and clears the selection if it was selected.
  - `updateKey` runs `change` on a copy, then restores `id`, `col`, `row`, `w` and `h` from the original, so the closure cannot break placement.
  - `setStat` only works on `.stat` widgets.
  - `setAction`:
    - `.primary` with a non-nil action sets `action`. `.primary` with nil is ignored.
    - `.long` sets `longAction`, and nil removes it.
  - `chooseApp(app, slot, id)` is one edit:
    - It sets the slot's action to `.openApp(path: app.path)`.
    - For `.primary` it also sets `icon = .app(path: app.path)`. It sets `label = app.name` when the label is empty, or equals `Key`, or equals the file name (without `.app`) of the previous primary `openApp` path.
    - `.long` never touches the label or icon.
- **History.**
  - `load` replaces the document (normalised as in `init`) and the baseline. It clears both stacks, sets `pageIndex = 0` and `selection = nil`.
  - `markSaved` sets the baseline to the document.
  - `externalChange`:
    - If the config equals the document, it only sets the baseline.
    - Else, if the model is not dirty, it does `load(config)`.
    - Else it does nothing: the user's edits win, and Save overwrites the file.
- **Issues** (`EditorIssues.check`, also used by `issues`):
  - Order: layout-level issues, then each page in order: page-level issues, then its widgets (keys, then live), each with its checks in the order of the table.
  - Messages are exact. `L:` marks an action check that also runs for `longAction`, with the prefix `Long press: `.

  | Level | Check | Severity | Message |
  | --- | --- | --- | --- |
  | layout | more than 8 pages | error | `<n> pages, the board takes at most 8` |
  | layout | `!LayoutPushPolicy.fits(LayoutSize.sealedBytes)` | error | `Layout is <b> bytes, the board takes at most 15360. Remove widgets or pages.` |
  | page | name over 23 bytes | error | `Page name is <n> bytes, at most 23` |
  | page | more than 16 widgets | error | `<n> widgets, at most 16 per page` |
  | widget | empty id | error | `Widget id is empty` |
  | widget | id over 15 bytes | error | `Widget id is <n> bytes, at most 15` |
  | widget | id already used earlier in the document | error | `Widget id <id> is used twice` |
  | widget | `!frame.isInGrid` | error | `Outside the 8x2 grid` |
  | widget | shares a cell with an earlier widget on the page | error | `Overlaps <earlier id>` |
  | widget | `claude_sessions` with `w < 2` | error | `Claude sessions needs at least 2 columns` |
  | key | `HexColor.parse(background) == nil` | error | `Background must be #RRGGBB` |
  | key | `foreground` set and not parseable | error | `Text colour must be #RRGGBB` |
  | key L: | `openApp` path empty | error | `Choose an app` |
  | key L: | `openURL` empty after trimming | error | `Enter a URL` |
  | key L: | `openURL` where `URL(string:)` is nil or its `scheme` is empty | error | `URL is not valid, include a scheme like https://` |
  | key L: | `hotkey` with key code 65535 | error | `Record a hotkey` |
  | key L: | `typeText` empty | error | `Enter text to type` |
  | key L: | `shell` empty after trimming | error | `Enter a shell command` |
  | key L: | `shortcut` empty after trimming | error | `Enter a Shortcut name` |
  | key L: | `openApp` path non-empty and `!env.fileExists(path)` | warning | `App not found: <path>` |
  | key | icon `.app(path)` with `!env.fileExists(path)` | warning | `Icon app not found: <path>` |
  | key | icon `.symbol(name)` with `!env.symbolExists(name)` | warning | `Unknown SF Symbol <name>` |
  | key | label empty after trimming and icon nil | warning | `Key shows nothing: add a label or an icon` |

  - `hasErrors` is true when any issue has `.error`.

- [ ] **Step 1: Write the failing tests**

  Fixture: `blank()` is `EditorModel(document: DeckConfig(version: 1, pages: [PageConfig(name: "A", keys: [])]), saved: <the same config>)`.

  - `EditorModelTests`:
    - `initAddsPageToEmptyDocument`: no pages and `saved: nil` give one page `Page 1` and `isDirty`.
    - `addKeyAtFirstFreeSpot`: on `blank()`:
      - `add(.key)` gives `key` at `(0,0,1,1)`, selected, and the model is dirty.
      - A second `add(.key)` gives `key2` at `(1,0,1,1)`.
    - `addUsesDefaultSizes`: on separate fresh models:
      - `.stat` gives id `cpu`, 2x1, `.stat(.cpu, .sparkline)`.
      - `.volume` is 3x1 and `.clock` is 2x1.
      - `.claudeSessions` gives `(0,0,4,2)`, and a following `.claudeUsage` gives `(4,0,4,1)`.
    - `addFallsBackToMinSizeThenFails`:
      - With 15 1x1 keys leaving only `(7,1)` free, `add(.stat)` gives a 1x1 at `(7,1)`.
      - Then `add(.key)` gives nil and `canAdd(.key)` is false.
      - On a fresh copy of the same 15-key page, `add(.claudeSessions)` gives nil.
    - `addAtCellShiftsIntoGrid`:
      - `add(.claudeUsage, col: 6, row: 1)` gives `(4,1,4,1)`.
      - With `(1,0)` taken, `add(.stat, col: 0, row: 0)` gives `(0,0,1,1)`.
      - With `(0,0)` taken, it gives nil.
    - `idsUniqueAcrossPages`: page A holds `key`. After `addPage()`, `add(.key)` on the new page gives `key2`.
    - `setFrameChecksBoundsAndCollisions`:
      - Moving a key to `(7,0,1,1)` is true. `(8,0,1,1)` and `(7,0,2,1)` are false.
      - A rect overlapping another key is false.
      - The same rect is true with `canUndo` unchanged.
      - A 4x2 `claude_sessions` set to w 1 is false.
    - `removeClearsSelection`.
    - `pagesAddRemoveMoveRename`:
      - Adding to `[A]` names `Page 2`, then `Page 3`. After renaming `Page 3` to `Page 4`, the next add is `Page 5`.
      - The 9th page is refused. On `blank()`, removing the only page is refused.
      - `movePage(from: 0, to: 2)` on `[A,B,C]` with A current gives `[B,C,A]` and `pageIndex == 2`. `movePage(from: 2, to: 0)` gives `[A,B,C]` again.
      - `renamePage(at: 0, to: "ทดสอบภาษาไทยยาว")` stores `ทดสอบภา` (21 bytes). A 30-char ASCII name stores its first 23 characters.
    - `removePageKeepsCurrentPage`: on `[A,B,C]` with C current, removing A keeps C current (`pageIndex == 1`).
    - `updateKeyCannotChangeIdOrFrame`: a closure that sets `id = "x"`, `col = 5` and `label = "Hi"` changes only the label.
    - `chooseAppSetsIconAndLabel`:
      - A new key with Calculator (`/System/Applications/Calculator.app`) gives `.openApp` with that path, icon `.app` with that path, and label `Calculator`.
      - After setting the label to `Calc`, choosing Notes keeps `Calc` but changes the icon and action.
      - With the label `Notes` (equal to the previous app's file name), choosing Safari gives `Safari`.
      - Choosing for `.long` sets `longAction` only.
      - Each choice is one undo step.
    - `setActionSlots`: `.long` with nil removes the long action. `.primary` with nil changes nothing.
    - `setStatOnlyForStats`.
    - `undoRedoRestoresDocumentAndSelection`:
      - Add a key, move it to `(3,0)`, then `undo`: the frame is back at `(0,0)` and `key` is selected. A second `undo` removes the key, and the selection is nil.
      - `redo` twice gives the moved key. A new edit after an undo clears `canRedo`.
    - `typingCoalescesIntoOneStep`:
      - `updateKey` with coalesce `label-key` setting `a`, `ab`, then `abc`, then one `undo`, gives label `Key`.
      - The same with `select(nil)`, `select("key")` between `ab` and `abc` gives two steps.
    - `undoLimitIs100`: 105 moves, then `undo` until `canUndo` is false, gives exactly 100 undos.
    - `dirtyFollowsSavedBaseline`:
      - Clean, then `add` makes it dirty, then `undo` makes it clean.
      - `add` then `markSaved` is clean, and a following `undo` is dirty.
    - `externalChangeRules`:
      - When clean, a different config replaces the document and clears `canUndo`.
      - When dirty, a different config changes nothing.
      - A config equal to the dirty document makes the model clean.
    - `selectionStaysOnCurrentPage`: `select` of an id on another page gives nil, and `selectPage` clears the selection.
    - `noOpEditsAddNoUndoStep`: `updateKey` that sets the same label leaves `canUndo` false.
  - `EditorIssuesTests` (`IssueEnvironment.permissive` unless stated):
    - `sampleHasNoIssues`: `SampleConfig.dev` gives `[]`.
    - `newKeyNeedsAnApp`: after `add(.key)` on `blank()`, the only issue is `(error, page 0, "key", "Choose an app")`.
    - `actionValueErrors`: one key per row of the action checks gives exactly that message. The same action as `longAction` gives `Long press: <message>`. Also `openURL("github.com")` is not valid and `openURL("https://github.com")` is fine.
    - `colourErrors`: background `#12345` and foreground `red` are errors. `#a1b2c3` is fine.
    - `layoutRuleErrorsPerWidget` (configs built directly; `EditorModel.init` does not validate):
      - A duplicate id is flagged on the second widget only.
      - Overlapping `a` then `b` gives `Overlaps a` on `b`.
      - A widget at col 7 with w 2 is `Outside the 8x2 grid`.
      - A 1x1 `claude_sessions` is flagged.
      - 17 widgets give a page-level error, a 24-byte page name gives one, and 9 pages give a layout error.
    - `warningsUseEnvironment`:
      - With `fileExists` false, `App not found: <path>` and `Icon app not found: <path>` appear.
      - With `symbolExists` false, `Unknown SF Symbol star` appears.
      - A key with empty label and nil icon warns.
      - None of these makes `hasErrors` true.
    - `tooLargeLayoutIsError`: `fullStatPages(7)` from Task 4 gives one layout-level error starting `Layout is` and containing `15360`. Copy the helper into this file.
    - `errorsCoverValidate`: for each fixture in `layoutRuleErrorsPerWidget` and for `SampleConfig.dev`, `(try? config.validate()) == nil` equals "some layout-rule error exists". Layout-rule errors are the table rows that `DeckConfig.validate()` also checks: every row above `Background must be #RRGGBB` except the frame-size row.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter "EditorModelTests|EditorIssuesTests"`. Expected: compile errors.

- [ ] **Step 3: Implement the types above**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `$SWIFT_TEST`. Expected: all pass.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add the editor model with placement, pages, undo and issues`

### Task 6: `LongDeckEditor` target, `EditorStore`, snapshot harness

**Files:**
- Modify: `mac/LongDeck/Package.swift`
- Create: `mac/LongDeck/Sources/LongDeckEditor/EditorStore.swift`
- Create: `mac/LongDeck/Tests/LongDeckEditorTests/Snapshot.swift`, `mac/LongDeck/Tests/LongDeckEditorTests/EditorStoreTests.swift`, `mac/LongDeck/Tests/LongDeckEditorTests/HarnessSnapshotTests.swift`

**Interfaces:**
- `Package.swift` targets become:
  - `LongDeckCore` (unchanged).
  - `.target(name: "LongDeckEditor", dependencies: ["LongDeckCore"], swiftSettings: [.swiftLanguageMode(.v5)])`.
  - `LongDeckApp` with dependencies `["LongDeckCore", "LongDeckEditor"]`, still Swift 5 mode.
  - `LongDeckCoreTests` (unchanged).
  - `.testTarget(name: "LongDeckEditorTests", dependencies: ["LongDeckEditor", "LongDeckCore"], swiftSettings: [.swiftLanguageMode(.v5)])`.

  `bundle.sh` needs no change, because the library links into the `LongDeckApp` product.
- `EditorStore.swift`:

```swift
@MainActor public final class EditorStore: ObservableObject {
    @Published public private(set) var model: EditorModel     // didSet recomputes issues
    @Published public private(set) var issues: [EditorIssue]
    @Published public var status: String
    @Published public private(set) var diskError: String?
    public var onSave: ((DeckConfig) -> SaveOutcome)?
    public init(config: DeckConfig, onDisk: Bool, diskError: String?,
                appRoots: [AppRoot] = AppCatalog.standardRoots, environment: IssueEnvironment = .live)
    public var apps: [AppEntry] { get }                        // scanned on first use, then cached
    public var canSave: Bool { get }                           // dirty and no error issues
    public var isDirty: Bool { get }
    public func issues(forWidget id: String) -> [EditorIssue]
    public func pageHasErrors(_ index: Int) -> Bool
    public func selectPage(_ index: Int)
    public func select(_ id: String?)
    public func reveal(_ issue: EditorIssue)                   // selects its page, then its widget
    public func addPage(); public func removePage(at index: Int); public func movePage(from: Int, to: Int)
    public func renamePage(at index: Int, to name: String)
    @discardableResult public func add(_ item: PaletteItem) -> String?
    @discardableResult public func add(_ item: PaletteItem, col: Int, row: Int) -> String?
    @discardableResult public func setFrame(_ id: String, _ rect: CellRect) -> Bool
    public func remove(_ id: String)
    public func updateKey(_ id: String, coalesce: String?, _ change: (inout KeyConfig) -> Void)
    public func setStat(_ id: String, metric: StatMetric, style: StatStyle)
    public func setAction(_ action: DeckAction?, slot: ActionSlot, for id: String, coalesce: String?)
    public func chooseApp(_ app: AppEntry, slot: ActionSlot, for id: String)
    public func undo(); public func redo()
    @discardableResult public func save() -> Bool
    public func externalChange(_ config: DeckConfig)
}
```

- `Snapshot.swift` (test target only):

```swift
@MainActor enum Snapshot {
    static func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep   // the harness recipe above
    static func save(_ rep: NSBitmapImageRep, _ name: String) throws           // writes <LONGDECK_SNAPSHOT_DIR>/<name>.png when set
    static func isUniform(_ rep: NSBitmapImageRep) -> Bool                     // every 4th pixel identical
}
```

Behaviour required:
- `init` creates `EditorModel(document: config, saved: onDisk ? config : nil)`. When `diskError` is set, it starts `status` with `config.json on disk is invalid: <error>. Saving replaces it.`
- Every forwarding method mutates `model`. Its `didSet` sets `issues = model.issues(environment)`.
- `apps` scans `appRoots` once, on first access.
- `setFrame` and `add` set `status = "No room there"` when they fail, and clear `status` on success.
- `save()`:
  - If `model.hasErrors`, it sets `status = "Fix <n> error(s) before saving"` and returns false.
  - Otherwise it calls `onSave?(model.document)`. A nil handler counts as `.failed("Saving is not available")`.
  - `.sent` does `markSaved`, clears `diskError`, sets `status = "Saved. Sending to the board."` and returns true.
  - `.savedOffline` is the same with `status = "Saved. The board updates when it connects."`
  - `.failed(m)` sets `status = "Not saved: <m>"`, keeps the model dirty and returns false.
- `externalChange` forwards to `model.externalChange` and does not touch `status`.

- [ ] **Step 1: Write the failing tests**

  - `EditorStoreTests` (`@MainActor`; temp app roots holding one fake `Tool.app`; `environment: .permissive`). Unless a test says otherwise, the store holds a one-page blank config with `onDisk: true`.
    - `addPublishesAndRecomputesIssues`: subscribe to `objectWillChange`. `add(.key)` fires it, and `issues` holds `Choose an app` for `key`.
    - `canSaveNeedsDirtyAndNoErrors`:
      - A clean `SampleConfig.dev` store cannot be saved.
      - After `selectPage(2)` and `add(.clock)`, which lands at `(6,1)`, it can.
      - A second `SampleConfig.dev` store after `selectPage(2)` and `add(.key)` (an error) cannot.
    - `saveSentMarksClean`: after `add(.clock)`, `onSave` records the config and returns `.sent`. After `save()`, the handler got the document, `isDirty` is false and the status is `Saved. Sending to the board.`
    - `saveFailedStaysDirty`: after `add(.clock)`, `.failed("disk full")` gives `Not saved: disk full`, and the store stays dirty.
    - `saveBlockedByErrors`: after `add(.key)`, `onSave` is never called, and the status starts with `Fix 1 error`.
    - `invalidDiskOpensDirty`: `onDisk: false, diskError: "x"` gives `isDirty` true and a status mentioning `x`. A successful save clears `diskError`.
    - `externalChangeWhenCleanReplaces`.
    - `appsScannedOnce`: `apps` lists `Tool`. After deleting the fake bundle, `apps` still lists it.
    - `revealSelectsPageAndWidget`.
    - `failedPlacementSetsStatus`.
  - `HarnessSnapshotTests` (`@Suite(.serialized)`, `@MainActor`): `harnessRendersControls` renders an `HStack { Toggle("On", isOn: .constant(true)); Button("Save") {}; Text("LongDeck") }.padding()` at 360x80. The rep is 720x160 and not uniform. Save it as `harness`.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `$SWIFT_TEST --filter "EditorStoreTests|HarnessSnapshotTests"`. Expected: compile errors.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the tests, write the snapshot, and look at it**

  Run: `$SWIFT_TEST`. Expected: all suites pass, `LongDeckEditorTests` included.
  Run: `cd /Users/lek/WORK/MY_PROJECT/T-Display-S3-Long/mac/LongDeck && mkdir -p /Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots && LONGDECK_SNAPSHOT_DIR=/Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing --filter HarnessSnapshotTests`
  Open `$SNAP_DIR/harness.png` with the Read tool. Expected: a dark panel with a checked checkbox `On`, a `Save` button and the text `LongDeck`, all drawn.
  Run: `cd mac/LongDeck && swift build`. Expected: SUCCESS.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add the editor library target and store`

### Task 7: Canvas, live placeholders and palette

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckEditor/`: `BoardColors.swift`, `FaceImageCache.swift`, `LivePlaceholderView.swift`, `DeckCanvasView.swift`, `WidgetPaletteView.swift`
- Test: `mac/LongDeck/Tests/LongDeckEditorTests/CanvasSnapshotTests.swift`

**Interfaces:**

```swift
enum BoardColors { static let bg, panel, panelHi, text, textDim, ok, warn, err: Color }   // hex values from Global Constraints
@MainActor final class FaceImageCache {
    static let shared: FaceImageCache
    func image(for key: KeyConfig) -> CGImage?     // FacePreview.image(for:), cached by FacePreview.cacheKey, max 256 entries
}
struct LivePlaceholderView: View { init(kind: LiveKind, size: CellSize, scale: CGFloat) }
final class CanvasInteraction: ObservableObject {
    struct Ghost: Equatable { var id: String; var rect: CellRect; var valid: Bool }
    @Published var ghost: Ghost?
    @Published var dropTargeted: Bool
}
public struct DeckCanvasView: View {
    public init(store: EditorStore, geometry: CanvasGeometry)
    init(store: EditorStore, geometry: CanvasGeometry, interaction: CanvasInteraction)   // tests; owned via StateObject(wrappedValue:)
}
public struct WidgetPaletteView: View { public init(store: EditorStore) }
```

Behaviour required:
- `DeckCanvasView` is a `ZStack(alignment: .topLeading)` of exactly `geometry.size`, drawn bottom to top:
  1. The `BoardColors.bg` background. A tap on empty space calls `store.select(nil)`.
  2. Grid lines, 1 pt `BoardColors.panelHi`, at x = `k*80*scale` (k = 1…7) and y = `90*scale`.
  3. Each widget of the current page, placed at `geometry.rect(for: frame)`:
     - A key draws `Image(decorative: FaceImageCache.shared.image(for:), scale: 1)`, resizable, interpolation `.none` when `scale` is a whole number and `.medium` otherwise, clipped to a rounded rect of radius `8*scale`. When the image is nil it draws a `BoardColors.panel` rect instead.
     - A live widget draws `LivePlaceholderView`.
  4. Outlines:
     - The selected widget gets a 2 pt `Color.accentColor` outline.
     - A widget with an error issue gets a 2 pt dashed `BoardColors.err` outline inset by 2 pt, and with only warnings a `BoardColors.warn` one.
  5. The ghost while dragging: the target rect outlined 2 pt in `ok` (valid) or `err` (invalid), filled with that colour at 15 %.
  6. Three 10x10 pt white resize handles with an accent border on the selected widget: at the middle of the right edge, the middle of the bottom edge and the bottom-right corner.
- Gestures:
  - A tap on a widget selects it.
  - `DragGesture(minimumDistance: 3)` on a widget:
    - On the first change, select the widget.
    - While dragging, set the ghost to `geometry.moved(frame, by: translation)`, with `valid = store.model.canPlace(rect, ignoring: id)`, and draw the widget at 50 % opacity.
    - On end, call `store.setFrame` when the ghost is valid, then clear the ghost.
  - Each handle's `DragGesture(minimumDistance: 1)` does the same with `geometry.resized(frame, handle:, by:, minSize: widget.minSize)`.
  - `.dropDestination(for: String.self)`:
    - Map the first item with `PaletteItem(rawValue:)` and the location with `geometry.cell(at:)`, then call `store.add(item, col:, row:)`. Return whether that gave an id.
    - `isTargeted` sets `dropTargeted`, which draws a 2 pt accent border around the whole canvas.
  - The canvas binds no keyboard shortcuts. Deleting is the inspector's trash button with `⌘⌫` (Task 8). Never bind a shortcut without a modifier anywhere in the editor, because it would fire while typing in a text field.
- `LivePlaceholderView`:
  - A `BoardColors.panel` rounded rect, radius `8*scale`, with `LiveTitles.title(kind)` top-left in `textDim`, `11*scale` pt.
  - A body glyph in `BoardColors.ok`, `text` and `panelHi`:

    | Kind | Glyph |
    | --- | --- |
    | stat bar | a bar 60 % full |
    | stat number | the text `42%` |
    | stat sparkline | a 12-point zigzag polyline |
    | volume | a slider track with a knob at 40 % and a speaker symbol |
    | clock | `12:34` |
    | `claude_sessions` | `min(4, h*2)` rows, each a coloured dot and a grey bar |
    | `claude_usage` | two bars labelled `5h` and `7d` |

  - It is only a stand-in. Live widgets are drawn by the board.
- `WidgetPaletteView`:
  - An `HStack` of 6 tiles (`PaletteItem.allCases`), each 96x64 pt: the SF Symbol over the title, on `BoardColors.panelHi`, radius 8.
  - Each tile is `.draggable(item.rawValue)`, and a tap calls `store.add(item)`.
  - Opacity is 0.4 when `!store.model.canAdd(item)`.
  - `.help("Drag onto the grid, or click to add at the first free spot")`.

- [ ] **Step 1: Write the snapshot tests**

  `CanvasSnapshotTests` (`@Suite(.serialized)`, `@MainActor`; stores use `environment: .permissive` and temp app roots). Each test asserts the rep size and `!isUniform`, then saves:
  - `canvasDevPage`: `SampleConfig.dev` page 0 at scale 2 (1280x360) is 2560x720. Save as `canvas-dev`.
  - `canvasMacPage`: page 1 at scale 2. Save as `canvas-mac`.
  - `canvasClaudePage`: page 2 at scale 1 (640x180). Save as `canvas-claude`.
  - `canvasStates`:
    - On page 2, `add(.key)`, which lands at `(6,1)` and is an error.
    - Set a ghost through the interaction object injected for tests: `DeckCanvasView` takes an internal `interaction:` parameter whose default is a fresh object.
    - Select `ccusage`.
    - At scale 2, save as `canvas-states`.
  - `paletteNormalAndFull`: the palette for page 0 of `SampleConfig.dev` (full, so every tile is dim) and for a blank page, stacked in a `VStack` at 640x150. Save as `palette`.
  - `faceCacheReturnsPreview`: `FaceImageCache.shared.image(for: k)` has the same width, height and bytes as `FacePreview.image(for: k)`. A second call returns the same object (`===`).

- [ ] **Step 2: Run them and confirm they fail**

  Run: `$SWIFT_TEST --filter CanvasSnapshotTests`. Expected: compile errors.

- [ ] **Step 3: Implement the views above**

- [ ] **Step 4: Run the tests, write the snapshots, and review them**

  Run: `$SWIFT_TEST`. Expected: all pass.
  Run: `cd /Users/lek/WORK/MY_PROJECT/T-Display-S3-Long/mac/LongDeck && mkdir -p /Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots && LONGDECK_SNAPSHOT_DIR=/Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing --filter CanvasSnapshotTests`
  Open each PNG in `$SNAP_DIR` with the Read tool and check:
  - `canvas-dev.png`:
    - 16 keys in an 8x2 grid on a near-black background, with even gaps between keys and faint grid lines.
    - White labels at the bottom of each face.
    - White SF Symbols (magnifying glass, camera, globe, terminal, bolt, media and speaker symbols).
    - App icons for VS Code, iTerm, Chrome and Finder when those apps are installed.
    - Edges are crisp, with no blur.
  - `canvas-mac.png`: 10 placeholders in the right cells (cpu, gpu and ram 2 wide, clock 2 wide, volume 3 wide), each titled, for example `CPU · sparkline` and `Volume`.
  - `canvas-claude.png`: the sessions placeholder 4x2 on the left, usage 4x1 top right, clock 2x1 below it.
  - `canvas-states.png`: a red dashed outline on the new key at col 6, row 1; the accent outline plus three handles on `ccusage`; the ghost rect.
  - `palette.png`: six tiles twice, the top row dimmed.

  Fix and re-run until every check holds.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add the editor canvas and widget palette`

### Task 8: Inspector, action editor, app picker, hotkey recorder

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckEditor/`: `InspectorView.swift`, `ActionEditorView.swift`, `AppPickerView.swift`, `AppIconCache.swift`, `HotkeyRecorderView.swift`
- Test: `mac/LongDeck/Tests/LongDeckEditorTests/InspectorSnapshotTests.swift`, `HotkeyRecorderFieldTests.swift`

**Interfaces:**

```swift
public struct InspectorView: View { public init(store: EditorStore) }
struct ActionEditorView: View { init(store: EditorStore, keyId: String, slot: ActionSlot) }
final class AppPickerState: ObservableObject { @Published var query = ""; @Published var selection: String? }
struct AppPickerView: View {
    init(apps: [AppEntry], onPick: @escaping (AppEntry) -> Void, onCancel: @escaping () -> Void)
    init(apps: [AppEntry], state: AppPickerState, onPick: @escaping (AppEntry) -> Void, onCancel: @escaping () -> Void)   // tests
}
@MainActor final class AppIconCache { static let shared: AppIconCache; func icon(path: String) -> NSImage }   // NSWorkspace.shared.icon(forFile:)
struct HotkeyRecorderView: NSViewRepresentable {
    init(keyCode: UInt16, modifiers: [KeyModifier], onRecord: @escaping (DeckAction) -> Void)
}
final class HotkeyRecorderField: NSView {
    var keyCode: UInt16
    var modifiers: [KeyModifier]
    var onRecord: ((DeckAction) -> Void)?
    private(set) var isRecording: Bool
    var hasMonitor: Bool { get }
    @discardableResult func handle(_ event: NSEvent) -> NSEvent?   // the local monitor calls this; nil swallows the event
}
```

Behaviour required:
- `InspectorView` is 320 pt wide, inside a `ScrollView`, with sections separated by `Divider`.
  - **No selection.**
    - A `Page` section with a name `TextField` bound through `store.renamePage` (coalesced), a byte counter `<n>/23 bytes`, and `<count>/16 widgets`.
    - The hint `Drag a widget from the palette onto the grid, or click it to add.`
  - **Key selected.**
    - Header: `Key`, the id in secondary monospaced text, and a trash button (`store.remove`) with `.keyboardShortcut(.delete, modifiers: .command)`.
    - `Face`:
      - Label: a `TextField`, coalesced `label-<id>`.
      - Icon: a segmented `Picker` with `None`, `App`, `Symbol`.
        - `App` shows the app icon, its name and `Choose…`, which opens `AppPickerView`. The pick sets only `icon` through `updateKey`.
        - `Symbol` shows a name `TextField` (coalesced `symbol-<id>`) and a `Menu` of `SymbolCatalog.common` with each symbol image.
      - Background: a `ColorPicker` with `supportsOpacity: false`, bound through `HexColor.from(NSColor(color))` and coalesced `background-<id>`.
      - Text colour: a `ColorPicker` plus a `Default` button that sets `foreground = nil`.
      - A 1:1 face preview: `FaceImageCache` image at its board size, interpolation `.none`.
    - `Size`: `w` and `h` `Stepper`s that call `store.setFrame` with the new size at the same `col` and `row`, plus `Column <c>, row <r>` text.
    - `Action`: `ActionEditorView(slot: .primary)`.
    - `Long press`: a `Toggle`. Turning it on sets `ActionKind.openApp.defaultAction` on `.long`, and turning it off sets nil. When on, it shows `ActionEditorView(slot: .long)`.
    - `Issues`: `store.issues(forWidget:)`, errors red and warnings orange, one line each.
  - **Live widget selected.**
    - Header: `LiveTitles.title`, the id and a trash button with `⌘⌫`.
    - For a stat: `Metric` and `Style` `Picker`s calling `store.setStat`.
    - `Size` and `Issues` as for keys, and the caption `Drawn live on the board.`
- `ActionEditorView`:
  - A `Picker("Action")` over `ActionKind.allCases` titles. Choosing a different kind calls `store.setAction(kind.defaultAction, …)`. Choosing the same kind does nothing.
  - The value editor below it:

    | Kind | Editor |
    | --- | --- |
    | `openApp` | the icon (20 pt), name (`AppCatalog.name(forPath:)`, or `No app chosen`) and `Choose…`, which presents `AppPickerView` in a `.sheet` driven by an `ObservableObject` flag; a pick calls `store.chooseApp(app, slot:, for:)` |
    | `openURL` | a `TextField("https://…")` |
    | `hotkey` | a `HotkeyRecorderView` whose `onRecord` calls `store.setAction` |
    | `media` | a segmented `Picker`: Play/Pause, Next, Previous |
    | `volume` | a segmented `Picker`: Up, Down, Mute |
    | `typeText` | `TextField(axis: .vertical)`, 1–4 lines |
    | `shell` | `TextField(axis: .vertical)`, monospaced, captioned `Runs with /bin/zsh -lc. Output is discarded.` |
    | `shortcut` | a `TextField`, captioned `Runs the macOS Shortcut with this name.` |

  - Text edits are coalesced as `action-<slot>-<id>`.
- `AppPickerView`, 420x480:
  - A search `TextField` bound to `AppPickerState.query`.
  - A `List` of `AppCatalog.filter(apps, query:)` rows: a 24 pt icon from `AppIconCache`, the name, and `folder` in secondary text.
  - Buttons:
    - `Other…` opens an `NSOpenPanel` with `allowedContentTypes = [.application]`, `directoryURL` `/Applications` and one selection. The pick goes through `AppCatalog.entry(forApp:)`.
    - `Cancel`.
    - `Choose`, the default action, enabled with a selection.
  - A double-click on a row picks it.
- `HotkeyRecorderField`:
  - It draws a 180x24 rounded field. While recording it has a 2 pt accent border and shows the modifier glyphs held so far followed by `…`, or `Type a shortcut (esc cancels)`. When idle it shows `HotkeyFormat.display(keyCode:modifiers:)`.
  - `acceptsFirstResponder` is true. `mouseDown` calls `window?.makeFirstResponder(self)`.
  - `becomeFirstResponder` installs **one** `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])` that calls `handle`, and sets `isRecording`.
  - `resignFirstResponder` and `viewWillMove(toWindow: nil)` remove the monitor and clear `isRecording`.
  - `handle`, when not recording, returns the event unchanged. While recording:
    - A `keyDown` with `isARepeat` returns nil.
    - A `keyDown` where `HotkeyFormat.isCancel` is true ends recording through `window?.makeFirstResponder(nil)` and returns nil.
    - Any other `keyDown` calls `onRecord(HotkeyFormat.action(keyCode:flags:))`, updates `keyCode` and `modifiers`, ends recording and returns nil.
    - A `flagsChanged` updates the live display and returns the event.

- [ ] **Step 1: Write the tests**

  - `HotkeyRecorderFieldTests` (`@MainActor`): put the field in an offscreen `NSWindow` (never ordered front) and use `window.makeFirstResponder(field)`. Build events with `NSEvent.keyEvent(with:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:)`.
    - `recordsShortcutAndStops`: ⌘⇧4 (key code 21) returns nil, `onRecord` gets `.hotkey(keyCode: 21, modifiers: [.command, .shift])`, `isRecording` is false and `hasMonitor` is false.
    - `escapeCancels`: Escape returns nil, `onRecord` is never called, recording stops and `keyCode` is unchanged.
    - `idleFieldPassesEventsThrough`: before `makeFirstResponder`, `handle` returns the same event object.
    - `repeatIgnored`: an `isARepeat` key down returns nil, does not record, and recording continues.
    - `monitorRemovedWhenLeavingWindow`: after `makeFirstResponder(field)`, `field.removeFromSuperview()` gives `hasMonitor == false`.
    - `oneMonitorOnly`: `makeFirstResponder(field)`, then `makeFirstResponder(nil)`, then `makeFirstResponder(field)` again leaves exactly one monitor installed, and after the `nil` step none. Expose an `internal` monitor count for this test.
  - `InspectorSnapshotTests` (`@Suite(.serialized)`, `@MainActor`). The store holds `SampleConfig.dev`, temp app roots and `.permissive`. `calculator` is `AppEntry(name: "Calculator", path: "/System/Applications/Calculator.app", folder: "System")`, built by hand because the scanned name may be localized. Each test asserts not uniform and saves:
    - `inspectorPage`: no selection, 320x420. Save as `inspector-page`.
    - `inspectorAppKey`: select `vscode`, then `chooseApp(calculator, slot: .primary)` and `setAction(.media(.playPause), slot: .long)`. 320x760. Save as `inspector-key-app`.
    - `inspectorHotkeyKey`: select `screenshot`, 320x760. Save as `inspector-key-hotkey`.
    - `inspectorErrorKey`: on page 2, `add(.key)`, 320x760. Save as `inspector-key-error`.
    - `inspectorStat`: select `cpu` on page 1, 320x420. Save as `inspector-stat`.
    - `appPicker`: `AppPickerView(apps:state:…)` with three hand-built entries: `calculator`, `Calendar` (`/System/Applications/Calendar.app`, `System`) and `Tool` (the temp fake, `Test`). The injected `AppPickerState` has the query `cal`. 420x480. Save as `app-picker`.
    - `hotkeyRecorderStates`: two `HotkeyRecorderView`s, one with `21/[.command,.shift]` and one with `ActionKind.unsetKeyCode`, at 420x80. Save as `hotkey-recorder`.

- [ ] **Step 2: Run them and confirm they fail**

  Run: `$SWIFT_TEST --filter "HotkeyRecorderFieldTests|InspectorSnapshotTests"`. Expected: compile errors.

- [ ] **Step 3: Implement the views above**

- [ ] **Step 4: Run the tests, write the snapshots, and review them**

  Run: `$SWIFT_TEST`. Expected: all pass.
  Run: `cd /Users/lek/WORK/MY_PROJECT/T-Display-S3-Long/mac/LongDeck && mkdir -p /Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots && LONGDECK_SNAPSHOT_DIR=/Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing --filter InspectorSnapshotTests`
  Open each PNG with the Read tool and check:
  - `inspector-page.png`: the page name `Dev`, `3/23 bytes`, `16/16 widgets`, and the hint.
  - `inspector-key-app.png`:
    - The label stays `VS Code`, because it was customised and is not the old app's name. The App icon mode shows the Calculator icon, plus the background and text colour wells.
    - A face preview showing the Calculator icon over `VS Code`.
    - Action `Open app` → Calculator. Long press on, with `Media key` Play/Pause.
    - No issues.
  - `inspector-key-hotkey.png`: action `Hotkey` with the recorder showing `⇧⌘4`.
  - `inspector-key-error.png`: `Choose an app` in red under Issues, and `No app chosen`.
  - `inspector-stat.png`: Metric `CPU`, Style `Sparkline`, Size 2 x 1, and `Drawn live on the board.`
  - `app-picker.png`: the search field with `cal`, then `Calculator` and `Calendar` rows with their real icons and `System`. `Tool` is filtered out. The `Other…`, `Cancel` and `Choose` buttons show.
  - `hotkey-recorder.png`: `⇧⌘4` and `Not set`.

  Fix and re-run until every check holds.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add the editor inspector, app picker and hotkey recorder`

### Task 9: Pages list, issue list and the editor root view

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckEditor/`: `PageListView.swift`, `IssueListView.swift`, `EditorView.swift`
- Test: `mac/LongDeck/Tests/LongDeckEditorTests/EditorSnapshotTests.swift`

**Interfaces:**

```swift
struct PageListView: View { init(store: EditorStore) }
struct IssueListView: View { init(store: EditorStore) }
public struct EditorView: View { public init(store: EditorStore) }
```

Behaviour required:
- `PageListView`, 200 pt wide:
  - A `List` with selection bound to `store.model.pageIndex`, through `Binding(get:set:)` calling `store.selectPage`.
  - Each row shows the page name (or `Untitled` when empty) and `<n> widgets` in secondary text. A red dot shows when `store.pageHasErrors(i)`.
  - Under the list, four buttons:
    - `+` (`store.addPage()`), disabled at 8 pages.
    - `−` (`removePage(at: pageIndex)`), disabled with one page.
    - `↑` and `↓` (`movePage`), disabled at the ends.
  - Renaming happens in the inspector's Page section.
- `IssueListView`:
  - At most 140 pt high. It lists every issue as `<icon> <page name> · <widget id>: <message>` (the page and widget parts only when present), errors first in red, warnings in orange.
  - A tap calls `store.reveal(issue)`.
  - It shows `No issues` in secondary text when empty.
- `EditorView`:
  - A `VStack(spacing: 0)`:
    1. A banner in `BoardColors.warn` with the `diskError` text, when set.
    2. An `HStack(spacing: 0)` of:
       - `PageListView`
       - `Divider`
       - the centre column (padding 16, spacing 12)
       - `Divider`
       - `InspectorView`
  - The centre column holds:
    - The toolbar row:
      - `Undo` (`⌘Z`) and `Redo` (`⇧⌘Z`), disabled by `canUndo` / `canRedo`.
      - The current page name.
      - `Spacer`, then `store.status` in secondary text.
      - `Save` (`⌘S`, `.borderedProminent`), disabled unless `store.canSave`.
    - The canvas: `DeckCanvasView` in a `GeometryReader` over the column width, using `CanvasGeometry.fitting(width:)`, framed to the geometry's height.
    - `WidgetPaletteView`.
    - `IssueListView`.
  - The minimum frame is 1200x600.

- [ ] **Step 1: Write the snapshot tests**

  `EditorSnapshotTests` (`@Suite(.serialized)`, `@MainActor`; the store as in Task 8):
  - `editorFull`: `SampleConfig.dev`, select page 2, `add(.key)`. Render `EditorView` at 1440x760. Not uniform. Save as `editor-full`.
  - `editorDiskError`: `onDisk: false, diskError: "Invalid deck config: duplicate widget id a"`, at 1440x760. Save as `editor-disk-error`.
  - `pageList`: `SampleConfig.dev` with page 2 selected after `add(.key)`, at 200x360. Save as `pages`.
  - `issueListReveal`: after `add(.key)` on page 2 and `selectPage(0)`, `store.reveal(store.issues[0])` gives `pageIndex == 2` and the new key selected.

- [ ] **Step 2: Run them and confirm they fail**

  Run: `$SWIFT_TEST --filter EditorSnapshotTests`. Expected: compile errors.

- [ ] **Step 3: Implement the views above**

- [ ] **Step 4: Run the tests, write the snapshots, and review them**

  Run: `$SWIFT_TEST`. Expected: all pass.
  Run: `cd /Users/lek/WORK/MY_PROJECT/T-Display-S3-Long/mac/LongDeck && mkdir -p /Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots && LONGDECK_SNAPSHOT_DIR=/Users/lek/.claude/jobs/1fd8bef7/tmp/m4-snapshots swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing --filter EditorSnapshotTests`
  Open each PNG with the Read tool and check:
  - `editor-full.png`:
    - Pages `Dev`, `Mac`, `Claude` on the left, with `Claude` selected and a red dot.
    - The Claude page canvas, with the new key outlined red and selected.
    - The palette below the canvas, and the issue list showing `Claude · key: Choose an app`.
    - The inspector for the new key on the right.
    - `Save` disabled, because there is an error. `Undo` enabled.
    - Nothing clipped or overlapping.
  - `editor-disk-error.png`: the orange banner across the top with the error text.
  - `pages.png`: three rows, the selected one highlighted, and the `+ − ↑ ↓` buttons.

  Fix and re-run until every check holds.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): assemble the editor window content`

### Task 10: App wiring (window, save, watcher guard, menu, quit)

**Files:**
- Create: `mac/LongDeck/Sources/LongDeckApp/EditorWindowController.swift`, `mac/LongDeck/Sources/LongDeckApp/AppDelegate.swift`
- Modify: `mac/LongDeck/Sources/LongDeckApp/AppModel.swift`, `MenuView.swift`, `LongDeckApp.swift`

**Interfaces:**
- `AppModel` gains:
  - `private var writeGuard = ConfigWriteGuard()`
  - `var onConfigApplied: ((DeckConfig) -> Void)?`
  - `lazy var editorWindow = EditorWindowController(model: self)`
  - `func openEditor()`
  - `func editorDocument() -> (config: DeckConfig, onDisk: Bool, diskError: String?)`
  - `func saveFromEditor(_ config: DeckConfig) -> SaveOutcome`
- `@MainActor final class EditorWindowController: NSObject, NSWindowDelegate`:
  - `init(model: AppModel)` keeps a weak model.
  - `func show()`
  - `func closeForQuit() -> Bool`
  - `windowShouldClose(_:)` and `windowWillClose(_:)`
- `final class AppDelegate: NSObject, NSApplicationDelegate`: `static weak var editor: EditorWindowController?` and `applicationShouldTerminate(_:)`.
- `LongDeckApp` gains `@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate`.

Behaviour required:
- `AppModel`:
  - `editorDocument()` returns `(config ?? SampleConfig.dev, config != nil && configError == nil, configError)`.
  - `saveFromEditor`:
    1. `let data = try ConfigSaver.prepare(config)` and `try ConfigSaver.write(data, to: Self.configURL)`.
    2. `writeGuard.recordWrite(data)`, then `apply(config)`. `apply` already pushes through `connection?.push(config:)`, which skips a hash the board has and enforces the frame limit.
    3. Return `.sent` when `connection?.isReady == true`, else `.savedOffline`. Any thrown error gives `.failed("\(error)")`.
  - `apply(_:)` calls `onConfigApplied?(loaded)` after it pushes.
  - The two existing `try? SampleConfig.dev.save(to:)` call sites record the returned bytes in `writeGuard` when the save succeeds.
  - The debounced watcher reload (`scheduleReload`) no longer calls `reloadConfig()` directly. It calls a new `reloadFromWatcher()`, which reads the file bytes, returns early when `writeGuard.matches(data)`, and otherwise calls `reloadConfig()`. `armFileWatcher()` still runs after it. "Reload config" in the menu keeps calling `reloadConfig()` unconditionally.
  - `openEditor()` calls `editorWindow.show()`.
- `EditorWindowController.show()`:
  - If the window exists: `NSApp.activate(ignoringOtherApps: true)` and `makeKeyAndOrderFront(nil)`. Done.
  - Otherwise:
    1. Read `editorDocument()` and create `EditorStore(config:, onDisk:, diskError:)`.
    2. Set `store.onSave = { [weak model] in model?.saveFromEditor($0) ?? .failed("LongDeck is quitting") }` and `model.onConfigApplied = { [weak store] in store?.externalChange($0) }`.
    3. Create `NSWindow(contentRect: 1280x720, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)`:
       - title `LongDeck Editor`, `minSize` 1200x600, `isReleasedWhenClosed = false`
       - `contentView = NSHostingView(rootView: EditorView(store: store))`
       - `delegate = self`
       - `setFrameAutosaveName("LongDeckEditor")`, and `center()` when no saved frame was restored
    4. `NSApp.setActivationPolicy(.regular)`, so the Dock icon and the main menu (Edit: copy, paste) work while editing. Then `NSApp.activate(ignoringOtherApps: true)` and `makeKeyAndOrderFront(nil)`.
  - `init` sets `AppDelegate.editor = self`.
- `windowShouldClose` returns `confirmSaveIfNeeded()`:
  - true when there is no store or it is clean.
  - Otherwise an `NSAlert`:
    - message `Save changes to the layout?`
    - informative `If you don't save, your changes are lost.`
    - buttons `Save`, `Don't Save`, `Cancel`, run with `runModal()`
  - `Save` returns `store.save()`. The window stays open with the status visible when saving fails. `Don't Save` returns true, and `Cancel` returns false.
- `windowWillClose`: set `model?.onConfigApplied = nil`, drop the store and the window, and call `NSApp.setActivationPolicy(.accessory)`.
- `closeForQuit()`:
  - With no window, true.
  - Otherwise `confirmSaveIfNeeded()`. On true it closes the window (`window.close()` runs `windowWillClose`) and returns true.
- `AppDelegate.applicationShouldTerminate` returns `.terminateNow` when `AppDelegate.editor?.closeForQuit() ?? true`, else `.terminateCancel`. That covers both the menu's `Quit` and `⌘Q` from the main menu while the editor is open.
- `MenuView` gains `Button("Edit layout…") { model.openEditor() }` right after `Pair with board…`. `Quit` stays `NSApp.terminate(nil)`.

- [ ] **Step 1: Implement the changes above**

- [ ] **Step 2: Build and test**

  Run: `cd mac/LongDeck && swift build`. Expected: SUCCESS with no new warnings in the edited files.
  Run: `$SWIFT_TEST`. Expected: all pass.
  Run: `grep -rn "orderFront\|makeKeyAndOrderFront\|setActivationPolicy\|runModal" mac/LongDeck/Sources mac/LongDeck/Tests`. Expected matches:
  - `EditorWindowController.swift`
  - `AppPickerView.swift` (`NSOpenPanel` only)
  - the existing `ClaudeController.swift` alerts

  No test file matches.
  Do not run `bundle.sh`, open the app, or click anything. The owner checks the behaviour in E1–E14.

- [ ] **Step 3: Commit**

  Message: `feat(longdeck): open the layout editor from the menu and save through the app`

### Task 11: Docs

**Files:**
- Modify: `mac/LongDeck/README.md`:
  - Add `## Editor` after `## Config`. Cover:
    - Opening it with "Edit layout…".
    - The pages list (+ − ↑ ↓, at most 8, rename in the inspector).
    - The palette: drag onto the grid, or click to add at the first free spot.
    - Move by dragging, resize with the three handles, delete with ⌘⌫.
    - The inspector fields, and that the text colour also tints SF Symbols.
    - The app picker (`/Applications`, `/System/Applications`, `~/Applications`, `Other…`) and that it sets the icon.
    - The hotkey recorder: click, press the combo, Esc cancels.
    - Undo and redo.
    - Save with ⌘S: errors block saving, and the board updates now or on its next connect.
    - The close and quit prompts, and the Dock icon while the window is open.
    - The new optional `foreground` key and the readable file format.
  - Change the `## Config` paragraph to say the editor writes the file. Hand edits still work and are picked up.
- Modify: `examples/ntp_clock/README.md`, LongDeck section. In Thai like the rest of the file, with technical terms in English, replace "edit config.json" in step 2 with: open the menu "Edit layout…", drag widgets onto the 8x2 grid, and press Save to push. Keep the 15360-byte note, worded as "the editor warns before saving".

- [ ] **Step 1: Write the sections above.** Keep the editor section to about 3 short paragraphs plus one JSON example of a key with `foreground`.

- [ ] **Step 2: Commit**

  Message: `docs(longdeck): document the layout editor`

## Hardware and live checklist (owner, after all tasks)

Agents do not run this. Build with `cd mac/LongDeck && LONGDECK_SIGN_ID="LongDeck Dev" ./scripts/bundle.sh`, back up the config with `cp ~/Library/Application\ Support/LongDeck/config.json /tmp/config.before.json`, then open `build/LongDeck.app`. The board is on Wi-Fi and paired as in M1–M3.

- [ ] **E1 Open.** "Edit layout…" opens the editor window in front, with a LongDeck Dock icon. The canvas shows the current Dev page exactly as the board shows it, and the colours and icons match side by side.
- [ ] **E2 Palette.** Drag `Stat` onto an empty cell: it lands there 2x1, or 1x1 when only one cell is free. Click `Clock`: it lands at the first free spot. On a full page the tiles are dim and a drop does nothing, with the status `No room there`.
- [ ] **E3 Move and resize.** Drag a key across the grid: the ghost snaps to whole cells, is red over another widget, and a red drop does nothing. Resize with each handle. `claude_sessions` cannot go below 2 columns.
- [ ] **E4 App picker.** Add a key and choose Calculator: the icon and label update in the canvas and the face preview. "Other…" can pick `/System/Library/CoreServices/Finder.app`. Search filters as you type.
- [ ] **E5 Hotkey.** Record ⇧⌘4 (no screenshot is taken while recording) and save. Pressing the key on the board takes a screenshot. Esc cancels a recording. Typing in the label field afterwards works normally, so the monitor is gone.
- [ ] **E6 Colours and text.** Change the background and text colours. The preview matches the board after Save. Copy and paste work in text fields.
- [ ] **E7 Save.**
  - ⌘S shows "Saved. Sending to the board." and the board shows the new layout within a few seconds.
  - The board serial log shows **one** `[deck] layout <hash>: N pages` line per save.
  - `config.json` is indented, with unescaped `/Applications/...` paths.
  - `diff <(jq -S . /tmp/config.before.json) <(jq -S . ~/Library/Application\ Support/LongDeck/config.json)` shows only your edits.
- [ ] **E8 Outside edit.**
  - With the editor clean, change `config.json` by hand (for example a key label): the editor shows it, and the board updates as before.
  - With unsaved editor changes, a hand edit is ignored by the editor. The editor's Save then overwrites it.
- [ ] **E9 Close prompt.** Make a change and close the window: Save / Don't Save / Cancel. Cancel keeps the window, Don't Save closes it and discards the change, and Save saves and closes. The Dock icon disappears after closing.
- [ ] **E10 Quit prompt.** Make a change, then use ⌘Q and the menu-bar "Quit": the same prompt shows, and Cancel keeps the app running.
- [ ] **E11 Undo and redo.** ⌘Z and ⇧⌘Z step through add, move, resize, label typing (one step per field) and page reorder. Undo back to the saved state disables Save.
- [ ] **E12 Errors.** A new key without an app, an empty shell command and an unrecorded hotkey each show a red outline and an issue row, and keep Save disabled. Clicking the issue row selects the widget. Seven full pages of 1x1 stats show the "Layout is … bytes" error.
- [ ] **E13 Offline.** Turn the board off and save: "Saved. The board updates when it connects." Turn it on: the new layout arrives after the reconnect.
- [ ] **E14 Regression.** Keys, live widgets, the volume slider, Claude widgets and the permission overlay work as before. A config saved by M3 loads unchanged in the editor, with no spurious dirty state.

## Execution order

- **One Mac lane, strictly sequential:** Task 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10.
  - Every task builds the same SwiftPM package, and SwiftPM locks `.build`. A half-written file in one target breaks `swift test` for every other task.
  - Each task also consumes the previous ones: Task 3 uses Task 2's `CellRect`, Task 5 uses Tasks 1–4, and the view tasks use the store and model.
  - Tasks 1–5 are `LongDeckCore` (Swift 6). Tasks 6–9 are `LongDeckEditor` (Swift 5), and Task 10 is the app target.
- **Task 11** edits only the two READMEs and builds nothing. It may run in parallel with Task 10, once Task 9 is done.
- No two concurrent tasks share a file. `Package.swift` belongs to Task 6 only, `AppModel.swift`, `MenuView.swift` and `LongDeckApp.swift` to Task 10 only, and `DeckConfig.swift` and `FaceRenderer.swift` to Task 1 only.
- No firmware lane: nothing under `examples/ntp_clock/` changes except its README in Task 11.
- Then the owner runs the Hardware and live checklist.

## Decisions made while planning

- **A new `LongDeckEditor` library target holds the SwiftUI views.** Tests can only import libraries, and the views must render offscreen for review. The app target keeps only the window controller and the wiring.
- **The editor window is an AppKit `NSWindow` with `NSHostingView`, not a SwiftUI `Window` scene,** because only `windowShouldClose` can refuse to close for the save prompt. The app switches to `.regular` while the editor is open and back to `.accessory` on close. Without a visible main menu, an `LSUIElement` app's text fields have no copy or paste shortcuts.
- **Quit goes through `applicationShouldTerminate`** (`@NSApplicationDelegateAdaptor`), so both the menu-bar Quit and ⌘Q ask about unsaved changes.
- **"Colours" means background plus an optional text colour.** `KeyConfig.foreground` also tints SF Symbols. It is omitted from JSON when nil, so M1–M3 configs, faces and layout hashes are unchanged.
- **The live preview is the editor canvas.** Key faces come from the same `FaceRenderer` bytes the board gets, decoded from RGB565 and blended over `COLOR_PANEL` with LVGL 8.4's mix formula. The board changes only on Save; unsaved edits are never pushed.
- **The saved file is pretty-printed with sorted keys, unescaped slashes and a trailing newline,** to make it human-readable as the spec asks.
- **Empty action values are errors that block Save.** That covers no app, an empty URL, command, text or Shortcut name, and an unrecorded hotkey. A missing app path is only a warning, because it may be installed later. A new key starts as "Open app" with no app, so it shows red until configured.
- **An unrecorded hotkey uses key code 65535.** The editor never saves it.
- **Hotkey recorder:** bare Escape cancels, and any other key (bare F-keys included) is accepted. The local monitor exists only while the field is first responder.
- **Drop placement:** the item's default size at the drop cell, shifted to fit the grid, then its minimum size; otherwise the drop is refused. A click adds at the first free spot in row-major order.
- **At least one page always exists.** New pages are appended as `Page N`. Pages are renamed in the inspector's Page section.
- **Choosing an app always sets the key icon to the app,** as the spec asks. The label follows only when it is empty, still `Key`, or the previous app's name. A long-press app choice never changes the face.
- **Outside changes to `config.json` while the editor is open** replace the editor document only when it is clean. With unsaved edits the editor wins, because the app is the file's only writer.
- **An invalid `config.json` on disk** opens the editor on the last valid config (or the sample), marked dirty, with a banner. Saving replaces the bad file.
- **No double push.** `ConfigWriteGuard` skips watcher reloads of the bytes the editor just wrote, and `DeckConnection.push` already skips a hash the board has.
- **The frame-size check adds 9 bytes of slack** for the real sequence number, so a layout the editor accepts always fits when it is sent.
- **Undo** is a snapshot stack of 100 steps, with typing coalesced per field.
- **Out of scope:** moving or duplicating widgets across pages, label fonts, emoji icons, and listing the user's Shortcuts.

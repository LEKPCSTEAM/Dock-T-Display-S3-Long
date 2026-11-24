# LongDeck Milestone 1 (Link and Keys) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The clock firmware becomes LongDeck. It pairs with a new macOS menu-bar app over Wi-Fi and shows custom key pages that the app pushes. Pressing a key makes the Mac run that key's action.

**Architecture:**

- The board runs a WebSocket server (port 81) inside `net_task`. The app finds it over Bonjour and connects as the client.
- Pairing uses X25519 with a 6-digit code shown on the board.
- Each connection derives a session key from fresh nonces. Every frame after the handshake carries a sequence number and an HMAC-SHA256.
- The app renders key faces as bitmaps. The board caches the layout and faces in LittleFS and builds the deck tiles at runtime, after the four fixed clock tiles.
- The pure protocol, crypto and layout code compiles both on the device and in a PlatformIO `native` test environment.

**Tech Stack:**

- Firmware: Arduino-ESP32 2.0.17 (`espressif32@6.13.0`), LVGL 8.4 (`lib/lvgl`), `links2004/WebSockets@2.6.1`, `bblanchon/ArduinoJson@7.2.1`, LittleFS. Vendored public-domain SHA-256 (Brad Conte) and TweetNaCl (scalarmult only). Unity tests on PlatformIO `native`.
- Mac: Swift 6.4 Package, SwiftUI `MenuBarExtra`, CryptoKit, Network.framework, `URLSessionWebSocketTask`, CGEvent, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-24-clock-deck-design.md`. This plan covers milestone 1. The live widgets, the Claude integration and the editor are out of scope.

## Global Constraints

- Firmware code lives in `examples/ntp_clock/`. The Mac app lives in `mac/LongDeck/`. Do not modify `lib/`.
- Never hand-edit `examples/ntp_clock/eez/gen/` or the `.eez-project` JSON. Change EEZ content only through the `eez-studio` MCP or CLI, then build.
- Comments: English, one line, at most about 10 words, only what the code cannot say. No file or class overview blocks.
- The board must never show or accept user-visible names "ThaiClock", "thaiclock", "Thai Clock", "ThaiDeck" or "นาฬิกาไทย".
- Custom-page grid: 8 columns x 2 rows, cell 80x90 px. A widget sits at `(col*80+3, row*90+3)`. Its size and face size are `(w*80-6) x (h*90-6)`.
- Caps: 8 deck pages, 16 widgets per page, 128 faces, layout JSON 16 KB.
- Face pixels are 3 bytes each: RGB565 **big-endian**, then A8. This matches `LV_IMG_CF_TRUE_COLOR_ALPHA` with `LV_COLOR_16_SWAP 1`.
- mDNS service `_longdeck._tcp`, port 81, TXT `id=<12 lowercase hex of the STA MAC>`.
- Bundle id `dev.longdeck.LongDeck`. Config path `~/Library/Application Support/LongDeck/config.json`.
- Run Swift commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (`xcode-select` points at CommandLineTools).
- Hooks, the Claude integration, stats and the editor UI are **not** part of milestone 1.

## Protocol (both sides implement exactly this)

Unauthenticated handshake frames are plain JSON text:

| Dir | Frame |
| --- | --- |
| app→board | `{"t":"hello","v":1,"nonce":"<32 hex>"}` |
| board→app | `{"t":"challenge","v":1,"nonce":"<32 hex>","paired":<bool>,"id":"<12 hex>"}` |
| app→board | `{"t":"auth","proof":"<64 hex>"}` with `HMAC(K, "app" ‖ board_nonce ‖ app_nonce)` |
| board→app | `{"t":"auth_ok","proof":"<64 hex>"}` with `HMAC(K, "board" ‖ app_nonce ‖ board_nonce)`, or `{"t":"error","code":"auth"}`, then close |
| app→board | `{"t":"pair_start","pub":"<64 hex>"}` (accepted any time after `challenge`) |
| board→app | `{"t":"pair_pub","pub":"<64 hex>"}`, or `{"t":"error","code":"busy"}` |
| app→board | `{"t":"pair_confirm","proof":"<64 hex>"}` with `HMAC(K', "confirm")` |
| board→app | `{"t":"pair_ok"}`. The app then sends `auth` using the same nonces. |

Pairing rules:

- `K' = SHA256(shared ‖ board_pub ‖ app_pub)`. X25519 keys and the shared secret are 32 bytes in the raw RFC 7748 little-endian form.
- Code = big-endian u32 of `HMAC(K', "pin")[0..3]`, mod 1 000 000, shown as 6 digits.
- The pairing code shows for at most 60 s.
- A `pair_start` arriving within 10 s of the previous one, or while a pairing is active, gets `busy`.
- The old key stays until `pair_confirm` verifies.

Session rules:

- Session key: `Ks = HMAC(K, "session" ‖ board_nonce ‖ app_nonce)`.
- Text frame: `{"t":"<type>","s":<u32>,"b":"<body JSON as a string>","m":"<64 hex>"}` with `m = HMAC(Ks, t ‖ "\n" ‖ decimal(s) ‖ "\n" ‖ b)`.
- Each direction counts `s` from 1. The receiver requires `s > last`, otherwise it closes.
- Binary frame: `0x46 ‖ s (u32 LE) ‖ mac[32] ‖ payload`, where `mac = HMAC(Ks, s(u32 LE) ‖ payload)`.
- Face chunk payload: `id u16 | w u16 | h u16 | y u16 | n u16` (all LE), then `w*n*3` pixel bytes. Each chunk is at most 12 KB.
- Message types:
  - app→board: `layout` (body = layout JSON) and face chunks.
  - board→app: `hello_state` with body `{"hash":"<16 hex or empty>"}`, sent once on Ready.
  - board→app: `press` with body `{"id":"<id>","kind":"tap"|"long"}`.
  - board→app: `page` with body `{"index":<deck page index or -1>}`.

Layout JSON:

```json
{"hash":"<16 hex>","pages":[{"name":"Dev","widgets":[{"id":"k1","type":"key","col":0,"row":0,"w":1,"h":1,"face":1,"long":false}]}]}
```

Test vectors. Shared by C++ and Swift tests:

- `K = 01 02 … 20` (32 bytes)
- `board_nonce = 10 11 … 1f`
- `app_nonce = 20 21 … 2f`

| Name | Value |
| --- | --- |
| `HMAC(K,"pin")` | `df18efbd810d7116591c8169c19386c2338e3f979e101cf7982afeb933c393ea` → code `953405` |
| app proof | `d8553dc93579ca07ca09ceaced0ae03beb2f50cbc05a811b84eae10a3d578adc` |
| board proof | `be8865b415254711f8712bac2543ea4f52fa39e8ccfd18e40dac9c5180cb4647` |
| confirm proof | `735fdd274a689ef40299136ed2f37ccd6b5be7d8f10b86dbf08eecf8b281fb06` |
| `Ks` | `f30b85454b252c5c01eb34d0352494ace01b9084a912da17aa6c413bb797f9cf` |
| `m` for `press`, s=1, b=`{"id":"k1","kind":"tap"}`, key `Ks` | `8af257832884a4edc1f300cf890aed11f0311e20987315e2498ab218314292bd` |
| face chunk mac, key `K`, s=1, payload `01 00 01 00 01 00 00 00 01 00 f8 00 ff` | `86bd1fd5de4300ce41a05a415509242569b7c27f9035f759cfc6545f4d63c5e3` |
| `SHA256(01×32 ‖ 02×32 ‖ 03×32)` (derive-key shape) | `8a2e491356cfdb05a1d13785e0794d7cd163f91af79a146c976b1d2ac643b679` |

X25519 is checked against RFC 7748 §6.1 (Alice/Bob keys and the shared secret, copied from the RFC).

## Review Focus

1. **Replay of a captured frame on a later connection.** It must be rejected, because `Ks` changes per connection. Tests: Task 3 `test_frame_from_other_session_rejected`, Task 4 `opener rejects frame sealed with another session key`.
2. **Mac sleeps or Wi-Fi drops without a close.** The board must notice within about 15 s and show the deck as offline. The app must reconnect with backoff. Tests: Task 8 heartbeat step (device check), Task 9 `ReconnectPolicy` test.
3. **Malformed, oversized or out-of-grid layout from the app.** The board rejects it, keeps the previous cache, and keeps running. Tests: Task 5 rejection tests, Task 8 "bad layout keeps cache" device check.
4. **A second client connects while one is Ready.** An unauthenticated second socket must not disturb the Ready one. A second socket that authenticates replaces the first. Test: Task 8 device check with two `websocat` sessions.
5. **Accessibility permission not granted.** Hotkey, media and type-text actions must not crash. The menu must show a "Grant Accessibility…" item. Test: Task 9 `ActionRunner reports permission error` test.

---

### Task 1: Native test environment and firmware crypto

**Files:**
- Modify: `platformio.ini`
- Create: `examples/ntp_clock/vendor/sha256.c`, `examples/ntp_clock/vendor/sha256.h` (Brad Conte crypto-algorithms, public domain, unmodified)
- Create: `examples/ntp_clock/vendor/tweetnacl.c`, `examples/ntp_clock/vendor/tweetnacl.h` (TweetNaCl 20140427, public domain, unmodified)
- Create: `examples/ntp_clock/deck_crypto.h`, `examples/ntp_clock/deck_crypto.cpp`
- Test: `examples/ntp_clock/test/test_crypto/test_main.cpp`

**Interfaces:**
- Produces (C++, `deck_crypto.h`, no Arduino includes):
  - `void deck_sha256(const uint8_t *msg, size_t len, uint8_t out[32]);`
  - `void deck_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t len, uint8_t out[32]);`
  - `void deck_x25519_public(uint8_t pub[32], const uint8_t priv[32]);`
  - `void deck_x25519_shared(uint8_t shared[32], const uint8_t priv[32], const uint8_t peer_pub[32]);`
  - `void deck_derive_key(uint8_t key[32], const uint8_t shared[32], const uint8_t board_pub[32], const uint8_t app_pub[32]);`
  - `void deck_session_key(uint8_t ks[32], const uint8_t key[32], const uint8_t board_nonce[16], const uint8_t app_nonce[16]);`
  - `uint32_t deck_pair_code(const uint8_t key[32]);`
  - `bool deck_ct_equal(const uint8_t *a, const uint8_t *b, size_t len);`
  - `void deck_hex_encode(const uint8_t *in, size_t len, char *out);` (writes `2*len` lowercase chars plus NUL)
  - `bool deck_hex_decode(const char *in, uint8_t *out, size_t out_len);` (exact length, either case)

- [ ] **Step 1: Restructure `platformio.ini` so a native env can exist**

  - Rename the `[env]` section to `[esp32_base]`, and change every `extends = env` to `extends = esp32_base`. A bare `[env]` is inherited by every env, the native one included.
  - Add `[platformio] test_dir = examples/ntp_clock/test`.
  - In `[env:ntp_clock]`, append `-<test/>` to `build_src_filter`. Add `lib_deps = bblanchon/ArduinoJson@7.2.1 links2004/WebSockets@2.6.1` and `build_flags = ${esp32_base.build_flags} -DWEBSOCKETS_SERVER_CLIENT_MAX=2`.
  - Add `[env:native_deck]` with `platform = native`, `test_framework = unity`, `test_build_src = yes`, `build_flags = -std=gnu++17`, `lib_deps = bblanchon/ArduinoJson@7.2.1`, and `build_src_filter = -<*> +<deck_crypto.cpp> +<deck_proto.cpp> +<deck_layout.cpp> +<vendor/>`.

- [ ] **Step 2: Write failing tests in `test/test_crypto/test_main.cpp`**

  - `test_hmac_rfc4231_case1` and `test_hmac_rfc4231_case2`: RFC 4231 HMAC-SHA256 vectors.
  - `test_x25519_rfc7748`: Alice's and Bob's public keys match the RFC. Both `deck_x25519_shared` directions equal the RFC shared secret.
  - `test_pair_code_vector`: `deck_pair_code(K) == 953405`.
  - `test_session_key_vector`: `deck_session_key` equals the `Ks` vector.
  - `test_derive_key_shape`: `deck_derive_key(…, 01×32, 02×32, 03×32)` equals `8a2e4913…b679`.
  - `test_hex_roundtrip`: round-trips through encode and decode. `deck_hex_decode` rejects a wrong length and a non-hex character.
  - `test_ct_equal`: equal and unequal buffers.

- [ ] **Step 3: Run the tests and confirm they fail**

  Run: `pio test -e native_deck -f test_crypto`
  Expected: link or compile errors for the missing `deck_*` symbols.

- [ ] **Step 4: Implement `deck_crypto.cpp` on the vendored code**

  - HMAC follows RFC 2104 over `sha256.c`.
  - X25519 uses `crypto_scalarmult` and `crypto_scalarmult_base` from TweetNaCl.
  - Define `extern "C" void randombytes(unsigned char *, unsigned long long)` as a stub that `abort()`s. TweetNaCl references it, and LongDeck never calls the keypair helpers.

- [ ] **Step 5: Run the tests and confirm they pass, then confirm the firmware still builds**

  Run: `pio test -e native_deck -f test_crypto`. Expected: all PASS.
  Run: `pio run -e ntp_clock`. Expected: SUCCESS.

- [ ] **Step 6: Commit**

  Commit `platformio.ini`, `vendor/`, `deck_crypto.*` and `test/test_crypto/` with the message `feat(longdeck): add native test env and deck crypto`.

### Task 2: Swift package skeleton and crypto

**Files:**
- Create: `mac/LongDeck/Package.swift`. Use swift-tools 6.0 and `.macOS(.v14)`. Targets: library `LongDeckCore`, executable `LongDeckApp` (a stub `@main` for now), test target `LongDeckCoreTests`.
- Create: `mac/LongDeck/Sources/LongDeckCore/DeckCrypto.swift`
- Create: `mac/LongDeck/Sources/LongDeckApp/LongDeckApp.swift`
- Create: `mac/LongDeck/.gitignore` (`.build/`, `build/`)
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/DeckCryptoTests.swift`

**Interfaces:**
- Produces (`enum DeckCrypto`, all `static`, `Data` in and out):
  - `hmac(key:message:)`
  - `sha256(_:)`
  - `pairCode(key:) -> UInt32`
  - `pairCodeString(key:) -> String` (6 digits, zero-padded)
  - `deriveKey(shared:boardPub:appPub:)`
  - `sessionKey(key:boardNonce:appNonce:)`
  - `appProof(key:boardNonce:appNonce:)`
  - `boardProof(key:appNonce:boardNonce:)`
  - `confirmProof(key:)`
  - `hex(_:) -> String`
  - `unhex(_:) -> Data?`
  - `newKeyPair() -> (priv: Curve25519.KeyAgreement.PrivateKey, pub: Data)`
  - `shared(priv:peerPub:) throws -> Data`

- [ ] **Step 1: Write failing tests (Swift Testing) in `DeckCryptoTests.swift`**

  Assert every value in the Protocol test-vector table: pair code `953405` and `"953405"`, app proof, board proof, confirm proof, `Ks`, and the derive-key shape. Add an X25519 test against RFC 7748 §6.1 using `Curve25519.KeyAgreement.PrivateKey(rawRepresentation:)`.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `cd mac/LongDeck && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
  Expected: compile error, `DeckCrypto` not found.

- [ ] **Step 3: Implement `DeckCrypto` with CryptoKit**

  Use `HMAC<SHA256>` and `SHA256`. For `shared`, use `sharedSecretFromKeyAgreement(with:)` and read its raw bytes with `withUnsafeBytes`. Do not use the HKDF helpers.

- [ ] **Step 4: Run the tests and confirm they pass**

  Same command. Expected: all pass.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add mac package and deck crypto`

### Task 3: Firmware session protocol (`DeckSession`)

**Files:**
- Create: `examples/ntp_clock/deck_proto.h`, `examples/ntp_clock/deck_proto.cpp`
- Test: `examples/ntp_clock/test/test_proto/test_main.cpp`

**Interfaces:**
- Consumes: `deck_crypto.h` (Task 1), ArduinoJson 7.
- Produces (`deck_proto.h`, no Arduino includes):

```cpp
#define DECK_WS_PORT           81
#define DECK_PROTO_VERSION     1
#define DECK_PAIR_TIMEOUT_MS   60000
#define DECK_PAIR_COOLDOWN_MS  10000
#define DECK_FACE_CHUNK_MAX    (12 * 1024)

struct DeckEnv {
    void     (*random)(uint8_t *buf, size_t len);
    bool     (*load_key)(uint8_t key[32]);
    void     (*store_key)(const uint8_t key[32]);
    void     (*pair_code)(uint32_t code, bool show);
    uint32_t (*now_ms)();
    const char *board_id;  // 12 lowercase hex
};

struct DeckFaceChunk { uint16_t id, w, h, y, n; const uint8_t *px; size_t px_len; };

class DeckSession {
public:
    explicit DeckSession(const DeckEnv *env);
    bool on_text(const char *data, size_t len, std::vector<std::string> *replies);  // false = close
    bool on_binary(const uint8_t *data, size_t len);                               // false = close
    void tick();
    bool seal(const char *type, const char *body_json, std::string *out);           // false unless ready
    bool ready() const;
    void (*on_message)(void *ctx, const char *type, const char *body, size_t body_len) = nullptr;
    void (*on_face)(void *ctx, const DeckFaceChunk *chunk) = nullptr;
    void *ctx = nullptr;
};
```

  - Pairing cooldown state is per process (file-static in `deck_proto.cpp`), so a new socket cannot bypass it.
  - `deck_proto_reset_for_test()` clears it for tests.

- [ ] **Step 1: Write the failing tests**

  The fake env's `random` returns `10 11 … 1f` for the nonce, then fixed bytes for the X25519 private key. Its `load_key` returns `K` or false, and it records `store_key` and `pair_code` calls.

  - `test_hello_gets_challenge`: the reply has `t=challenge`, `v=1`, `nonce="101112…1f"`, `paired=true`, and `id` equal to the env board id.
  - `test_auth_ok_vector`: `auth` with the app-proof vector gets an `auth_ok` reply carrying the board-proof vector, and `ready()` becomes true.
  - `test_auth_bad_proof_closes`: one flipped byte makes `on_text` return false, with an `error`/`auth` reply.
  - `test_frame_before_ready_closes`: a sealed-shape frame before auth returns false.
  - `test_seal_vector`: once ready, `seal("press", "{\"id\":\"k1\",\"kind\":\"tap\"}")` yields `s=1` and the `m` vector.
  - `test_replay_rejected`: a valid app frame with `s=1` is accepted, and the same frame again returns false.
  - `test_frame_from_other_session_rejected`: a frame sealed under `Ks` from different nonces returns false.
  - `test_message_dispatch`: a valid `layout` frame calls `on_message` with type `layout` and the body bytes.
  - `test_face_chunk_dispatch`: a valid binary chunk calls `on_face` with `id=1 w=1 h=1 y=0 n=1` and the 3 pixel bytes. A bad mac returns false. A chunk over 12 KB returns false.
  - `test_pair_flow`: with no key, `pair_start` with the app pub gets `pair_pub`, and `pair_code(code, true)` is called with `code == deck_pair_code(K')`. The test computes `K'` through `deck_crypto`. `pair_confirm` with `HMAC(K',"confirm")` calls `store_key(K')` and gets `pair_ok`. A following `auth` under `K'` succeeds.
  - `test_pair_wrong_confirm_keeps_old_key`: `store_key` is not called, and the reply is an `error`.
  - `test_pair_cooldown_busy`: a second `pair_start` within 10 s from a new `DeckSession` gets `error`/`busy`.
  - `test_pair_timeout_hides_code`: `tick()` at `now+60000` calls `pair_code(_, false)`.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `pio test -e native_deck -f test_proto`. Expected: compile errors.

- [ ] **Step 3: Implement `DeckSession` in `deck_proto.cpp`**

  It is a state machine: `AwaitHello → AwaitAuth (⇄ Pairing) → Ready`. Parse JSON with ArduinoJson `JsonDocument`, and compare MACs with `deck_ct_equal`.

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `pio test -e native_deck`. Expected: `test_crypto` and `test_proto` PASS.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add board session protocol`

### Task 4: Swift frames and handshake

**Files:**
- Create: `mac/LongDeck/Sources/LongDeckCore/DeckFrames.swift`, `mac/LongDeck/Sources/LongDeckCore/DeckHandshake.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/DeckFramesTests.swift`, `mac/LongDeck/Tests/LongDeckCoreTests/DeckHandshakeTests.swift`

**Interfaces:**
- Consumes: `DeckCrypto` (Task 2).
- Produces:
  - `struct FrameSealer`:
    - `init(sessionKey: Data)`
    - `mutating func seal(type: String, body: String) -> String`
    - `mutating func faceChunks(id: UInt16, w: UInt16, h: UInt16, pixels: Data) -> [Data]`. Splits into chunks of at most 12 KB and seals each.
  - `struct FrameOpener`:
    - `init(sessionKey: Data)`
    - `mutating func open(_ text: String) throws -> (type: String, body: String)`. Throws `FrameError.badMac`, `.replay` or `.malformed`.
  - `enum HandshakeOutput: Equatable { case send(String), needPairCode, ready(sessionKey: Data, boardId: String), paired(key: Data, boardId: String), failed(String) }`
  - `struct DeckHandshake`:
    - `init(storedKey: (String) -> Data?, random: (Int) -> Data, keyPair: () -> (Curve25519.KeyAgreement.PrivateKey, Data))`
    - `mutating func start() -> [HandshakeOutput]`
    - `mutating func receive(_ text: String) -> [HandshakeOutput]`
    - `mutating func beginPairing() -> [HandshakeOutput]`
    - `mutating func submitPairCode(_ code: String) -> [HandshakeOutput]`. A wrong code gives `.failed("code")` and sends nothing.

- [ ] **Step 1: Write the failing tests**

  - Frames:
    - `seal matches vector`: `Ks` with the press body gives the `m` vector, and `s` is 1.
    - `faceChunks single pixel matches vector`: a sealer keyed with `K` produces the face-chunk mac vector.
    - `faceChunks splits large face`: a 1x1 face (74x84 px, 18 648 B) gives 2 chunks. Each payload is at most 12 KB, and their `n` values add up to 84.
    - `opener rejects replay`.
    - `opener rejects frame sealed with another session key`.
    - `opener rejects tampered body`.
  - Handshake. The fake `random` gives `20…2f` for the app nonce:
    - `start sends hello`.
    - `paired board yields auth then ready`: the challenge JSON uses the vector nonce. The output is `send(auth)` with the app-proof vector. On `auth_ok` with the board-proof vector, it gives `.ready(Ks vector, id)`.
    - `bad board proof fails`.
    - `unknown board asks to pair`: a challenge with `paired:false` and no stored key gives `.needPairCode` after `beginPairing()` and a `pair_pub` reply.
    - `pair code mismatch fails`.
    - `pair code match sends confirm then auth`: the test computes the expected code from `K'`.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `cd mac/LongDeck && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. Expected: compile errors.

- [ ] **Step 3: Implement both types per the Protocol section**

  Body strings are produced with `JSONSerialization` or `JSONEncoder` with `.sortedKeys`. The MAC covers the exact string sent.

- [ ] **Step 4: Run the tests and confirm they pass**

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add mac frames and handshake`

### Task 5: Firmware layout parser

**Files:**
- Create: `examples/ntp_clock/deck_layout.h`, `examples/ntp_clock/deck_layout.cpp`
- Test: `examples/ntp_clock/test/test_layout/test_main.cpp`

**Interfaces:**
- Produces (`deck_layout.h`, no Arduino includes):

```cpp
#define DECK_COLS 8
#define DECK_ROWS 2
#define DECK_MAX_PAGES 8
#define DECK_MAX_WIDGETS 16
#define DECK_MAX_FACES 128
#define DECK_LAYOUT_MAX_BYTES (16 * 1024)

enum DeckWidgetType : uint8_t { DW_KEY = 0, DW_UNKNOWN = 255 };
struct DeckWidget { char id[16]; uint8_t type, col, row, w, h; uint16_t face; bool has_long; };
struct DeckPage   { char name[24]; uint8_t count; DeckWidget widgets[DECK_MAX_WIDGETS]; };
struct DeckLayout { char hash[17]; uint8_t page_count; DeckPage pages[DECK_MAX_PAGES]; };

bool deck_layout_parse(const char *json, size_t len, DeckLayout *out, char *err, size_t err_len);
```

- [ ] **Step 1: Write the failing tests**

  - `test_parse_sample`: two pages (8 keys and 3 keys). Fields, hash and `has_long` are read correctly.
  - `test_reject_out_of_grid`: `col+w>8`, `row+h>2`, and `w==0` are each rejected with a non-empty `err`.
  - `test_reject_overlap`.
  - `test_reject_duplicate_id`: the same id on two pages is rejected.
  - `test_reject_too_many_pages`: 9 pages.
  - `test_reject_too_many_widgets`: 17 widgets.
  - `test_reject_face_out_of_range`: face 0 or 129.
  - `test_reject_missing_hash`.
  - `test_reject_malformed_json`.
  - `test_reject_oversize`: `len > DECK_LAYOUT_MAX_BYTES`.
  - `test_unknown_type_kept_as_placeholder`: `type:"gauge"` parses as `DW_UNKNOWN` and still takes grid space.
  - `test_out_unchanged_on_error`: `out` keeps its previous content when a parse fails.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `pio test -e native_deck -f test_layout`

- [ ] **Step 3: Implement `deck_layout_parse`**

  Parse into a temporary `DeckLayout`, and copy it to `out` only after it validates.

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `pio test -e native_deck`. Expected: all three suites PASS.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add layout parser`

### Task 6: Swift config, faces and layout builder

**Files:**
- Create: `mac/LongDeck/Sources/LongDeckCore/DeckConfig.swift`, `FaceRenderer.swift`, `LayoutBuilder.swift`, `SampleConfig.swift`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/DeckConfigTests.swift`, `FaceRendererTests.swift`, `LayoutBuilderTests.swift`

**Interfaces:**
- Produces:
  - `struct DeckConfig: Codable, Equatable { var version: Int; var pages: [PageConfig] }`
  - `struct PageConfig: Codable, Equatable { var name: String; var keys: [KeyConfig] }`
  - `struct KeyConfig: Codable, Equatable { var id: String; var col, row, w, h: Int; var label: String; var icon: IconRef?; var background: String; var action: DeckAction; var longAction: DeckAction? }`
  - `enum IconRef: Codable, Equatable { case app(path: String), symbol(name: String) }`
  - `enum DeckAction: Codable, Equatable { case openApp(path: String), openURL(String), hotkey(keyCode: UInt16, modifiers: [KeyModifier]), media(MediaKey), volume(VolumeKey), typeText(String), shell(String), shortcut(String) }`
  - `enum KeyModifier: String, Codable { case command, shift, option, control }`
  - `enum MediaKey: String, Codable { case playPause, next, previous }`
  - `enum VolumeKey: String, Codable { case up, down, mute }`
  - `DeckConfig.load(from: URL) throws -> DeckConfig`. A missing file returns `SampleConfig.dev`, and the caller writes it.
  - `DeckConfig.save(to: URL) throws`
  - `enum FaceRenderer`:
    - `static func faceSize(w: Int, h: Int) -> (Int, Int)` returns `(w*80-6, h*90-6)`.
    - `static func pack(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> [UInt8]` returns RGB565 big-endian plus A8.
    - `static func render(_ key: KeyConfig) -> Data` returns `faceSize` pixels, 3 bytes each.
  - `struct BuiltLayout { let json: String; let hash: String; let faces: [UInt16: (w: UInt16, h: UInt16, pixels: Data)] }`
  - `enum LayoutBuilder { static func build(_ config: DeckConfig, render: (KeyConfig) -> Data = FaceRenderer.render) -> BuiltLayout }`
    - Face ids are 1-based in page-then-key order.
    - `has_long` is `longAction != nil`.
    - `hash` is the first 16 hex of `SHA256(json-without-hash ‖ faces in id order)`.
    - The JSON uses `.sortedKeys`, and the `hash` key is inserted afterwards.

- [ ] **Step 1: Write the failing tests**

  - `pack red/green/blue/white`: `(255,0,0,255) → [0xF8,0x00,0xFF]`, `(0,255,0,128) → [0x07,0xE0,0x80]`, `(0,0,255,0) → [0x00,0x1F,0x00]`, `(255,255,255,255) → [0xFF,0xFF,0xFF]`.
  - `faceSize 1x1 and 2x2`: `(74,84)` and `(154,174)`.
  - `render size matches faceSize`: a 1x1 key gives 18 648 bytes.
  - `config round-trips through JSON`: every `DeckAction` case is included.
  - `load missing file returns sample`.
  - `sample config uses every action type at least once and fits the grid`.
  - `builder assigns face ids and has_long`.
  - `builder hash changes when a label changes and is stable otherwise`.
  - `builder output parses as the board layout schema`: decode the JSON and check the keys `hash`, `pages[].name` and `widgets[].{id,type,col,row,w,h,face,long}`.

- [ ] **Step 2: Run the tests and confirm they fail**

- [ ] **Step 3: Implement**

  - `render` draws with CoreGraphics into an RGBA8 `CGContext`: rounded-rect background `background`, icon centred in the top 60%, and label in the bottom band at system font 13 pt, white, single line, truncated. Then it packs every pixel.
  - An app icon comes from `NSWorkspace.shared.icon(forFile:)`. A symbol icon comes from `NSImage(systemSymbolName:accessibilityDescription:)` tinted white.
  - `SampleConfig.dev` has one page named "Dev":
    - Row 0: VS Code, iTerm2 and Google Chrome (`openApp`), a Spotlight `hotkey` (keyCode 49, command), a Screenshot `hotkey` (keyCode 21, command+shift), `openURL` `https://github.com`, a `shell` key running `open ~/WORK`, and a `shortcut` key.
    - Row 1: `media` previous, playPause and next; `volume` mute, down and up; a `typeText` key; and an `openApp` Finder key with `longAction` `openURL` `file:///Applications`.

- [ ] **Step 4: Run the tests and confirm they pass**

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add mac config, face renderer and layout builder`

### Task 7: Firmware rename to LongDeck

**Files:**
- Modify: `examples/ntp_clock/app_state.h:11-12` (`CLOCK_HOSTNAME "longdeck"`, `CLOCK_AP_PREFIX "LongDeck-"`)
- Modify: `examples/ntp_clock/settings.cpp` (`NVS_NS "longdeck"` plus migration)
- Modify: `examples/ntp_clock/web_pages.h:111` (title `LongDeck`), `:193` (fallback `LongDeck-xxxx`)
- Modify: `examples/ntp_clock/README.md` (title, AP name, URL `http://longdeck.local`, wording)
- Rename: `examples/ntp_clock/eez/thaiclock.eez-project` → `examples/ntp_clock/eez/longdeck.eez-project`. Rebuild `eez/gen/`.

**Interfaces:**
- Produces: `void settings_begin()` now migrates once. If namespace `longdeck` has no `wifi_ssid` key and namespace `thaiclock` exists, it copies every key that `settings.cpp` reads or writes, then calls `clear()` on the old namespace. The migration is idempotent.

- [ ] **Step 1: Make the code changes listed above**

  In the EEZ project, change four texts through the `eez-studio` MCP: the splash title becomes `LongDeck`, the system-page IP preview becomes `IP 192.168.1.42 · longdeck.local`, the portal QR becomes `WIFI:T:nopass;S:LongDeck-D5C0;;`, and the portal hint becomes `1) สแกน QR หรือต่อ WiFi: LongDeck-D5C0`. Then build.

- [ ] **Step 2: Verify no old name remains**

  Run: `git grep -niIE 'thai ?clock|thaideck|นาฬิกาไทย' -- examples/ntp_clock platformio.ini`
  Expected: no output. Untracked `*.bak` and `.eez-render/` files are git-ignored, so they don't count.

- [ ] **Step 3: Build and flash**

  Run: `pio run -e ntp_clock -t upload`. Find the port by USB serial `74:4D:BD:88:D5:C0`. Expected: SUCCESS.

- [ ] **Step 4: Device check**

  - Saved Wi-Fi still connects after the upgrade, which proves the migration.
  - `ping longdeck.local` answers.
  - The splash shows "LongDeck".
  - Holding BOOT for 2 s opens the AP `LongDeck-XXXX`.

- [ ] **Step 5: Commit**

  Message: `refactor(longdeck): rename the clock firmware to LongDeck`

### Task 8: Firmware store and network link

**Files:**
- Create: `examples/ntp_clock/partitions_longdeck.csv` with these rows:
  - `nvs 0x9000 0x5000`
  - `otadata 0xe000 0x2000`
  - `app0 0x10000 0x300000`
  - `spiffs 0x310000 0xCE0000`
  - `coredump 0xFF0000 0x10000`
- Modify: `platformio.ini`. Set `[env:ntp_clock] board_build.partitions = examples/ntp_clock/partitions_longdeck.csv`.
- Create: `examples/ntp_clock/deck_store.h`, `examples/ntp_clock/deck_store.cpp`
- Create: `examples/ntp_clock/deck_net.h`, `examples/ntp_clock/deck_net.cpp`
- Modify: `examples/ntp_clock/settings.cpp`, `examples/ntp_clock/app_state.h`. Add the deck-key functions below. The NVS key is `deck_key`, a 32-byte blob.
- Modify: `examples/ntp_clock/net.cpp`. In `net_task`, call `deck_net_begin()` after `server_setup()` and `deck_net_loop()` inside the `for(;;)`. In `on_connected()`, call `deck_net_on_connected()` after the mDNS service is added. Add the route `POST /api/deck/forget` → `deck_net_forget()`.
- Modify: `examples/ntp_clock/web_pages.h`. Add a "ลืม Mac ที่จับคู่ไว้" button that POSTs `/api/deck/forget`.

**Interfaces:**
- Consumes: `DeckSession` (Task 3), `deck_layout_parse` (Task 5).
- Produces:

```cpp
// app_state.h (thread-safe like the other settings_*)
bool settings_get_deck_key(uint8_t key[32]);
void settings_set_deck_key(const uint8_t key[32]);
void settings_clear_deck_key();

// deck_store.h — LittleFS on partition label "spiffs", mount point "/littlefs"
bool   deck_store_begin();                                   // formats on first mount
bool   deck_store_save_layout(const char *json, size_t len);  // /deck/layout.json
size_t deck_store_load_layout(char *buf, size_t cap);         // 0 if none
bool   deck_store_save_face(uint16_t id, uint16_t w, uint16_t h, const uint8_t *px);  // /deck/f<id>.bin
bool   deck_store_load_face(uint16_t id, lv_img_dsc_t *out);  // ps_malloc'd, TRUE_COLOR_ALPHA
void   deck_store_free_face(lv_img_dsc_t *img);
void   deck_store_prune(const DeckLayout *keep);              // deletes unreferenced faces

// deck_net.h — net_task side: begin/on_connected/loop; everything else is safe from the LVGL thread
void     deck_net_begin();
void     deck_net_on_connected();
void     deck_net_loop();
bool     deck_net_ready();
uint32_t deck_net_layout_version();
bool     deck_net_layout(DeckLayout *out);
bool     deck_net_take_dirty_faces(uint8_t bits[DECK_MAX_FACES / 8]);
bool     deck_net_pair_code(uint32_t *code);
void     deck_net_press(const char *id, bool long_press);
void     deck_net_page(int8_t deck_index);
void     deck_net_forget();
```

  Behaviour required:
  - `WebSocketsServer` on `DECK_WS_PORT` with `enableHeartbeat(5000, 3000, 2)`. There is one `DeckSession` per client slot.
  - When a session becomes ready, any other ready client is disconnected. Unauthenticated sockets never affect a ready one.
  - On ready, the board sends `hello_state` with the cached layout hash.
  - A `layout` message that parses gets saved, the cache is pruned, and the layout version bumps. A layout that fails to parse is logged and dropped, and the old cache stays.
  - Face chunks are assembled into one PSRAM buffer per face id. When `y+n == h`, the face is saved and its dirty bit set.
  - `deck_net_press` and `deck_net_page` go through a FreeRTOS queue (depth 8) that `deck_net_loop` drains with `seal`. They are dropped when not ready.
  - At boot, `deck_net_begin` loads the cached layout so deck pages render before any Mac connects.
  - `DeckEnv.random` is `esp_fill_random`, and `board_id` is the STA MAC.
  - `deck_net_forget` clears the key and disconnects all clients.

- [ ] **Step 1: Implement the files above**

- [ ] **Step 2: Build**

  Run: `pio run -e ntp_clock`. Expected: SUCCESS. RAM and flash use are printed; the app must stay under 3 MB.

- [ ] **Step 3: Flash and run the device checks with `websocat` (`brew install websocat`)**

  - `dns-sd -B _longdeck._tcp` lists the board.
  - `websocat ws://longdeck.local:81` with `{"t":"hello","v":1,"nonce":"202122232425262728292a2b2c2d2e2f"}` gets a `challenge`.
  - A frame with a bad proof closes the socket.
  - Opening two `websocat` sessions does not crash the board. The serial log shows the second socket was handled.
  - After a pull-the-plug test (Mac Wi-Fi off), the serial log shows the client dropped within 15 s.

- [ ] **Step 4: Run the native tests to prove the pure modules are untouched**

  Run: `pio test -e native_deck`. Expected: PASS.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add deck websocket link and cache`

### Task 9: Mac app: transport, actions and menu bar

**Files:**
- Create in `mac/LongDeck/Sources/LongDeckCore/`: `ActionRunner.swift`, `SystemControl.swift`, `ReconnectPolicy.swift`, `KeyStore.swift`
- Create in `mac/LongDeck/Sources/LongDeckApp/`: `AppModel.swift`, `DeckConnection.swift`, `Discovery.swift`, `MenuView.swift`, `PairView.swift`. Modify `LongDeckApp.swift`.
- Create: `mac/LongDeck/scripts/bundle.sh`, `mac/LongDeck/Resources/Info.plist`, `mac/LongDeck/README.md`
- Test: `mac/LongDeck/Tests/LongDeckCoreTests/ActionRunnerTests.swift`, `ReconnectPolicyTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 4 and 6.
- Produces:
  - `protocol SystemControl`:
    - `func openApp(path: String) throws`
    - `func openURL(_ url: URL) throws`
    - `func postKey(code: UInt16, flags: CGEventFlags) throws`
    - `func postSystemKey(_ nx: Int32) throws`
    - `func typeText(_ s: String) throws`
    - `func runShell(_ cmd: String) throws`
    - `func runShortcut(_ name: String) throws`
    - `var isTrusted: Bool { get }`
  - `enum ActionError: Error, Equatable { case notTrusted, unknownKey(String), failed(String) }`
  - `struct ActionRunner`:
    - `let system: SystemControl`
    - `func run(_ action: DeckAction) throws`
    - `func handlePress(id: String, kind: String, config: DeckConfig) throws`. `kind` is `"tap"` or `"long"`. A long press with no `longAction` does nothing.
  - `struct ReconnectPolicy { mutating func nextDelay() -> TimeInterval; mutating func reset() }`. Delays run 1, 2, 4, 8, 15, 15, …
  - `enum KeyStore`:
    - `static func load(boardId: String) -> Data?`
    - `static func save(_ key: Data, boardId: String) throws`
    - `static func delete(boardId: String)`
    - Keychain generic password, service `dev.longdeck.LongDeck`.

- [ ] **Step 1: Write the failing tests**

  - The mock `SystemControl` records calls.
    - `media maps to NX keys`: playPause→16, next→17, previous→18.
    - `volume maps to NX keys`: up→0, down→1, mute→7.
    - `hotkey maps modifiers`: keyCode 21 with command+shift → `postKey(21, [.maskCommand, .maskShift])`.
    - `openApp`, `openURL`, `typeText`, `shell` and `shortcut` each go to their call.
  - `ActionRunner reports permission error`: with `isTrusted == false`, `hotkey`, `media`, `volume` and `typeText` throw `.notTrusted` and post nothing, while `openApp` still works.
  - `handlePress unknown id throws unknownKey`.
  - `handlePress long without longAction does nothing`.
  - `ReconnectPolicy sequence and reset`.

- [ ] **Step 2: Run the tests and confirm they fail, then implement until they pass**

  Run: `cd mac/LongDeck && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

- [ ] **Step 3: Implement the app layer**

  - The real `SystemControl`:
    - CGEvent keyboard events go to `.cghidEventTap`.
    - System keys are `NSEvent.otherEvent(with: .systemDefined, …, subtype: 8, data1: (nx << 16) | (0xA << 8))`, then key-up with `0xB`, posted via `.cgEvent?.post`.
    - `typeText` uses `CGEvent.keyboardSetUnicodeString`.
    - `runShell` runs `/bin/zsh -lc` with output discarded.
    - `runShortcut` runs `/usr/bin/shortcuts run <name>`.
    - `isTrusted` is `AXIsProcessTrusted()`.
  - `Discovery` uses `NWBrowser` for `_longdeck._tcp` and publishes `[(name, id, endpoint)]`.
  - `DeckConnection`:
    - Resolve the endpoint and open `URLSessionWebSocketTask` to `ws://<host>:81`.
    - Run `DeckHandshake`. On `.ready`, send the layout when `hello_state.hash` differs, then all face chunks.
    - On `press`, call `ActionRunner.handlePress`.
    - Reconnect with `ReconnectPolicy`.
    - Watch the config file with `DispatchSource` and push again on change.
  - `MenuView` shows:
    - The status (Offline, Connecting, Pairing, or Connected to `<id>`).
    - "Pair with board…", which opens `PairView`: pick a discovered board, then type the 6-digit code.
    - "Reload config" and "Open config folder".
    - "Grant Accessibility…" when not trusted; it opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
    - "Quit".
  - `Info.plist`:
    - `CFBundleIdentifier dev.longdeck.LongDeck`, `CFBundleName LongDeck`, `LSUIElement true`.
    - `NSLocalNetworkUsageDescription`, and `NSBonjourServices` = [`_longdeck._tcp`].
  - `bundle.sh`:
    - `swift build -c release`, then assemble `build/LongDeck.app`.
    - `codesign --force --deep -s "${LONGDECK_SIGN_ID:--}"`.
  - The README explains how to create a self-signed "Code Signing" certificate in Keychain Access, so the Accessibility grant survives rebuilds.

- [ ] **Step 4: Build the bundle**

  Run: `cd mac/LongDeck && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/bundle.sh && codesign -dv build/LongDeck.app`
  Expected: the app is signed, and `open build/LongDeck.app` shows the menu-bar icon.

- [ ] **Step 5: Commit**

  Message: `feat(longdeck): add mac menu-bar app with actions and link`

### Task 10: Firmware deck pages and pairing overlay

**Files:**
- Modify: `examples/ntp_clock/ui.cpp`:
  - Size `tiles` and `dots` as `PAGE_COUNT + DECK_MAX_PAGES`.
  - Add `ui_set_deck_pages()` and `ui_deck_tile()`.
  - `current_page`, `tile_visible`, `ui_next_page` and the dots use `PAGE_COUNT + deck_pages`.
  - `tick_cb` calls `page_deck_update` and `ui_pair_update`.
- Modify: `examples/ntp_clock/ui_internal.h`. Declare the functions below.
- Create: `examples/ntp_clock/ui_page_deck.cpp`, `examples/ntp_clock/ui_pair.cpp`

**Interfaces:**
- Consumes: `deck_net_*` and `deck_store_load_face`/`free_face` (Task 8), and `DeckLayout` (Task 5).
- Produces:
  - `void ui_set_deck_pages(uint8_t n)`. It adds or deletes tiles at column `PAGE_COUNT+i` and rebuilds the dots. If the visible tile is deleted, it moves to `PAGE_CLOCK` first.
  - `lv_obj_t *ui_deck_tile(uint8_t i)`
  - `void page_deck_update(const UiTick *t)`
  - `void ui_pair_update(const UiTick *t)`

  Behaviour required:
  - When `deck_net_layout_version()` changes, rebuild the deck tiles from `deck_net_layout()`. A key is an `lv_img` inside a clickable `lv_obj` at the grid geometry from Global Constraints. Until its face arrives it shows a `COLOR_PANEL` rect.
  - Faces are reloaded only for ids from `deck_net_take_dirty_faces`. The UI thread owns all face buffers.
  - `LV_EVENT_SHORT_CLICKED` → `deck_net_press(id, false)`. `LV_EVENT_LONG_PRESSED` → `deck_net_press(id, true)`, only if `has_long`.
  - While pressed, the key scales to 95% and brightens.
  - While `!deck_net_ready()`: keys are at 40% opacity, presses are ignored, and a top-right badge reads "Mac offline".
  - With no cached layout, there is one deck tile with a centred hint: "เปิดแอป LongDeck บน Mac แล้วกด Pair".
  - `DW_UNKNOWN` widgets show an empty `COLOR_PANEL` rect.
  - Call `deck_net_page` with the visible deck index, or -1, whenever it changes.
  - The pairing overlay sits on `lv_layer_top` while `deck_net_pair_code()` is true. It shows the 6-digit code in `ui_font_digits_56`, a `ui_font_th_22` line "ใส่รหัสนี้ในแอป LongDeck", and a countdown bar over 60 s.

- [ ] **Step 1: Implement the files above**

- [ ] **Step 2: Build and flash**

  Run: `pio run -e ntp_clock -t upload`. Expected: SUCCESS.

- [ ] **Step 3: Device checks**

  - The clock pages look and behave as before, including night mode and the portal.
  - With no Mac, swiping past System shows the hint tile.
  - BOOT cycles through every tile.

- [ ] **Step 4: Commit**

  Message: `feat(longdeck): add deck pages and pairing overlay`

### Task 11: End-to-end on hardware and docs

**Files:**
- Modify: `examples/ntp_clock/README.md`. Add a LongDeck section covering pairing, the config file path, how to forget a Mac, and the partition change (the first flash after this change formats the data partition; Wi-Fi survives).

- [ ] **Step 1: Pair**

  Run `open mac/LongDeck/build/LongDeck.app`, choose Pair, and pick the board. The code shows on the board. Type it in. Expected: the menu shows "Connected", and the board's deck page fills with the sample faces within 5 s.

- [ ] **Step 2: Press every sample key**

  Each key's action happens on the Mac. Volume keys show the system HUD. A long press on Finder opens `/Applications`.

- [ ] **Step 3: Resilience**

  - Quit the app: within 15 s the board shows "Mac offline" and presses do nothing.
  - Relaunch the app: it reconnects without pairing, and the layout is not resent (the hash matches).
  - Edit a label in `config.json`: within 2 s the face updates on the board.
  - Put an invalid `col` in `config.json`: the app refuses to push and shows an error. If the board receives a bad layout through `websocat`, it keeps the old cache.

- [ ] **Step 4: Forget**

  `curl -X POST http://longdeck.local/api/deck/forget`. Expected: the app falls back to "Pair with board…", and the old key is rejected.

- [ ] **Step 5: Commit**

  Message: `docs(longdeck): document pairing and deck setup`

## Execution order

- Wave 1 (parallel): Task 1, Task 2, Task 7.
- Wave 2 (parallel): Task 3, Task 4, Task 5, Task 6.
- Wave 3 (parallel): Task 8, Task 9.
- Wave 4: Task 10.
- Wave 5: Task 11.

Task 1 and Task 7 both avoid each other's files. Task 8 edits `web_pages.h` and `settings.cpp` after Task 7 has finished.

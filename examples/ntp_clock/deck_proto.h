#pragma once
#include <stddef.h>
#include <stdint.h>
#include <string>
#include <vector>

#define DECK_WS_PORT           81
#define DECK_PROTO_VERSION     1
#define DECK_PAIR_TIMEOUT_MS   60000
#define DECK_PAIR_COOLDOWN_MS  10000
#define DECK_FACE_CHUNK_MAX    (12 * 1024)
#define DECK_TEXT_FRAME_MAX    (20 * 1024)
#define DECK_HANDSHAKE_FRAME_MAX 512

struct DeckEnv {
  void (*random)(uint8_t *buf, size_t len);
  bool (*load_key)(uint8_t key[32]);
  void (*store_key)(const uint8_t key[32]);
  void (*pair_code)(uint32_t code, bool show);
  uint32_t (*now_ms)();
  const char *board_id;  // 12 lowercase hex
};

struct DeckFaceChunk {
  uint16_t id, w, h, y, n;
  const uint8_t *px;
  size_t px_len;
};

class DeckSession {
 public:
  explicit DeckSession(const DeckEnv *env);
  ~DeckSession();
  DeckSession(const DeckSession &) = delete;
  DeckSession &operator=(const DeckSession &) = delete;

  bool on_text(const char *data, size_t len, std::vector<std::string> *replies);  // false = close
  bool on_binary(const uint8_t *data, size_t len);                               // false = close
  void tick();
  bool seal(const char *type, const char *body_json, std::string *out);  // false unless ready
  bool ready() const;

  void (*on_message)(void *ctx, const char *type, const char *body, size_t body_len) = nullptr;
  void (*on_face)(void *ctx, const DeckFaceChunk *chunk) = nullptr;
  void *ctx = nullptr;

 private:
  enum State { AwaitHello, AwaitAuth, Pairing, Ready, Closed };

  bool fail(std::vector<std::string> *replies, const char *code);
  bool handle_hello(const char *nonce_hex,std::vector<std::string> *replies);
  bool handle_auth(const char *proof_hex, std::vector<std::string> *replies);
  bool handle_pair_start(const char *pub_hex, std::vector<std::string> *replies);
  bool handle_pair_confirm(const char *proof_hex, std::vector<std::string> *replies);
  void end_pairing();

  const DeckEnv *env_;
  State state_ = AwaitHello;
  bool have_key_ = false;
  uint8_t key_[32] = {0};
  uint8_t ks_[32] = {0};
  uint8_t board_nonce_[16] = {0};
  uint8_t app_nonce_[16] = {0};
  uint8_t pair_key_[32] = {0};
  uint32_t last_rx_ = 0;
  uint32_t tx_ = 0;
  uint32_t pair_started_ = 0;
};

void deck_proto_reset_for_test();

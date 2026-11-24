#include "deck_proto.h"

#include <ArduinoJson.h>
#include <string.h>

#include "deck_crypto.h"

#define FACE_HEADER_LEN 10
#define BIN_MAGIC 0x46
#define BIN_HEADER_LEN (1 + 4 + 32)

static bool g_pair_active = false;
static bool g_has_last_start = false;
static uint32_t g_last_start = 0;

void deck_proto_reset_for_test() {
  g_pair_active = false;
  g_has_last_start = false;
  g_last_start = 0;
}

static std::string to_json(JsonDocument &doc) {
  std::string out;
  serializeJson(doc, out);
  return out;
}

static std::string simple_frame(const char *type) {
  JsonDocument d;
  d["t"] = type;
  return to_json(d);
}

static std::string error_frame(const char *code) {
  JsonDocument d;
  d["t"] = "error";
  d["code"] = code;
  return to_json(d);
}

static std::string hex_str(const uint8_t *b, size_t n) {
  std::string s(n * 2 + 1, '\0');
  deck_hex_encode(b, n, &s[0]);
  s.resize(n * 2);
  return s;
}

static void put_u32le(uint8_t *p, uint32_t v) {
  for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i));
}

static uint16_t get_u16le(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }

static void text_mac(uint8_t out[32], const uint8_t ks[32], const char *t, uint32_t s,
                     const char *b, size_t b_len) {
  std::string in = t;
  in += '\n';
  in += std::to_string(s);
  in += '\n';
  in.append(b, b_len);
  deck_hmac_sha256(ks, 32, (const uint8_t *)in.data(), in.size(), out);
}

DeckSession::DeckSession(const DeckEnv *env) : env_(env) {}

DeckSession::~DeckSession() {
  if (state_ == Pairing) end_pairing();
}

bool DeckSession::ready() const { return state_ == Ready; }

bool DeckSession::fail(std::vector<std::string> *replies, const char *code) {
  if (replies) replies->push_back(error_frame(code));
  if (state_ == Pairing) end_pairing();
  state_ = Closed;
  return false;
}

void DeckSession::end_pairing() {
  g_pair_active = false;
  env_->pair_code(0, false);
  if (state_ == Pairing) state_ = AwaitAuth;
}

bool DeckSession::handle_hello(const char *nonce_hex, std::vector<std::string> *replies) {
  if (state_ != AwaitHello || !nonce_hex || !deck_hex_decode(nonce_hex, app_nonce_, 16))
    return fail(replies, "proto");
  env_->random(board_nonce_, 16);
  have_key_ = env_->load_key(key_);
  state_ = AwaitAuth;
  JsonDocument d;
  d["t"] = "challenge";
  d["v"] = DECK_PROTO_VERSION;
  d["nonce"] = hex_str(board_nonce_, 16);
  d["paired"] = have_key_;
  d["id"] = env_->board_id;
  replies->push_back(to_json(d));
  return true;
}

bool DeckSession::handle_auth(const char *proof_hex, std::vector<std::string> *replies) {
  uint8_t proof[32];
  if (state_ != AwaitAuth) return fail(replies, "proto");
  if (!have_key_ || !proof_hex || !deck_hex_decode(proof_hex, proof, 32))
    return fail(replies, "auth");
  uint8_t msg[3 + 32], want[32];
  memcpy(msg, "app", 3);
  memcpy(msg + 3, board_nonce_, 16);
  memcpy(msg + 19, app_nonce_, 16);
  deck_hmac_sha256(key_, 32, msg, 35, want);
  if (!deck_ct_equal(want, proof, 32)) return fail(replies, "auth");

  uint8_t bmsg[5 + 32], bproof[32];
  memcpy(bmsg, "board", 5);
  memcpy(bmsg + 5, app_nonce_, 16);
  memcpy(bmsg + 21, board_nonce_, 16);
  deck_hmac_sha256(key_, 32, bmsg, 37, bproof);
  deck_session_key(ks_, key_, board_nonce_, app_nonce_);
  state_ = Ready;
  JsonDocument d;
  d["t"] = "auth_ok";
  d["proof"] = hex_str(bproof, 32);
  replies->push_back(to_json(d));
  return true;
}

bool DeckSession::handle_pair_start(const char *pub_hex, std::vector<std::string> *replies) {
  uint8_t app_pub[32];
  if ((state_ != AwaitAuth && state_ != Pairing) || !pub_hex ||
      !deck_hex_decode(pub_hex, app_pub, 32))
    return fail(replies, "proto");
  uint32_t now = env_->now_ms();
  if (g_pair_active || (g_has_last_start && now - g_last_start < DECK_PAIR_COOLDOWN_MS)) {
    replies->push_back(error_frame("busy"));
    return true;
  }
  uint8_t priv[32], board_pub[32], shared[32];
  env_->random(priv, 32);
  deck_x25519_public(board_pub, priv);
  deck_x25519_shared(shared, priv, app_pub);
  deck_derive_key(pair_key_, shared, board_pub, app_pub);
  memset(priv, 0, sizeof priv);
  memset(shared, 0, sizeof shared);

  g_pair_active = true;
  g_has_last_start = true;
  g_last_start = now;
  pair_started_ = now;
  state_ = Pairing;
  env_->pair_code(deck_pair_code(pair_key_), true);
  JsonDocument d;
  d["t"] = "pair_pub";
  d["pub"] = hex_str(board_pub, 32);
  replies->push_back(to_json(d));
  return true;
}

bool DeckSession::handle_pair_confirm(const char *proof_hex, std::vector<std::string> *replies) {
  uint8_t proof[32], want[32];
  if (state_ != Pairing) return fail(replies, "proto");
  if (!proof_hex || !deck_hex_decode(proof_hex, proof, 32)) return fail(replies, "pair");
  deck_hmac_sha256(pair_key_, 32, (const uint8_t *)"confirm", 7, want);
  if (!deck_ct_equal(want, proof, 32)) return fail(replies, "pair");
  env_->store_key(pair_key_);
  memcpy(key_, pair_key_, 32);
  have_key_ = true;
  end_pairing();
  replies->push_back(simple_frame("pair_ok"));
  return true;
}

bool DeckSession::on_text(const char *data, size_t len, std::vector<std::string> *replies) {
  if (state_ == Closed) return false;
  JsonDocument doc;
  if (deserializeJson(doc, data, len)) return fail(replies, "proto");
  const char *t = doc["t"].is<const char *>() ? doc["t"].as<const char *>() : nullptr;
  if (!t) return fail(replies, "proto");

  if (state_ == Ready || !doc["m"].isNull()) {
    if (state_ != Ready) return fail(replies, "proto");
    const char *b = doc["b"].is<const char *>() ? doc["b"].as<const char *>() : nullptr;
    const char *m = doc["m"].is<const char *>() ? doc["m"].as<const char *>() : nullptr;
    if (!m || !b || !doc["s"].is<uint32_t>()) return fail(replies, "proto");
    uint32_t s = doc["s"].as<uint32_t>();
    uint8_t got[32], want[32];
    if (!deck_hex_decode(m, got, 32)) return fail(replies, "auth");
    size_t b_len = strlen(b);
    text_mac(want, ks_, t, s, b, b_len);
    if (!deck_ct_equal(want, got, 32)) return fail(replies, "auth");
    if (s <= last_rx_) return fail(replies, "proto");
    last_rx_ = s;
    if (on_message) on_message(ctx, t, b, b_len);
    return true;
  }

  if (!strcmp(t, "hello")) return handle_hello(doc["nonce"] | (const char *)nullptr, replies);
  if (!strcmp(t, "auth")) return handle_auth(doc["proof"] | (const char *)nullptr, replies);
  if (!strcmp(t, "pair_start")) return handle_pair_start(doc["pub"] | (const char *)nullptr, replies);
  if (!strcmp(t, "pair_confirm"))
    return handle_pair_confirm(doc["proof"] | (const char *)nullptr, replies);
  return fail(replies, "proto");
}

bool DeckSession::on_binary(const uint8_t *data, size_t len) {
  if (state_ != Ready) return false;
  if (len < BIN_HEADER_LEN + FACE_HEADER_LEN || data[0] != BIN_MAGIC) return false;
  const uint8_t *payload = data + BIN_HEADER_LEN;
  size_t payload_len = len - BIN_HEADER_LEN;
  if (payload_len > DECK_FACE_CHUNK_MAX) return false;

  uint32_t s = (uint32_t)data[1] | ((uint32_t)data[2] << 8) | ((uint32_t)data[3] << 16) |
               ((uint32_t)data[4] << 24);
  std::vector<uint8_t> in(4 + payload_len);
  put_u32le(in.data(), s);
  memcpy(in.data() + 4, payload, payload_len);
  uint8_t want[32];
  deck_hmac_sha256(ks_, 32, in.data(), in.size(), want);
  if (!deck_ct_equal(want, data + 5, 32)) return false;
  if (s <= last_rx_) return false;
  last_rx_ = s;

  DeckFaceChunk c;
  c.id = get_u16le(payload);
  c.w = get_u16le(payload + 2);
  c.h = get_u16le(payload + 4);
  c.y = get_u16le(payload + 6);
  c.n = get_u16le(payload + 8);
  c.px = payload + FACE_HEADER_LEN;
  c.px_len = payload_len - FACE_HEADER_LEN;
  if (c.px_len != (size_t)c.w * c.n * 3) return false;
  if ((uint32_t)c.y + c.n > c.h) return false;
  if (on_face) on_face(ctx, &c);
  return true;
}

void DeckSession::tick() {
  if (state_ == Pairing && env_->now_ms() - pair_started_ >= DECK_PAIR_TIMEOUT_MS) end_pairing();
}

bool DeckSession::seal(const char *type, const char *body_json, std::string *out) {
  if (state_ != Ready) return false;
  uint32_t s = ++tx_;
  size_t b_len = strlen(body_json);
  uint8_t mac[32];
  text_mac(mac, ks_, type, s, body_json, b_len);
  JsonDocument d;
  d["t"] = type;
  d["s"] = s;
  d["b"] = body_json;
  d["m"] = hex_str(mac, 32);
  *out = to_json(d);
  return true;
}

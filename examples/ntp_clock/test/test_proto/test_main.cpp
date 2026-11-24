#include <unity.h>
#include <ArduinoJson.h>
#include <string.h>
#include <string>
#include <vector>
#include "deck_crypto.h"
#include "deck_proto.h"

static const char *BOARD_ID = "aabbccddeeff";
static const char *BOARD_NONCE_HEX = "101112131415161718191a1b1c1d1e1f";
static const char *APP_NONCE_HEX = "202122232425262728292a2b2c2d2e2f";

static uint8_t K[32], BN[16], AN[16], KS[32];
static int g_random_calls;
static bool g_has_key;
static uint8_t g_stored[32];
static int g_store_calls;
static int g_code_calls;
static uint32_t g_code_val;
static bool g_code_show;
static uint32_t g_now;

static void seq(uint8_t *b, size_t n, uint8_t start) {
  for (size_t i = 0; i < n; i++) b[i] = (uint8_t)(start + i);
}

static void env_random(uint8_t *buf, size_t len) {
  if (g_random_calls++ == 0) seq(buf, len, 0x10);
  else seq(buf, len, 0x40);
}
static bool env_load(uint8_t key[32]) {
  if (!g_has_key) return false;
  memcpy(key, K, 32);
  return true;
}
static void env_store(const uint8_t key[32]) {
  g_store_calls++;
  memcpy(g_stored, key, 32);
}
static void env_code(uint32_t code, bool show) {
  g_code_calls++;
  g_code_val = code;
  g_code_show = show;
}
static uint32_t env_now() { return g_now; }

static DeckEnv ENV = {env_random, env_load, env_store, env_code, env_now, "aabbccddeeff"};

static int g_msg_calls;
static std::string g_msg_type, g_msg_body;
static int g_face_calls;
static DeckFaceChunk g_face;
static std::vector<uint8_t> g_face_px;

static void on_msg(void *, const char *t, const char *b, size_t n) {
  g_msg_calls++;
  g_msg_type = t;
  g_msg_body.assign(b, n);
}
static void on_face(void *, const DeckFaceChunk *c) {
  g_face_calls++;
  g_face = *c;
  g_face_px.assign(c->px, c->px + c->px_len);
}

void setUp() {
  seq(K, 32, 1);
  seq(BN, 16, 0x10);
  seq(AN, 16, 0x20);
  deck_session_key(KS, K, BN, AN);
  g_random_calls = 0;
  g_has_key = true;
  g_store_calls = 0;
  g_code_calls = 0;
  g_code_val = 0;
  g_code_show = false;
  g_now = 1000;
  g_msg_calls = 0;
  g_face_calls = 0;
  deck_proto_reset_for_test();
}
void tearDown() {}

static std::string hex(const uint8_t *b, size_t n) {
  std::string s(n * 2 + 1, '\0');
  deck_hex_encode(b, n, &s[0]);
  s.resize(n * 2);
  return s;
}

static std::string app_proof() {
  uint8_t msg[3 + 32], out[32];
  memcpy(msg, "app", 3);
  memcpy(msg + 3, BN, 16);
  memcpy(msg + 19, AN, 16);
  deck_hmac_sha256(K, 32, msg, 35, out);
  return hex(out, 32);
}

static JsonDocument parse(const std::string &s) {
  JsonDocument d;
  TEST_ASSERT_TRUE(!deserializeJson(d, s));
  return d;
}

static std::string hello_frame() {
  return std::string("{\"t\":\"hello\",\"v\":1,\"nonce\":\"") + APP_NONCE_HEX + "\"}";
}
static std::string auth_frame(const std::string &proof) {
  return "{\"t\":\"auth\",\"proof\":\"" + proof + "\"}";
}

static bool send(DeckSession &s, const std::string &f, std::vector<std::string> *r) {
  return s.on_text(f.data(), f.size(), r);
}

static void do_hello(DeckSession &s) {
  std::vector<std::string> r;
  TEST_ASSERT_TRUE(send(s, hello_frame(), &r));
}

static void make_ready(DeckSession &s) {
  do_hello(s);
  std::vector<std::string> r;
  TEST_ASSERT_TRUE(send(s, auth_frame(app_proof()), &r));
  TEST_ASSERT_TRUE(s.ready());
}

static std::string app_text(const char *t, uint32_t sn, const std::string &b, const uint8_t *key) {
  std::string mi = std::string(t) + "\n" + std::to_string(sn) + "\n" + b;
  uint8_t mac[32];
  deck_hmac_sha256(key, 32, (const uint8_t *)mi.data(), mi.size(), mac);
  JsonDocument d;
  d["t"] = t;
  d["s"] = sn;
  d["b"] = b;
  d["m"] = hex(mac, 32);
  std::string out;
  serializeJson(d, out);
  return out;
}

static std::vector<uint8_t> app_bin(uint32_t sn, const std::vector<uint8_t> &payload,
                                    const uint8_t *key, bool flip = false) {
  std::vector<uint8_t> in(4 + payload.size());
  for (int i = 0; i < 4; i++) in[i] = (uint8_t)(sn >> (8 * i));
  memcpy(in.data() + 4, payload.data(), payload.size());
  uint8_t mac[32];
  deck_hmac_sha256(key, 32, in.data(), in.size(), mac);
  if (flip) mac[0] ^= 1;
  std::vector<uint8_t> f;
  f.push_back(0x46);
  f.insert(f.end(), in.begin(), in.begin() + 4);
  f.insert(f.end(), mac, mac + 32);
  f.insert(f.end(), payload.begin(), payload.end());
  return f;
}

static std::vector<uint8_t> face_payload(uint16_t id, uint16_t w, uint16_t h, uint16_t y,
                                         uint16_t n, size_t px_len) {
  std::vector<uint8_t> p;
  uint16_t v[5] = {id, w, h, y, n};
  for (int i = 0; i < 5; i++) {
    p.push_back(v[i] & 0xff);
    p.push_back(v[i] >> 8);
  }
  for (size_t i = 0; i < px_len; i++) p.push_back((uint8_t)i);
  return p;
}

void test_hello_gets_challenge() {
  DeckSession s(&ENV);
  std::vector<std::string> r;
  TEST_ASSERT_TRUE(send(s, hello_frame(), &r));
  TEST_ASSERT_EQUAL(1, (int)r.size());
  JsonDocument d = parse(r[0]);
  TEST_ASSERT_EQUAL_STRING("challenge", d["t"].as<const char *>());
  TEST_ASSERT_EQUAL(1, d["v"].as<int>());
  TEST_ASSERT_EQUAL_STRING(BOARD_NONCE_HEX, d["nonce"].as<const char *>());
  TEST_ASSERT_TRUE(d["paired"].as<bool>());
  TEST_ASSERT_EQUAL_STRING(BOARD_ID, d["id"].as<const char *>());
}

void test_auth_ok_vector() {
  DeckSession s(&ENV);
  do_hello(s);
  std::vector<std::string> r;
  TEST_ASSERT_EQUAL_STRING("d8553dc93579ca07ca09ceaced0ae03beb2f50cbc05a811b84eae10a3d578adc",
                           app_proof().c_str());
  TEST_ASSERT_TRUE(send(s, auth_frame(app_proof()), &r));
  TEST_ASSERT_EQUAL(1, (int)r.size());
  JsonDocument d = parse(r[0]);
  TEST_ASSERT_EQUAL_STRING("auth_ok", d["t"].as<const char *>());
  TEST_ASSERT_EQUAL_STRING("be8865b415254711f8712bac2543ea4f52fa39e8ccfd18e40dac9c5180cb4647",
                           d["proof"].as<const char *>());
  TEST_ASSERT_TRUE(s.ready());
}

void test_auth_bad_proof_closes() {
  DeckSession s(&ENV);
  do_hello(s);
  std::string p = app_proof();
  p[0] = p[0] == '0' ? '1' : '0';
  std::vector<std::string> r;
  TEST_ASSERT_FALSE(send(s, auth_frame(p), &r));
  TEST_ASSERT_EQUAL(1, (int)r.size());
  JsonDocument d = parse(r[0]);
  TEST_ASSERT_EQUAL_STRING("error", d["t"].as<const char *>());
  TEST_ASSERT_EQUAL_STRING("auth", d["code"].as<const char *>());
  TEST_ASSERT_FALSE(s.ready());
}

void test_frame_before_ready_closes() {
  DeckSession s(&ENV);
  do_hello(s);
  std::vector<std::string> r;
  TEST_ASSERT_FALSE(send(s, app_text("layout", 1, "{}", KS), &r));
}

void test_seal_vector() {
  DeckSession s(&ENV);
  make_ready(s);
  std::string out;
  TEST_ASSERT_TRUE(s.seal("press", "{\"id\":\"k1\",\"kind\":\"tap\"}", &out));
  JsonDocument d = parse(out);
  TEST_ASSERT_EQUAL_STRING("press", d["t"].as<const char *>());
  TEST_ASSERT_EQUAL(1, d["s"].as<int>());
  TEST_ASSERT_EQUAL_STRING("{\"id\":\"k1\",\"kind\":\"tap\"}", d["b"].as<const char *>());
  TEST_ASSERT_EQUAL_STRING("8af257832884a4edc1f300cf890aed11f0311e20987315e2498ab218314292bd",
                           d["m"].as<const char *>());
}

void test_seal_before_ready_fails() {
  DeckSession s(&ENV);
  std::string out;
  TEST_ASSERT_FALSE(s.seal("press", "{}", &out));
}

void test_replay_rejected() {
  DeckSession s(&ENV);
  make_ready(s);
  std::vector<std::string> r;
  std::string f = app_text("layout", 1, "{}", KS);
  TEST_ASSERT_TRUE(send(s, f, &r));
  TEST_ASSERT_FALSE(send(s, f, &r));
}

void test_counter_shared_with_binary() {
  DeckSession s(&ENV);
  make_ready(s);
  s.on_face = on_face;
  std::vector<std::string> r;
  TEST_ASSERT_TRUE(send(s, app_text("layout", 2, "{}", KS), &r));
  std::vector<uint8_t> f = app_bin(2, face_payload(1, 1, 1, 0, 1, 3), KS);
  TEST_ASSERT_FALSE(s.on_binary(f.data(), f.size()));
}

void test_frame_from_other_session_rejected() {
  DeckSession s(&ENV);
  make_ready(s);
  uint8_t bn2[16], other[32];
  seq(bn2, 16, 0x50);
  deck_session_key(other, K, bn2, AN);
  std::vector<std::string> r;
  TEST_ASSERT_FALSE(send(s, app_text("layout", 1, "{}", other), &r));
}

void test_unsealed_frame_after_ready_closes() {
  DeckSession s(&ENV);
  make_ready(s);
  std::vector<std::string> r;
  TEST_ASSERT_FALSE(send(s, hello_frame(), &r));
}

void test_message_dispatch() {
  DeckSession s(&ENV);
  make_ready(s);
  s.on_message = on_msg;
  std::vector<std::string> r;
  std::string body = "{\"hash\":\"abc\",\"pages\":[]}";
  TEST_ASSERT_TRUE(send(s, app_text("layout", 1, body, KS), &r));
  TEST_ASSERT_EQUAL(1, g_msg_calls);
  TEST_ASSERT_EQUAL_STRING("layout", g_msg_type.c_str());
  TEST_ASSERT_EQUAL_STRING(body.c_str(), g_msg_body.c_str());
}

void test_face_chunk_dispatch() {
  DeckSession s(&ENV);
  make_ready(s);
  s.on_face = on_face;
  std::vector<uint8_t> p = face_payload(1, 1, 1, 0, 1, 3);
  std::vector<uint8_t> f = app_bin(1, p, KS);
  TEST_ASSERT_TRUE(s.on_binary(f.data(), f.size()));
  TEST_ASSERT_EQUAL(1, g_face_calls);
  TEST_ASSERT_EQUAL(1, g_face.id);
  TEST_ASSERT_EQUAL(1, g_face.w);
  TEST_ASSERT_EQUAL(1, g_face.h);
  TEST_ASSERT_EQUAL(0, g_face.y);
  TEST_ASSERT_EQUAL(1, g_face.n);
  TEST_ASSERT_EQUAL(3, (int)g_face_px.size());
  TEST_ASSERT_EQUAL_UINT8(2, g_face_px[2]);
}

void test_face_chunk_vector_mac() {
  uint8_t pl[13] = {1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0xf8, 0, 0xff};
  uint8_t in[4 + 13] = {1, 0, 0, 0}, mac[32];
  memcpy(in + 4, pl, 13);
  deck_hmac_sha256(K, 32, in, sizeof in, mac);
  TEST_ASSERT_EQUAL_STRING("86bd1fd5de4300ce41a05a415509242569b7c27f9035f759cfc6545f4d63c5e3",
                           hex(mac, 32).c_str());
}

void test_face_chunk_bad_mac_closes() {
  DeckSession s(&ENV);
  make_ready(s);
  s.on_face = on_face;
  std::vector<uint8_t> f = app_bin(1, face_payload(1, 1, 1, 0, 1, 3), KS, true);
  TEST_ASSERT_FALSE(s.on_binary(f.data(), f.size()));
  TEST_ASSERT_EQUAL(0, g_face_calls);
}

void test_face_chunk_too_big_closes() {
  DeckSession s(&ENV);
  make_ready(s);
  s.on_face = on_face;
  // 12289 total with header; w*n*3 matches so only the size rule rejects it
  std::vector<uint8_t> f = app_bin(1, face_payload(1, 4093, 4096, 0, 1, 4093 * 3), KS);
  TEST_ASSERT_FALSE(s.on_binary(f.data(), f.size()));
  TEST_ASSERT_EQUAL(0, g_face_calls);
}

void test_face_chunk_at_limit_ok() {
  DeckSession s(&ENV);
  make_ready(s);
  s.on_face = on_face;
  std::vector<uint8_t> f = app_bin(1, face_payload(1, 4092, 4096, 0, 1, 4092 * 3), KS);
  TEST_ASSERT_TRUE(s.on_binary(f.data(), f.size()));
  TEST_ASSERT_EQUAL(1, g_face_calls);
}

void test_face_chunk_bad_pixel_count_closes() {
  DeckSession s(&ENV);
  make_ready(s);
  s.on_face = on_face;
  std::vector<uint8_t> f = app_bin(1, face_payload(1, 2, 2, 0, 1, 3), KS);
  TEST_ASSERT_FALSE(s.on_binary(f.data(), f.size()));
}

void test_face_chunk_past_height_closes() {
  DeckSession s(&ENV);
  make_ready(s);
  s.on_face = on_face;
  std::vector<uint8_t> f = app_bin(1, face_payload(1, 1, 2, 2, 1, 3), KS);
  TEST_ASSERT_FALSE(s.on_binary(f.data(), f.size()));
}

void test_binary_before_ready_closes() {
  DeckSession s(&ENV);
  do_hello(s);
  std::vector<uint8_t> f = app_bin(1, face_payload(1, 1, 1, 0, 1, 3), KS);
  TEST_ASSERT_FALSE(s.on_binary(f.data(), f.size()));
}

struct Pairing {
  uint8_t app_priv[32], app_pub[32], board_pub[32], kp[32];
};

static void pair_start(DeckSession &s, Pairing *p, std::vector<std::string> *r) {
  seq(p->app_priv, 32, 0x80);
  deck_x25519_public(p->app_pub, p->app_priv);
  std::string f = "{\"t\":\"pair_start\",\"pub\":\"" + hex(p->app_pub, 32) + "\"}";
  TEST_ASSERT_TRUE(send(s, f, r));
  JsonDocument d = parse((*r)[0]);
  TEST_ASSERT_EQUAL_STRING("pair_pub", d["t"].as<const char *>());
  TEST_ASSERT_TRUE(deck_hex_decode(d["pub"].as<const char *>(), p->board_pub, 32));
  uint8_t shared[32];
  deck_x25519_shared(shared, p->app_priv, p->board_pub);
  deck_derive_key(p->kp, shared, p->board_pub, p->app_pub);
}

static std::string confirm_frame(const uint8_t *key) {
  uint8_t mac[32];
  deck_hmac_sha256(key, 32, (const uint8_t *)"confirm", 7, mac);
  return "{\"t\":\"pair_confirm\",\"proof\":\"" + hex(mac, 32) + "\"}";
}

void test_pair_flow() {
  g_has_key = false;
  DeckSession s(&ENV);
  std::vector<std::string> r;
  TEST_ASSERT_TRUE(send(s, hello_frame(), &r));
  TEST_ASSERT_FALSE(parse(r[0])["paired"].as<bool>());
  r.clear();
  Pairing p;
  pair_start(s, &p, &r);
  TEST_ASSERT_EQUAL(1, g_code_calls);
  TEST_ASSERT_TRUE(g_code_show);
  TEST_ASSERT_EQUAL_UINT32(deck_pair_code(p.kp), g_code_val);
  r.clear();
  TEST_ASSERT_TRUE(send(s, confirm_frame(p.kp), &r));
  TEST_ASSERT_EQUAL(1, g_store_calls);
  TEST_ASSERT_EQUAL_UINT8_ARRAY(p.kp, g_stored, 32);
  TEST_ASSERT_EQUAL_STRING("pair_ok", parse(r[0])["t"].as<const char *>());
  TEST_ASSERT_FALSE(g_code_show);
  uint8_t msg[35], proof[32];
  memcpy(msg, "app", 3);
  memcpy(msg + 3, BN, 16);
  memcpy(msg + 19, AN, 16);
  deck_hmac_sha256(p.kp, 32, msg, 35, proof);
  r.clear();
  TEST_ASSERT_TRUE(send(s, auth_frame(hex(proof, 32)), &r));
  TEST_ASSERT_TRUE(s.ready());
}

void test_pair_wrong_confirm_keeps_old_key() {
  DeckSession s(&ENV);
  do_hello(s);
  std::vector<std::string> r;
  Pairing p;
  pair_start(s, &p, &r);
  r.clear();
  TEST_ASSERT_FALSE(send(s, confirm_frame(K), &r));
  TEST_ASSERT_EQUAL(0, g_store_calls);
  TEST_ASSERT_EQUAL_STRING("error", parse(r[0])["t"].as<const char *>());
  TEST_ASSERT_EQUAL_STRING("pair", parse(r[0])["code"].as<const char *>());
}

void test_pair_cooldown_busy() {
  DeckSession s1(&ENV);
  do_hello(s1);
  std::vector<std::string> r;
  Pairing p;
  pair_start(s1, &p, &r);
  DeckSession s2(&ENV);
  g_random_calls = 0;
  do_hello(s2);
  std::string f = "{\"t\":\"pair_start\",\"pub\":\"" + hex(p.app_pub, 32) + "\"}";
  std::vector<std::string> r2;
  TEST_ASSERT_TRUE(send(s2, f, &r2));
  JsonDocument d = parse(r2[0]);
  TEST_ASSERT_EQUAL_STRING("error", d["t"].as<const char *>());
  TEST_ASSERT_EQUAL_STRING("busy", d["code"].as<const char *>());
}

void test_pair_allowed_after_cooldown() {
  DeckSession s1(&ENV);
  do_hello(s1);
  std::vector<std::string> r;
  Pairing p;
  pair_start(s1, &p, &r);
  g_now += DECK_PAIR_TIMEOUT_MS;
  s1.tick();
  DeckSession s2(&ENV);
  g_random_calls = 0;
  do_hello(s2);
  r.clear();
  pair_start(s2, &p, &r);
}

void test_pair_timeout_hides_code() {
  DeckSession s(&ENV);
  do_hello(s);
  std::vector<std::string> r;
  Pairing p;
  pair_start(s, &p, &r);
  TEST_ASSERT_TRUE(g_code_show);
  g_now += DECK_PAIR_TIMEOUT_MS - 1;
  s.tick();
  TEST_ASSERT_TRUE(g_code_show);
  g_now += 1;
  s.tick();
  TEST_ASSERT_EQUAL(2, g_code_calls);
  TEST_ASSERT_FALSE(g_code_show);
}

void test_handshake_after_ready_closes() {
  DeckSession s(&ENV);
  make_ready(s);
  std::vector<std::string> r;
  TEST_ASSERT_FALSE(send(s, auth_frame(app_proof()), &r));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_hello_gets_challenge);
  RUN_TEST(test_auth_ok_vector);
  RUN_TEST(test_auth_bad_proof_closes);
  RUN_TEST(test_frame_before_ready_closes);
  RUN_TEST(test_seal_vector);
  RUN_TEST(test_seal_before_ready_fails);
  RUN_TEST(test_replay_rejected);
  RUN_TEST(test_counter_shared_with_binary);
  RUN_TEST(test_frame_from_other_session_rejected);
  RUN_TEST(test_unsealed_frame_after_ready_closes);
  RUN_TEST(test_message_dispatch);
  RUN_TEST(test_face_chunk_dispatch);
  RUN_TEST(test_face_chunk_vector_mac);
  RUN_TEST(test_face_chunk_bad_mac_closes);
  RUN_TEST(test_face_chunk_too_big_closes);
  RUN_TEST(test_face_chunk_at_limit_ok);
  RUN_TEST(test_face_chunk_bad_pixel_count_closes);
  RUN_TEST(test_face_chunk_past_height_closes);
  RUN_TEST(test_binary_before_ready_closes);
  RUN_TEST(test_pair_flow);
  RUN_TEST(test_pair_wrong_confirm_keeps_old_key);
  RUN_TEST(test_pair_cooldown_busy);
  RUN_TEST(test_pair_allowed_after_cooldown);
  RUN_TEST(test_pair_timeout_hides_code);
  RUN_TEST(test_handshake_after_ready_closes);
  return UNITY_END();
}

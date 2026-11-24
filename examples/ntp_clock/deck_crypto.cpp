#include "deck_crypto.h"

#include <stdlib.h>
#include <string.h>

extern "C" {
#include "vendor/sha256.h"
#include "vendor/tweetnacl.h"

void randombytes(unsigned char *, unsigned long long) { abort(); }
}

void deck_sha256(const uint8_t *msg, size_t len, uint8_t out[32]) {
  SHA256_CTX ctx;
  sha256_init(&ctx);
  sha256_update(&ctx, msg, len);
  sha256_final(&ctx, out);
}

void deck_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t len,
                      uint8_t out[32]) {
  deck_hmac_sha256_2(key, key_len, msg, len, nullptr, 0, out);
}

void deck_hmac_sha256_2(const uint8_t *key, size_t key_len, const uint8_t *a, size_t a_len,
                        const uint8_t *b, size_t b_len, uint8_t out[32]) {
  uint8_t k[64] = {0};
  if (key_len > 64) {
    deck_sha256(key, key_len, k);
  } else if (key_len > 0) {
    memcpy(k, key, key_len);
  }
  uint8_t pad[64];
  uint8_t inner[32];
  SHA256_CTX ctx;
  for (int i = 0; i < 64; i++) pad[i] = k[i] ^ 0x36;
  sha256_init(&ctx);
  sha256_update(&ctx, pad, 64);
  if (a_len > 0) sha256_update(&ctx, a, a_len);
  if (b_len > 0) sha256_update(&ctx, b, b_len);
  sha256_final(&ctx, inner);
  for (int i = 0; i < 64; i++) pad[i] = k[i] ^ 0x5c;
  sha256_init(&ctx);
  sha256_update(&ctx, pad, 64);
  sha256_update(&ctx, inner, 32);
  sha256_final(&ctx, out);
}

void deck_x25519_public(uint8_t pub[32], const uint8_t priv[32]) {
  crypto_scalarmult_base(pub, priv);
}

void deck_x25519_shared(uint8_t shared[32], const uint8_t priv[32], const uint8_t peer_pub[32]) {
  crypto_scalarmult(shared, priv, peer_pub);
}

void deck_derive_key(uint8_t key[32], const uint8_t shared[32], const uint8_t board_pub[32],
                     const uint8_t app_pub[32]) {
  uint8_t buf[96];
  memcpy(buf, shared, 32);
  memcpy(buf + 32, board_pub, 32);
  memcpy(buf + 64, app_pub, 32);
  deck_sha256(buf, sizeof buf, key);
}

void deck_session_key(uint8_t ks[32], const uint8_t key[32], const uint8_t board_nonce[16],
                      const uint8_t app_nonce[16]) {
  uint8_t buf[7 + 16 + 16];
  memcpy(buf, "session", 7);
  memcpy(buf + 7, board_nonce, 16);
  memcpy(buf + 23, app_nonce, 16);
  deck_hmac_sha256(key, 32, buf, sizeof buf, ks);
}

uint32_t deck_pair_code(const uint8_t key[32]) {
  uint8_t mac[32];
  deck_hmac_sha256(key, 32, (const uint8_t *)"pin", 3, mac);
  uint32_t v = ((uint32_t)mac[0] << 24) | ((uint32_t)mac[1] << 16) | ((uint32_t)mac[2] << 8) | mac[3];
  return v % 1000000;
}

bool deck_ct_equal(const uint8_t *a, const uint8_t *b, size_t len) {
  uint8_t diff = 0;
  for (size_t i = 0; i < len; i++) diff |= a[i] ^ b[i];
  return diff == 0;
}

void deck_hex_encode(const uint8_t *in, size_t len, char *out) {
  static const char digits[] = "0123456789abcdef";
  for (size_t i = 0; i < len; i++) {
    out[2 * i] = digits[in[i] >> 4];
    out[2 * i + 1] = digits[in[i] & 0x0f];
  }
  out[2 * len] = '\0';
}

static int hex_val(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool deck_hex_decode(const char *in, uint8_t *out, size_t out_len) {
  if (strlen(in) != 2 * out_len) return false;
  for (size_t i = 0; i < out_len; i++) {
    int hi = hex_val(in[2 * i]);
    int lo = hex_val(in[2 * i + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = (uint8_t)((hi << 4) | lo);
  }
  return true;
}

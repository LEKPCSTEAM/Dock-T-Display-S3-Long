#pragma once
#include <stddef.h>
#include <stdint.h>

void deck_sha256(const uint8_t *msg, size_t len, uint8_t out[32]);
void deck_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg, size_t len,
                      uint8_t out[32]);
void deck_x25519_public(uint8_t pub[32], const uint8_t priv[32]);
void deck_x25519_shared(uint8_t shared[32], const uint8_t priv[32], const uint8_t peer_pub[32]);
void deck_derive_key(uint8_t key[32], const uint8_t shared[32], const uint8_t board_pub[32],
                     const uint8_t app_pub[32]);
void deck_session_key(uint8_t ks[32], const uint8_t key[32], const uint8_t board_nonce[16],
                      const uint8_t app_nonce[16]);
uint32_t deck_pair_code(const uint8_t key[32]);
bool deck_ct_equal(const uint8_t *a, const uint8_t *b, size_t len);
void deck_hex_encode(const uint8_t *in, size_t len, char *out);
bool deck_hex_decode(const char *in, uint8_t *out, size_t out_len);

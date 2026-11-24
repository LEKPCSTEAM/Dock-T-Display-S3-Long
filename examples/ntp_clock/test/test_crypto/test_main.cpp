#include <unity.h>
#include <string.h>
#include "deck_crypto.h"

void setUp() {}
void tearDown() {}

static void seq(uint8_t *b, size_t n, uint8_t start) {
  for (size_t i = 0; i < n; i++) b[i] = (uint8_t)(start + i);
}

static void hex_to_bytes(const char *hex, uint8_t *out, size_t n) {
  TEST_ASSERT_TRUE(deck_hex_decode(hex, out, n));
}

static void expect_hex(const char *hex, const uint8_t *got, size_t n) {
  uint8_t want[64];
  hex_to_bytes(hex, want, n);
  TEST_ASSERT_EQUAL_UINT8_ARRAY(want, got, n);
}

void test_hmac_rfc4231_case1() {
  uint8_t key[20], out[32];
  memset(key, 0x0b, sizeof key);
  deck_hmac_sha256(key, sizeof key, (const uint8_t *)"Hi There", 8, out);
  expect_hex("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", out, 32);
}

void test_hmac_rfc4231_case2() {
  uint8_t out[32];
  deck_hmac_sha256((const uint8_t *)"Jefe", 4,
                   (const uint8_t *)"what do ya want for nothing?", 28, out);
  expect_hex("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", out, 32);
}

void test_x25519_rfc7748() {
  uint8_t a_priv[32], a_pub[32], b_priv[32], b_pub[32], s1[32], s2[32];
  hex_to_bytes("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", a_priv, 32);
  hex_to_bytes("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb", b_priv, 32);
  deck_x25519_public(a_pub, a_priv);
  deck_x25519_public(b_pub, b_priv);
  expect_hex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", a_pub, 32);
  expect_hex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", b_pub, 32);
  deck_x25519_shared(s1, a_priv, b_pub);
  deck_x25519_shared(s2, b_priv, a_pub);
  expect_hex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", s1, 32);
  expect_hex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", s2, 32);
}

void test_pair_code_vector() {
  uint8_t k[32];
  seq(k, 32, 1);
  TEST_ASSERT_EQUAL_UINT32(953405, deck_pair_code(k));
}

void test_session_key_vector() {
  uint8_t k[32], bn[16], an[16], ks[32];
  seq(k, 32, 1);
  seq(bn, 16, 0x10);
  seq(an, 16, 0x20);
  deck_session_key(ks, k, bn, an);
  expect_hex("f30b85454b252c5c01eb34d0352494ace01b9084a912da17aa6c413bb797f9cf", ks, 32);
}

void test_derive_key_shape() {
  uint8_t s[32], bp[32], ap[32], k[32];
  memset(s, 1, 32);
  memset(bp, 2, 32);
  memset(ap, 3, 32);
  deck_derive_key(k, s, bp, ap);
  expect_hex("8a2e491356cfdb05a1d13785e0794d7cd163f91af79a146c976b1d2ac643b679", k, 32);
}

void test_hex_roundtrip() {
  uint8_t in[4] = {0x00, 0xab, 0xcd, 0xff}, out[4];
  char hex[9];
  deck_hex_encode(in, 4, hex);
  TEST_ASSERT_EQUAL_STRING("00abcdff", hex);
  TEST_ASSERT_TRUE(deck_hex_decode(hex, out, 4));
  TEST_ASSERT_EQUAL_UINT8_ARRAY(in, out, 4);
  TEST_ASSERT_TRUE(deck_hex_decode("00ABCDFF", out, 4));
  TEST_ASSERT_EQUAL_UINT8_ARRAY(in, out, 4);
  TEST_ASSERT_FALSE(deck_hex_decode("00abcd", out, 4));
  TEST_ASSERT_FALSE(deck_hex_decode("00abcdff00", out, 4));
  TEST_ASSERT_FALSE(deck_hex_decode("00abcdfg", out, 4));
}

void test_ct_equal() {
  uint8_t a[4] = {1, 2, 3, 4}, b[4] = {1, 2, 3, 4}, c[4] = {1, 2, 3, 5};
  TEST_ASSERT_TRUE(deck_ct_equal(a, b, 4));
  TEST_ASSERT_FALSE(deck_ct_equal(a, c, 4));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_hmac_rfc4231_case1);
  RUN_TEST(test_hmac_rfc4231_case2);
  RUN_TEST(test_x25519_rfc7748);
  RUN_TEST(test_pair_code_vector);
  RUN_TEST(test_session_key_vector);
  RUN_TEST(test_derive_key_shape);
  RUN_TEST(test_hex_roundtrip);
  RUN_TEST(test_ct_equal);
  return UNITY_END();
}

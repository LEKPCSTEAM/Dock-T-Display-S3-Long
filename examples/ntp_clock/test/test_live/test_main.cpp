#include <unity.h>
#include <math.h>
#include <string.h>
#include <string>
#include "deck_live.h"

void setUp() {}
void tearDown() {}

static const char *S1 =
    "{\"battery\":-1,\"cpu\":37,\"disk_free_pct\":58,\"disk_io_bps\":1048576,\"gpu\":12,\"net_down_bps\":125000,"
    "\"net_up_bps\":2048,\"ram\":62,\"temp_c\":67}";
static const char *S2 =
    "{\"battery\":-1,\"cpu\":0,\"disk_free_pct\":100,\"disk_io_bps\":0,\"gpu\":100,\"net_down_bps\":0,"
    "\"net_up_bps\":0,\"ram\":100,\"temp_c\":null}";
static const char *V1 = "{\"available\":true,\"level\":44,\"muted\":false}";
static const char *V2 = "{\"available\":false,\"level\":0,\"muted\":false}";
static const char *P1 = "{\"id\":\"vol\",\"value\":55}";

static bool parse_stats(const char *j, DeckStats *s) { return deck_stats_parse(j, strlen(j), s); }
static bool has(const DeckStats &s, int m) { return s.valid & (1u << m); }

void test_stats_parse_s1() {
  DeckStats s;
  TEST_ASSERT_TRUE(parse_stats(S1, &s));
  TEST_ASSERT_EQUAL_FLOAT(37, s.v[DM_CPU]);
  TEST_ASSERT_EQUAL_FLOAT(62, s.v[DM_RAM]);
  TEST_ASSERT_EQUAL_FLOAT(12, s.v[DM_GPU]);
  TEST_ASSERT_EQUAL_FLOAT(67, s.v[DM_TEMP]);
  TEST_ASSERT_EQUAL_FLOAT(125000, s.v[DM_NET_DOWN]);
  TEST_ASSERT_EQUAL_FLOAT(2048, s.v[DM_NET_UP]);
  TEST_ASSERT_EQUAL_FLOAT(58, s.v[DM_DISK_FREE]);
  TEST_ASSERT_EQUAL_FLOAT(1048576, s.v[DM_DISK_IO]);
  for (int m = 0; m < DM_COUNT; m++) TEST_ASSERT_EQUAL(m != DM_BATTERY, has(s, m));
}

void test_stats_parse_s2_null_temp() {
  DeckStats s;
  TEST_ASSERT_TRUE(parse_stats(S2, &s));
  TEST_ASSERT_FALSE(has(s, DM_TEMP));
  TEST_ASSERT_TRUE(has(s, DM_CPU));
  TEST_ASSERT_EQUAL_FLOAT(0, s.v[DM_CPU]);
  TEST_ASSERT_EQUAL_FLOAT(100, s.v[DM_GPU]);
  TEST_ASSERT_EQUAL_FLOAT(100, s.v[DM_DISK_FREE]);
}

void test_stats_accepts_float_and_clamps() {
  DeckStats s;
  TEST_ASSERT_TRUE(parse_stats("{\"cpu\":12.5,\"ram\":150,\"net_down_bps\":-5}", &s));
  TEST_ASSERT_EQUAL_FLOAT(12.5f, s.v[DM_CPU]);
  TEST_ASSERT_EQUAL_FLOAT(100, s.v[DM_RAM]);
  TEST_ASSERT_EQUAL_FLOAT(0, s.v[DM_NET_DOWN]);
  TEST_ASSERT_TRUE(has(s, DM_NET_DOWN));
  TEST_ASSERT_FALSE(has(s, DM_GPU));
  TEST_ASSERT_FALSE(has(s, DM_TEMP));
  TEST_ASSERT_FALSE(has(s, DM_BATTERY));
}

void test_stats_wrong_type_is_unknown() {
  DeckStats s;
  TEST_ASSERT_TRUE(parse_stats("{\"cpu\":\"x\",\"gpu\":true}", &s));
  TEST_ASSERT_FALSE(has(s, DM_CPU));
  TEST_ASSERT_FALSE(has(s, DM_GPU));
}

void test_stats_malformed_keeps_out() {
  DeckStats s, ref;
  memset(&s, 0xA5, sizeof s);
  memcpy(&ref, &s, sizeof s);
  TEST_ASSERT_FALSE(parse_stats("{\"cpu\":", &s));
  TEST_ASSERT_FALSE(parse_stats("[1,2]", &s));
  std::string big = "{\"cpu\":1}";
  big.resize(513, ' ');
  TEST_ASSERT_EQUAL(513, big.size());
  TEST_ASSERT_FALSE(deck_stats_parse(big.c_str(), big.size(), &s));
  TEST_ASSERT_EQUAL_INT(0, memcmp(&s, &ref, sizeof s));
}

void test_volume_parse_v1_v2() {
  DeckVolume v;
  TEST_ASSERT_TRUE(deck_volume_parse(V1, strlen(V1), &v));
  TEST_ASSERT_EQUAL_UINT8(44, v.level);
  TEST_ASSERT_FALSE(v.muted);
  TEST_ASSERT_TRUE(v.available);
  TEST_ASSERT_TRUE(deck_volume_parse(V2, strlen(V2), &v));
  TEST_ASSERT_FALSE(v.available);
}

void test_volume_missing_field_rejected() {
  DeckVolume v = {7, true, true};
  const char *a = "{\"level\":10,\"muted\":false}";
  const char *b = "{\"level\":\"x\",\"muted\":false,\"available\":true}";
  const char *c = "{\"level\":150,\"muted\":false,\"available\":true}";
  TEST_ASSERT_FALSE(deck_volume_parse(a, strlen(a), &v));
  TEST_ASSERT_FALSE(deck_volume_parse(b, strlen(b), &v));
  TEST_ASSERT_EQUAL_UINT8(7, v.level);
  TEST_ASSERT_TRUE(deck_volume_parse(c, strlen(c), &v));
  TEST_ASSERT_EQUAL_UINT8(100, v.level);
}

void test_history_order_and_wrap() {
  DeckHistory h;
  deck_history_clear(&h);
  for (int i = 0; i < 65; i++) {
    DeckStats s;
    memset(&s, 0, sizeof s);
    s.valid = 1u << DM_CPU;
    s.v[DM_CPU] = (float)i;
    deck_history_push(&h, &s);
  }
  float out[DECK_HISTORY_LEN];
  TEST_ASSERT_EQUAL_UINT8(60, deck_history_series(&h, DM_CPU, out));
  TEST_ASSERT_EQUAL_FLOAT(5, out[0]);
  TEST_ASSERT_EQUAL_FLOAT(64, out[59]);
  TEST_ASSERT_EQUAL_FLOAT(64, deck_history_max(&h, DM_CPU));
}

void test_history_unknown_is_nan_and_ignored_by_max() {
  DeckHistory h;
  deck_history_clear(&h);
  DeckStats s;
  memset(&s, 0, sizeof s);
  for (int i = 0; i < 5; i++) deck_history_push(&h, &s);
  float out[DECK_HISTORY_LEN];
  TEST_ASSERT_EQUAL_UINT8(5, deck_history_series(&h, DM_TEMP, out));
  for (int i = 0; i < 5; i++) TEST_ASSERT_TRUE(isnan(out[i]));
  TEST_ASSERT_EQUAL_FLOAT(0, deck_history_max(&h, DM_TEMP));
}

void test_history_clear() {
  DeckHistory h;
  deck_history_clear(&h);
  DeckStats s;
  memset(&s, 0, sizeof s);
  deck_history_push(&h, &s);
  deck_history_clear(&h);
  float out[DECK_HISTORY_LEN];
  TEST_ASSERT_EQUAL_UINT8(0, h.count);
  TEST_ASSERT_EQUAL_UINT8(0, deck_history_series(&h, DM_CPU, out));
  TEST_ASSERT_EQUAL_FLOAT(0, deck_history_max(&h, DM_CPU));
}

void test_level_percent_and_temp() {
  TEST_ASSERT_EQUAL_INT(37, deck_live_level(DM_CPU, 37, 0));
  TEST_ASSERT_EQUAL_INT(100, deck_live_level(DM_CPU, 120, 0));
  TEST_ASSERT_EQUAL_INT(0, deck_live_level(DM_CPU, -3, 0));
  TEST_ASSERT_EQUAL_INT(67, deck_live_level(DM_TEMP, 67.4f, 0));
  TEST_ASSERT_EQUAL_INT(100, deck_live_level(DM_TEMP, 130, 0));
}

void test_level_rates_use_floor_and_max() {
  TEST_ASSERT_EQUAL_INT(50, deck_live_level(DM_NET_DOWN, 50000, 0));
  TEST_ASSERT_EQUAL_INT(25, deck_live_level(DM_NET_DOWN, 50000, 200000));
  TEST_ASSERT_EQUAL_INT(100, deck_live_level(DM_DISK_IO, 1e6f, 1e6f));
  TEST_ASSERT_EQUAL_INT(0, deck_live_level(DM_NET_UP, NAN, 1e6f));
  TEST_ASSERT_EQUAL_INT(0, deck_live_level(DM_CPU, NAN, 0));
}

static void expect_format(uint8_t metric, float value, const char *text, const char *unit) {
  DeckStats s;
  memset(&s, 0, sizeof s);
  s.v[metric] = value;
  if (!isnan(value)) s.valid = 1u << metric;
  char v[16], u[16];
  deck_live_format(metric, &s, v, sizeof v, u, sizeof u);
  TEST_ASSERT_EQUAL_STRING(text, v);
  TEST_ASSERT_EQUAL_STRING(unit, u);
}

void test_format_vectors() {
  expect_format(DM_CPU, 37, "37", "%");
  expect_format(DM_TEMP, 67, "67", "\xC2\xB0"
                                   "C");
  expect_format(DM_NET_DOWN, 0, "0", "B/s");
  expect_format(DM_NET_DOWN, 999, "999", "B/s");
  expect_format(DM_NET_DOWN, 999.6f, "1.0", "KB/s");
  expect_format(DM_NET_DOWN, 2048, "2.0", "KB/s");
  expect_format(DM_NET_DOWN, 9960, "10", "KB/s");
  expect_format(DM_NET_DOWN, 125000, "125", "KB/s");
  expect_format(DM_NET_DOWN, 999999, "1.0", "MB/s");
  expect_format(DM_DISK_IO, 1048576, "1.0", "MB/s");
  expect_format(DM_NET_UP, 2.5e9f, "2.5", "GB/s");
  expect_format(DM_BATTERY, NAN, "--", "");
  expect_format(DM_TEMP, NAN, "--", "");
}

void test_metric_labels() {
  TEST_ASSERT_EQUAL_STRING("CPU", deck_metric_label(DM_CPU));
  TEST_ASSERT_EQUAL_STRING("NET \xEF\x81\xB8", deck_metric_label(DM_NET_DOWN));
  TEST_ASSERT_EQUAL_STRING("NET \xEF\x81\xB7", deck_metric_label(DM_NET_UP));
  TEST_ASSERT_EQUAL_STRING("DISK I/O", deck_metric_label(DM_DISK_IO));
  TEST_ASSERT_EQUAL_STRING("BAT", deck_metric_label(DM_BATTERY));
}

static bool offer(DeckSliderGate *g, uint32_t t, int v, int *out) { return deck_slider_offer(g, t, v, out); }

void test_slider_rate_limit_vector() {
  DeckSliderGate g;
  deck_slider_reset(&g);
  int o = -1;
  TEST_ASSERT_TRUE(offer(&g, 0, 10, &o));
  TEST_ASSERT_EQUAL_INT(10, o);
  TEST_ASSERT_FALSE(offer(&g, 30, 20, &o));
  TEST_ASSERT_FALSE(offer(&g, 60, 30, &o));
  TEST_ASSERT_FALSE(deck_slider_poll(&g, 90, &o));
  TEST_ASSERT_TRUE(deck_slider_poll(&g, 100, &o));
  TEST_ASSERT_EQUAL_INT(30, o);
  TEST_ASSERT_FALSE(offer(&g, 150, 40, &o));
  TEST_ASSERT_FALSE(deck_slider_poll(&g, 199, &o));
  TEST_ASSERT_TRUE(deck_slider_poll(&g, 200, &o));
  TEST_ASSERT_EQUAL_INT(40, o);
  TEST_ASSERT_FALSE(deck_slider_poll(&g, 400, &o));
  TEST_ASSERT_FALSE(offer(&g, 400, 40, &o));
  TEST_ASSERT_TRUE(offer(&g, 401, 41, &o));
  TEST_ASSERT_EQUAL_INT(41, o);
}

void test_slider_at_most_10_per_second() {
  DeckSliderGate g;
  deck_slider_reset(&g);
  int sends = 0, o = 0;
  for (uint32_t t = 0; t < 1000; t += 10) {
    if (offer(&g, t, (int)(t / 10), &o)) sends++;
    if (t % 30 == 0 && deck_slider_poll(&g, t, &o)) sends++;
  }
  TEST_ASSERT_TRUE(sends <= 10);
  TEST_ASSERT_TRUE(deck_slider_poll(&g, 1100, &o));
  TEST_ASSERT_EQUAL_INT(99, o);
}

void test_slider_final_value_delivered() {
  DeckSliderGate g;
  deck_slider_reset(&g);
  int o = 0;
  TEST_ASSERT_TRUE(offer(&g, 0, 10, &o));
  TEST_ASSERT_FALSE(offer(&g, 20, 77, &o));
  TEST_ASSERT_FALSE(deck_slider_poll(&g, 99, &o));
  TEST_ASSERT_TRUE(deck_slider_poll(&g, 100, &o));
  TEST_ASSERT_EQUAL_INT(77, o);
}

void test_slider_body_p1() {
  char b[64];
  TEST_ASSERT_TRUE(deck_slider_body("vol", 55, b, sizeof b));
  TEST_ASSERT_EQUAL_STRING(P1, b);
  TEST_ASSERT_TRUE(deck_slider_body("vol", 150, b, sizeof b));
  TEST_ASSERT_NOT_NULL(strstr(b, "\"value\":100"));
  char small[8];
  TEST_ASSERT_FALSE(deck_slider_body("vol", 55, small, sizeof small));
  TEST_ASSERT_FALSE(deck_slider_body("", 55, b, sizeof b));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_stats_parse_s1);
  RUN_TEST(test_stats_parse_s2_null_temp);
  RUN_TEST(test_stats_accepts_float_and_clamps);
  RUN_TEST(test_stats_wrong_type_is_unknown);
  RUN_TEST(test_stats_malformed_keeps_out);
  RUN_TEST(test_volume_parse_v1_v2);
  RUN_TEST(test_volume_missing_field_rejected);
  RUN_TEST(test_history_order_and_wrap);
  RUN_TEST(test_history_unknown_is_nan_and_ignored_by_max);
  RUN_TEST(test_history_clear);
  RUN_TEST(test_level_percent_and_temp);
  RUN_TEST(test_level_rates_use_floor_and_max);
  RUN_TEST(test_format_vectors);
  RUN_TEST(test_metric_labels);
  RUN_TEST(test_slider_rate_limit_vector);
  RUN_TEST(test_slider_at_most_10_per_second);
  RUN_TEST(test_slider_final_value_delivered);
  RUN_TEST(test_slider_body_p1);
  return UNITY_END();
}

#include <unity.h>
#include <string.h>
#include <string>
#include "deck_layout.h"

void setUp() {}
void tearDown() {}

static const char *HASH = "0123456789abcdef";

static std::string key(const char *id, int col, int row, int w, int h, int face,
                       const char *type = "key", bool lng = false) {
  char buf[200];
  snprintf(buf, sizeof buf,
           "{\"id\":\"%s\",\"type\":\"%s\",\"col\":%d,\"row\":%d,\"w\":%d,\"h\":%d,\"face\":%d,\"long\":%s}",
           id, type, col, row, w, h, face, lng ? "true" : "false");
  return buf;
}

static std::string page(const char *name, const std::string &widgets) {
  return std::string("{\"name\":\"") + name + "\",\"widgets\":[" + widgets + "]}";
}

static std::string layout(const std::string &pages, const char *hash = HASH) {
  return std::string("{\"hash\":\"") + hash + "\",\"pages\":[" + pages + "]}";
}

static bool parse(const std::string &s, DeckLayout *out, char *err, size_t n = 64) {
  err[0] = 0;
  return deck_layout_parse(s.c_str(), s.size(), out, err, n);
}

static void expect_reject(const std::string &s) {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_FALSE(parse(s, &l, err));
  TEST_ASSERT_TRUE(strlen(err) > 0);
}

void test_parse_sample() {
  std::string w1;
  for (int i = 0; i < 8; i++) {
    char id[8];
    snprintf(id, sizeof id, "k%d", i);
    if (i) w1 += ",";
    w1 += key(id, i, 0, 1, 1, i + 1, "key", i == 3);
  }
  std::string w2 = key("a", 0, 0, 2, 1, 9) + "," + key("b", 2, 1, 1, 1, 10) + "," +
                   key("c", 7, 0, 1, 2, 128);
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("Dev", w1) + "," + page("Med\\/ia", w2)), &l, err));
  TEST_ASSERT_EQUAL_STRING(HASH, l.hash);
  TEST_ASSERT_EQUAL_UINT8(2, l.page_count);
  TEST_ASSERT_EQUAL_STRING("Dev", l.pages[0].name);
  TEST_ASSERT_EQUAL_UINT8(8, l.pages[0].count);
  TEST_ASSERT_EQUAL_STRING("k3", l.pages[0].widgets[3].id);
  TEST_ASSERT_TRUE(l.pages[0].widgets[3].has_long);
  TEST_ASSERT_FALSE(l.pages[0].widgets[2].has_long);
  TEST_ASSERT_EQUAL_UINT8(DW_KEY, l.pages[0].widgets[7].type);
  TEST_ASSERT_EQUAL_UINT8(7, l.pages[0].widgets[7].col);
  TEST_ASSERT_EQUAL_UINT16(8, l.pages[0].widgets[7].face);
  TEST_ASSERT_EQUAL_STRING("Med/ia", l.pages[1].name);
  TEST_ASSERT_EQUAL_UINT8(3, l.pages[1].count);
  TEST_ASSERT_EQUAL_UINT8(2, l.pages[1].widgets[0].w);
  TEST_ASSERT_EQUAL_UINT8(1, l.pages[1].widgets[1].row);
  TEST_ASSERT_EQUAL_UINT8(2, l.pages[1].widgets[2].h);
  TEST_ASSERT_EQUAL_UINT16(128, l.pages[1].widgets[2].face);
}

void test_reject_out_of_grid() {
  expect_reject(layout(page("P", key("a", 7, 0, 2, 1, 1))));
  expect_reject(layout(page("P", key("a", 0, 1, 1, 2, 1))));
  expect_reject(layout(page("P", key("a", 0, 0, 0, 1, 1))));
  expect_reject(layout(page("P", key("a", 0, 0, 1, 0, 1))));
}

void test_reject_overlap() {
  expect_reject(layout(page("P", key("a", 0, 0, 2, 2, 1) + "," + key("b", 1, 1, 1, 1, 2))));
}

void test_reject_duplicate_id() {
  expect_reject(layout(page("P", key("a", 0, 0, 1, 1, 1)) + "," + page("Q", key("a", 0, 0, 1, 1, 1))));
}

void test_reject_too_many_pages() {
  std::string p;
  for (int i = 0; i < 9; i++) {
    char id[8];
    snprintf(id, sizeof id, "k%d", i);
    if (i) p += ",";
    p += page("P", key(id, 0, 0, 1, 1, 1));
  }
  expect_reject(layout(p));
}

void test_accept_eight_pages() {
  std::string p;
  for (int i = 0; i < 8; i++) {
    char id[8];
    snprintf(id, sizeof id, "k%d", i);
    if (i) p += ",";
    p += page("P", key(id, 0, 0, 1, 1, 1));
  }
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(p), &l, err));
  TEST_ASSERT_EQUAL_UINT8(8, l.page_count);
}

void test_reject_too_many_widgets() {
  std::string w;
  for (int i = 0; i < 17; i++) {
    char id[8];
    snprintf(id, sizeof id, "k%d", i);
    if (i) w += ",";
    w += key(id, i % 8, i / 8, 1, 1, 1);
  }
  expect_reject(layout(page("P", w)));
}

void test_reject_face_out_of_range() {
  expect_reject(layout(page("P", key("a", 0, 0, 1, 1, 0))));
  expect_reject(layout(page("P", key("a", 0, 0, 1, 1, 129))));
}

void test_reject_missing_hash() {
  expect_reject("{\"pages\":[" + page("P", key("a", 0, 0, 1, 1, 1)) + "]}");
}

void test_reject_bad_hash() {
  const std::string p = page("P", key("a", 0, 0, 1, 1, 1));
  expect_reject(layout(p, "0123456789abcde"));
  expect_reject(layout(p, "0123456789abcdef0"));
  expect_reject(layout(p, "0123456789ABCDEF"));
  expect_reject(layout(p, "0123456789abcdeg"));
}

void test_reject_long_names() {
  expect_reject(layout(page("P", key("0123456789abcdef", 0, 0, 1, 1, 1))));
  expect_reject(layout(page("012345678901234567890123", key("a", 0, 0, 1, 1, 1))));
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("01234567890123456789012", key("012345678901234", 0, 0, 1, 1, 1))), &l, err));
}

void test_reject_malformed_json() {
  expect_reject("{\"hash\":\"0123456789abcdef\",\"pages\":[");
  expect_reject("not json");
}

void test_reject_oversize() {
  std::string s(DECK_LAYOUT_MAX_BYTES + 1, ' ');
  DeckLayout l;
  char err[64];
  TEST_ASSERT_FALSE(deck_layout_parse(s.c_str(), s.size(), &l, err, sizeof err));
  TEST_ASSERT_TRUE(strlen(err) > 0);
}

void test_unknown_type_kept_as_placeholder() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("P", key("g", 0, 0, 2, 1, 1, "gauge"))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(1, l.pages[0].count);
  TEST_ASSERT_EQUAL_UINT8(DW_UNKNOWN, l.pages[0].widgets[0].type);
  expect_reject(layout(page("P", key("g", 0, 0, 2, 1, 1, "gauge") + "," + key("a", 1, 0, 1, 1, 1))));
}

void test_out_unchanged_on_error() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("Keep", key("a", 0, 0, 1, 1, 5))), &l, err));
  TEST_ASSERT_FALSE(parse(layout(page("Bad", key("a", 7, 0, 2, 1, 5))), &l, err));
  TEST_ASSERT_EQUAL_STRING("Keep", l.pages[0].name);
  TEST_ASSERT_EQUAL_UINT8(1, l.page_count);
  TEST_ASSERT_EQUAL_UINT16(5, l.pages[0].widgets[0].face);
}

static const char *L1 =
    "{\"hash\":\"0123456789abcdef\",\"pages\":[{\"name\":\"Mac\",\"widgets\":[{\"col\":7,\"face\":1,\"h\":1,\"id\":\"k1\","
    "\"long\":false,\"row\":0,\"type\":\"key\",\"w\":1},{\"col\":0,\"face\":0,\"h\":1,\"id\":\"cpu\",\"metric\":\"cpu\","
    "\"row\":0,\"style\":\"sparkline\",\"type\":\"stat\",\"w\":2},{\"col\":2,\"face\":0,\"h\":1,\"id\":\"vol\",\"row\":0,"
    "\"type\":\"volume\",\"w\":3},{\"col\":5,\"face\":0,\"h\":1,\"id\":\"clk\",\"row\":0,\"type\":\"clock\",\"w\":2},"
    "{\"col\":0,\"face\":0,\"h\":1,\"id\":\"tmp\",\"metric\":\"temp\",\"row\":1,\"style\":\"number\",\"type\":\"stat\","
    "\"w\":1}]}]}";

static std::string stat(const char *id, int col, int row, int w, const char *metric, const char *style) {
  std::string s = std::string("{\"id\":\"") + id + "\",\"type\":\"stat\",\"col\":" + std::to_string(col) +
                  ",\"row\":" + std::to_string(row) + ",\"w\":" + std::to_string(w) + ",\"h\":1";
  if (metric) s += std::string(",\"metric\":\"") + metric + "\"";
  if (style) s += std::string(",\"style\":\"") + style + "\"";
  return s + "}";
}

void test_parse_live_example() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(deck_layout_parse(L1, strlen(L1), &l, err, sizeof err));
  TEST_ASSERT_EQUAL_UINT8(5, l.pages[0].count);
  const DeckWidget *w = l.pages[0].widgets;
  TEST_ASSERT_EQUAL_UINT8(DW_KEY, w[0].type);
  TEST_ASSERT_EQUAL_UINT16(1, w[0].face);
  TEST_ASSERT_EQUAL_UINT8(DW_STAT, w[1].type);
  TEST_ASSERT_EQUAL_UINT8(DM_CPU, w[1].metric);
  TEST_ASSERT_EQUAL_UINT8(DS_SPARKLINE, w[1].style);
  TEST_ASSERT_EQUAL_UINT16(0, w[1].face);
  TEST_ASSERT_EQUAL_UINT8(DW_VOLUME, w[2].type);
  TEST_ASSERT_EQUAL_UINT8(DW_CLOCK, w[3].type);
  TEST_ASSERT_EQUAL_UINT8(DW_STAT, w[4].type);
  TEST_ASSERT_EQUAL_UINT8(DM_TEMP, w[4].metric);
  TEST_ASSERT_EQUAL_UINT8(DS_NUMBER, w[4].style);
}

void test_every_metric_and_style_name() {
  const char *m[] = {"cpu", "ram", "gpu", "temp", "net_down", "net_up", "disk_free", "disk_io", "battery"};
  for (int i = 0; i < 9; i++) TEST_ASSERT_EQUAL_INT(i, deck_metric_from_name(m[i]));
  TEST_ASSERT_EQUAL_INT(-1, deck_metric_from_name("fan"));
  TEST_ASSERT_EQUAL_INT(-1, deck_metric_from_name(""));
  TEST_ASSERT_EQUAL_INT(DS_BAR, deck_style_from_name("bar"));
  TEST_ASSERT_EQUAL_INT(DS_NUMBER, deck_style_from_name("number"));
  TEST_ASSERT_EQUAL_INT(DS_SPARKLINE, deck_style_from_name("sparkline"));
  TEST_ASSERT_EQUAL_INT(-1, deck_style_from_name("fan"));
  TEST_ASSERT_EQUAL_INT(-1, deck_style_from_name(""));
}

void test_stat_unknown_metric_is_placeholder() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("P", stat("s", 0, 0, 2, "fan", "bar"))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(DW_UNKNOWN, l.pages[0].widgets[0].type);
  expect_reject(layout(page("P", stat("s", 0, 0, 2, "fan", "bar") + "," + key("a", 1, 0, 1, 1, 1))));
}

void test_stat_missing_style_is_placeholder() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("P", stat("s", 0, 0, 2, "cpu", nullptr))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(DW_UNKNOWN, l.pages[0].widgets[0].type);
  TEST_ASSERT_TRUE(parse(layout(page("P", stat("s", 0, 0, 2, nullptr, "bar"))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(DW_UNKNOWN, l.pages[0].widgets[0].type);
}

void test_live_widget_face_and_long_ignored() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("P", key("v", 0, 0, 2, 1, 7, "volume", true))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(DW_VOLUME, l.pages[0].widgets[0].type);
  TEST_ASSERT_EQUAL_UINT16(0, l.pages[0].widgets[0].face);
  TEST_ASSERT_FALSE(l.pages[0].widgets[0].has_long);
  TEST_ASSERT_TRUE(parse(layout(page("P", key("g", 0, 0, 2, 1, 7, "gauge", true))), &l, err));
  TEST_ASSERT_EQUAL_UINT16(0, l.pages[0].widgets[0].face);
  TEST_ASSERT_FALSE(l.pages[0].widgets[0].has_long);
}

void test_live_widgets_respect_grid() {
  expect_reject(layout(page("P", key("v", 7, 0, 2, 1, 0, "volume"))));
  expect_reject(layout(page("P", key("c", 0, 0, 2, 1, 0, "clock") + "," + key("a", 1, 0, 1, 1, 1))));
  expect_reject(layout(page("P", key("a", 0, 0, 1, 1, 1)) + "," + page("Q", stat("a", 0, 0, 1, "cpu", "bar"))));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_parse_live_example);
  RUN_TEST(test_every_metric_and_style_name);
  RUN_TEST(test_stat_unknown_metric_is_placeholder);
  RUN_TEST(test_stat_missing_style_is_placeholder);
  RUN_TEST(test_live_widget_face_and_long_ignored);
  RUN_TEST(test_live_widgets_respect_grid);
  RUN_TEST(test_parse_sample);
  RUN_TEST(test_reject_out_of_grid);
  RUN_TEST(test_reject_overlap);
  RUN_TEST(test_reject_duplicate_id);
  RUN_TEST(test_reject_too_many_pages);
  RUN_TEST(test_accept_eight_pages);
  RUN_TEST(test_reject_too_many_widgets);
  RUN_TEST(test_reject_face_out_of_range);
  RUN_TEST(test_reject_missing_hash);
  RUN_TEST(test_reject_bad_hash);
  RUN_TEST(test_reject_long_names);
  RUN_TEST(test_reject_malformed_json);
  RUN_TEST(test_reject_oversize);
  RUN_TEST(test_unknown_type_kept_as_placeholder);
  RUN_TEST(test_out_unchanged_on_error);
  return UNITY_END();
}

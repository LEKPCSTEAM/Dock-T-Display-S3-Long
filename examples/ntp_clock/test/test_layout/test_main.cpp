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

int main() {
  UNITY_BEGIN();
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

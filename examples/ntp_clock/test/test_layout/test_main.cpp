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

void test_parse_claude_example() {
  const char *L2 =
      "{\"hash\":\"0123456789abcdef\",\"pages\":[{\"name\":\"Claude\",\"widgets\":["
      "{\"col\":0,\"face\":0,\"h\":2,\"id\":\"ccs\",\"row\":0,\"type\":\"claude_sessions\",\"w\":4},"
      "{\"col\":4,\"face\":0,\"h\":1,\"id\":\"ccu\",\"row\":0,\"type\":\"claude_usage\",\"w\":4}]}]}";
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(L2, &l, err));
  const DeckWidget &a = l.pages[0].widgets[0];
  const DeckWidget &b = l.pages[0].widgets[1];
  TEST_ASSERT_EQUAL_UINT8(DW_CLAUDE_SESSIONS, a.type);
  TEST_ASSERT_EQUAL_UINT8(4, a.w);
  TEST_ASSERT_EQUAL_UINT8(2, a.h);
  TEST_ASSERT_EQUAL_UINT8(DW_CLAUDE_USAGE, b.type);
  TEST_ASSERT_EQUAL_UINT8(4, b.w);
  TEST_ASSERT_EQUAL_UINT8(1, b.h);
  TEST_ASSERT_EQUAL_UINT16(0, a.face);
  TEST_ASSERT_EQUAL_UINT16(0, b.face);
  TEST_ASSERT_FALSE(a.has_long);
  TEST_ASSERT_FALSE(b.has_long);
}

void test_claude_sessions_needs_two_columns() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("P", key("c", 0, 0, 1, 1, 0, "claude_sessions"))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(DW_UNKNOWN, l.pages[0].widgets[0].type);
  expect_reject(layout(page("P", key("c", 0, 0, 1, 1, 0, "claude_sessions") + "," + key("a", 0, 0, 1, 1, 1))));
}

void test_claude_face_and_long_ignored() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("P", key("u", 0, 0, 1, 1, 9, "claude_usage", true))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(DW_CLAUDE_USAGE, l.pages[0].widgets[0].type);
  TEST_ASSERT_EQUAL_UINT16(0, l.pages[0].widgets[0].face);
  TEST_ASSERT_FALSE(l.pages[0].widgets[0].has_long);
}

static std::string list(int n, int v) {
  std::string s;
  for (int i = 0; i < n; i++) s += (i ? "," : "") + std::to_string(v + i);
  return s;
}

static std::string sprites(int first, const std::string &tags, int ms_n, int frames, const std::string &hats,
                           int hx_n = -1) {
  if (hx_n < 0) hx_n = frames;
  return ",\"agent_sprites\":{\"w\":60,\"h\":72,\"first\":" + std::to_string(first) + ",\"tags\":" + tags +
         ",\"ms\":[" + list(ms_n, 150) + "],\"hx\":[" + list(hx_n, 0) + "],\"hy\":[" + list(frames, 1) +
         "],\"hats\":" + hats + ",\"hw\":60,\"hh\":30}";
}

static const char *TAGS14 = "[[0,4],[4,2],[6,4],[10,4]]";

static std::string with_sprites(const std::string &sp) {
  std::string l = layout(page("P", key("a", 0, 0, 2, 1, 1, "claude_agents")));
  l.insert(l.size() - 1, sp);
  return l;
}

void test_agents_widget_type() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("P", key("a", 0, 0, 2, 1, 1, "claude_agents"))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(DW_CLAUDE_AGENTS, l.pages[0].widgets[0].type);
  TEST_ASSERT_TRUE(parse(layout(page("P", key("a", 0, 0, 1, 1, 1, "claude_agents"))), &l, err));
  TEST_ASSERT_EQUAL_UINT8(DW_UNKNOWN, l.pages[0].widgets[0].type);
}

void test_sprite_table_parse() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(with_sprites(sprites(129, TAGS14, 14, 14, "[143,8]")), &l, err));
  const DeckAgentSprites &s = l.sprites;
  TEST_ASSERT_TRUE(s.present);
  TEST_ASSERT_EQUAL_UINT8(60, s.w);
  TEST_ASSERT_EQUAL_UINT8(72, s.h);
  TEST_ASSERT_EQUAL_UINT8(14, s.frames);
  TEST_ASSERT_EQUAL_UINT16(129, s.first_id);
  TEST_ASSERT_EQUAL_UINT8(8, s.hat_count);
  TEST_ASSERT_EQUAL_UINT16(143, s.hat_first);
  TEST_ASSERT_EQUAL_UINT8(60, s.hat_w);
  TEST_ASSERT_EQUAL_UINT8(30, s.hat_h);
  const uint8_t first[4] = {0, 4, 6, 10}, count[4] = {4, 2, 4, 4};
  for (int i = 0; i < 4; i++) {
    TEST_ASSERT_EQUAL_UINT8(first[i], s.tag_first[i]);
    TEST_ASSERT_EQUAL_UINT8(count[i], s.tag_count[i]);
  }
  for (int i = 0; i < 14; i++) {
    TEST_ASSERT_EQUAL_UINT16(150 + i, s.ms[i]);
    TEST_ASSERT_EQUAL_UINT8(i, s.hat_x[i]);
    TEST_ASSERT_EQUAL_UINT8(1 + i, s.hat_y[i]);
  }
}

void test_absent_sprites_default() {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(layout(page("P", key("a", 0, 0, 1, 1, 1))), &l, err));
  TEST_ASSERT_FALSE(l.sprites.present);
}

static void expect_no_sprites(const std::string &sp) {
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(with_sprites(sp), &l, err));
  TEST_ASSERT_FALSE(l.sprites.present);
}

void test_bad_sprite_table_is_absent() {
  expect_no_sprites(sprites(129, TAGS14, 13, 14, "[143,8]"));
  expect_no_sprites(sprites(129, TAGS14, 14, 14, "[143,8]", 13));
  expect_no_sprites(sprites(129, "[[0,4],[4,0],[4,4],[8,6]]", 14, 14, "[143,8]"));
  expect_no_sprites(sprites(190, TAGS14, 14, 14, "[143,8]"));
  expect_no_sprites(sprites(129, TAGS14, 14, 14, "[140,8]"));
  expect_no_sprites(sprites(128, TAGS14, 14, 14, "[143,8]"));
  expect_no_sprites(sprites(129, TAGS14, 14, 14, "[185,9]"));
  expect_no_sprites(sprites(129, TAGS14, 14, 14, "[100,8]"));
}

void test_face_range_192() {
  expect_reject(layout(page("P", key("a", 0, 0, 1, 1, 129))));
  DeckLayout l;
  char err[64];
  TEST_ASSERT_TRUE(parse(with_sprites(sprites(161, "[[0,32]]", 32, 32, "[0,0]")), &l, err));
  TEST_ASSERT_TRUE(l.sprites.present);
  TEST_ASSERT_TRUE(parse(with_sprites(sprites(129, TAGS14, 14, 14, "[185,8]")), &l, err));
  TEST_ASSERT_TRUE(l.sprites.present);
  TEST_ASSERT_EQUAL_UINT16(185, l.sprites.hat_first);
}

static bool s_have[DECK_MAX_FACES + 1];
static bool have(uint16_t id) { return id <= DECK_MAX_FACES && s_have[id]; }

void test_faces_cached_needs_sprites() {
  DeckLayout l;
  char err[64];
  std::string s = layout(page("P", key("a", 0, 0, 2, 1, 1, "claude_agents") + "," + key("k", 2, 0, 1, 1, 5) + "," +
                                       key("v", 3, 0, 1, 1, 9, "volume")));
  s.insert(s.size() - 1, sprites(129, TAGS14, 14, 14, "[143,8]"));
  TEST_ASSERT_TRUE(parse(s, &l, err));
  memset(s_have, 0, sizeof s_have);
  s_have[5] = true;
  for (int id = 129; id < 151; id++) s_have[id] = true;
  TEST_ASSERT_TRUE(deck_layout_faces_cached(&l, have));
  s_have[142] = false;
  TEST_ASSERT_FALSE(deck_layout_faces_cached(&l, have));
  s_have[142] = true;
  s_have[150] = false;
  TEST_ASSERT_FALSE(deck_layout_faces_cached(&l, have));
  s_have[150] = true;
  s_have[5] = false;
  TEST_ASSERT_FALSE(deck_layout_faces_cached(&l, have));
  s_have[5] = true;
  l.sprites.present = false;
  memset(s_have + 129, 0, sizeof s_have - 129);
  TEST_ASSERT_TRUE(deck_layout_faces_cached(&l, have));
  TEST_ASSERT_FALSE(deck_layout_faces_cached(&l, nullptr));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_parse_claude_example);
  RUN_TEST(test_claude_sessions_needs_two_columns);
  RUN_TEST(test_claude_face_and_long_ignored);
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
  RUN_TEST(test_agents_widget_type);
  RUN_TEST(test_sprite_table_parse);
  RUN_TEST(test_absent_sprites_default);
  RUN_TEST(test_bad_sprite_table_is_absent);
  RUN_TEST(test_face_range_192);
  RUN_TEST(test_faces_cached_needs_sprites);
  return UNITY_END();
}

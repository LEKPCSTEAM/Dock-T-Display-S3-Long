#include <unity.h>
#include <string.h>
#include <stdio.h>
#include <string>
#include "deck_claude.h"
#include "deck_layout.h"

void setUp() {}
void tearDown() {}

static const char *SID_A = "5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42";
static const char *SID_B = "9b2d7e00-1111-4222-8333-444455556666";

static const char *C1 =
    "{\"prompt\":{\"pending\":1,\"project\":\"T-Display-S3-Long\",\"request\":\"a3f9-1\","
    "\"session\":\"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42\",\"summary\":\"pio run -e ntp_clock\","
    "\"tmux\":true,\"tool\":\"Bash\"},\"sessions\":[{\"cost_cents\":142,\"ctx\":37,"
    "\"id\":\"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42\",\"model\":\"Opus 5.5\","
    "\"project\":\"T-Display-S3-Long\",\"state\":\"permission\",\"tmux\":true},"
    "{\"cost_cents\":-1,\"ctx\":-1,\"id\":\"9b2d7e00-1111-4222-8333-444455556666\",\"model\":\"\","
    "\"project\":\"caltera\",\"state\":\"working\",\"tmux\":false}],"
    "\"usage\":{\"five_hour\":{\"pct\":42,\"resets_at\":1795530000},"
    "\"seven_day\":{\"pct\":13,\"resets_at\":1795900000}}}";
static const char *C2 = "{\"prompt\":null,\"sessions\":[],\"usage\":{\"five_hour\":null,\"seven_day\":null}}";

static bool parse(const std::string &s, DeckClaude *out) { return deck_claude_parse(s.c_str(), s.size(), out); }

static std::string sess(const std::string &id, const char *state = "working", const std::string &extra = "") {
  return "{\"id\":\"" + id + "\",\"state\":\"" + state + "\"" + extra + "}";
}

static std::string body(const std::string &sessions, const std::string &prompt = "null",
                        const std::string &usage = "{}") {
  return "{\"sessions\":[" + sessions + "],\"usage\":" + usage + ",\"prompt\":" + prompt + "}";
}

void test_parse_c1() {
  DeckClaude c;
  TEST_ASSERT_TRUE(deck_claude_parse(C1, strlen(C1), &c));
  TEST_ASSERT_EQUAL_UINT8(2, c.count);
  TEST_ASSERT_EQUAL_STRING(SID_A, c.s[0].id);
  TEST_ASSERT_EQUAL_STRING("T-Display-S3-Long", c.s[0].project);
  TEST_ASSERT_EQUAL_STRING("Opus 5.5", c.s[0].model);
  TEST_ASSERT_EQUAL_UINT8(DCS_PERMISSION, c.s[0].state);
  TEST_ASSERT_EQUAL_INT8(37, c.s[0].ctx);
  TEST_ASSERT_EQUAL_INT32(142, c.s[0].cost_cents);
  TEST_ASSERT_TRUE(c.s[0].tmux);
  TEST_ASSERT_EQUAL_UINT8(DCS_WORKING, c.s[1].state);
  TEST_ASSERT_EQUAL_INT8(-1, c.s[1].ctx);
  TEST_ASSERT_EQUAL_INT32(-1, c.s[1].cost_cents);
  TEST_ASSERT_EQUAL_STRING("", c.s[1].model);
  TEST_ASSERT_FALSE(c.s[1].tmux);
  TEST_ASSERT_TRUE(c.five_hour.known);
  TEST_ASSERT_EQUAL_UINT8(42, c.five_hour.pct);
  TEST_ASSERT_EQUAL_UINT32(1795530000u, c.five_hour.resets_at);
  TEST_ASSERT_TRUE(c.seven_day.known);
  TEST_ASSERT_EQUAL_UINT8(13, c.seven_day.pct);
  TEST_ASSERT_EQUAL_UINT32(1795900000u, c.seven_day.resets_at);
  TEST_ASSERT_TRUE(c.prompt.present);
  TEST_ASSERT_EQUAL_UINT8(1, c.prompt.pending);
  TEST_ASSERT_EQUAL_STRING("a3f9-1", c.prompt.request);
  TEST_ASSERT_EQUAL_STRING("Bash", c.prompt.tool);
  TEST_ASSERT_EQUAL_STRING("pio run -e ntp_clock", c.prompt.summary);
  TEST_ASSERT_TRUE(c.prompt.tmux);
  TEST_ASSERT_EQUAL_STRING(SID_A, c.prompt.session);
}

void test_parse_c2() {
  DeckClaude c;
  TEST_ASSERT_TRUE(deck_claude_parse(C2, strlen(C2), &c));
  TEST_ASSERT_EQUAL_UINT8(0, c.count);
  TEST_ASSERT_FALSE(c.five_hour.known);
  TEST_ASSERT_FALSE(c.seven_day.known);
  TEST_ASSERT_FALSE(c.prompt.present);
}

void test_parse_rejects_and_keeps_out() {
  const std::string bad[] = {"{", "[]", std::string(4097, ' '), "{\"sessions\":[]}", "{\"usage\":{}}"};
  for (const std::string &s : bad) {
    DeckClaude c, ref;
    memset(&c, 0xA5, sizeof c);
    memset(&ref, 0xA5, sizeof ref);
    TEST_ASSERT_FALSE(parse(s, &c));
    TEST_ASSERT_EQUAL_INT(0, memcmp(&c, &ref, sizeof c));
  }
  TEST_ASSERT_FALSE(deck_claude_parse(nullptr, 0, nullptr));
}

void test_parse_skips_bad_sessions() {
  DeckClaude c;
  const std::string s = sess("a") + "," + sess("x", "sleeping") + ",{\"state\":\"done\"}," +
                        sess("", "done") + "," + sess("b", "done");
  TEST_ASSERT_TRUE(parse(body(s), &c));
  TEST_ASSERT_EQUAL_UINT8(2, c.count);
  TEST_ASSERT_EQUAL_STRING("a", c.s[0].id);
  TEST_ASSERT_EQUAL_STRING("b", c.s[1].id);
  TEST_ASSERT_EQUAL_UINT8(DCS_DONE, c.s[1].state);
}

void test_cap_24() {
  DeckClaude c;
  std::string s;
  for (int i = 0; i < 30; i++) {
    if (i) s += ",";
    s += sess("id" + std::to_string(i));
  }
  TEST_ASSERT_TRUE(parse(body(s), &c));
  TEST_ASSERT_EQUAL_UINT8(24, c.count);
  TEST_ASSERT_EQUAL_STRING("id0", c.s[0].id);
  TEST_ASSERT_EQUAL_STRING("id23", c.s[23].id);
}

void test_agent_fields_parse() {
  DeckClaude c;
  const std::string s = sess("a", "working",
                             ",\"project\":\"proj\",\"name\":\"Nova\",\"tool\":\"Bash\",\"agents\":3,"
                             "\"since\":1795530000,\"hat\":7,\"tint\":2,\"live\":false");
  const std::string b = "{\"sessions\":[" + s + "],\"usage\":{},\"prompt\":null,\"agents_total\":9}";
  TEST_ASSERT_TRUE(parse(b, &c));
  TEST_ASSERT_EQUAL_STRING("Nova", c.s[0].name);
  TEST_ASSERT_EQUAL_STRING("Bash", c.s[0].tool);
  TEST_ASSERT_EQUAL_UINT8(3, c.s[0].agents);
  TEST_ASSERT_EQUAL_UINT32(1795530000u, c.s[0].since);
  TEST_ASSERT_EQUAL_UINT8(7, c.s[0].hat);
  TEST_ASSERT_EQUAL_UINT8(2, c.s[0].tint);
  TEST_ASSERT_FALSE(c.s[0].live);
  TEST_ASSERT_EQUAL_UINT8(9, c.agents_total);
}

void test_agents_clamp_255() {
  DeckClaude c;
  const std::string b = "{\"sessions\":[" + sess("a", "working", ",\"agents\":900") +
                        "],\"usage\":{},\"prompt\":null,\"agents_total\":1000}";
  TEST_ASSERT_TRUE(parse(b, &c));
  TEST_ASSERT_EQUAL_UINT8(255, c.s[0].agents);
  TEST_ASSERT_EQUAL_UINT8(255, c.agents_total);
}

void test_old_frame_defaults() {
  DeckClaude c;
  TEST_ASSERT_TRUE(parse(body(sess("a", "working", ",\"project\":\"proj\"")), &c));
  TEST_ASSERT_EQUAL_STRING("proj", c.s[0].name);
  TEST_ASSERT_EQUAL_UINT8(0, c.s[0].agents);
  TEST_ASSERT_TRUE(c.s[0].live);
  TEST_ASSERT_EQUAL_UINT32(0, c.s[0].since);
  TEST_ASSERT_EQUAL_UINT8(0, c.agents_total);
}

void test_name_truncates_safely() {
  DeckClaude c;
  std::string thai;
  for (int i = 0; i < 40 / 3; i++) thai += "\xE0\xB8\x81";
  thai += "a";
  TEST_ASSERT_EQUAL_UINT32(40, thai.size());
  TEST_ASSERT_TRUE(parse(body(sess("a", "working", ",\"name\":\"" + thai + "\"")), &c));
  const size_t n = strlen(c.s[0].name);
  TEST_ASSERT_TRUE(n <= 23);
  TEST_ASSERT_EQUAL_UINT32(21, n);
  TEST_ASSERT_EQUAL_INT(0, memcmp(c.s[0].name, thai.c_str(), n));
}

void test_age_strings() {
  char b[16];
  TEST_ASSERT_EQUAL_UINT32(3, deck_claude_age(b, sizeof b, 1000, 1030));
  TEST_ASSERT_EQUAL_STRING("now", b);
  deck_claude_age(b, sizeof b, 1000, 1000 + 300);
  TEST_ASSERT_EQUAL_STRING("5m ago", b);
  deck_claude_age(b, sizeof b, 1000, 1000 + 3 * 3600);
  TEST_ASSERT_EQUAL_STRING("3h ago", b);
  deck_claude_age(b, sizeof b, 1000, 1000 + 2 * 86400);
  TEST_ASSERT_EQUAL_STRING("2d ago", b);
}

void test_age_without_clock() {
  char b[16] = "x";
  TEST_ASSERT_EQUAL_UINT32(0, deck_claude_age(b, sizeof b, 1000, 0));
  TEST_ASSERT_EQUAL_STRING("", b);
  strcpy(b, "x");
  TEST_ASSERT_EQUAL_UINT32(0, deck_claude_age(b, sizeof b, 1120, 1000));
  TEST_ASSERT_EQUAL_STRING("", b);
  strcpy(b, "x");
  TEST_ASSERT_EQUAL_UINT32(0, deck_claude_age(b, sizeof b, 0, 1000));
  TEST_ASSERT_EQUAL_STRING("", b);
}

void test_parse_truncates_utf8_safely() {
  DeckClaude c;
  std::string thai;
  for (int i = 0; i < 30; i++) thai += "\xE0\xB8\x81";
  const std::string s = sess(std::string(40, 'i'), "working", ",\"project\":\"" + thai + "\"");
  const std::string p = "{\"session\":\"s\",\"request\":\"r\",\"summary\":\"" + std::string(100, 's') + "\"}";
  TEST_ASSERT_TRUE(parse(body(s, p), &c));
  TEST_ASSERT_EQUAL_UINT32(21, strlen(c.s[0].project));
  TEST_ASSERT_EQUAL_INT(0, memcmp(c.s[0].project, thai.c_str(), 21));
  TEST_ASSERT_EQUAL_UINT32(39, strlen(c.s[0].id));
  TEST_ASSERT_EQUAL_UINT32(83, strlen(c.prompt.summary));
}

void test_parse_clamps_numbers() {
  DeckClaude c;
  const std::string s = sess("a", "working", ",\"ctx\":150,\"cost_cents\":-7") + "," +
                        sess("b", "working", ",\"ctx\":-5") + "," + sess("c", "working", ",\"ctx\":12.6") +
                        "," + sess("d", "working", ",\"ctx\":\"x\",\"cost_cents\":\"y\"");
  const std::string u = "{\"five_hour\":{\"pct\":101,\"resets_at\":5},\"seven_day\":{\"pct\":-3,\"resets_at\":6}}";
  const std::string p = "{\"session\":\"s\",\"request\":\"r\",\"pending\":0}";
  TEST_ASSERT_TRUE(parse(body(s, p, u), &c));
  TEST_ASSERT_EQUAL_INT8(100, c.s[0].ctx);
  TEST_ASSERT_EQUAL_INT32(-1, c.s[0].cost_cents);
  TEST_ASSERT_EQUAL_INT8(-1, c.s[1].ctx);
  TEST_ASSERT_EQUAL_INT8(13, c.s[2].ctx);
  TEST_ASSERT_EQUAL_INT8(-1, c.s[3].ctx);
  TEST_ASSERT_EQUAL_INT32(-1, c.s[3].cost_cents);
  TEST_ASSERT_EQUAL_UINT8(100, c.five_hour.pct);
  TEST_ASSERT_EQUAL_UINT8(0, c.seven_day.pct);
  TEST_ASSERT_EQUAL_UINT8(1, c.prompt.pending);
  TEST_ASSERT_TRUE(parse(body("", "{\"session\":\"s\",\"request\":\"r\",\"pending\":500}"), &c));
  TEST_ASSERT_EQUAL_UINT8(99, c.prompt.pending);
}

void test_parse_prompt_requires_ids() {
  DeckClaude c;
  TEST_ASSERT_TRUE(parse(body("", "{\"session\":\"\",\"request\":\"r\"}"), &c));
  TEST_ASSERT_FALSE(c.prompt.present);
  TEST_ASSERT_TRUE(parse(body("", "{\"session\":\"s\"}"), &c));
  TEST_ASSERT_FALSE(c.prompt.present);
  TEST_ASSERT_TRUE(parse(body("", "{\"session\":\"s\",\"request\":\"r\"}"), &c));
  TEST_ASSERT_TRUE(c.prompt.present);
  TEST_ASSERT_EQUAL_UINT8(1, c.prompt.pending);
  TEST_ASSERT_EQUAL_STRING("", c.prompt.tool);
  TEST_ASSERT_FALSE(c.prompt.tmux);
}

void test_state_names() {
  TEST_ASSERT_EQUAL_INT(DCS_WORKING, deck_claude_state_from_name("working"));
  TEST_ASSERT_EQUAL_INT(DCS_PERMISSION, deck_claude_state_from_name("permission"));
  TEST_ASSERT_EQUAL_INT(DCS_WAITING, deck_claude_state_from_name("waiting"));
  TEST_ASSERT_EQUAL_INT(DCS_DONE, deck_claude_state_from_name("done"));
  TEST_ASSERT_EQUAL_INT(-1, deck_claude_state_from_name("x"));
  TEST_ASSERT_EQUAL_INT(-1, deck_claude_state_from_name(nullptr));
}

void test_ack_parse_k1_k2() {
  const char *K1 = "{\"ok\":false,\"reason\":\"mismatch\",\"request\":\"a3f9-1\"}";
  const char *K2 = "{\"ok\":true,\"reason\":\"\",\"request\":\"a3f9-1\"}";
  DeckClaudeAck a;
  TEST_ASSERT_TRUE(deck_claude_ack_parse(K1, strlen(K1), &a));
  TEST_ASSERT_FALSE(a.ok);
  TEST_ASSERT_EQUAL_STRING("a3f9-1", a.request);
  TEST_ASSERT_EQUAL_STRING("mismatch", a.reason);
  TEST_ASSERT_TRUE(deck_claude_ack_parse(K2, strlen(K2), &a));
  TEST_ASSERT_TRUE(a.ok);
  TEST_ASSERT_EQUAL_STRING("", a.reason);
}

void test_ack_rejects() {
  const char *bad[] = {"{\"request\":\"r\"}", "{\"ok\":\"false\",\"request\":\"r\"}", "{\"ok\":true}", "[]", "{"};
  for (const char *s : bad) {
    DeckClaudeAck a, ref;
    memset(&a, 0xA5, sizeof a);
    memset(&ref, 0xA5, sizeof ref);
    TEST_ASSERT_FALSE(deck_claude_ack_parse(s, strlen(s), &a));
    TEST_ASSERT_EQUAL_INT(0, memcmp(&a, &ref, sizeof a));
  }
}

void test_action_body_a1_a2() {
  char out[160];
  TEST_ASSERT_TRUE(deck_claude_action_body(SID_A, "a3f9-1", DCA_APPROVE, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING(
      "{\"action\":\"approve\",\"request\":\"a3f9-1\",\"session\":\"5f0c6c1e-2b7a-4c55-9a51-0d7f3b1c9e42\"}", out);
  TEST_ASSERT_TRUE(deck_claude_action_body(SID_B, "", DCA_FOCUS, out, sizeof out));
  TEST_ASSERT_EQUAL_STRING(
      "{\"action\":\"focus\",\"request\":\"\",\"session\":\"9b2d7e00-1111-4222-8333-444455556666\"}", out);
  TEST_ASSERT_FALSE(deck_claude_action_body(SID_A, "", DCA_APPROVE, out, sizeof out));
  TEST_ASSERT_TRUE(deck_claude_action_body(SID_A, "", DCA_INTERRUPT, out, sizeof out));
  TEST_ASSERT_FALSE(deck_claude_action_body(SID_A, "r", 9, out, sizeof out));
  TEST_ASSERT_FALSE(deck_claude_action_body("", "r", DCA_DENY, out, sizeof out));
  TEST_ASSERT_FALSE(deck_claude_action_body(nullptr, "r", DCA_DENY, out, sizeof out));
  TEST_ASSERT_FALSE(deck_claude_action_body(SID_A, "r", DCA_DENY, out, 16));
}

void test_action_names() {
  TEST_ASSERT_EQUAL_STRING("approve", deck_claude_action_name(DCA_APPROVE));
  TEST_ASSERT_EQUAL_STRING("always", deck_claude_action_name(DCA_ALWAYS));
  TEST_ASSERT_EQUAL_STRING("deny", deck_claude_action_name(DCA_DENY));
  TEST_ASSERT_EQUAL_STRING("interrupt", deck_claude_action_name(DCA_INTERRUPT));
  TEST_ASSERT_EQUAL_STRING("focus", deck_claude_action_name(DCA_FOCUS));
  TEST_ASSERT_EQUAL_STRING("", deck_claude_action_name(5));
}

void test_format_reset_vectors() {
  const uint32_t now = 1795520000u;
  const struct { int64_t d; const char *text; } v[] = {
      {-10, "0m"},     {0, "0m"},        {59, "<1m"},      {60, "1m"},          {3599, "59m"},
      {3600, "1h 0m"}, {15179, "4h 12m"}, {86399, "23h 59m"}, {86400, "1d 0h"}, {190801, "2d 5h"}};
  char out[16];
  for (const auto &t : v) {
    deck_claude_format_reset((uint32_t)(now + t.d), now, out, sizeof out);
    TEST_ASSERT_EQUAL_STRING(t.text, out);
  }
  deck_claude_format_reset(0, now, out, sizeof out);
  TEST_ASSERT_EQUAL_STRING("--", out);
  deck_claude_format_reset(now, 0, out, sizeof out);
  TEST_ASSERT_EQUAL_STRING("--", out);
}

void test_format_cost_vectors() {
  const struct { int32_t c; const char *text; } v[] = {{-1, "--"},      {0, "$0.00"},       {5, "$0.05"},
                                                       {142, "$1.42"},  {9999, "$99.99"},   {10000, "$100"},
                                                       {12345, "$123"}};
  char out[16];
  for (const auto &t : v) {
    deck_claude_format_cost(t.c, out, sizeof out);
    TEST_ASSERT_EQUAL_STRING(t.text, out);
  }
}

void test_prompt_same() {
  DeckClaudePrompt a, b;
  memset(&a, 0, sizeof a);
  memset(&b, 0, sizeof b);
  TEST_ASSERT_TRUE(deck_claude_prompt_same(&a, &b));
  a.present = b.present = true;
  strcpy(a.session, "s");
  strcpy(b.session, "s");
  strcpy(a.request, "r1");
  strcpy(b.request, "r1");
  TEST_ASSERT_TRUE(deck_claude_prompt_same(&a, &b));
  strcpy(b.request, "r2");
  TEST_ASSERT_FALSE(deck_claude_prompt_same(&a, &b));
  b.present = false;
  TEST_ASSERT_FALSE(deck_claude_prompt_same(&a, &b));
}

void test_agents_grid() {
  const struct { uint8_t w, h; int bw, bh, tiles, cols, rows, tw, th; } v[] = {
      {2, 1, 154, 84, 1, 1, 1, 142, 84},  {4, 1, 314, 84, 2, 2, 1, 151, 84},
      {2, 2, 154, 174, 2, 1, 2, 142, 87}, {8, 2, 634, 174, 8, 4, 2, 155, 87},
      {3, 1, 234, 84, 1, 1, 1, 222, 84},  {1, 1, 74, 84, 1, 1, 1, 62, 84}};
  for (const auto &t : v) {
    int cols = -1, rows = -1, tw = -1, th = -1;
    TEST_ASSERT_EQUAL_INT(t.tiles, deck_claude_agents_grid(t.w, t.h, t.bw, t.bh, &cols, &rows, &tw, &th));
    TEST_ASSERT_EQUAL_INT(t.cols, cols);
    TEST_ASSERT_EQUAL_INT(t.rows, rows);
    TEST_ASSERT_EQUAL_INT(t.tw, tw);
    TEST_ASSERT_EQUAL_INT(t.th, th);
  }
}

static DeckClaudeSession agent(uint8_t state, const char *tool, int8_t ctx) {
  DeckClaudeSession s;
  memset(&s, 0, sizeof s);
  s.state = state;
  s.ctx = ctx;
  s.live = true;
  strcpy(s.tool, tool);
  return s;
}

static std::string status(const DeckClaudeSession &s, uint32_t now = 0, const char *sep = " \xC2\xB7 ") {
  char b[48];
  memset(b, 'x', sizeof b);
  deck_claude_agent_status(&s, now, sep, b, sizeof b);
  return b;
}

void test_agent_status_lines() {
  TEST_ASSERT_EQUAL_STRING("bash \xC2\xB7 98% ctx", status(agent(DCS_WORKING, "bash", 98)).c_str());
  TEST_ASSERT_EQUAL_STRING("bash\n98% ctx", status(agent(DCS_WORKING, "bash", 98), 0, "\n").c_str());
  TEST_ASSERT_EQUAL_STRING("bash", status(agent(DCS_WORKING, "bash", -1)).c_str());
  TEST_ASSERT_EQUAL_STRING("working", status(agent(DCS_WORKING, "", 37)).c_str());
  TEST_ASSERT_EQUAL_STRING("permission \xC2\xB7 Bash", status(agent(DCS_PERMISSION, "bash", 5)).c_str());
  TEST_ASSERT_EQUAL_STRING("permission \xC2\xB7 Edit", status(agent(DCS_PERMISSION, "Edit", -1)).c_str());
  TEST_ASSERT_EQUAL_STRING("permission \xC2\xB7 9p", status(agent(DCS_PERMISSION, "9p", -1)).c_str());
  TEST_ASSERT_EQUAL_STRING("permission", status(agent(DCS_PERMISSION, "", -1)).c_str());
  TEST_ASSERT_EQUAL_STRING("hungry \xC2\xB7 feed me", status(agent(DCS_WAITING, "bash", 40)).c_str());
  TEST_ASSERT_EQUAL_STRING("hungry\nfeed me", status(agent(DCS_WAITING, "", -1), 0, "\n").c_str());
}

void test_agent_status_done_age() {
  DeckClaudeSession s = agent(DCS_DONE, "", -1);
  s.since = 1000;
  TEST_ASSERT_EQUAL_STRING("done \xC2\xB7 5m ago", status(s, 1300).c_str());
  TEST_ASSERT_EQUAL_STRING("done \xC2\xB7 now", status(s, 1010).c_str());
  TEST_ASSERT_EQUAL_STRING("done", status(s, 0).c_str());
  s.since = 0;
  TEST_ASSERT_EQUAL_STRING("done", status(s, 1300).c_str());
}

void test_agent_status_small_buffer() {
  char b[6];
  memset(b, 'x', sizeof b);
  deck_claude_agent_status(nullptr, 0, " ", b, sizeof b);
  TEST_ASSERT_EQUAL_STRING("", b);
  DeckClaudeSession s = agent(DCS_WAITING, "", -1);
  deck_claude_agent_status(&s, 0, " \xC2\xB7 ", b, sizeof b);
  TEST_ASSERT_EQUAL_STRING("hungr", b);
}

static DeckAgentSprites sprites4() {
  DeckAgentSprites sp;
  memset(&sp, 0, sizeof sp);
  sp.present = true;
  sp.frames = 8;
  const uint8_t first[DECK_AGENT_TAGS] = {0, 3, 5, 6}, count[DECK_AGENT_TAGS] = {3, 2, 1, 2};
  for (int i = 0; i < DECK_AGENT_TAGS; i++) {
    sp.tag_first[i] = first[i];
    sp.tag_count[i] = count[i];
  }
  for (int i = 0; i < 8; i++) sp.ms[i] = 100;
  return sp;
}

void test_agent_tag_fallback() {
  DeckAgentSprites sp = sprites4();
  for (int s = 0; s < DCS_COUNT; s++) TEST_ASSERT_EQUAL_INT(s, deck_claude_agent_tag(&sp, (uint8_t)s));
  TEST_ASSERT_EQUAL_INT(0, deck_claude_agent_tag(&sp, 9));
  sp.tag_count[2] = 0;
  TEST_ASSERT_EQUAL_INT(0, deck_claude_agent_tag(&sp, DCS_WAITING));
  sp.tag_count[0] = 0;
  TEST_ASSERT_EQUAL_INT(-1, deck_claude_agent_tag(&sp, DCS_WAITING));
  TEST_ASSERT_EQUAL_INT(3, deck_claude_agent_tag(&sp, DCS_DONE));
  sp.present = false;
  TEST_ASSERT_EQUAL_INT(-1, deck_claude_agent_tag(&sp, DCS_DONE));
  TEST_ASSERT_EQUAL_INT(-1, deck_claude_agent_tag(nullptr, DCS_DONE));
}

void test_agent_step_timing() {
  DeckAgentSprites sp = sprites4();
  uint8_t f = 0;
  uint32_t at = 1000;
  TEST_ASSERT_FALSE(deck_claude_agent_step(&sp, 0, &f, &at, 1099, 1));
  TEST_ASSERT_EQUAL_UINT8(0, f);
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 0, &f, &at, 1100, 1));
  TEST_ASSERT_EQUAL_UINT8(1, f);
  TEST_ASSERT_EQUAL_UINT32(1100, at);
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 0, &f, &at, 1250, 1));
  TEST_ASSERT_EQUAL_UINT8(2, f);
  TEST_ASSERT_EQUAL_UINT32(1200, at);
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 0, &f, &at, 1300, 1));
  TEST_ASSERT_EQUAL_UINT8(0, f);
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 0, &f, &at, 5000, 1));
  TEST_ASSERT_EQUAL_UINT8(1, f);
  TEST_ASSERT_EQUAL_UINT32(5000, at);
}

void test_agent_step_edges() {
  DeckAgentSprites sp = sprites4();
  uint8_t f = 0;
  uint32_t at = 0;
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 1, &f, &at, 777, 1));
  TEST_ASSERT_EQUAL_UINT8(3, f);
  TEST_ASSERT_EQUAL_UINT32(777, at);
  f = 5;
  TEST_ASSERT_FALSE(deck_claude_agent_step(&sp, 2, &f, &at, 99999, 1));
  TEST_ASSERT_EQUAL_UINT8(5, f);
  sp.ms[3] = 0;
  f = 3;
  at = 0;
  TEST_ASSERT_FALSE(deck_claude_agent_step(&sp, 1, &f, &at, 99, 1));
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 1, &f, &at, 100, 1));
  TEST_ASSERT_EQUAL_UINT8(4, f);
  TEST_ASSERT_FALSE(deck_claude_agent_step(&sp, -1, &f, &at, 5000, 1));
  TEST_ASSERT_FALSE(deck_claude_agent_step(&sp, 7, &f, &at, 5000, 1));
  TEST_ASSERT_FALSE(deck_claude_agent_step(nullptr, 0, &f, &at, 5000, 1));
}

void test_agent_step_beat_rounds_durations() {
  DeckAgentSprites sp = sprites4();
  sp.ms[0] = 150;
  sp.ms[1] = 149;
  sp.ms[2] = 40;
  uint8_t f = 0;
  uint32_t at = 1000;
  TEST_ASSERT_FALSE(deck_claude_agent_step(&sp, 0, &f, &at, 1100, 100));
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 0, &f, &at, 1200, 100));
  TEST_ASSERT_EQUAL_UINT8(1, f);
  TEST_ASSERT_EQUAL_UINT32(1200, at);
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 0, &f, &at, 1300, 100));
  TEST_ASSERT_EQUAL_UINT8(2, f);
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 0, &f, &at, 1400, 100));
  TEST_ASSERT_EQUAL_UINT8(0, f);
  TEST_ASSERT_EQUAL_UINT32(1400, at);
  TEST_ASSERT_FALSE(deck_claude_agent_step(&sp, 0, &f, &at, 1549, 0));
  TEST_ASSERT_TRUE(deck_claude_agent_step(&sp, 0, &f, &at, 1550, 0));
}

static void needy_row(DeckClaude *c, int i, const char *id, uint8_t state) {
  memset(&c->s[i], 0, sizeof c->s[i]);
  strcpy(c->s[i].id, id);
  c->s[i].state = state;
  c->s[i].live = true;
}

void test_needy_update() {
  DeckClaude c;
  memset(&c, 0, sizeof c);
  uint32_t keys[DECK_CLAUDE_MAX_SESSIONS];
  uint8_t n = 0;
  c.count = 2;
  needy_row(&c, 0, "a", DCS_WORKING);
  needy_row(&c, 1, "b", DCS_WAITING);
  TEST_ASSERT_TRUE(deck_claude_needy_update(&c, keys, &n));
  TEST_ASSERT_EQUAL_UINT8(1, n);
  TEST_ASSERT_FALSE(deck_claude_needy_update(&c, keys, &n));
  c.s[1].state = DCS_PERMISSION;
  TEST_ASSERT_TRUE(deck_claude_needy_update(&c, keys, &n));
  c.s[0].state = DCS_WAITING;
  TEST_ASSERT_TRUE(deck_claude_needy_update(&c, keys, &n));
  TEST_ASSERT_EQUAL_UINT8(2, n);
  c.s[0].state = DCS_DONE;
  TEST_ASSERT_FALSE(deck_claude_needy_update(&c, keys, &n));
  TEST_ASSERT_EQUAL_UINT8(1, n);
  needy_row(&c, 0, "b", DCS_PERMISSION);
  needy_row(&c, 1, "a", DCS_DONE);
  TEST_ASSERT_FALSE(deck_claude_needy_update(&c, keys, &n));
  needy_row(&c, 0, "c", DCS_PERMISSION);
  TEST_ASSERT_TRUE(deck_claude_needy_update(&c, keys, &n));
  c.count = 0;
  TEST_ASSERT_FALSE(deck_claude_needy_update(&c, keys, &n));
  TEST_ASSERT_EQUAL_UINT8(0, n);
  TEST_ASSERT_FALSE(deck_claude_needy_update(nullptr, keys, &n));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_parse_c1);
  RUN_TEST(test_parse_c2);
  RUN_TEST(test_parse_rejects_and_keeps_out);
  RUN_TEST(test_parse_skips_bad_sessions);
  RUN_TEST(test_cap_24);
  RUN_TEST(test_agent_fields_parse);
  RUN_TEST(test_agents_clamp_255);
  RUN_TEST(test_old_frame_defaults);
  RUN_TEST(test_name_truncates_safely);
  RUN_TEST(test_age_strings);
  RUN_TEST(test_age_without_clock);
  RUN_TEST(test_parse_truncates_utf8_safely);
  RUN_TEST(test_parse_clamps_numbers);
  RUN_TEST(test_parse_prompt_requires_ids);
  RUN_TEST(test_state_names);
  RUN_TEST(test_ack_parse_k1_k2);
  RUN_TEST(test_ack_rejects);
  RUN_TEST(test_action_body_a1_a2);
  RUN_TEST(test_action_names);
  RUN_TEST(test_format_reset_vectors);
  RUN_TEST(test_format_cost_vectors);
  RUN_TEST(test_prompt_same);
  RUN_TEST(test_agents_grid);
  RUN_TEST(test_agent_status_lines);
  RUN_TEST(test_agent_status_done_age);
  RUN_TEST(test_agent_status_small_buffer);
  RUN_TEST(test_agent_tag_fallback);
  RUN_TEST(test_agent_step_timing);
  RUN_TEST(test_agent_step_edges);
  RUN_TEST(test_agent_step_beat_rounds_durations);
  RUN_TEST(test_needy_update);
  return UNITY_END();
}

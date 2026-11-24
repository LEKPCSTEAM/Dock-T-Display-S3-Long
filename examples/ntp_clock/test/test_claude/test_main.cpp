#include <unity.h>
#include <string.h>
#include <stdio.h>
#include <string>
#include "deck_claude.h"

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

void test_parse_caps_sessions_at_8() {
  DeckClaude c;
  std::string s;
  for (int i = 0; i < 10; i++) {
    if (i) s += ",";
    s += sess("id" + std::to_string(i));
  }
  TEST_ASSERT_TRUE(parse(body(s), &c));
  TEST_ASSERT_EQUAL_UINT8(8, c.count);
  TEST_ASSERT_EQUAL_STRING("id0", c.s[0].id);
  TEST_ASSERT_EQUAL_STRING("id7", c.s[7].id);
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

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_parse_c1);
  RUN_TEST(test_parse_c2);
  RUN_TEST(test_parse_rejects_and_keeps_out);
  RUN_TEST(test_parse_skips_bad_sessions);
  RUN_TEST(test_parse_caps_sessions_at_8);
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
  return UNITY_END();
}

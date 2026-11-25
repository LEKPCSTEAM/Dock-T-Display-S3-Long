#include "deck_claude.h"
#include "deck_layout.h"
#include <ArduinoJson.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

void deck_claude_copy(char *dst, size_t dst_len, const char *src) {
  if (!dst || !dst_len) return;
  size_t n = src ? strlen(src) : 0;
  if (n > dst_len - 1) {
    n = dst_len - 1;
    while (n > 0 && ((uint8_t)src[n] & 0xC0) == 0x80) n--;
  }
  if (n) memcpy(dst, src, n);
  dst[n] = 0;
}

static const char *const STATE_NAMES[DCS_COUNT] = {"working", "permission", "waiting", "done"};
static const char *const ACTION_NAMES[DCA_COUNT] = {"approve", "always", "deny", "interrupt", "focus"};

int deck_claude_state_from_name(const char *name) {
  if (!name) return -1;
  for (int i = 0; i < DCS_COUNT; i++)
    if (strcmp(name, STATE_NAMES[i]) == 0) return i;
  return -1;
}

const char *deck_claude_action_name(uint8_t action) { return action < DCA_COUNT ? ACTION_NAMES[action] : ""; }

static double round_half_up(double x) { return floor(x + 0.5); }

static double clamp_d(double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); }

static const char *str_of(JsonVariantConst v) { return v.is<const char *>() ? v.as<const char *>() : ""; }

static int8_t parse_ctx(JsonVariantConst v) {
  if (!v.is<double>()) return -1;
  const double x = v.as<double>();
  if (x < 0) return -1;
  return (int8_t)clamp_d(round_half_up(x), 0, 100);
}

static int32_t parse_cost(JsonVariantConst v) {
  if (!v.is<double>()) return -1;
  const double x = v.as<double>();
  if (x < 0) return -1;
  return (int32_t)clamp_d(round_half_up(x), 0, 2000000000);
}

static uint8_t parse_u8(JsonVariantConst v, double hi) {
  if (!v.is<double>()) return 0;
  return (uint8_t)clamp_d(round_half_up(v.as<double>()), 0, hi);
}

static uint32_t parse_u32(JsonVariantConst v) {
  if (!v.is<double>()) return 0;
  return (uint32_t)clamp_d(v.as<double>(), 0, 4294967295.0);
}

static void parse_window(JsonVariantConst v, DeckClaudeWindow *w) {
  memset(w, 0, sizeof *w);
  if (!v.is<JsonObjectConst>()) return;
  JsonVariantConst pct = v["pct"];
  JsonVariantConst at = v["resets_at"];
  if (!pct.is<double>() || !at.is<double>()) return;
  const double t = at.as<double>();
  if (t < 0 || t > 4294967295.0) return;
  w->known = true;
  w->pct = (uint8_t)clamp_d(round_half_up(pct.as<double>()), 0, 100);
  w->resets_at = (uint32_t)t;
}

static void parse_prompt(JsonVariantConst v, DeckClaudePrompt *p) {
  memset(p, 0, sizeof *p);
  if (!v.is<JsonObjectConst>()) return;
  const char *session = str_of(v["session"]);
  const char *request = str_of(v["request"]);
  if (!*session || !*request) return;
  p->present = true;
  deck_claude_copy(p->session, sizeof p->session, session);
  deck_claude_copy(p->request, sizeof p->request, request);
  deck_claude_copy(p->project, sizeof p->project, str_of(v["project"]));
  deck_claude_copy(p->tool, sizeof p->tool, str_of(v["tool"]));
  deck_claude_copy(p->summary, sizeof p->summary, str_of(v["summary"]));
  p->tmux = v["tmux"] | false;
  p->pending = 1;
  if (v["pending"].is<double>()) p->pending = (uint8_t)clamp_d(round_half_up(v["pending"].as<double>()), 1, 99);
}

bool deck_claude_parse(const char *json, size_t len, DeckClaude *out) {
  if (!json || !out || len > DECK_CLAUDE_BODY_MAX) return false;
  JsonDocument doc;
  if (deserializeJson(doc, json, len)) return false;
  if (!doc.is<JsonObject>()) return false;
  JsonArrayConst sessions = doc["sessions"].as<JsonArrayConst>();
  if (sessions.isNull() || !doc["usage"].is<JsonObjectConst>()) return false;

  DeckClaude &c = *out;
  memset(&c, 0, sizeof c);
  for (JsonVariantConst js : sessions) {
    if (c.count >= DECK_CLAUDE_MAX_SESSIONS) break;
    const char *id = str_of(js["id"]);
    const int state = deck_claude_state_from_name(js["state"].is<const char *>() ? js["state"].as<const char *>() : nullptr);
    if (!*id || state < 0) continue;
    DeckClaudeSession &s = c.s[c.count++];
    deck_claude_copy(s.id, sizeof s.id, id);
    deck_claude_copy(s.project, sizeof s.project, str_of(js["project"]));
    deck_claude_copy(s.model, sizeof s.model, str_of(js["model"]));
    s.state = (uint8_t)state;
    s.ctx = parse_ctx(js["ctx"]);
    s.cost_cents = parse_cost(js["cost_cents"]);
    s.tmux = js["tmux"] | false;
    const char *name = str_of(js["name"]);
    deck_claude_copy(s.name, sizeof s.name, *name ? name : str_of(js["project"]));
    deck_claude_copy(s.tool, sizeof s.tool, str_of(js["tool"]));
    s.agents = parse_u8(js["agents"], 255);
    s.since = parse_u32(js["since"]);
    s.hat = parse_u8(js["hat"], 255);
    s.tint = parse_u8(js["tint"], 255);
    s.live = js["live"] | true;
  }
  c.agents_total = parse_u8(doc["agents_total"], 255);
  parse_window(doc["usage"]["five_hour"], &c.five_hour);
  parse_window(doc["usage"]["seven_day"], &c.seven_day);
  parse_prompt(doc["prompt"], &c.prompt);
  return true;
}

bool deck_claude_ack_parse(const char *json, size_t len, DeckClaudeAck *out) {
  if (!json || !out) return false;
  JsonDocument doc;
  if (deserializeJson(doc, json, len)) return false;
  if (!doc.is<JsonObject>()) return false;
  if (!doc["ok"].is<bool>() || !doc["request"].is<const char *>()) return false;
  DeckClaudeAck a;
  memset(&a, 0, sizeof a);
  a.ok = doc["ok"].as<bool>();
  deck_claude_copy(a.request, sizeof a.request, str_of(doc["request"]));
  deck_claude_copy(a.reason, sizeof a.reason, str_of(doc["reason"]));
  *out = a;
  return true;
}

bool deck_claude_action_body(const char *session, const char *request, uint8_t action, char *out, size_t out_len) {
  if (!session || !*session || action >= DCA_COUNT || !out || !out_len) return false;
  if (!request) request = "";
  if (!*request && action <= DCA_DENY) return false;
  JsonDocument doc;
  doc["action"] = ACTION_NAMES[action];
  doc["request"] = request;
  doc["session"] = session;
  if (measureJson(doc) >= out_len) return false;
  serializeJson(doc, out, out_len);
  return true;
}

void deck_claude_format_reset(uint32_t resets_at, uint32_t now, char *out, size_t len) {
  if (!out || !len) return;
  if (!resets_at || !now) {
    snprintf(out, len, "--");
    return;
  }
  const int64_t d = (int64_t)resets_at - (int64_t)now;
  if (d <= 0) snprintf(out, len, "0m");
  else if (d < 60) snprintf(out, len, "<1m");
  else if (d < 3600) snprintf(out, len, "%um", (unsigned)(d / 60));
  else if (d < 86400) snprintf(out, len, "%uh %um", (unsigned)(d / 3600), (unsigned)((d % 3600) / 60));
  else snprintf(out, len, "%ud %uh", (unsigned)(d / 86400), (unsigned)((d % 86400) / 3600));
}

size_t deck_claude_age(char *out, size_t n, uint32_t since, uint32_t now) {
  if (!out || !n) return 0;
  out[0] = 0;
  if (!now || !since || (uint64_t)since > (uint64_t)now + 60) return 0;
  const uint32_t d = since > now ? 0 : now - since;
  int w;
  if (d < 60) w = snprintf(out, n, "now");
  else if (d < 3600) w = snprintf(out, n, "%um ago", (unsigned)(d / 60));
  else if (d < 86400) w = snprintf(out, n, "%uh ago", (unsigned)(d / 3600));
  else w = snprintf(out, n, "%ud ago", (unsigned)(d / 86400));
  return w < 0 ? 0 : ((size_t)w < n ? (size_t)w : n - 1);
}

void deck_claude_format_cost(int32_t cents, char *out, size_t len) {
  if (!out || !len) return;
  if (cents < 0) snprintf(out, len, "--");
  else if (cents < 10000) snprintf(out, len, "$%d.%02d", (int)(cents / 100), (int)(cents % 100));
  else snprintf(out, len, "$%d", (int)(cents / 100));
}

bool deck_claude_prompt_same(const DeckClaudePrompt *a, const DeckClaudePrompt *b) {
  if (!a->present || !b->present) return a->present == b->present;
  return strcmp(a->session, b->session) == 0 && strcmp(a->request, b->request) == 0;
}

int deck_claude_agents_grid(uint8_t w, uint8_t h, int box_w, int box_h, int *cols, int *rows, int *tw, int *th) {
  const int c = w / 2 > 0 ? w / 2 : 1;
  const int r = h > 0 ? h : 1;
  *cols = c;
  *rows = r;
  *tw = (box_w - DECK_AGENTS_RAIL_W) / c;
  *th = box_h / r;
  return c * r;
}

void deck_claude_agent_status(const DeckClaudeSession *s, uint32_t now, const char *sep, char *out, size_t n) {
  if (!out || !n) return;
  out[0] = 0;
  if (!s) return;
  if (!sep) sep = " ";
  char tool[DECK_CLAUDE_TOOL_MAX], age[16];
  switch (s->state) {
  case DCS_WORKING:
    if (!s->tool[0]) snprintf(out, n, "working");
    else if (s->ctx < 0) snprintf(out, n, "%s", s->tool);
    else snprintf(out, n, "%s%s%d%% ctx", s->tool, sep, s->ctx);
    break;
  case DCS_PERMISSION:
    deck_claude_copy(tool, sizeof tool, s->tool);
    if (tool[0] >= 'a' && tool[0] <= 'z') tool[0] = (char)(tool[0] - 'a' + 'A');
    if (tool[0]) snprintf(out, n, "permission%s%s", sep, tool);
    else snprintf(out, n, "permission");
    break;
  case DCS_WAITING:
    snprintf(out, n, "hungry%sfeed me", sep);
    break;
  default:
    if (deck_claude_age(age, sizeof age, s->since, now)) snprintf(out, n, "done%s%s", sep, age);
    else snprintf(out, n, "done");
    break;
  }
}

int deck_claude_agent_tag(const DeckAgentSprites *sp, uint8_t state) {
  if (!sp || !sp->present) return -1;
  if (state < DECK_AGENT_TAGS && sp->tag_count[state]) return state;
  return sp->tag_count[0] ? 0 : -1;
}

bool deck_claude_agent_step(const DeckAgentSprites *sp, int tag, uint8_t *frame, uint32_t *entered, uint32_t now,
                            uint32_t beat) {
  if (!sp || !frame || !entered || tag < 0 || tag >= DECK_AGENT_TAGS || !sp->tag_count[tag]) return false;
  const uint8_t first = sp->tag_first[tag], count = sp->tag_count[tag];
  if (*frame < first || *frame >= first + count) {
    *frame = first;
    *entered = now;
    return true;
  }
  if (count == 1) return false;
  uint32_t dur = sp->ms[*frame] ? sp->ms[*frame] : DECK_AGENT_DEFAULT_MS;
  if (beat > 1) {
    dur = (dur + beat / 2) / beat * beat;
    if (dur < beat) dur = beat;
  }
  const uint32_t elapsed = now - *entered;
  if (elapsed < dur) return false;
  *entered = elapsed >= 2 * dur ? now : *entered + dur;
  *frame = (uint8_t)(first + (*frame - first + 1) % count);
  return true;
}

static uint32_t needy_key(const DeckClaudeSession &s) {
  uint32_t h = 2166136261u;
  for (const char *p = s.id; *p; p++) h = (h ^ (uint8_t)*p) * 16777619u;
  return (h ^ s.state) * 16777619u;
}

bool deck_claude_needy_update(const DeckClaude *c, uint32_t keys[DECK_CLAUDE_MAX_SESSIONS], uint8_t *count) {
  if (!c || !keys || !count) return false;
  const uint8_t old = *count < DECK_CLAUDE_MAX_SESSIONS ? *count : DECK_CLAUDE_MAX_SESSIONS;
  uint32_t cur[DECK_CLAUDE_MAX_SESSIONS];
  uint8_t n = 0;
  bool fresh = false;
  for (int i = 0; i < c->count && i < DECK_CLAUDE_MAX_SESSIONS; i++) {
    const DeckClaudeSession &s = c->s[i];
    if (s.state != DCS_PERMISSION && s.state != DCS_WAITING) continue;
    const uint32_t k = needy_key(s);
    bool seen = false;
    for (int j = 0; j < old && !seen; j++) seen = keys[j] == k;
    fresh = fresh || !seen;
    cur[n++] = k;
  }
  if (n) memcpy(keys, cur, n * sizeof cur[0]);
  *count = n;
  return fresh;
}

const DeckClaudeSession *deck_claude_tap_target(const DeckClaude *c, const char *id, bool interrupt) {
  if (!c || !id || !*id) return nullptr;
  for (int i = 0; i < c->count && i < DECK_CLAUDE_MAX_SESSIONS; i++) {
    const DeckClaudeSession &s = c->s[i];
    if (!s.live || strcmp(s.id, id) != 0) continue;
    if (!s.tmux || (interrupt && s.state != DCS_WORKING)) return nullptr;
    return &s;
  }
  return nullptr;
}

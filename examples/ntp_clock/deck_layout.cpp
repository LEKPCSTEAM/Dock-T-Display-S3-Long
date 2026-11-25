#include "deck_layout.h"
#include <ArduinoJson.h>
#include <stdio.h>
#include <string.h>

static bool fail(char *err, size_t err_len, const char *msg) {
  if (err && err_len) snprintf(err, err_len, "%s", msg);
  return false;
}

static bool valid_hash(const char *s) {
  if (!s || strlen(s) != 16) return false;
  for (int i = 0; i < 16; i++) {
    const char c = s[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  }
  return true;
}

static bool get_u8(JsonVariantConst v, int lo, int hi, uint8_t *out) {
  if (!v.is<int>()) return false;
  const int n = v.as<int>();
  if (n < lo || n > hi) return false;
  *out = (uint8_t)n;
  return true;
}

static int name_index(const char *name, const char *const *names, int n) {
  if (!name) return -1;
  for (int i = 0; i < n; i++)
    if (strcmp(name, names[i]) == 0) return i;
  return -1;
}

int deck_metric_from_name(const char *name) {
  static const char *const names[DM_COUNT] = {"cpu",      "ram",     "gpu",     "temp",    "net_down",
                                              "net_up",   "disk_free", "disk_io", "battery"};
  return name_index(name, names, DM_COUNT);
}

int deck_style_from_name(const char *name) {
  static const char *const names[DS_COUNT] = {"bar", "number", "sparkline"};
  return name_index(name, names, DS_COUNT);
}

static bool parse_widget(JsonObjectConst jw, DeckWidget *w, uint16_t *occ, char *err, size_t err_len) {
  const char *id = jw["id"] | (const char *)nullptr;
  if (!id || !*id) return fail(err, err_len, "widget id missing");
  if (strlen(id) >= sizeof w->id) return fail(err, err_len, "widget id too long");
  memset(w, 0, sizeof *w);
  strcpy(w->id, id);

  const char *type = jw["type"] | "";
  if (strcmp(type, "key") == 0) w->type = DW_KEY;
  else if (strcmp(type, "volume") == 0) w->type = DW_VOLUME;
  else if (strcmp(type, "clock") == 0) w->type = DW_CLOCK;
  else if (strcmp(type, "claude_usage") == 0) w->type = DW_CLAUDE_USAGE;
  else if (strcmp(type, "claude_sessions") == 0) w->type = DW_CLAUDE_SESSIONS;
  else if (strcmp(type, "claude_agents") == 0) w->type = DW_CLAUDE_AGENTS;
  else if (strcmp(type, "stat") == 0) {
    const int metric = deck_metric_from_name(jw["metric"] | (const char *)nullptr);
    const int style = deck_style_from_name(jw["style"] | (const char *)nullptr);
    if (metric < 0 || style < 0) w->type = DW_UNKNOWN;
    else {
      w->type = DW_STAT;
      w->metric = (uint8_t)metric;
      w->style = (uint8_t)style;
    }
  } else w->type = DW_UNKNOWN;

  if (!get_u8(jw["col"], 0, DECK_COLS - 1, &w->col) || !get_u8(jw["row"], 0, DECK_ROWS - 1, &w->row) ||
      !get_u8(jw["w"], 1, DECK_COLS, &w->w) || !get_u8(jw["h"], 1, DECK_ROWS, &w->h))
    return fail(err, err_len, "widget geometry invalid");
  if (w->col + w->w > DECK_COLS || w->row + w->h > DECK_ROWS) return fail(err, err_len, "widget outside grid");
  if (w->type == DW_CLAUDE_SESSIONS && w->w < 2) w->type = DW_UNKNOWN;
  if (w->type == DW_CLAUDE_AGENTS && w->w < 2) w->type = DW_UNKNOWN;

  if (w->type == DW_KEY) {
    const int face = jw["face"] | 0;
    if (face < 1 || face > DECK_KEY_MAX_FACE) return fail(err, err_len, "face out of range");
    w->face = (uint16_t)face;
  }
  if (w->type == DW_KEY) w->has_long = jw["long"] | false;

  for (int r = w->row; r < w->row + w->h; r++)
    for (int c = w->col; c < w->col + w->w; c++) {
      if (occ[r] & (1u << c)) return fail(err, err_len, "widgets overlap");
      occ[r] |= (1u << c);
    }
  return true;
}

static bool parse_u8_list(JsonVariantConst v, uint8_t n, uint8_t *out) {
  JsonArrayConst a = v.as<JsonArrayConst>();
  if (a.isNull() || a.size() != n) return false;
  uint8_t i = 0;
  for (JsonVariantConst e : a)
    if (!get_u8(e, 0, 255, &out[i++])) return false;
  return true;
}

static void parse_sprites(JsonVariantConst js, DeckAgentSprites *sp) {
  memset(sp, 0, sizeof *sp);
  if (!js.is<JsonObjectConst>()) return;
  DeckAgentSprites t;
  memset(&t, 0, sizeof t);
  JsonArrayConst tags = js["tags"].as<JsonArrayConst>();
  if (tags.isNull() || tags.size() < 1 || tags.size() > DECK_AGENT_TAGS) return;
  int frames = 0, ti = 0;
  for (JsonVariantConst jt : tags) {
    JsonArrayConst pair = jt.as<JsonArrayConst>();
    if (pair.isNull() || pair.size() != 2) return;
    if (!get_u8(pair[0], 0, DECK_SPRITE_MAX_FRAMES - 1, &t.tag_first[ti]) ||
        !get_u8(pair[1], 1, DECK_SPRITE_MAX_FRAMES, &t.tag_count[ti]))
      return;
    frames += t.tag_count[ti++];
  }
  if (frames > DECK_SPRITE_MAX_FRAMES) return;
  for (int i = 0; i < ti; i++)
    if (t.tag_first[i] + t.tag_count[i] > frames) return;
  t.frames = (uint8_t)frames;

  const int first = js["first"] | 0;
  if (first < DECK_SPRITE_FIRST_ID || first + frames - 1 > DECK_MAX_FACES) return;
  t.first_id = (uint16_t)first;
  if (!get_u8(js["w"], 1, 255, &t.w) || !get_u8(js["h"], 1, 255, &t.h)) return;

  JsonArrayConst ms = js["ms"].as<JsonArrayConst>();
  if (ms.isNull() || ms.size() != (size_t)frames) return;
  int i = 0;
  for (JsonVariantConst e : ms) {
    if (!e.is<int>() || e.as<int>() < 0 || e.as<int>() > 65535) return;
    t.ms[i++] = (uint16_t)e.as<int>();
  }
  if (!parse_u8_list(js["hx"], t.frames, t.hat_x) || !parse_u8_list(js["hy"], t.frames, t.hat_y)) return;

  JsonArrayConst hats = js["hats"].as<JsonArrayConst>();
  if (!hats.isNull()) {
    if (hats.size() != 2 || !hats[0].is<int>() || !hats[1].is<int>()) return;
    const int hf = hats[0].as<int>(), hn = hats[1].as<int>();
    if (hn < 0 || hn > 255) return;
    if (hn > 0) {
      if (hf < DECK_SPRITE_FIRST_ID || hf + hn - 1 > DECK_MAX_FACES) return;
      if (hf < first + frames && hf + hn > first) return;
      if (!get_u8(js["hw"], 1, 255, &t.hat_w) || !get_u8(js["hh"], 1, 255, &t.hat_h)) return;
      t.hat_first = (uint16_t)hf;
      t.hat_count = (uint8_t)hn;
    }
  }
  t.present = true;
  *sp = t;
}

bool deck_layout_parse(const char *json, size_t len, DeckLayout *out, char *err, size_t err_len) {
  if (err && err_len) err[0] = 0;
  if (!json || !out) return fail(err, err_len, "null argument");
  if (len > DECK_LAYOUT_MAX_BYTES) return fail(err, err_len, "layout too large");

  JsonDocument doc;
  if (deserializeJson(doc, json, len)) return fail(err, err_len, "malformed json");

  static DeckLayout tmp;
  memset(&tmp, 0, sizeof tmp);

  const char *hash = doc["hash"] | (const char *)nullptr;
  if (!valid_hash(hash)) return fail(err, err_len, "bad hash");
  strcpy(tmp.hash, hash);

  JsonArrayConst pages = doc["pages"].as<JsonArrayConst>();
  if (pages.isNull()) return fail(err, err_len, "pages missing");
  if (pages.size() > DECK_MAX_PAGES) return fail(err, err_len, "too many pages");

  for (JsonObjectConst jp : pages) {
    DeckPage &p = tmp.pages[tmp.page_count];
    const char *name = jp["name"] | (const char *)nullptr;
    if (!name) return fail(err, err_len, "page name missing");
    if (strlen(name) >= sizeof p.name) return fail(err, err_len, "page name too long");
    strcpy(p.name, name);

    JsonArrayConst widgets = jp["widgets"].as<JsonArrayConst>();
    if (widgets.isNull()) return fail(err, err_len, "widgets missing");
    if (widgets.size() > DECK_MAX_WIDGETS) return fail(err, err_len, "too many widgets");

    uint16_t occ[DECK_ROWS] = {0};
    for (JsonObjectConst jw : widgets) {
      DeckWidget &w = p.widgets[p.count];
      if (!parse_widget(jw, &w, occ, err, err_len)) return false;
      for (uint8_t i = 0; i < tmp.page_count; i++)
        for (uint8_t j = 0; j < tmp.pages[i].count; j++)
          if (strcmp(tmp.pages[i].widgets[j].id, w.id) == 0) return fail(err, err_len, "duplicate widget id");
      for (uint8_t j = 0; j < p.count; j++)
        if (strcmp(p.widgets[j].id, w.id) == 0) return fail(err, err_len, "duplicate widget id");
      p.count++;
    }
    tmp.page_count++;
  }

  parse_sprites(doc["agent_sprites"], &tmp.sprites);

  *out = tmp;
  return true;
}

bool deck_layout_faces_cached(const DeckLayout *l, bool (*exists)(uint16_t id)) {
  if (!l || !exists) return false;
  for (int p = 0; p < l->page_count; p++) {
    const DeckPage &pg = l->pages[p];
    for (int i = 0; i < pg.count; i++)
      if (pg.widgets[i].type == DW_KEY && !exists(pg.widgets[i].face)) return false;
  }
  const DeckAgentSprites &sp = l->sprites;
  if (!sp.present) return true;
  for (int i = 0; i < sp.frames; i++)
    if (!exists((uint16_t)(sp.first_id + i))) return false;
  for (int i = 0; i < sp.hat_count; i++)
    if (!exists((uint16_t)(sp.hat_first + i))) return false;
  return true;
}

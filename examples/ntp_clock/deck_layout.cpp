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

  if (w->type == DW_KEY) {
    const int face = jw["face"] | 0;
    if (face < 1 || face > DECK_MAX_FACES) return fail(err, err_len, "face out of range");
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

  *out = tmp;
  return true;
}

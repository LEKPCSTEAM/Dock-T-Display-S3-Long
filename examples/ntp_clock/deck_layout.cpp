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

static bool parse_widget(JsonObjectConst jw, DeckWidget *w, uint16_t *occ, char *err, size_t err_len) {
  const char *id = jw["id"] | (const char *)nullptr;
  if (!id || !*id) return fail(err, err_len, "widget id missing");
  if (strlen(id) >= sizeof w->id) return fail(err, err_len, "widget id too long");
  memset(w, 0, sizeof *w);
  strcpy(w->id, id);

  const char *type = jw["type"] | "";
  w->type = strcmp(type, "key") == 0 ? DW_KEY : DW_UNKNOWN;

  if (!get_u8(jw["col"], 0, DECK_COLS - 1, &w->col) || !get_u8(jw["row"], 0, DECK_ROWS - 1, &w->row) ||
      !get_u8(jw["w"], 1, DECK_COLS, &w->w) || !get_u8(jw["h"], 1, DECK_ROWS, &w->h))
    return fail(err, err_len, "widget geometry invalid");
  if (w->col + w->w > DECK_COLS || w->row + w->h > DECK_ROWS) return fail(err, err_len, "widget outside grid");

  if (w->type == DW_KEY) {
    const int face = jw["face"] | 0;
    if (face < 1 || face > DECK_MAX_FACES) return fail(err, err_len, "face out of range");
    w->face = (uint16_t)face;
  }
  w->has_long = jw["long"] | false;

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

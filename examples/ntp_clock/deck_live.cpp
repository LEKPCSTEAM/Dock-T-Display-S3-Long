#include "deck_live.h"
#include <ArduinoJson.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static bool is_rate(uint8_t m) { return m == DM_NET_DOWN || m == DM_NET_UP || m == DM_DISK_IO; }

static int clamp_round(float x) {
  if (x <= 0) return 0;
  if (x >= 100) return 100;
  return (int)floorf(x + 0.5f);
}

static void read_metric(JsonObjectConst o, const char *key, uint8_t m, float hi, DeckStats *s) {
  JsonVariantConst v = o[key];
  if (!v.is<float>()) return;
  float x = v.as<float>();
  if (m == DM_BATTERY && x < 0) return;
  if (x < 0) x = 0;
  if (x > hi) x = hi;
  s->v[m] = x;
  s->valid |= (uint16_t)(1u << m);
}

bool deck_stats_parse(const char *json, size_t len, DeckStats *out) {
  if (!json || !out || len > DECK_LIVE_BODY_MAX) return false;
  JsonDocument doc;
  if (deserializeJson(doc, json, len)) return false;
  JsonObjectConst o = doc.as<JsonObjectConst>();
  if (o.isNull()) return false;

  DeckStats s;
  memset(&s, 0, sizeof s);
  read_metric(o, "cpu", DM_CPU, 100, &s);
  read_metric(o, "ram", DM_RAM, 100, &s);
  read_metric(o, "gpu", DM_GPU, 100, &s);
  read_metric(o, "temp_c", DM_TEMP, 1000, &s);
  read_metric(o, "net_down_bps", DM_NET_DOWN, INFINITY, &s);
  read_metric(o, "net_up_bps", DM_NET_UP, INFINITY, &s);
  read_metric(o, "disk_free_pct", DM_DISK_FREE, 100, &s);
  read_metric(o, "disk_io_bps", DM_DISK_IO, INFINITY, &s);
  read_metric(o, "battery", DM_BATTERY, 100, &s);
  *out = s;
  return true;
}

bool deck_volume_parse(const char *json, size_t len, DeckVolume *out) {
  if (!json || !out || len > DECK_LIVE_BODY_MAX) return false;
  JsonDocument doc;
  if (deserializeJson(doc, json, len)) return false;
  JsonObjectConst o = doc.as<JsonObjectConst>();
  if (o.isNull() || !o["level"].is<float>() || !o["muted"].is<bool>() || !o["available"].is<bool>()) return false;
  const float level = o["level"].as<float>();
  out->level = (uint8_t)clamp_round(level);
  out->muted = o["muted"].as<bool>();
  out->available = o["available"].as<bool>();
  return true;
}

void deck_history_clear(DeckHistory *h) { memset(h, 0, sizeof *h); }

void deck_history_push(DeckHistory *h, const DeckStats *s) {
  for (int m = 0; m < DM_COUNT; m++) h->v[m][h->head] = (s->valid & (1u << m)) ? s->v[m] : NAN;
  h->head = (uint8_t)((h->head + 1) % DECK_HISTORY_LEN);
  if (h->count < DECK_HISTORY_LEN) h->count++;
}

uint8_t deck_history_series(const DeckHistory *h, uint8_t metric, float out[DECK_HISTORY_LEN]) {
  if (metric >= DM_COUNT) return 0;
  const int start = (h->head + DECK_HISTORY_LEN - h->count) % DECK_HISTORY_LEN;
  for (int i = 0; i < h->count; i++) out[i] = h->v[metric][(start + i) % DECK_HISTORY_LEN];
  return h->count;
}

float deck_history_max(const DeckHistory *h, uint8_t metric) {
  float out[DECK_HISTORY_LEN];
  const uint8_t n = deck_history_series(h, metric, out);
  float mx = 0;
  for (int i = 0; i < n; i++)
    if (!isnan(out[i]) && out[i] > mx) mx = out[i];
  return mx;
}

int deck_live_level(uint8_t metric, float value, float rate_max) {
  if (isnan(value) || metric >= DM_COUNT) return 0;
  if (is_rate(metric)) {
    const float cap = rate_max > DECK_RATE_FLOOR_BPS ? rate_max : DECK_RATE_FLOOR_BPS;
    return clamp_round(value * 100.0f / cap);
  }
  return clamp_round(value);
}

void deck_live_format(uint8_t metric, const DeckStats *s, char *val, size_t val_len, char *unit, size_t unit_len) {
  val[0] = 0;
  unit[0] = 0;
  if (metric >= DM_COUNT || !(s->valid & (1u << metric))) {
    snprintf(val, val_len, "--");
    return;
  }
  const float x = s->v[metric];
  if (!is_rate(metric)) {
    snprintf(val, val_len, "%.0f", x);
    snprintf(unit, unit_len, "%s", metric == DM_TEMP ? "\xC2\xB0" "C" : "%");
    return;
  }
  const char *u;
  float scaled;
  if (x < 999.5f) { scaled = x; u = "B/s"; }
  else if (x < 999500.0f) { scaled = x / 1e3f; u = "KB/s"; }
  else if (x < 999.5e6f) { scaled = x / 1e6f; u = "MB/s"; }
  else { scaled = x / 1e9f; u = "GB/s"; }
  const bool bytes = u[0] == 'B';
  snprintf(val, val_len, (!bytes && scaled < 9.95f) ? "%.1f" : "%.0f", scaled);
  snprintf(unit, unit_len, "%s", u);
}

const char *deck_metric_label(uint8_t metric) {
  static const char *const labels[DM_COUNT] = {"CPU", "RAM", "GPU", "TEMP", "NET \xEF\x81\xB8",
                                               "NET \xEF\x81\xB7", "DISK", "DISK I/O", "BAT"};
  return metric < DM_COUNT ? labels[metric] : "";
}

void deck_slider_reset(DeckSliderGate *g) { memset(g, 0, sizeof *g); }

static void mark_sent(DeckSliderGate *g, uint32_t now_ms, int value) {
  g->last_ms = now_ms;
  g->last_sent = (int16_t)value;
  g->sent_once = true;
  g->has_pending = false;
}

bool deck_slider_offer(DeckSliderGate *g, uint32_t now_ms, int value, int *out) {
  const bool due = !g->sent_once || (uint32_t)(now_ms - g->last_ms) >= DECK_SLIDER_MIN_MS;
  if (due && (!g->sent_once || value != g->last_sent)) {
    mark_sent(g, now_ms, value);
    *out = value;
    return true;
  }
  g->pending = (int16_t)value;
  g->has_pending = true;
  return false;
}

bool deck_slider_poll(DeckSliderGate *g, uint32_t now_ms, int *out) {
  if (!g->has_pending || (uint32_t)(now_ms - g->last_ms) < DECK_SLIDER_MIN_MS) return false;
  const int value = g->pending;
  g->has_pending = false;
  if (g->sent_once && value == g->last_sent) return false;
  mark_sent(g, now_ms, value);
  *out = value;
  return true;
}

bool deck_slider_body(const char *id, int value, char *out, size_t out_len) {
  if (!id || !*id || !out || !out_len) return false;
  JsonDocument doc;
  doc["id"] = id;
  doc["value"] = value < 0 ? 0 : (value > 100 ? 100 : value);
  if (measureJson(doc) >= out_len) return false;
  serializeJson(doc, out, out_len);
  return true;
}

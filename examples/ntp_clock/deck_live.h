#pragma once
#include <stddef.h>
#include <stdint.h>
#include "deck_layout.h"

#define DECK_HISTORY_LEN 60
#define DECK_LIVE_BODY_MAX 512
#define DECK_SLIDER_MIN_MS 100
#define DECK_RATE_FLOOR_BPS 100000.0f

struct DeckStats {
  float v[DM_COUNT];
  uint16_t valid;  // bit = 1 << metric
};
struct DeckVolume {
  uint8_t level;
  bool muted;
  bool available;
};
struct DeckHistory {
  float v[DM_COUNT][DECK_HISTORY_LEN];
  uint8_t head, count;
};
struct DeckSliderGate {
  uint32_t last_ms;
  int16_t last_sent, pending;
  bool sent_once, has_pending;
};

bool deck_stats_parse(const char *json, size_t len, DeckStats *out);
bool deck_volume_parse(const char *json, size_t len, DeckVolume *out);
void deck_history_clear(DeckHistory *h);
void deck_history_push(DeckHistory *h, const DeckStats *s);
uint8_t deck_history_series(const DeckHistory *h, uint8_t metric, float out[DECK_HISTORY_LEN]);
float deck_history_max(const DeckHistory *h, uint8_t metric);
int deck_live_level(uint8_t metric, float value, float rate_max);
void deck_live_format(uint8_t metric, const DeckStats *s, char *val, size_t val_len, char *unit, size_t unit_len);
const char *deck_metric_label(uint8_t metric);
void deck_slider_reset(DeckSliderGate *g);
bool deck_slider_offer(DeckSliderGate *g, uint32_t now_ms, int value, int *out);
bool deck_slider_poll(DeckSliderGate *g, uint32_t now_ms, int *out);
bool deck_slider_body(const char *id, int value, char *out, size_t out_len);

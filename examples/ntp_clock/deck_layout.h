#pragma once
#include <stddef.h>
#include <stdint.h>

#define DECK_COLS 8
#define DECK_ROWS 2
#define DECK_MAX_PAGES 8
#define DECK_MAX_WIDGETS 16
#define DECK_MAX_FACES 192
#define DECK_KEY_MAX_FACE 128
#define DECK_SPRITE_FIRST_ID 129
#define DECK_AGENT_TAGS 4
#define DECK_SPRITE_MAX_FRAMES 32
#define DECK_LAYOUT_MAX_BYTES (16 * 1024)

enum DeckWidgetType : uint8_t { DW_KEY = 0, DW_STAT = 1, DW_VOLUME = 2, DW_CLOCK = 3,
                                 DW_CLAUDE_SESSIONS = 4, DW_CLAUDE_USAGE = 5, DW_CLAUDE_AGENTS = 6, DW_UNKNOWN = 255 };
enum DeckMetric : uint8_t {
  DM_CPU = 0, DM_RAM, DM_GPU, DM_TEMP, DM_NET_DOWN, DM_NET_UP, DM_DISK_FREE, DM_DISK_IO, DM_BATTERY, DM_COUNT
};
enum DeckStatStyle : uint8_t { DS_BAR = 0, DS_NUMBER, DS_SPARKLINE, DS_COUNT };

struct DeckWidget {
  char id[16];
  uint8_t type, col, row, w, h;
  uint16_t face;
  bool has_long;
  uint8_t metric, style;  // DW_STAT only
};

struct DeckPage {
  char name[24];
  uint8_t count;
  DeckWidget widgets[DECK_MAX_WIDGETS];
};

struct DeckAgentSprites {
  bool present;
  uint8_t w, h, hat_w, hat_h, frames, hat_count;
  uint16_t first_id, hat_first;
  uint8_t tag_first[DECK_AGENT_TAGS], tag_count[DECK_AGENT_TAGS];  // frame indexes
  uint16_t ms[DECK_SPRITE_MAX_FRAMES];
  uint8_t hat_x[DECK_SPRITE_MAX_FRAMES], hat_y[DECK_SPRITE_MAX_FRAMES];
};

struct DeckLayout {
  char hash[17];
  uint8_t page_count;
  DeckPage pages[DECK_MAX_PAGES];
  DeckAgentSprites sprites;
};

int deck_metric_from_name(const char *name);  // -1 if unknown
int deck_style_from_name(const char *name);   // -1 if unknown

bool deck_layout_parse(const char *json, size_t len, DeckLayout *out, char *err, size_t err_len);
bool deck_layout_faces_cached(const DeckLayout *l, bool (*exists)(uint16_t id));  // keys, sprite frames, hats

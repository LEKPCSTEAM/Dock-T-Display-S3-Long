#pragma once
#include <stddef.h>
#include <stdint.h>

#define DECK_COLS 8
#define DECK_ROWS 2
#define DECK_MAX_PAGES 8
#define DECK_MAX_WIDGETS 16
#define DECK_MAX_FACES 128
#define DECK_LAYOUT_MAX_BYTES (16 * 1024)

enum DeckWidgetType : uint8_t { DW_KEY = 0, DW_UNKNOWN = 255 };

struct DeckWidget {
  char id[16];
  uint8_t type, col, row, w, h;
  uint16_t face;
  bool has_long;
};

struct DeckPage {
  char name[24];
  uint8_t count;
  DeckWidget widgets[DECK_MAX_WIDGETS];
};

struct DeckLayout {
  char hash[17];
  uint8_t page_count;
  DeckPage pages[DECK_MAX_PAGES];
};

bool deck_layout_parse(const char *json, size_t len, DeckLayout *out, char *err, size_t err_len);

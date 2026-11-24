#pragma once
#include <stdint.h>
#include "deck_layout.h"

// begin/on_connected/loop run on net_task; the rest is safe from the LVGL thread.
void     deck_net_begin();
void     deck_net_on_connected();
void     deck_net_loop();
bool     deck_net_ready();
uint32_t deck_net_layout_version();
bool     deck_net_layout(DeckLayout *out);
bool     deck_net_take_dirty_faces(uint8_t bits[DECK_MAX_FACES / 8]);  // bit (id-1)
bool     deck_net_pair_code(uint32_t *code);
void     deck_net_press(const char *id, bool long_press);
void     deck_net_page(int8_t deck_index);
void     deck_net_forget();

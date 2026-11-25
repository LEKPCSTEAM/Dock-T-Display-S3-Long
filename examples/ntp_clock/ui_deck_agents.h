#pragma once

#include <stdint.h>
#include "ui_internal.h"

// Board Claude agents widget inside deck tiles (ui_deck_agents.cpp).
void ui_agents_reset();
bool ui_agents_create(lv_obj_t *tile, const DeckWidget *w, const DeckAgentSprites *sprites);
void ui_agents_update(const UiTick *t, bool ready, bool visible);  // visible: a deck page is on screen
void ui_agents_face_changed(uint16_t id);

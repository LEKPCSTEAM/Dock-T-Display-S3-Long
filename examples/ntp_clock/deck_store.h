#pragma once
#include <stddef.h>
#include <stdint.h>
#include "lvgl.h"
#include "deck_layout.h"

bool   deck_store_begin();
bool   deck_store_save_layout(const char *json, size_t len);
size_t deck_store_load_layout(char *buf, size_t cap);
bool   deck_store_save_face(uint16_t id, uint16_t w, uint16_t h, const uint8_t *px);
void   deck_store_invalidate_faces(const DeckLayout *layout);
bool   deck_store_face_exists(uint16_t id);
bool   deck_store_load_face(uint16_t id, lv_img_dsc_t *out);
void   deck_store_free_face(lv_img_dsc_t *img);
void   deck_store_prune(const DeckLayout *keep);

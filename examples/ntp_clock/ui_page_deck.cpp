#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ui_internal.h"
#include "deck_net.h"
#include "deck_store.h"

#define CELL_W          80
#define CELL_H          90
#define CELL_PAD        3
#define OFFLINE_OPA     102
#define PRESS_ZOOM      243
#define PRESS_BRIGHTEN  50

struct DeckKey {
    lv_obj_t *btn;
    lv_obj_t *img;
    uint16_t  face;
    bool      has_long;
    char      id[16];
};

static DeckKey      keys[DECK_MAX_PAGES * DECK_MAX_WIDGETS];
static int          key_count;
static lv_img_dsc_t *faces[DECK_MAX_FACES + 1];
static lv_obj_t     *badges[DECK_MAX_PAGES];
static uint8_t       built_pages;
static bool          have_layout;

static DeckLayout layout;
static uint32_t   built_version = UINT32_MAX;
static bool       shown_ready   = true;
static int8_t     sent_page     = -2;

static void face_free(uint16_t id)
{
    if (id == 0 || id > DECK_MAX_FACES || !faces[id]) {
        return;
    }
    deck_store_free_face(faces[id]);
    free(faces[id]);
    faces[id] = NULL;
}

static void key_set_face(DeckKey *k)
{
    lv_img_dsc_t *f = k->face <= DECK_MAX_FACES ? faces[k->face] : NULL;
    if (f) {
        lv_img_set_src(k->img, f);
        lv_obj_clear_flag(k->img, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(k->img, LV_OBJ_FLAG_HIDDEN);
    }
}

static void face_reload(uint16_t id)
{
    lv_img_dsc_t *old = faces[id];
    lv_img_dsc_t *nu  = (lv_img_dsc_t *)malloc(sizeof(lv_img_dsc_t));
    if (nu && !deck_store_load_face(id, nu)) {
        free(nu);
        nu = NULL;
    }
    faces[id] = nu;
    for (int i = 0; i < key_count; i++) {
        if (keys[i].face == id) {
            key_set_face(&keys[i]);
        }
    }
    if (old) {
        deck_store_free_face(old);
        free(old);
    }
}

static void key_press_visual(lv_obj_t *img, bool down)
{
    lv_img_set_zoom(img, down ? PRESS_ZOOM : LV_IMG_ZOOM_NONE);
    lv_obj_set_style_img_recolor(img, lv_color_white(), 0);
    lv_obj_set_style_img_recolor_opa(img, down ? PRESS_BRIGHTEN : LV_OPA_TRANSP, 0);
}

static void key_cb(lv_event_t *e)
{
    DeckKey *k = (DeckKey *)lv_event_get_user_data(e);
    switch (lv_event_get_code(e)) {
    case LV_EVENT_PRESSED:
        if (deck_net_ready()) {
            key_press_visual(k->img, true);
        }
        break;
    case LV_EVENT_RELEASED:
    case LV_EVENT_PRESS_LOST:
        key_press_visual(k->img, false);
        break;
    case LV_EVENT_SHORT_CLICKED:
        if (deck_net_ready()) {
            deck_net_press(k->id, false);
        }
        break;
    case LV_EVENT_LONG_PRESSED:
        if (k->has_long && deck_net_ready()) {
            deck_net_press(k->id, true);
        }
        break;
    default:
        break;
    }
}

static void badge_create(uint8_t page, lv_obj_t *tile)
{
    lv_obj_t *b = lv_obj_create(tile);
    ui_strip_obj(b);
    lv_obj_clear_flag(b, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(b, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(b, COLOR_PANEL_HI, 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(b, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_pad_hor(b, 10, 0);
    lv_obj_set_style_pad_ver(b, 3, 0);
    ui_label(b, &ui_font_th_16, COLOR_WARN, "Mac offline");
    lv_obj_align(b, LV_ALIGN_TOP_RIGHT, -6, 4);
    lv_obj_add_flag(b, LV_OBJ_FLAG_HIDDEN);
    badges[page] = b;
}

static void hint_create(lv_obj_t *tile)
{
    lv_obj_t *l = ui_label(tile, &ui_font_th_22, COLOR_TEXT_DIM, "เปิดแอป LongDeck บน Mac แล้วกด Pair");
    lv_obj_center(l);
}

static void key_create(lv_obj_t *tile, const DeckWidget *w)
{
    lv_coord_t x  = w->col * CELL_W + CELL_PAD;
    lv_coord_t y  = w->row * CELL_H + CELL_PAD;
    lv_coord_t bw = w->w * CELL_W - 2 * CELL_PAD;
    lv_coord_t bh = w->h * CELL_H - 2 * CELL_PAD;

    lv_obj_t *btn = lv_obj_create(tile);
    ui_strip_obj(btn);
    lv_obj_set_pos(btn, x, y);
    lv_obj_set_size(btn, bw, bh);
    lv_obj_set_style_bg_color(btn, COLOR_PANEL, 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(btn, 8, 0);
    if (w->type != DW_KEY || key_count >= (int)(sizeof(keys) / sizeof(keys[0]))) {
        lv_obj_clear_flag(btn, LV_OBJ_FLAG_CLICKABLE);
        return;
    }

    DeckKey *k = &keys[key_count++];
    k->btn      = btn;
    k->face     = w->face;
    k->has_long = w->has_long;
    snprintf(k->id, sizeof(k->id), "%s", w->id);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_GESTURE_BUBBLE);

    k->img = lv_img_create(btn);
    lv_obj_clear_flag(k->img, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_center(k->img);
    lv_obj_add_flag(k->img, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(btn, key_cb, LV_EVENT_ALL, k);
}

static void deck_rebuild()
{
    bool have = deck_net_layout(&layout) && layout.page_count > 0;
    uint8_t n = have ? layout.page_count : 1;
    have_layout = have;

    ui_set_deck_pages(n);
    for (uint8_t i = 0; i < built_pages && i < DECK_MAX_PAGES; i++) {
        lv_obj_t *tile = ui_deck_tile(i);
        if (tile) {
            lv_obj_clean(tile);
        }
        badges[i] = NULL;
    }
    key_count = 0;
    for (uint16_t id = 1; id <= DECK_MAX_FACES; id++) {
        face_free(id);
    }
    built_pages = n;

    for (uint8_t p = 0; p < n; p++) {
        lv_obj_t *tile = ui_deck_tile(p);
        if (!tile) {
            continue;
        }
        if (!have) {
            hint_create(tile);
            continue;
        }
        const DeckPage *page = &layout.pages[p];
        for (uint8_t i = 0; i < page->count && i < DECK_MAX_WIDGETS; i++) {
            key_create(tile, &page->widgets[i]);
        }
        badge_create(p, tile);
    }
    for (int i = 0; i < key_count; i++) {
        uint16_t id = keys[i].face;
        if (id >= 1 && id <= DECK_MAX_FACES && !faces[id]) {
            face_reload(id);
        } else {
            key_set_face(&keys[i]);
        }
    }
    shown_ready = !deck_net_ready();
}

static int visible_deck_index(bool have)
{
    if (!have) {
        return -1;
    }
    for (uint8_t i = 0; i < built_pages; i++) {
        lv_obj_t *tile = ui_deck_tile(i);
        if (!tile) {
            continue;
        }
        lv_area_t a;
        lv_obj_get_coords(tile, &a);
        if (a.x1 >= 0 && a.x1 < SCREEN_W / 2) {
            return i;
        }
    }
    return -1;
}

void page_deck_update(const UiTick *)
{
    uint32_t ver = deck_net_layout_version();
    bool rebuilt = ver != built_version;
    uint8_t dirty[DECK_MAX_FACES / 8];
    bool    any_dirty = deck_net_take_dirty_faces(dirty);

    if (rebuilt) {
        built_version = ver;
        deck_rebuild();
    } else if (any_dirty) {
        for (uint16_t id = 1; id <= DECK_MAX_FACES; id++) {
            if (dirty[(id - 1) / 8] & (1 << ((id - 1) % 8))) {
                bool used = false;
                for (int i = 0; i < key_count && !used; i++) {
                    used = keys[i].face == id;
                }
                if (used) {
                    face_reload(id);
                }
            }
        }
    }

    bool ready = deck_net_ready();
    if (ready != shown_ready) {
        shown_ready = ready;
        for (int i = 0; i < key_count; i++) {
            lv_obj_set_style_opa(keys[i].btn, ready ? LV_OPA_COVER : OFFLINE_OPA, 0);
        }
        for (uint8_t p = 0; p < built_pages; p++) {
            if (badges[p]) {
                if (ready) {
                    lv_obj_add_flag(badges[p], LV_OBJ_FLAG_HIDDEN);
                } else {
                    lv_obj_clear_flag(badges[p], LV_OBJ_FLAG_HIDDEN);
                }
            }
        }
    }

    int8_t idx = (int8_t)visible_deck_index(have_layout);
    if (idx != sent_page) {
        sent_page = idx;
        deck_net_page(idx);
    }
}

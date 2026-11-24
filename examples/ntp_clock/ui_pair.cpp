#include <stdio.h>
#include "ui_internal.h"
#include "deck_net.h"

#define PAIR_TOTAL_MS 60000
#define BAR_W         360
#define BAR_H         8

static lv_obj_t *overlay;
static lv_obj_t *code_label;
static lv_obj_t *bar;
static uint32_t  shown_code = UINT32_MAX;
static uint32_t  start_ms;

static void overlay_create(const UiTick *t)
{
    overlay = lv_obj_create(lv_layer_top());
    ui_strip_obj(overlay);
    lv_obj_set_size(overlay, SCREEN_W, SCREEN_H);
    lv_obj_set_style_bg_color(overlay, COLOR_BG, 0);
    lv_obj_set_style_bg_opa(overlay, LV_OPA_COVER, 0);

    code_label = ui_label(overlay, &ui_font_digits_56, t->accent, "000000");
    lv_obj_align(code_label, LV_ALIGN_CENTER, 0, -34);

    lv_obj_t *hint = ui_label(overlay, &ui_font_th_22, COLOR_TEXT, "ใส่รหัสนี้ในแอป LongDeck");
    lv_obj_align(hint, LV_ALIGN_CENTER, 0, 28);

    bar = lv_bar_create(overlay);
    lv_obj_set_size(bar, BAR_W, BAR_H);
    lv_obj_align(bar, LV_ALIGN_CENTER, 0, 66);
    lv_bar_set_range(bar, 0, PAIR_TOTAL_MS);
    lv_obj_set_style_bg_color(bar, COLOR_PANEL_HI, LV_PART_MAIN);
    lv_obj_set_style_bg_color(bar, t->accent, LV_PART_INDICATOR);
}

void ui_pair_update(const UiTick *t)
{
    uint32_t code;
    if (!deck_net_pair_code(&code)) {
        if (overlay) {
            lv_obj_add_flag(overlay, LV_OBJ_FLAG_HIDDEN);
        }
        shown_code = UINT32_MAX;
        return;
    }
    if (!overlay) {
        overlay_create(t);
    }
    if (code != shown_code) {
        char buf[8];
        snprintf(buf, sizeof(buf), "%06lu", (unsigned long)(code % 1000000));
        lv_label_set_text(code_label, buf);
        lv_obj_set_style_text_color(code_label, t->accent, 0);
        shown_code = code;
        start_ms   = lv_tick_get();
    }
    uint32_t left = lv_tick_elaps(start_ms);
    lv_bar_set_value(bar, left >= PAIR_TOTAL_MS ? 0 : PAIR_TOTAL_MS - (int32_t)left, LV_ANIM_OFF);

    // Cover the splash and any toast or flash created since.
    lv_obj_move_foreground(overlay);
    lv_obj_clear_flag(overlay, LV_OBJ_FLAG_HIDDEN);
}

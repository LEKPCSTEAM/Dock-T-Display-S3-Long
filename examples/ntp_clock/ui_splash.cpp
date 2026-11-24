#include <stdio.h>
#include <string.h>
#include "ui_internal.h"

#define SPLASH_MAX_MS   10000
#define SPLASH_MIN_MS   1200
#define SPLASH_FADE_MS  400
#define TRACK_W         220
#define SWEEP_W         70
#define SWEEP_MS        1100

static lv_obj_t *overlay;
static lv_obj_t *status_label;
static lv_obj_t *sweep;
static uint32_t  start_ms;
static bool      closing;
static char      shown_status[96];

static void sweep_cb(void *, int32_t v)
{
    lv_obj_set_x(sweep, v);
    lv_obj_set_style_bg_color(sweep, lv_color_hsv_to_rgb((uint32_t)(v * 360 / (TRACK_W - SWEEP_W)), 75, 100), 0);
}

static void fade_cb(void *obj, int32_t v)
{
    lv_obj_set_style_opa((lv_obj_t *)obj, (lv_opa_t)v, 0);
}

static void fade_done_cb(lv_anim_t *a)
{
    lv_obj_del((lv_obj_t *)a->var);
    overlay = NULL;
}

void ui_splash_create()
{
    start_ms = lv_tick_get();
    overlay  = lv_obj_create(lv_layer_top());
    ui_strip_obj(overlay);
    lv_obj_set_size(overlay, SCREEN_W, SCREEN_H);
    lv_obj_set_style_bg_color(overlay, COLOR_BG, 0);
    lv_obj_set_style_bg_opa(overlay, LV_OPA_COVER, 0);

    lv_obj_t *row = lv_obj_create(overlay);
    ui_strip_obj(row);
    lv_obj_clear_flag(row, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(row, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, 18, 0);
    lv_obj_align(row, LV_ALIGN_TOP_MID, 0, 22);

    lv_obj_t *spin = lv_spinner_create(row, 1000, 70);
    lv_obj_set_size(spin, 52, 52);
    lv_obj_set_style_arc_width(spin, 5, LV_PART_MAIN);
    lv_obj_set_style_arc_width(spin, 5, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(spin, COLOR_PANEL_HI, LV_PART_MAIN);
    lv_obj_set_style_arc_color(spin, ui_day_color(1), LV_PART_INDICATOR);

    lv_obj_t *col = lv_obj_create(row);
    ui_strip_obj(col);
    lv_obj_clear_flag(col, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(col, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    ui_label(col, &font_th_32, COLOR_TEXT, "นาฬิกาไทย");
    ui_label(col, &font_th_16, COLOR_TEXT_DIM, "ThaiClock");

    lv_obj_t *track = lv_obj_create(overlay);
    ui_strip_obj(track);
    lv_obj_clear_flag(track, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(track, TRACK_W, 4);
    lv_obj_align(track, LV_ALIGN_TOP_MID, 0, 106);
    lv_obj_set_style_bg_color(track, COLOR_PANEL_HI, 0);
    lv_obj_set_style_bg_opa(track, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(track, 2, 0);

    sweep = lv_obj_create(track);
    ui_strip_obj(sweep);
    lv_obj_clear_flag(sweep, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(sweep, SWEEP_W, 4);
    lv_obj_set_style_bg_opa(sweep, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(sweep, 2, 0);

    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, sweep);
    lv_anim_set_exec_cb(&a, sweep_cb);
    lv_anim_set_values(&a, 0, TRACK_W - SWEEP_W);
    lv_anim_set_time(&a, SWEEP_MS);
    lv_anim_set_playback_time(&a, SWEEP_MS);
    lv_anim_set_repeat_count(&a, LV_ANIM_REPEAT_INFINITE);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
    lv_anim_start(&a);

    status_label = ui_label(overlay, &font_th_16, COLOR_TEXT_DIM, "");
    lv_obj_align(status_label, LV_ALIGN_TOP_MID, 0, 128);
    lv_obj_set_style_text_align(status_label, LV_TEXT_ALIGN_CENTER, 0);
}

static void status_text(const NetStatus *n, char *out, size_t len)
{
    switch (n->phase) {
    case NET_CONNECTING:
        if (n->ssid[0]) {
            snprintf(out, len, "กำลังเชื่อมต่อ WiFi %s…", n->ssid);
        } else {
            snprintf(out, len, "กำลังเชื่อมต่อ WiFi…");
        }
        break;
    case NET_CONNECTED:
        snprintf(out, len, "กำลังซิงค์เวลา…");
        break;
    case NET_PORTAL:
        snprintf(out, len, "เปิดโหมดตั้งค่า WiFi");
        break;
    case NET_OFFLINE:
        snprintf(out, len, "ไม่พบ WiFi กำลังลองใหม่…");
        break;
    default:
        snprintf(out, len, "กำลังเริ่มระบบ…");
        break;
    }
}

bool ui_splash_update(const UiTick *t)
{
    if (!overlay) {
        return false;
    }
    if (closing) {
        return true;
    }

    char text[96];
    status_text(t->net, text, sizeof(text));
    if (strcmp(text, shown_status) != 0) {
        snprintf(shown_status, sizeof(shown_status), "%s", text);
        lv_label_set_text(status_label, text);
        lv_obj_align(status_label, LV_ALIGN_TOP_MID, 0, 128);
    }

    uint32_t elapsed = lv_tick_elaps(start_ms);
    bool done = (t->time_valid && elapsed >= SPLASH_MIN_MS) || elapsed >= SPLASH_MAX_MS ||
                t->net->phase == NET_PORTAL;
    if (done) {
        closing = true;
        lv_anim_t a;
        lv_anim_init(&a);
        lv_anim_set_var(&a, overlay);
        lv_anim_set_exec_cb(&a, fade_cb);
        lv_anim_set_values(&a, 255, 0);
        lv_anim_set_time(&a, SPLASH_FADE_MS);
        lv_anim_set_path_cb(&a, lv_anim_path_linear);
        lv_anim_set_ready_cb(&a, fade_done_cb);
        lv_anim_start(&a);
    }
    return true;
}

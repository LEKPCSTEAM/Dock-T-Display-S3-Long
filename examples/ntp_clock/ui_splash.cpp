#include <stdio.h>
#include <string.h>
#include "ui_internal.h"
#include "eez/gen/screens.h"

#define SPLASH_MAX_MS   10000
#define SPLASH_MIN_MS   1200
#define SPLASH_FADE_MS  400
#define TRACK_W         220
#define SWEEP_W         70
#define SWEEP_MS        1100

static lv_obj_t *overlay;
static uint32_t  start_ms;
static bool      closing;
static char      shown_status[96];

static void sweep_cb(void *obj, int32_t v)
{
    lv_obj_set_x((lv_obj_t *)obj, v);
    lv_obj_set_style_bg_color((lv_obj_t *)obj, lv_color_hsv_to_rgb((uint32_t)(v * 360 / (TRACK_W - SWEEP_W)), 75, 100), 0);
}

static void fade_cb(void *obj, int32_t v)
{
    lv_obj_set_style_opa((lv_obj_t *)obj, (lv_opa_t)v, 0);
}

static void fade_done_cb(lv_anim_t *a)
{
    lv_obj_del((lv_obj_t *)a->var);
    overlay = NULL;
    objects.spinner_splash        = NULL;
    objects.label_splash_title    = NULL;
    objects.label_splash_subtitle = NULL;
    objects.cont_splash_underline = NULL;
    objects.cont_splash_sweep     = NULL;
    objects.label_splash_status   = NULL;
}

void ui_splash_create()
{
    start_ms = lv_tick_get();
    overlay  = lv_obj_create(lv_layer_top());
    ui_strip_obj(overlay);
    lv_obj_set_size(overlay, SCREEN_W, SCREEN_H);
    lv_obj_set_style_bg_color(overlay, COLOR_BG, 0);
    lv_obj_set_style_bg_opa(overlay, LV_OPA_COVER, 0);

    create_screen_splash_page();
    ui_mount_screen(objects.splash_page, overlay);
    objects.splash_page = NULL;

    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, objects.cont_splash_sweep);
    lv_anim_set_exec_cb(&a, sweep_cb);
    lv_anim_set_values(&a, 0, TRACK_W - SWEEP_W);
    lv_anim_set_time(&a, SWEEP_MS);
    lv_anim_set_playback_time(&a, SWEEP_MS);
    lv_anim_set_repeat_count(&a, LV_ANIM_REPEAT_INFINITE);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
    lv_anim_start(&a);

    lv_label_set_text(objects.label_splash_status, "");
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
        lv_label_set_text(objects.label_splash_status, text);
        lv_obj_align(objects.label_splash_status, LV_ALIGN_TOP_MID, 0, 128);
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

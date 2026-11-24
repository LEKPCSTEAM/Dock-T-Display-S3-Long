#include "ui_internal.h"

#include "eez/gen/screens.h"

#include <Arduino.h>
#include <stdio.h>

namespace {

enum Mode : uint8_t { MODE_FOCUS = 0, MODE_SHORT, MODE_LONG };

const uint32_t MODE_MS[3] = {25UL * 60000, 5UL * 60000, 15UL * 60000};
const char *const MODE_NAME[3] = {"โฟกัส", "พักสั้น", "พักยาว"};
const uint8_t SESSIONS_PER_CYCLE = 4;
const int     ARC_MAX = 1000;
const int     DOT_COUNT = SESSIONS_PER_CYCLE;

enum State : uint8_t { STATE_IDLE = 0, STATE_RUNNING, STATE_PAUSED };

lv_obj_t *s_tile;
lv_obj_t *s_arc;
lv_obj_t *s_icon;
lv_obj_t *s_time;
lv_obj_t *s_mode;
lv_obj_t *s_hint;
lv_obj_t *s_dots[DOT_COUNT];

Mode     s_cur_mode = MODE_FOCUS;
uint8_t  s_done;
bool     s_running;
uint32_t s_deadline;
uint32_t s_remaining_ms = MODE_MS[MODE_FOCUS];
bool     s_ignore_click;
bool     s_prev_active;

int        s_shown_secs = -1;
int        s_shown_arc = -1;
int        s_shown_mode = -1;
int        s_shown_state = -1;
int        s_shown_done = -1;
bool       s_accent_valid;
lv_color_t s_shown_accent;

uint32_t remaining_now()
{
    if (!s_running) {
        return s_remaining_ms;
    }
    const int32_t left = (int32_t)(s_deadline - millis());
    return left > 0 ? (uint32_t)left : 0;
}

State current_state()
{
    if (s_running) {
        return STATE_RUNNING;
    }
    return s_remaining_ms == MODE_MS[s_cur_mode] ? STATE_IDLE : STATE_PAUSED;
}

void load_mode(Mode m)
{
    s_cur_mode = m;
    s_running = false;
    s_remaining_ms = MODE_MS[m];
}

void toggle_run()
{
    if (s_running) {
        s_remaining_ms = remaining_now();
        s_running = false;
    } else {
        s_deadline = millis() + s_remaining_ms;
        s_running = true;
    }
}

void finish_phase()
{
    if (s_cur_mode == MODE_FOCUS) {
        s_done++;
        load_mode(s_done >= SESSIONS_PER_CYCLE ? MODE_LONG : MODE_SHORT);
        ui_toast("หมดเวลาโฟกัส! พักสายตาหน่อย");
    } else {
        if (s_cur_mode == MODE_LONG) {
            s_done = 0;
        }
        load_mode(MODE_FOCUS);
        ui_toast("หมดเวลาพัก ลุยต่อ!");
    }
    ui_flash_screen(s_accent_valid ? s_shown_accent : COLOR_TEXT);
}

void tile_event_cb(lv_event_t *e)
{
    switch (lv_event_get_code(e)) {
    case LV_EVENT_PRESSED:
        s_ignore_click = false;
        break;
    case LV_EVENT_LONG_PRESSED:
        s_ignore_click = true;
        s_done = 0;
        load_mode(MODE_FOCUS);
        ui_toast("รีเซ็ตโฟกัสแล้ว");
        break;
    case LV_EVENT_CLICKED:
        if (!s_ignore_click) {
            toggle_run();
        }
        s_ignore_click = false;
        break;
    default:
        break;
    }
}

void paint_dots(lv_color_t accent)
{
    for (int i = 0; i < DOT_COUNT; i++) {
        const bool filled = i < s_done;
        lv_obj_set_style_bg_color(s_dots[i], filled ? accent : COLOR_PANEL, 0);
        lv_obj_set_style_border_color(s_dots[i], filled ? accent : COLOR_TEXT_DIM, 0);
    }
}

}  // namespace

void page_focus_create(lv_obj_t *tile)
{
    s_tile = tile;
    lv_obj_add_flag(tile, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(tile, tile_event_cb, LV_EVENT_ALL, nullptr);

    s_arc = objects.arc_focus_ring;
    lv_arc_set_range(s_arc, 0, ARC_MAX);
    lv_arc_set_value(s_arc, ARC_MAX);

    s_icon = objects.label_focus_icon;
    s_time = objects.label_focus_time;
    s_mode = objects.label_focus_mode;
    s_hint = objects.label_focus_hint;
    s_dots[0] = objects.cont_focus_dot0;
    s_dots[1] = objects.cont_focus_dot1;
    s_dots[2] = objects.cont_focus_dot2;
    s_dots[3] = objects.cont_focus_dot3;

    lv_label_set_text(s_time, "25:00");
    lv_label_set_text(s_mode, MODE_NAME[MODE_FOCUS]);
    lv_label_set_text(s_icon, SYM_BRAIN);
    paint_dots(COLOR_TEXT);
}

void page_focus_update(const UiTick *t)
{
    if (s_running && remaining_now() == 0) {
        finish_phase();
    }

    if (!t->active) {
        s_prev_active = false;
        return;
    }
    if (!s_prev_active) {
        s_prev_active = true;
        s_shown_secs = s_shown_arc = s_shown_mode = s_shown_state = s_shown_done = -1;
    }

    const uint32_t rem = remaining_now();
    const State    state = current_state();
    const bool     accent_changed = !s_accent_valid || t->accent.full != s_shown_accent.full;
    const bool     look_changed = accent_changed || s_shown_state != state ||
                              s_shown_mode != s_cur_mode;

    const int secs = (int)((rem + 999) / 1000);
    if (secs != s_shown_secs) {
        s_shown_secs = secs;
        char buf[24];
        snprintf(buf, sizeof(buf), "%02d:%02d", secs / 60, secs % 60);
        lv_label_set_text(s_time, buf);
    }

    const int arc = (int)((uint64_t)rem * ARC_MAX / MODE_MS[s_cur_mode]);
    if (arc != s_shown_arc) {
        s_shown_arc = arc;
        lv_arc_set_value(s_arc, arc);
    }

    if (s_shown_mode != s_cur_mode) {
        lv_label_set_text(s_icon, s_cur_mode == MODE_FOCUS ? SYM_BRAIN : SYM_COFFEE);
        lv_obj_center(s_icon);
    }

    if (look_changed) {
        s_shown_accent = t->accent;
        s_accent_valid = true;
        const bool     paused = state == STATE_PAUSED;
        const lv_opa_t opa = paused ? LV_OPA_40 : LV_OPA_COVER;
        lv_label_set_text(s_mode, paused ? "หยุดชั่วคราว" : MODE_NAME[s_cur_mode]);
        lv_obj_set_style_text_color(s_mode, paused ? COLOR_TEXT_DIM : t->accent, 0);
        lv_obj_set_style_text_opa(s_time, opa, 0);
        lv_obj_set_style_arc_color(s_arc, t->accent, LV_PART_INDICATOR);
        lv_obj_set_style_arc_opa(s_arc, opa, LV_PART_INDICATOR);
        lv_obj_set_style_text_color(s_icon, state == STATE_IDLE ? COLOR_TEXT_DIM : t->accent, 0);
        s_shown_state = state;
        s_shown_mode = s_cur_mode;
        s_shown_done = -1;
    }

    if (s_shown_done != s_done) {
        s_shown_done = s_done;
        paint_dots(t->accent);
    }
}

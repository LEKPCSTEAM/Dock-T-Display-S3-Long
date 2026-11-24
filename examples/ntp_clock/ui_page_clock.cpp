#include <stdio.h>
#include <string.h>
#include "ui_internal.h"

#define CELL_W        84
#define COLON_W       28
#define CELL_Y        28
#define TIME_X        16
#define ROLL_MS       350
#define ROLL_TRAVEL   48
#define BOUNCE_MS     700
#define BOUNCE_HEIGHT 18
#define SWEEP_MS      1400
#define BAR_H         5
#define PANEL_X       462
#define PANEL_Y       8
#define PANEL_W       170
#define PANEL_H       159
#define PANEL_PAD_L   16
#define PANEL_INNER_W 146
#define COLON_DIM_OPA 70
#define NIGHT_DIGIT   0x9A2A18
#define CITY_UNSET    "\x01"  // never equals a real city, so the hint always refreshes

struct Digit {
    lv_obj_t *cell;
    lv_obj_t *cur;
    lv_obj_t *old;
    int       shown;  // -2 unset, -1 blank, else 0..9
};

static const char *const THEME_NAME[THEME_COUNT] = {"สีประจำวัน", "สีรุ้ง", "ขาวเรียบ"};

static lv_obj_t *time_area;
static Digit     digits[4];
static lv_obj_t *colon;
static lv_obj_t *placeholder;
static lv_obj_t *sec_label;
static lv_obj_t *hint_label;
static lv_obj_t *stripe;
static lv_obj_t *wifi_icon;
static lv_obj_t *sat_icon;
static lv_obj_t *day_label;
static lv_obj_t *date_label;
static lv_obj_t *wx_icon;
static lv_obj_t *wx_temp;
static lv_obj_t *wx_text;
static lv_obj_t *bar;

static bool       stale = true;
static int        c_valid = -1;
static int        c_sec = -1;
static int        c_colon = -1;
static int        c_night = -1;
static int        c_wday = -1;
static int        c_date = -1;
static int        c_bar = -1;
static int        c_net_key = -1;
static long       c_wx_key = -1;
static char       c_city[48];
static uint16_t   c_accent = 0xFFFF;
static bool       c_accent_set;
static bool       sweeping;

static void set_hidden(lv_obj_t *o, bool hide)
{
    if (hide) {
        lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_clear_flag(o, LV_OBJ_FLAG_HIDDEN);
    }
}

static void set_text_if(lv_obj_t *label, const char *text)
{
    if (strcmp(lv_label_get_text(label), text) != 0) {
        lv_label_set_text(label, text);
    }
}

static void digit_text(lv_obj_t *label, int d)
{
    char s[2] = {d >= 0 ? (char)('0' + d) : '\0', '\0'};
    lv_label_set_text(label, s);
}

static void roll_cb(void *var, int32_t v)
{
    Digit *d = (Digit *)var;
    lv_obj_set_style_translate_y(d->cur, ROLL_TRAVEL * (255 - v) / 255, 0);
    lv_obj_set_style_opa(d->cur, (lv_opa_t)v, 0);
    lv_obj_set_style_translate_y(d->old, -ROLL_TRAVEL * v / 255, 0);
    lv_obj_set_style_opa(d->old, (lv_opa_t)(255 - v), 0);
}

static void roll_done_cb(lv_anim_t *a)
{
    lv_obj_add_flag(((Digit *)a->var)->old, LV_OBJ_FLAG_HIDDEN);
}

static void digit_set(Digit *d, int value, bool animate)
{
    if (d->shown == value) {
        return;
    }
    int prev = d->shown;
    d->shown = value;
    lv_anim_del(d, roll_cb);
    digit_text(d->cur, value);
    if (!animate || prev == -2) {
        lv_obj_set_style_translate_y(d->cur, 0, 0);
        lv_obj_set_style_opa(d->cur, LV_OPA_COVER, 0);
        lv_obj_add_flag(d->old, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    digit_text(d->old, prev);
    lv_obj_clear_flag(d->old, LV_OBJ_FLAG_HIDDEN);
    roll_cb(d, 0);

    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, d);
    lv_anim_set_exec_cb(&a, roll_cb);
    lv_anim_set_values(&a, 0, 255);
    lv_anim_set_time(&a, ROLL_MS);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_out);
    lv_anim_set_ready_cb(&a, roll_done_cb);
    lv_anim_start(&a);
}

static void bounce_cb(void *var, int32_t v)
{
    int y = -(lv_trigo_sin((int16_t)(v * 180 / 1000)) * BOUNCE_HEIGHT) / 32767;
    lv_obj_set_style_translate_y((lv_obj_t *)var, y, 0);
}

static void bounce_digits()
{
    for (int i = 0; i < 4; i++) {
        lv_anim_t a;
        lv_anim_init(&a);
        lv_anim_set_var(&a, digits[i].cell);
        lv_anim_set_exec_cb(&a, bounce_cb);
        lv_anim_set_values(&a, 0, 1000);
        lv_anim_set_delay(&a, i * 70);
        lv_anim_set_time(&a, BOUNCE_MS);
        lv_anim_set_path_cb(&a, lv_anim_path_linear);
        lv_anim_start(&a);
    }
}

static void sweep_cb(void *, int32_t v)
{
    lv_bar_set_value(bar, v, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(bar, lv_color_hsv_to_rgb(v * 360 / SCREEN_W, 80, 100), LV_PART_INDICATOR);
}

static void sweep_done_cb(lv_anim_t *)
{
    sweeping = false;
    c_bar    = -1;
    c_accent_set = false;
}

static void start_sweep()
{
    sweeping = true;
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, bar);
    lv_anim_set_exec_cb(&a, sweep_cb);
    lv_anim_set_values(&a, 0, SCREEN_W);
    lv_anim_set_time(&a, SWEEP_MS);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_in_out);
    lv_anim_set_ready_cb(&a, sweep_done_cb);
    lv_anim_start(&a);
}

static void tap_cb(lv_event_t *)
{
    ClockSettings s = settings_get();
    s.theme = (s.theme + 1) % THEME_COUNT;
    settings_set(s);
    ui_toast(THEME_NAME[s.theme]);
}

static lv_obj_t *make_row(lv_obj_t *parent, lv_flex_flow_t flow)
{
    lv_obj_t *row = lv_obj_create(parent);
    ui_strip_obj(row);
    lv_obj_clear_flag(row, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(row, PANEL_INNER_W, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(row, flow);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    return row;
}

static lv_obj_t *scrolling_label(lv_obj_t *parent, const lv_font_t *font, lv_color_t color, lv_coord_t w)
{
    lv_obj_t *l = ui_label(parent, font, color, "");
    lv_label_set_long_mode(l, LV_LABEL_LONG_SCROLL_CIRCULAR);
    lv_obj_set_width(l, w);
    return l;
}

void page_clock_create(lv_obj_t *tile)
{
    time_area = lv_obj_create(tile);
    ui_strip_obj(time_area);
    lv_obj_set_pos(time_area, 0, 0);
    lv_obj_set_size(time_area, PANEL_X - 4, SCREEN_H - BAR_H);
    lv_obj_add_event_cb(time_area, tap_cb, LV_EVENT_CLICKED, NULL);

    lv_coord_t x = TIME_X;
    for (int i = 0; i < 4; i++) {
        Digit *d = &digits[i];
        d->shown = -2;
        d->cell  = lv_obj_create(time_area);
        ui_strip_obj(d->cell);
        lv_obj_clear_flag(d->cell, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_pos(d->cell, x, CELL_Y);
        lv_obj_set_size(d->cell, CELL_W, ui_font_digits_128.line_height);
        d->old = ui_label(d->cell, &ui_font_digits_128, COLOR_TEXT, "");
        d->cur = ui_label(d->cell, &ui_font_digits_128, COLOR_TEXT, "");
        lv_obj_t *pair[2] = {d->old, d->cur};
        for (int k = 0; k < 2; k++) {
            lv_obj_set_width(pair[k], CELL_W);
            lv_obj_set_style_text_align(pair[k], LV_TEXT_ALIGN_CENTER, 0);
            lv_obj_set_pos(pair[k], 0, 0);
        }
        lv_obj_add_flag(d->old, LV_OBJ_FLAG_HIDDEN);
        x += CELL_W;
        if (i == 1) {
            colon = ui_label(time_area, &ui_font_digits_128, COLOR_TEXT, ":");
            lv_obj_set_width(colon, COLON_W);
            lv_obj_set_style_text_align(colon, LV_TEXT_ALIGN_CENTER, 0);
            lv_obj_set_pos(colon, x, CELL_Y);
            x += COLON_W;
        }
    }

    placeholder = ui_label(time_area, &ui_font_digits_56, COLOR_TEXT_DIM, "--:--");
    lv_obj_set_pos(placeholder, TIME_X, CELL_Y + (ui_font_digits_128.line_height - ui_font_digits_56.line_height) / 2);

    lv_coord_t base128 = ui_font_digits_128.line_height - ui_font_digits_128.base_line;
    lv_coord_t base56  = ui_font_digits_56.line_height - ui_font_digits_56.base_line;
    lv_coord_t sec_y   = CELL_Y + base128 - base56;
    sec_label = ui_label(time_area, &ui_font_digits_56, COLOR_TEXT, "00");
    lv_obj_set_pos(sec_label, x + 2, sec_y);

    hint_label = ui_label(time_area, &ui_font_th_16, COLOR_TEXT_DIM, "");
    lv_obj_set_pos(hint_label, TIME_X + 4, CELL_Y + ui_font_digits_128.line_height + 10);

    lv_obj_t *panel = lv_obj_create(tile);
    ui_strip_obj(panel);
    lv_obj_clear_flag(panel, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(panel, PANEL_X, PANEL_Y);
    lv_obj_set_size(panel, PANEL_W, PANEL_H);
    lv_obj_set_style_bg_color(panel, COLOR_PANEL, 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(panel, 16, 0);
    lv_obj_set_style_pad_left(panel, PANEL_PAD_L, 0);
    lv_obj_set_style_pad_top(panel, 8, 0);
    lv_obj_set_style_pad_row(panel, 4, 0);
    lv_obj_set_flex_flow(panel, LV_FLEX_FLOW_COLUMN);

    stripe = lv_obj_create(panel);
    ui_strip_obj(stripe);
    lv_obj_add_flag(stripe, LV_OBJ_FLAG_FLOATING);
    lv_obj_clear_flag(stripe, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(stripe, 7 - PANEL_PAD_L, 6);  // floating pos is relative to the padded content box
    lv_obj_set_size(stripe, 3, PANEL_H - 28);
    lv_obj_set_style_radius(stripe, 2, 0);
    lv_obj_set_style_bg_opa(stripe, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(stripe, COLOR_TEXT_DIM, 0);

    lv_obj_t *icons = make_row(panel, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(icons, 12, 0);
    wifi_icon = ui_label(icons, &ui_font_th_16, COLOR_WARN, LV_SYMBOL_WIFI);
    sat_icon  = ui_label(icons, &ui_font_th_16, COLOR_TEXT_DIM, SYM_SATELLITE);

    day_label  = scrolling_label(panel, &ui_font_th_32, COLOR_TEXT, PANEL_INNER_W);
    date_label = scrolling_label(panel, &ui_font_th_22, COLOR_TEXT, PANEL_INNER_W);

    lv_obj_t *wx = make_row(panel, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(wx, 6, 0);
    wx_icon = ui_label(wx, &ui_font_th_22, COLOR_TEXT, "");
    wx_temp = ui_label(wx, &ui_font_th_22, COLOR_TEXT, "");
    wx_text = scrolling_label(wx, &ui_font_th_16, COLOR_TEXT_DIM, 70);

    bar = lv_bar_create(tile);
    lv_obj_remove_style_all(bar);
    lv_obj_set_pos(bar, 0, SCREEN_H - BAR_H);
    lv_obj_set_size(bar, SCREEN_W, BAR_H);
    lv_bar_set_range(bar, 0, SCREEN_W);
    lv_obj_set_style_bg_color(bar, COLOR_PANEL, LV_PART_MAIN);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(bar, COLOR_TEXT_DIM, LV_PART_INDICATOR);
}

static void apply_accent(lv_color_t c)
{
    lv_obj_set_style_text_color(sec_label, c, 0);
    lv_obj_set_style_text_color(day_label, c, 0);
    lv_obj_set_style_text_color(wx_icon, c, 0);
    lv_obj_set_style_bg_color(stripe, c, 0);
    if (!sweeping) {
        lv_obj_set_style_bg_color(bar, c, LV_PART_INDICATOR);
    }
}

static void apply_digit_color(bool night)
{
    lv_color_t c = night ? lv_color_hex(NIGHT_DIGIT) : COLOR_TEXT;
    for (int i = 0; i < 4; i++) {
        lv_obj_set_style_text_color(digits[i].cur, c, 0);
        lv_obj_set_style_text_color(digits[i].old, c, 0);
    }
    lv_obj_set_style_text_color(colon, c, 0);
}

static void apply_validity(bool valid)
{
    for (int i = 0; i < 4; i++) {
        set_hidden(digits[i].cell, !valid);
        if (!valid) {
            digits[i].shown = -2;
        }
    }
    set_hidden(colon, !valid);
    set_hidden(sec_label, !valid);
    set_hidden(placeholder, valid);
    if (!valid) {
        set_text_if(hint_label, "กำลังรอซิงค์เวลา…");
        strcpy(c_city, CITY_UNSET);
        set_text_if(day_label, "วัน-");
        set_text_if(date_label, "--");
        c_wday = c_date = -1;
    }
}

static void update_net_icons(const UiTick *t)
{
    int key = (int)t->net->phase * 2 + (t->net->time_synced ? 1 : 0);
    if (key == c_net_key) {
        return;
    }
    c_net_key = key;
    switch (t->net->phase) {
    case NET_CONNECTED:
        lv_label_set_text(wifi_icon, LV_SYMBOL_WIFI);
        lv_obj_set_style_text_color(wifi_icon, COLOR_OK, 0);
        break;
    case NET_PORTAL:
        lv_label_set_text(wifi_icon, SYM_QRCODE);
        lv_obj_set_style_text_color(wifi_icon, COLOR_WARN, 0);
        break;
    default:
        lv_label_set_text(wifi_icon, LV_SYMBOL_WIFI);
        lv_obj_set_style_text_color(wifi_icon, COLOR_WARN, 0);
        break;
    }
    lv_obj_set_style_text_color(sat_icon, t->net->time_synced ? COLOR_OK : COLOR_TEXT_DIM, 0);
}

static void update_weather(const UiTick *t)
{
    const WeatherInfo *w = &t->net->weather;
    long key = w->valid ? 1 + (long)(int)(w->temp_c * 2) * 4096L + w->code * 2L + (w->is_day ? 1 : 0) : 0;
    if (key == c_wx_key) {
        return;
    }
    c_wx_key = key;
    if (!w->valid) {
        lv_label_set_text(wx_icon, "");
        lv_label_set_text(wx_temp, "—");
        lv_label_set_text(wx_text, "");
        return;
    }
    char buf[16];
    snprintf(buf, sizeof(buf), "%d°", (int)(w->temp_c + (w->temp_c < 0 ? -0.5f : 0.5f)));
    lv_label_set_text(wx_icon, ui_weather_icon(w->code, w->is_day));
    lv_label_set_text(wx_temp, buf);
    lv_label_set_text(wx_text, ui_weather_text(w->code));
}

static void update_info(const UiTick *t)
{
    update_net_icons(t);
    update_weather(t);
    if (!t->time_valid) {
        return;
    }
    if (t->now.tm_wday != c_wday) {
        c_wday = t->now.tm_wday;
        char buf[48];
        snprintf(buf, sizeof(buf), "%s", TH_DAY_NAME[c_wday % 7]);
        lv_label_set_text(day_label, buf);
    }
    int date_key = t->now.tm_year * 400 + t->now.tm_mon * 32 + t->now.tm_mday;
    if (date_key != c_date) {
        c_date = date_key;
        char buf[48];
        snprintf(buf, sizeof(buf), "%d %s %d", t->now.tm_mday, TH_MONTH_SHORT[t->now.tm_mon % 12], ui_be_year(&t->now));
        lv_label_set_text(date_label, buf);
    }
    if (strcmp(c_city, t->settings->city) != 0) {
        snprintf(c_city, sizeof(c_city), "%s", t->settings->city);
        if (c_city[0]) {
            char buf[64];
            snprintf(buf, sizeof(buf), SYM_PIN " %s", c_city);
            lv_label_set_text(hint_label, buf);
        } else {
            lv_label_set_text(hint_label, "");
        }
    }
}

void page_clock_update(const UiTick *t)
{
    if (!t->active) {
        stale = true;
        return;
    }
    bool snap = stale;
    if (snap) {
        stale    = false;
        c_valid  = -1;
        c_sec    = c_colon = c_night = c_bar = -1;
        c_wday   = c_date = -1;
        c_net_key = -1;
        c_wx_key  = -1;
        strcpy(c_city, CITY_UNSET);
        c_accent_set = false;
    }

    if ((int)t->time_valid != c_valid) {
        c_valid = t->time_valid;
        apply_validity(t->time_valid);
    }
    if (!c_accent_set || t->accent.full != c_accent) {
        c_accent     = t->accent.full;
        c_accent_set = true;
        apply_accent(t->accent);
    }
    if ((int)t->night != c_night) {
        c_night = t->night;
        apply_digit_color(t->night);
    }
    update_info(t);

    if (!t->time_valid) {
        return;
    }

    int h = t->now.tm_hour;
    digit_set(&digits[0], h / 10, !snap);
    digit_set(&digits[1], h % 10, !snap);
    digit_set(&digits[2], t->now.tm_min / 10, !snap);
    digit_set(&digits[3], t->now.tm_min % 10, !snap);

    int colon_on = t->ms < 500;
    if (colon_on != c_colon) {
        c_colon = colon_on;
        lv_obj_set_style_opa(colon, colon_on ? LV_OPA_COVER : COLON_DIM_OPA, 0);
    }

    if (t->now.tm_sec != c_sec) {
        c_sec = t->now.tm_sec;
        char buf[4];
        snprintf(buf, sizeof(buf), "%02d", c_sec);
        lv_label_set_text(sec_label, buf);
    }

    if (!snap && !t->night && t->new_second && t->now.tm_min == 0 && t->now.tm_sec == 0) {
        bounce_digits();
        start_sweep();
    }

    if (!sweeping) {
        int pos = (t->now.tm_sec * 1000 + t->ms) * SCREEN_W / 60000;
        if (pos != c_bar) {
            c_bar = pos;
            lv_bar_set_value(bar, pos, LV_ANIM_OFF);
        }
    }
}

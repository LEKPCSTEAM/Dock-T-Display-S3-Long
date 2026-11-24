#include <math.h>
#include <stdio.h>
#include <string.h>
#include "ui_internal.h"
#include "deck_net.h"

#define CELL_W       80
#define CELL_H       90
#define CELL_PAD     3
#define OFFLINE_OPA  102
#define INNER_PAD    12
#define MUTE_MAX     56
#define MAX_LIVE     (DECK_MAX_PAGES * DECK_MAX_WIDGETS)

struct LiveWidget {
    lv_obj_t        *box;
    lv_obj_t        *name;
    lv_obj_t        *text;
    lv_obj_t        *unit;
    lv_obj_t        *bar;
    lv_obj_t        *chart;
    lv_obj_t        *btn;
    lv_obj_t        *btn_label;
    lv_obj_t        *slider;
    lv_chart_series_t *ser;
    DeckSliderGate   gate;
    char             id[16];
    uint8_t          type;
    uint8_t          metric;
    uint8_t          style;
    uint8_t          w;
    bool             clock_fresh;
};

static LiveWidget  widgets[MAX_LIVE];
static int         widget_count;
static int         mac_count;

static DeckStats   stats;
static DeckHistory hist;
static DeckVolume  vol;
static bool        stats_ok;
static bool        vol_ok;

static bool        live_dirty = true;
static uint32_t    seen_version;
static bool        seen_ready;
static uint32_t    seen_accent = UINT32_MAX;
static uint32_t    clock_accent = UINT32_MAX;
static bool        clock_valid;

static const DeckStats empty_stats = {};

static bool is_rate(uint8_t metric)
{
    return metric == DM_NET_DOWN || metric == DM_NET_UP || metric == DM_DISK_IO;
}

static void no_click(lv_obj_t *o)
{
    lv_obj_clear_flag(o, LV_OBJ_FLAG_CLICKABLE);
}

static lv_obj_t *child_label(lv_obj_t *parent, const lv_font_t *font, lv_color_t color, const char *text)
{
    lv_obj_t *l = ui_label(parent, font, color, text);
    no_click(l);
    return l;
}

static const lv_font_t *pick_font(bool allow_digits, const char *widest, lv_coord_t avail)
{
    const lv_font_t *cands[3];
    int n = 0;
    if (allow_digits) {
        cands[n++] = &ui_font_digits_56;
    }
    cands[n++] = &ui_font_th_32;
    cands[n++] = &ui_font_th_22;
    for (int i = 0; i < n; i++) {
        lv_point_t sz;
        lv_txt_get_size(&sz, widest, cands[i], 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
        if (sz.x <= avail) {
            return cands[i];
        }
    }
    return &ui_font_th_22;
}

static void join_text(char *out, size_t n, const char *val, const char *unit)
{
    char c = unit[0];
    bool letter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    snprintf(out, n, letter ? "%s %s" : "%s%s", val, unit);
}

static void slider_cb(lv_event_t *e)
{
    LiveWidget *lw = (LiveWidget *)lv_event_get_user_data(e);
    if (lv_obj_has_state(lw->slider, LV_STATE_DISABLED)) {
        return;
    }
    int v = lv_slider_get_value(lw->slider);
    if (lv_event_get_code(e) == LV_EVENT_VALUE_CHANGED && lw->text) {
        lv_label_set_text_fmt(lw->text, "%d%%", v);
    }
    int out;
    if (deck_slider_offer(&lw->gate, lv_tick_get(), v, &out)) {
        deck_net_slider(lw->id, (uint8_t)out);
    }
}

static void mute_cb(lv_event_t *e)
{
    LiveWidget *lw = (LiveWidget *)lv_event_get_user_data(e);
    if (deck_net_ready() && vol_ok && vol.available) {
        deck_net_press(lw->id, false);
    }
}

static lv_obj_t *box_create(lv_obj_t *tile, const DeckWidget *w, lv_coord_t *bw, lv_coord_t *bh)
{
    *bw = w->w * CELL_W - 2 * CELL_PAD;
    *bh = w->h * CELL_H - 2 * CELL_PAD;
    lv_obj_t *box = lv_obj_create(tile);
    ui_strip_obj(box);
    lv_obj_set_pos(box, w->col * CELL_W + CELL_PAD, w->row * CELL_H + CELL_PAD);
    lv_obj_set_size(box, *bw, *bh);
    lv_obj_set_style_bg_color(box, COLOR_PANEL, 0);
    lv_obj_set_style_bg_opa(box, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(box, 8, 0);
    no_click(box);
    lv_obj_add_flag(box, LV_OBJ_FLAG_GESTURE_BUBBLE);
    return box;
}

static void stat_create(LiveWidget *lw, lv_coord_t bw, lv_coord_t bh)
{
    lv_coord_t inner = bw - INNER_PAD;
    lw->name = child_label(lw->box, &ui_font_th_16, COLOR_TEXT_DIM, deck_metric_label(lw->metric));
    bool narrow = lw->w < 2;
    lv_obj_align(lw->name, LV_ALIGN_TOP_LEFT, 6, narrow && lw->style != DS_BAR ? 0 : 4);

    if (lw->style == DS_NUMBER) {
        const lv_font_t *f = narrow ? &ui_font_th_22
                                    : pick_font(true, is_rate(lw->metric) ? "888" : "100", inner);
        lw->text = child_label(lw->box, f, COLOR_TEXT, "--");
        lw->unit = child_label(lw->box, &ui_font_th_16, COLOR_TEXT_DIM, "");
        if (narrow) {
            lv_obj_align(lw->text, LV_ALIGN_TOP_MID, 0, 25);
            lv_obj_align(lw->unit, LV_ALIGN_TOP_MID, 0, 58);
        } else {
            lv_obj_align(lw->text, LV_ALIGN_CENTER, 0, 8);
        }
    } else if (lw->style == DS_SPARKLINE) {
        lw->text = child_label(lw->box, &ui_font_th_16, COLOR_TEXT, "--");
        if (narrow) {
            lv_obj_align(lw->text, LV_ALIGN_TOP_MID, 0, 25);
        } else {
            lv_obj_align(lw->text, LV_ALIGN_TOP_RIGHT, -6, 4);
        }
        lv_obj_t *c = lv_chart_create(lw->box);
        no_click(c);
        lv_obj_set_size(c, inner, bh - (narrow ? 58 : 34));
        lv_obj_align(c, LV_ALIGN_BOTTOM_MID, 0, -6);
        lv_chart_set_type(c, LV_CHART_TYPE_LINE);
        lv_chart_set_point_count(c, DECK_HISTORY_LEN);
        lv_chart_set_range(c, LV_CHART_AXIS_PRIMARY_Y, 0, 100);
        lv_chart_set_div_line_count(c, 0, 0);
        lv_obj_set_style_bg_opa(c, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(c, 0, 0);
        lv_obj_set_style_pad_all(c, 0, 0);
        lv_obj_set_style_size(c, 0, LV_PART_INDICATOR);
        lv_obj_set_style_line_width(c, 2, LV_PART_ITEMS);
        lw->ser = lv_chart_add_series(c, COLOR_TEXT, LV_CHART_AXIS_PRIMARY_Y);
        lw->chart = c;
    } else {
        lw->text = child_label(lw->box, &ui_font_th_22, COLOR_TEXT, "--");
        if (lw->w >= 2) {
            lv_obj_align(lw->text, LV_ALIGN_TOP_RIGHT, -6, 2);
        } else {
            lv_obj_align(lw->text, LV_ALIGN_TOP_MID, 0, 29);
        }
        lv_obj_t *b = lv_bar_create(lw->box);
        no_click(b);
        lv_obj_set_size(b, inner, 10);
        lv_obj_align(b, LV_ALIGN_BOTTOM_MID, 0, -8);
        lv_bar_set_range(b, 0, 100);
        lv_obj_set_style_bg_color(b, COLOR_PANEL_HI, LV_PART_MAIN);
        lv_obj_set_style_bg_opa(b, LV_OPA_COVER, LV_PART_MAIN);
        lv_obj_set_style_bg_opa(b, LV_OPA_COVER, LV_PART_INDICATOR);
        lw->bar = b;
    }
}

static void volume_create(LiveWidget *lw, lv_coord_t bw, lv_coord_t bh)
{
    lv_coord_t side = bh - INNER_PAD < MUTE_MAX ? bh - INNER_PAD : MUTE_MAX;

    lw->btn = lv_obj_create(lw->box);
    ui_strip_obj(lw->btn);
    lv_obj_set_size(lw->btn, side, side);
    lv_obj_set_style_bg_color(lw->btn, COLOR_PANEL_HI, 0);
    lv_obj_set_style_bg_opa(lw->btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(lw->btn, 8, 0);
    lv_obj_add_flag(lw->btn, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_flag(lw->btn, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_event_cb(lw->btn, mute_cb, LV_EVENT_SHORT_CLICKED, lw);
    lw->btn_label = child_label(lw->btn, &ui_font_th_22, COLOR_TEXT, LV_SYMBOL_VOLUME_MAX);
    lv_obj_center(lw->btn_label);

    lw->text = child_label(lw->box, &ui_font_th_16, COLOR_TEXT_DIM, "--");

    if (lw->w >= 2) {
        lv_obj_align(lw->btn, LV_ALIGN_LEFT_MID, 6, 0);
        lv_obj_align(lw->text, LV_ALIGN_TOP_RIGHT, -6, 4);
        lv_coord_t x = 6 + side + 10;
        lv_obj_t *s = lv_slider_create(lw->box);
        lv_obj_set_size(s, bw - x - 12, 12);
        lv_obj_align(s, LV_ALIGN_LEFT_MID, x, 0);
        lv_slider_set_range(s, 0, 100);
        lv_obj_clear_flag(s, LV_OBJ_FLAG_SCROLL_CHAIN);
        lv_obj_set_ext_click_area(s, 14);
        lv_obj_set_style_bg_color(s, COLOR_PANEL_HI, LV_PART_MAIN);
        lv_obj_set_style_bg_color(s, COLOR_TEXT, LV_PART_KNOB);
        lv_obj_set_style_opa(s, OFFLINE_OPA, LV_STATE_DISABLED);
        lv_obj_add_event_cb(s, slider_cb, LV_EVENT_VALUE_CHANGED, lw);
        lv_obj_add_event_cb(s, slider_cb, LV_EVENT_RELEASED, lw);
        lw->slider = s;
        deck_slider_reset(&lw->gate);
    } else {
        lv_obj_align(lw->btn, LV_ALIGN_TOP_MID, 0, 2);
        lv_obj_align(lw->text, LV_ALIGN_BOTTOM_MID, 0, -1);
    }
}

static void clock_create(LiveWidget *lw, lv_coord_t bw)
{
    const lv_font_t *f = pick_font(lw->w >= 2, "88:88", bw - INNER_PAD);
    lw->text = child_label(lw->box, f, COLOR_TEXT, "--:--");
    lv_obj_center(lw->text);
    lw->clock_fresh = true;
}

void ui_live_reset()
{
    widget_count = 0;
    mac_count    = 0;
    live_dirty   = true;
}

bool ui_live_create(lv_obj_t *tile, const DeckWidget *w)
{
    if (w->type != DW_STAT && w->type != DW_VOLUME && w->type != DW_CLOCK) {
        return false;
    }
    lv_coord_t bw, bh;
    lv_obj_t *box = box_create(tile, w, &bw, &bh);
    if (widget_count >= MAX_LIVE) {
        return true;
    }
    LiveWidget *lw = &widgets[widget_count++];
    memset(lw, 0, sizeof(*lw));
    lw->box    = box;
    lw->type   = w->type;
    lw->metric = w->metric;
    lw->style  = w->style;
    lw->w      = w->w;
    snprintf(lw->id, sizeof(lw->id), "%s", w->id);

    if (w->type == DW_STAT) {
        stat_create(lw, bw, bh);
        mac_count++;
    } else if (w->type == DW_VOLUME) {
        volume_create(lw, bw, bh);
        mac_count++;
    } else {
        clock_create(lw, bw);
    }
    return true;
}

static void stat_refresh(LiveWidget *lw, const UiTick *t, bool ready)
{
    const DeckStats *s = ready && stats_ok ? &stats : &empty_stats;
    char val[24], unit[8], joined[40];
    deck_live_format(lw->metric, s, val, sizeof(val), unit, sizeof(unit));

    if (lw->style == DS_NUMBER) {
        lv_label_set_text(lw->text, val);
        lv_label_set_text(lw->unit, unit);
        if (lw->w >= 2) {
            lv_obj_update_layout(lw->box);
            lv_obj_align_to(lw->unit, lw->text, LV_ALIGN_OUT_RIGHT_BOTTOM, 4, -4);
        }
        return;
    }

    if (lw->w < 2 && is_rate(lw->metric)) {
        snprintf(joined, sizeof(joined), "%s%c", val, unit[0] ? unit[0] : '\0');
    } else {
        join_text(joined, sizeof(joined), val, unit);
    }
    lv_label_set_text(lw->text, joined);
    bool known = s->valid & (1u << lw->metric);
    float peak = known ? deck_history_max(&hist, lw->metric) : 0;

    if (lw->style == DS_BAR) {
        lv_obj_set_style_bg_color(lw->bar, COLOR_PANEL_HI, LV_PART_MAIN);
        lv_obj_set_style_bg_color(lw->bar, t->accent, LV_PART_INDICATOR);
        lv_bar_set_value(lw->bar, known ? deck_live_level(lw->metric, s->v[lw->metric], peak) : 0, LV_ANIM_OFF);
        return;
    }

    lv_chart_set_series_color(lw->chart, lw->ser, t->accent);
    lv_chart_set_all_value(lw->chart, lw->ser, LV_CHART_POINT_NONE);
    if (ready && stats_ok) {
        float series[DECK_HISTORY_LEN];
        uint8_t n = deck_history_series(&hist, lw->metric, series);
        if (n > DECK_HISTORY_LEN) {
            n = DECK_HISTORY_LEN;
        }
        for (uint8_t i = 0; i < n; i++) {
            if (!isnan(series[i])) {
                lv_chart_set_value_by_id(lw->chart, lw->ser, DECK_HISTORY_LEN - n + i,
                                         deck_live_level(lw->metric, series[i], peak));
            }
        }
    }
    lv_chart_refresh(lw->chart);
}

static void volume_refresh(LiveWidget *lw, const UiTick *t, bool ready)
{
    bool known = ready && vol_ok;
    lv_obj_set_style_bg_color(lw->btn, COLOR_PANEL_HI, 0);
    lv_label_set_text(lw->btn_label, known && vol.muted ? LV_SYMBOL_MUTE : LV_SYMBOL_VOLUME_MAX);

    if (!known) {
        lv_label_set_text(lw->text, "--");
    } else if (!vol.available) {
        lv_label_set_text(lw->text, lw->w >= 2 ? "unavailable" : "n/a");
    } else {
        lv_label_set_text_fmt(lw->text, "%d%%", vol.level);
    }
    if (!lw->slider) {
        return;
    }
    lv_obj_set_style_bg_color(lw->slider, known && vol.muted ? COLOR_TEXT_DIM : t->accent, LV_PART_INDICATOR);
    if (known && !vol.available) {
        lv_obj_add_flag(lw->slider, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_clear_flag(lw->slider, LV_OBJ_FLAG_HIDDEN);
    if (!known) {
        lv_obj_add_state(lw->slider, LV_STATE_DISABLED);
        return;
    }
    lv_obj_clear_state(lw->slider, LV_STATE_DISABLED);
    if (!lv_slider_is_dragged(lw->slider)) {
        lv_slider_set_value(lw->slider, vol.level, LV_ANIM_OFF);
    }
}

static void clock_refresh(LiveWidget *lw, const UiTick *t)
{
    lv_obj_set_style_text_color(lw->text, t->accent, 0);
    if (t->time_valid) {
        lv_label_set_text_fmt(lw->text, "%02d:%02d", t->now.tm_hour, t->now.tm_min);
    } else {
        lv_label_set_text(lw->text, "--:--");
    }
}

void ui_live_update(const UiTick *t, bool ready)
{
    if (widget_count == 0) {
        return;
    }
    uint32_t accent = lv_color_to32(t->accent);

    if (mac_count > 0) {
        uint32_t ver = deck_net_live_version();
        if (live_dirty || ver != seen_version || ready != seen_ready || accent != seen_accent) {
            live_dirty   = false;
            seen_version = ver;
            seen_ready   = ready;
            seen_accent  = accent;
            stats_ok = deck_net_stats(&stats, &hist);
            vol_ok   = deck_net_volume(&vol);
            for (int i = 0; i < widget_count; i++) {
                LiveWidget *lw = &widgets[i];
                lv_opa_t opa = ready ? LV_OPA_COVER : OFFLINE_OPA;
                if (lw->type == DW_STAT) {
                    lv_obj_set_style_opa(lw->box, opa, 0);
                    stat_refresh(lw, t, ready);
                } else if (lw->type == DW_VOLUME) {
                    lv_obj_set_style_opa(lw->box, opa, 0);
                    volume_refresh(lw, t, ready);
                }
            }
        }
        for (int i = 0; i < widget_count; i++) {
            LiveWidget *lw = &widgets[i];
            int out;
            if (lw->type == DW_VOLUME && lw->slider && deck_slider_poll(&lw->gate, lv_tick_get(), &out)) {
                deck_net_slider(lw->id, (uint8_t)out);
            }
        }
    }

    bool redraw = t->new_second || accent != clock_accent || t->time_valid != clock_valid;
    clock_accent = accent;
    clock_valid  = t->time_valid;
    for (int i = 0; i < widget_count; i++) {
        LiveWidget *lw = &widgets[i];
        if (lw->type == DW_CLOCK && (redraw || lw->clock_fresh)) {
            lw->clock_fresh = false;
            clock_refresh(lw, t);
        }
    }
}

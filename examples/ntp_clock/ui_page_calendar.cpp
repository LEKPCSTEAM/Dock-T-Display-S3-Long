#include "ui_internal.h"

#include <stdio.h>
#include <string.h>

namespace {

struct Holiday {
    uint8_t     month;  // 1..12
    uint8_t     day;
    const char *name;
};

const Holiday HOLIDAYS[] = {
    {1, 1, "วันขึ้นปีใหม่"},
    {4, 6, "วันจักรี"},
    {4, 13, "วันสงกรานต์"},
    {5, 1, "วันแรงงานแห่งชาติ"},
    {5, 4, "วันฉัตรมงคล"},
    {6, 3, "วันเฉลิมฯ พระราชินี"},
    {7, 28, "วันเฉลิมฯ ร.10"},
    {8, 12, "วันแม่แห่งชาติ"},
    {10, 13, "วันนวมินทรมหาราช"},
    {10, 23, "วันปิยมหาราช"},
    {12, 5, "วันพ่อแห่งชาติ"},
    {12, 10, "วันรัฐธรรมนูญ"},
    {12, 31, "วันสิ้นปี"},
};

const char *const CHILDREN_DAY = "วันเด็กแห่งชาติ";

lv_obj_t            *s_meter;
lv_meter_indicator_t *s_hour_needle;
lv_meter_indicator_t *s_min_needle;
lv_meter_indicator_t *s_sec_needle;

lv_obj_t *s_date;
lv_obj_t *s_year;
lv_obj_t *s_doy;
lv_obj_t *s_bar;
lv_obj_t *s_progress;
lv_obj_t *s_gift;
lv_obj_t *s_holiday;

char s_date_txt[64];
char s_year_txt[48];
char s_doy_txt[64];
char s_progress_txt[48];
char s_holiday_txt[96];

int32_t    s_hour_val = -1;
int32_t    s_min_val = -1;
int32_t    s_sec_val = -1;
int        s_bar_val = -1;
bool       s_holiday_today;
bool       s_text_ready;
bool       s_was_valid;
lv_color_t s_accent;
bool       s_accent_init;

bool is_leap(int y)
{
    return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
}

// Days since 1970-01-01 (proleptic Gregorian).
int32_t days_from_civil(int y, int m, int d)
{
    y -= m <= 2;
    const int era = (y >= 0 ? y : y - 399) / 400;
    const int yoe = y - era * 400;
    const int doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

int weekday_of(int y, int m, int d)
{
    return (int)(((days_from_civil(y, m, d) + 4) % 7 + 7) % 7);
}

int iso_weeks_in_year(int y)
{
    auto p = [](int yr) { return (yr + yr / 4 - yr / 100 + yr / 400) % 7; };
    return (p(y) == 4 || p(y - 1) == 3) ? 53 : 52;
}

int iso_week(const struct tm *t)
{
    const int y = t->tm_year + 1900;
    const int wd = (t->tm_wday + 6) % 7 + 1;
    int w = (t->tm_yday + 1 - wd + 10) / 7;
    if (w < 1) {
        return iso_weeks_in_year(y - 1);
    }
    if (w > iso_weeks_in_year(y)) {
        return 1;
    }
    return w;
}

int children_day_of(int year)
{
    const int wd = weekday_of(year, 1, 1);
    return 1 + (6 - wd + 7) % 7 + 7;
}

void set_text(lv_obj_t *label, char *cache, size_t cache_len, const char *txt)
{
    if (strncmp(cache, txt, cache_len) != 0) {
        snprintf(cache, cache_len, "%s", txt);
        lv_label_set_text(label, txt);
    }
}

void find_next_holiday(const struct tm *now, char *out, size_t out_len, bool *today)
{
    const int     year = now->tm_year + 1900;
    const int32_t today_days = days_from_civil(year, now->tm_mon + 1, now->tm_mday);
    int32_t       best = 0x7FFFFFFF;
    const char   *best_name = "";
    int           best_month = 1;
    int           best_day = 1;

    for (int yr = year; yr <= year + 1; yr++) {
        for (const Holiday &h : HOLIDAYS) {
            const int32_t diff = days_from_civil(yr, h.month, h.day) - today_days;
            if (diff >= 0 && diff < best) {
                best = diff;
                best_name = h.name;
                best_month = h.month;
                best_day = h.day;
            }
        }
        const int     cd = children_day_of(yr);
        const int32_t diff = days_from_civil(yr, 1, cd) - today_days;
        if (diff >= 0 && diff < best) {
            best = diff;
            best_name = CHILDREN_DAY;
            best_month = 1;
            best_day = cd;
        }
    }

    *today = best == 0;
    if (best == 0) {
        snprintf(out, out_len, "วันนี้! %s", best_name);
    } else {
        snprintf(out, out_len, "อีก %d วัน · %s (%d %s)", (int)best, best_name, best_day,
                 TH_MONTH_SHORT[best_month - 1]);
    }
}

void refresh_text(const UiTick *t)
{
    char buf[96];

    if (!t->time_valid) {
        set_text(s_date, s_date_txt, sizeof(s_date_txt), "—");
        set_text(s_year, s_year_txt, sizeof(s_year_txt), "—");
        set_text(s_doy, s_doy_txt, sizeof(s_doy_txt), "—");
        set_text(s_progress, s_progress_txt, sizeof(s_progress_txt), "—");
        set_text(s_holiday, s_holiday_txt, sizeof(s_holiday_txt), "—");
        if (s_bar_val != 0) {
            s_bar_val = 0;
            lv_bar_set_value(s_bar, 0, LV_ANIM_OFF);
        }
        s_holiday_today = false;
        return;
    }

    const struct tm &n = t->now;
    const int        year = n.tm_year + 1900;

    snprintf(buf, sizeof(buf), "วัน%sที่ %d %s", TH_DAY_NAME[n.tm_wday], n.tm_mday,
             TH_MONTH_FULL[n.tm_mon]);
    set_text(s_date, s_date_txt, sizeof(s_date_txt), buf);

    snprintf(buf, sizeof(buf), "พ.ศ. %d · ค.ศ. %d", ui_be_year(&n), year);
    set_text(s_year, s_year_txt, sizeof(s_year_txt), buf);

    snprintf(buf, sizeof(buf), "วันที่ %d ของปี · สัปดาห์ที่ %d", n.tm_yday + 1, iso_week(&n));
    set_text(s_doy, s_doy_txt, sizeof(s_doy_txt), buf);

    const float total = is_leap(year) ? 366.0f : 365.0f;
    const float day_frac = (n.tm_hour * 3600 + n.tm_min * 60 + n.tm_sec) / 86400.0f;
    const float pct = (n.tm_yday + day_frac) / total * 100.0f;
    snprintf(buf, sizeof(buf), "ปีนี้ผ่านไปแล้ว %.1f%%", pct);
    set_text(s_progress, s_progress_txt, sizeof(s_progress_txt), buf);
    const int bar = (int)(pct * 10.0f);
    if (bar != s_bar_val) {
        s_bar_val = bar;
        lv_bar_set_value(s_bar, bar, LV_ANIM_OFF);
    }

    bool today = false;
    find_next_holiday(&n, buf, sizeof(buf), &today);
    set_text(s_holiday, s_holiday_txt, sizeof(s_holiday_txt), buf);
    s_holiday_today = today;
}

void apply_accent(lv_color_t accent)
{
    lv_obj_set_style_text_color(s_date, accent, 0);
    lv_obj_set_style_bg_color(s_bar, accent, LV_PART_INDICATOR);
    lv_obj_set_style_text_color(s_gift, accent, 0);
    lv_obj_set_style_text_color(s_holiday, s_holiday_today ? accent : COLOR_TEXT, 0);
    s_sec_needle->type_data.needle_line.color = accent;
    lv_obj_invalidate(s_meter);
}

}  // namespace

void page_calendar_create(lv_obj_t *tile)
{
    s_meter = lv_meter_create(tile);
    lv_obj_set_size(s_meter, 168, 168);
    lv_obj_set_pos(s_meter, 14, 6);
    lv_obj_clear_flag(s_meter, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_bg_color(s_meter, COLOR_PANEL, 0);
    lv_obj_set_style_bg_opa(s_meter, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(s_meter, 0, 0);
    lv_obj_set_style_pad_all(s_meter, 6, 0);
    lv_obj_set_style_text_opa(s_meter, LV_OPA_TRANSP, LV_PART_TICKS);

    lv_meter_scale_t *scale = lv_meter_add_scale(s_meter);
    // Range is 1/60 s units so the second needle sweeps smoothly.
    lv_meter_set_scale_range(s_meter, scale, 0, 3600, 360, 270);
    lv_meter_set_scale_ticks(s_meter, scale, 61, 1, 6, COLOR_TEXT_DIM);
    lv_meter_set_scale_major_ticks(s_meter, scale, 5, 3, 12, COLOR_TEXT, 0);

    s_hour_needle = lv_meter_add_needle_line(s_meter, scale, 5, COLOR_TEXT, -40);
    s_min_needle = lv_meter_add_needle_line(s_meter, scale, 3, COLOR_TEXT, -20);
    s_sec_needle = lv_meter_add_needle_line(s_meter, scale, 2, COLOR_TEXT, -12);

    lv_obj_set_style_bg_color(s_meter, COLOR_TEXT, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(s_meter, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_pad_all(s_meter, 5, LV_PART_INDICATOR);
    lv_obj_set_style_radius(s_meter, LV_RADIUS_CIRCLE, LV_PART_INDICATOR);

    const lv_coord_t x = 204;

    s_date = ui_label(tile, &ui_font_th_22, COLOR_TEXT, "—");
    lv_obj_set_pos(s_date, x, 6);

    s_year = ui_label(tile, &ui_font_th_16, COLOR_TEXT_DIM, "—");
    lv_obj_set_pos(s_year, x, 38);

    s_doy = ui_label(tile, &ui_font_th_16, COLOR_TEXT_DIM, "—");
    lv_obj_set_pos(s_doy, x, 62);

    s_bar = lv_bar_create(tile);
    lv_obj_set_size(s_bar, 300, 8);
    lv_obj_set_pos(s_bar, x, 94);
    lv_bar_set_range(s_bar, 0, 1000);
    lv_obj_set_style_bg_color(s_bar, COLOR_PANEL_HI, 0);
    lv_obj_set_style_bg_opa(s_bar, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_opa(s_bar, LV_OPA_COVER, LV_PART_INDICATOR);

    s_progress = ui_label(tile, &ui_font_th_16, COLOR_TEXT_DIM, "—");
    lv_obj_set_pos(s_progress, x, 108);

    s_gift = ui_label(tile, &ui_font_th_22, COLOR_TEXT, SYM_GIFT);
    lv_obj_set_pos(s_gift, x, 142);

    s_holiday = ui_label(tile, &ui_font_th_16, COLOR_TEXT, "—");
    lv_obj_set_pos(s_holiday, x + 34, 146);

    s_date_txt[0] = s_year_txt[0] = s_doy_txt[0] = s_progress_txt[0] = s_holiday_txt[0] = 0;
    s_accent = COLOR_TEXT;
    apply_accent(COLOR_TEXT);
}

void page_calendar_update(const UiTick *t)
{
    if (t->time_valid != s_was_valid || t->new_minute || !s_text_ready) {
        s_was_valid = t->time_valid;
        s_text_ready = true;
        refresh_text(t);
        s_accent_init = false;
    }

    if (!s_accent_init || (t->active && t->accent.full != s_accent.full)) {
        s_accent_init = true;
        s_accent = t->accent;
        apply_accent(t->accent);
    }

    if (!t->time_valid) {
        return;
    }

    const struct tm &n = t->now;
    const int32_t    hour_val = (n.tm_hour % 12) * 300 + n.tm_min * 5;
    const int32_t    min_val = n.tm_min * 60 + n.tm_sec;
    if (hour_val != s_hour_val) {
        s_hour_val = hour_val;
        lv_meter_set_indicator_value(s_meter, s_hour_needle, hour_val);
    }
    if (min_val != s_min_val) {
        s_min_val = min_val;
        lv_meter_set_indicator_value(s_meter, s_min_needle, min_val);
    }

    if (t->active) {
        const int32_t sec_val = (int32_t)((n.tm_sec + t->ms / 1000.0f) * 60.0f);
        if (sec_val != s_sec_val) {
            s_sec_val = sec_val;
            lv_meter_set_indicator_value(s_meter, s_sec_needle, sec_val);
        }
    }
}

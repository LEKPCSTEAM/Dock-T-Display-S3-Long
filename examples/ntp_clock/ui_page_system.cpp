#include "ui_internal.h"

#include <Arduino.h>
#include <stdio.h>
#include <string.h>

#include "board.h"
#include "eez/gen/screens.h"

namespace {

enum Row : uint8_t { ROW_WIFI = 0, ROW_IP, ROW_SYNC, ROW_UPTIME, ROW_BATTERY, ROW_CITY, ROW_COUNT };

const int  BAR_COUNT = 4;
const uint32_t BATTERY_PERIOD_MS = 5000;

struct CachedLabel {
    lv_obj_t *obj;
    char      txt[96];
};

lv_obj_t   *s_icons[ROW_COUNT];
CachedLabel s_text[ROW_COUNT];
CachedLabel s_dbm;
lv_obj_t   *s_bars[BAR_COUNT];
lv_obj_t   *s_slider;
lv_obj_t   *s_sun_icon;
lv_obj_t   *s_night_sw;

bool     s_has_pmu;
bool     s_prev_active;
bool     s_accent_valid;
lv_color_t s_accent;
int      s_bars_on = -1;
bool     s_bars_visible = true;
uint32_t s_battery_at;
int      s_battery_mv = -1;
bool     s_battery_read;

int  s_seen_brightness = -1;
int  s_seen_night = -1;

void set_cached(CachedLabel &c, const char *txt)
{
    if (strcmp(c.txt, txt) != 0) {
        snprintf(c.txt, sizeof(c.txt), "%s", txt);
        lv_label_set_text(c.obj, c.txt);
    }
}

void bind_row(Row row, lv_obj_t *icon, lv_obj_t *text)
{
    s_icons[row] = icon;
    s_text[row].obj = text;
    s_text[row].txt[0] = 0;
    lv_label_set_text(text, "—");
}

void on_slider(lv_event_t *e)
{
    lv_obj_t *slider = lv_event_get_target(e);
    const int value = lv_slider_get_value(slider);
    if (lv_event_get_code(e) == LV_EVENT_VALUE_CHANGED) {
        ui_preview_backlight((uint8_t)value);
    } else {
        ClockSettings s = settings_get();
        s.brightness = (uint8_t)value;
        s_seen_brightness = value;
        settings_set(s);
    }
}

void on_night(lv_event_t *e)
{
    ClockSettings s = settings_get();
    s.auto_night = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    s_seen_night = s.auto_night;
    settings_set(s);
}

void on_portal(lv_event_t *)
{
    net_request_portal();
}

void on_sync(lv_event_t *)
{
    net_request_ntp_sync();
    ui_toast("กำลังซิงค์เวลา");
}

void format_ago(char *out, size_t len, time_t secs)
{
    if (secs < 60) {
        snprintf(out, len, "เมื่อสักครู่");
    } else if (secs < 3600) {
        snprintf(out, len, "%d นาทีที่แล้ว", (int)(secs / 60));
    } else if (secs < 86400) {
        snprintf(out, len, "%d ชม.ที่แล้ว", (int)(secs / 3600));
    } else {
        snprintf(out, len, "%d วันที่แล้ว", (int)(secs / 86400));
    }
}

int bars_for_rssi(int rssi)
{
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -78) return 2;
    if (rssi >= -88) return 1;
    return 0;
}

const char *battery_symbol(int mv)
{
    if (mv >= 4100) return LV_SYMBOL_BATTERY_FULL;
    if (mv >= 3900) return LV_SYMBOL_BATTERY_3;
    if (mv >= 3700) return LV_SYMBOL_BATTERY_2;
    if (mv >= 3500) return LV_SYMBOL_BATTERY_1;
    return LV_SYMBOL_BATTERY_EMPTY;
}

void paint_bars(int on, lv_color_t accent)
{
    for (int i = 0; i < BAR_COUNT; i++) {
        lv_obj_set_style_bg_color(s_bars[i], i < on ? accent : COLOR_PANEL_HI, 0);
    }
}

void apply_accent(lv_color_t accent)
{
    lv_obj_set_style_bg_color(s_slider, accent, LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(s_night_sw, accent, LV_PART_INDICATOR | LV_STATE_CHECKED);
    lv_obj_set_style_text_color(s_sun_icon, accent, 0);
    for (int r = ROW_SYNC; r < ROW_COUNT; r++) {
        lv_obj_set_style_text_color(s_icons[r], accent, 0);
    }
    paint_bars(s_bars_on < 0 ? 0 : s_bars_on, accent);
}

void sync_controls(const ClockSettings *cs)
{
    if (cs->brightness != s_seen_brightness) {
        s_seen_brightness = cs->brightness;
        if (!lv_slider_is_dragged(s_slider)) {
            lv_slider_set_value(s_slider, cs->brightness, LV_ANIM_OFF);
        }
    }
    if (cs->auto_night != s_seen_night) {
        s_seen_night = cs->auto_night;
        if (cs->auto_night) {
            lv_obj_add_state(s_night_sw, LV_STATE_CHECKED);
        } else {
            lv_obj_clear_state(s_night_sw, LV_STATE_CHECKED);
        }
    }
}

void refresh_info(const UiTick *t)
{
    const NetStatus *net = t->net;
    char             buf[96];

    bool connected = net->phase == NET_CONNECTED;
    switch (net->phase) {
    case NET_CONNECTED:  snprintf(buf, sizeof(buf), "%s", net->ssid); break;
    case NET_CONNECTING: snprintf(buf, sizeof(buf), "กำลังเชื่อมต่อ"); break;
    case NET_PORTAL:     snprintf(buf, sizeof(buf), "โหมดตั้งค่า"); break;
    case NET_OFFLINE:    snprintf(buf, sizeof(buf), "ออฟไลน์"); break;
    default:             snprintf(buf, sizeof(buf), "กำลังเริ่มระบบ"); break;
    }
    set_cached(s_text[ROW_WIFI], buf);
    lv_obj_set_style_text_color(s_icons[ROW_WIFI], connected ? t->accent : COLOR_TEXT_DIM, 0);

    if (connected != s_bars_visible) {
        s_bars_visible = connected;
        for (int i = 0; i < BAR_COUNT; i++) {
            if (connected) {
                lv_obj_clear_flag(s_bars[i], LV_OBJ_FLAG_HIDDEN);
            } else {
                lv_obj_add_flag(s_bars[i], LV_OBJ_FLAG_HIDDEN);
            }
        }
        if (connected) {
            lv_obj_clear_flag(s_dbm.obj, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(s_dbm.obj, LV_OBJ_FLAG_HIDDEN);
        }
    }
    if (connected) {
        const int on = bars_for_rssi(net->rssi);
        if (on != s_bars_on) {
            s_bars_on = on;
            paint_bars(on, t->accent);
        }
        snprintf(buf, sizeof(buf), "%d dBm", (int)net->rssi);
        set_cached(s_dbm, buf);
    }

    if (net->ip[0]) {
        snprintf(buf, sizeof(buf), "IP %s · %s.local", net->ip, CLOCK_HOSTNAME);
    } else {
        snprintf(buf, sizeof(buf), "IP —");
    }
    set_cached(s_text[ROW_IP], buf);

    if (net->last_sync > 0) {
        struct tm lt;
        time_t    sync = net->last_sync;
        localtime_r(&sync, &lt);
        char ago[48];
        const time_t diff = time(nullptr) - net->last_sync;
        format_ago(ago, sizeof(ago), diff > 0 ? diff : 0);
        snprintf(buf, sizeof(buf), "ซิงค์ล่าสุด %02d:%02d น. (%s)", lt.tm_hour, lt.tm_min, ago);
    } else {
        snprintf(buf, sizeof(buf), "ยังไม่ได้ซิงค์");
    }
    set_cached(s_text[ROW_SYNC], buf);

    const uint32_t mins = millis() / 60000;
    if (mins >= 1440) {
        snprintf(buf, sizeof(buf), "เปิดเครื่อง %u วัน %u ชม.", (unsigned)(mins / 1440),
                 (unsigned)(mins / 60 % 24));
    } else if (mins >= 60) {
        snprintf(buf, sizeof(buf), "เปิดเครื่อง %u ชม. %u นาที", (unsigned)(mins / 60),
                 (unsigned)(mins % 60));
    } else {
        snprintf(buf, sizeof(buf), "เปิดเครื่อง %u นาที", (unsigned)mins);
    }
    set_cached(s_text[ROW_UPTIME], buf);

    if (s_has_pmu) {
        const uint32_t now_ms = millis();
        if (!s_battery_read || now_ms - s_battery_at >= BATTERY_PERIOD_MS) {
            s_battery_read = true;
            s_battery_at = now_ms;
            s_battery_mv = board_battery_mv();
        }
        const bool usb = board_usb_powered();
        if (s_battery_mv < 0) {
            snprintf(buf, sizeof(buf), "ไม่พบแบตเตอรี่%s", usb ? "  " LV_SYMBOL_USB : "");
            lv_label_set_text(s_icons[ROW_BATTERY], LV_SYMBOL_BATTERY_EMPTY);
        } else {
            snprintf(buf, sizeof(buf), "%.2f V%s", s_battery_mv / 1000.0f,
                     usb ? "  " LV_SYMBOL_USB : "");
            lv_label_set_text(s_icons[ROW_BATTERY], battery_symbol(s_battery_mv));
        }
        set_cached(s_text[ROW_BATTERY], buf);
    }

    const ClockSettings *cs = t->settings;
    const char *city = cs->city[0] ? cs->city : "—";
    if (net->weather.valid && net->weather.updated > 0) {
        struct tm lt;
        time_t    upd = net->weather.updated;
        localtime_r(&upd, &lt);
        snprintf(buf, sizeof(buf), "%s · อากาศอัปเดต %02d:%02d น.", city, lt.tm_hour, lt.tm_min);
    } else {
        snprintf(buf, sizeof(buf), "%s", city);
    }
    set_cached(s_text[ROW_CITY], buf);
}

}  // namespace

void page_system_create(lv_obj_t *)
{
    s_has_pmu = board_has_pmu();

    s_sun_icon = objects.label_system_sun;
    s_slider = objects.slider_system_brightness;
    s_night_sw = objects.switch_system_night;

    lv_obj_clear_flag(s_slider, LV_OBJ_FLAG_SCROLL_CHAIN);
    lv_obj_set_ext_click_area(s_slider, 14);
    lv_obj_add_event_cb(s_slider, on_slider, LV_EVENT_VALUE_CHANGED, nullptr);
    lv_obj_add_event_cb(s_slider, on_slider, LV_EVENT_RELEASED, nullptr);
    lv_obj_add_event_cb(s_night_sw, on_night, LV_EVENT_VALUE_CHANGED, nullptr);
    lv_obj_add_event_cb(objects.btn_system_wifi, on_portal, LV_EVENT_CLICKED, nullptr);
    lv_obj_add_event_cb(objects.btn_system_sync, on_sync, LV_EVENT_CLICKED, nullptr);

    bind_row(ROW_WIFI, objects.label_system_wifi_icon, objects.label_system_wifi_text);
    bind_row(ROW_IP, objects.label_system_ip_icon, objects.label_system_ip_text);
    bind_row(ROW_SYNC, objects.label_system_sync_icon, objects.label_system_sync_text);
    bind_row(ROW_UPTIME, objects.label_system_uptime_icon, objects.label_system_uptime_text);
    bind_row(ROW_BATTERY, objects.label_system_battery_icon, objects.label_system_battery_text);
    bind_row(ROW_CITY, objects.label_system_city_icon, objects.label_system_city_text);

    if (!s_has_pmu) {
        const lv_coord_t city_y = lv_obj_get_y(s_icons[ROW_BATTERY]);
        const lv_coord_t battery_y = lv_obj_get_y(s_icons[ROW_CITY]);
        lv_obj_set_y(s_icons[ROW_CITY], city_y);
        lv_obj_set_y(s_text[ROW_CITY].obj, city_y);
        lv_obj_set_y(s_icons[ROW_BATTERY], battery_y);
        lv_obj_set_y(s_text[ROW_BATTERY].obj, battery_y);
        lv_obj_add_flag(s_icons[ROW_BATTERY], LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_text[ROW_BATTERY].obj, LV_OBJ_FLAG_HIDDEN);
    }

    s_bars[0] = objects.cont_system_bar0;
    s_bars[1] = objects.cont_system_bar1;
    s_bars[2] = objects.cont_system_bar2;
    s_bars[3] = objects.cont_system_bar3;
    s_dbm.obj = objects.label_system_dbm;
    s_dbm.txt[0] = 0;
    lv_label_set_text(s_dbm.obj, "—");

    apply_accent(COLOR_TEXT);
}

void page_system_update(const UiTick *t)
{
    if (!t->active) {
        s_prev_active = false;
        return;
    }

    const bool entering = !s_prev_active;
    s_prev_active = true;

    sync_controls(t->settings);

    const bool accent_changed = !s_accent_valid || t->accent.full != s_accent.full;
    if (accent_changed) {
        s_accent_valid = true;
        s_accent = t->accent;
        apply_accent(t->accent);
    }

    if (entering || t->new_second) {
        refresh_info(t);
    }
}

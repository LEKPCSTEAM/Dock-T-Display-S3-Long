#pragma once

#include <time.h>
#include "lvgl.h"
#include "fonts.h"
#include "app_state.h"

#define SCREEN_W 640
#define SCREEN_H 180

#define COLOR_BG       lv_color_hex(0x05070A)
#define COLOR_PANEL    lv_color_hex(0x121820)
#define COLOR_PANEL_HI lv_color_hex(0x1C2530)
#define COLOR_TEXT     lv_color_hex(0xF2F4F7)
#define COLOR_TEXT_DIM lv_color_hex(0x7D8794)
#define COLOR_OK       lv_color_hex(0x4ADE80)
#define COLOR_WARN     lv_color_hex(0xFBBF24)
#define COLOR_ERR      lv_color_hex(0xF87171)
#define COLOR_NIGHT    lv_color_hex(0xC2341F)

enum UiPage : uint8_t {
    PAGE_CLOCK = 0,
    PAGE_CALENDAR,
    PAGE_FOCUS,
    PAGE_SYSTEM,
    PAGE_COUNT,
};

// Snapshot handed to every page on each UI tick (~30 ms).
struct UiTick {
    struct tm            now;         // local Thai time
    bool                 time_valid;  // false until the clock holds a real date
    uint16_t             ms;          // 0..999 within the current second
    bool                 new_second;
    bool                 new_minute;
    const NetStatus     *net;
    const ClockSettings *settings;
    lv_color_t           accent;      // theme + night mode already applied
    bool                 night;
    bool                 active;      // this page is the visible tile
};

extern const char *const TH_DAY_NAME[7];      // "อาทิตย์".."เสาร์", index = tm_wday
extern const char *const TH_MONTH_FULL[12];   // "มกราคม".."ธันวาคม"
extern const char *const TH_MONTH_SHORT[12];  // "ม.ค.".."ธ.ค."

lv_color_t  ui_day_color(int wday);           // Thai colour of the day
lv_color_t  ui_accent(const struct tm *now, const ClockSettings *s, bool night);
bool        ui_is_night(const struct tm *now, const ClockSettings *s);
int         ui_be_year(const struct tm *t);   // Buddhist Era
const char *ui_weather_text(uint16_t wmo_code);
const char *ui_weather_icon(uint16_t wmo_code, bool is_day);
lv_obj_t   *ui_label(lv_obj_t *parent, const lv_font_t *font, lv_color_t color, const char *text);
void        ui_strip_obj(lv_obj_t *obj);      // transparent, no border/padding/scroll

// Implemented in ui.cpp.
void ui_toast(const char *text);
void ui_flash_screen(lv_color_t color);
void ui_preview_backlight(uint8_t level);     // live slider feedback until next settings_set

// One pair per tile; ui.cpp owns the tileview and calls these.
void page_clock_create(lv_obj_t *tile);
void page_clock_update(const UiTick *t);
void page_calendar_create(lv_obj_t *tile);
void page_calendar_update(const UiTick *t);
void page_focus_create(lv_obj_t *tile);
void page_focus_update(const UiTick *t);
void page_system_create(lv_obj_t *tile);
void page_system_update(const UiTick *t);

// Full-screen overlays on lv_layer_top(), driven from the ui.cpp tick.
void ui_portal_update(const UiTick *t);
void ui_splash_create();
bool ui_splash_update(const UiTick *t);       // false once the splash has closed

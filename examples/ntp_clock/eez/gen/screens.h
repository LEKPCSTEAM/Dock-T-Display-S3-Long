#ifndef EEZ_LVGL_UI_SCREENS_H
#define EEZ_LVGL_UI_SCREENS_H

#include <lvgl.h>

#ifdef __cplusplus
extern "C" {
#endif

// Screens

enum ScreensEnum {
    _SCREEN_ID_FIRST = 1,
    SCREEN_ID_CLOCK_PAGE = 1,
    SCREEN_ID_CALENDAR_PAGE = 2,
    SCREEN_ID_FOCUS_PAGE = 3,
    SCREEN_ID_SYSTEM_PAGE = 4,
    SCREEN_ID_PORTAL_PAGE = 5,
    SCREEN_ID_SPLASH_PAGE = 6,
    _SCREEN_ID_LAST = 6
};

typedef struct _objects_t {
    lv_obj_t *clock_page;
    lv_obj_t *calendar_page;
    lv_obj_t *focus_page;
    lv_obj_t *system_page;
    lv_obj_t *portal_page;
    lv_obj_t *splash_page;
    lv_obj_t *cont_clock_time;
    lv_obj_t *cont_clock_d0;
    lv_obj_t *label_clock_d0_a;
    lv_obj_t *label_clock_d0_b;
    lv_obj_t *cont_clock_d1;
    lv_obj_t *label_clock_d1_a;
    lv_obj_t *label_clock_d1_b;
    lv_obj_t *label_clock_colon;
    lv_obj_t *cont_clock_d2;
    lv_obj_t *label_clock_d2_a;
    lv_obj_t *label_clock_d2_b;
    lv_obj_t *cont_clock_d3;
    lv_obj_t *label_clock_d3_a;
    lv_obj_t *label_clock_d3_b;
    lv_obj_t *label_clock_placeholder;
    lv_obj_t *label_clock_sec;
    lv_obj_t *label_clock_hint;
    lv_obj_t *panel_clock_info;
    lv_obj_t *cont_clock_stripe;
    lv_obj_t *label_clock_wifi;
    lv_obj_t *label_clock_sat;
    lv_obj_t *label_clock_day;
    lv_obj_t *label_clock_date;
    lv_obj_t *label_clock_wx_icon;
    lv_obj_t *label_clock_wx_temp;
    lv_obj_t *label_clock_wx_text;
    lv_obj_t *bar_clock_seconds;
    lv_obj_t *cont_calendar_meter;
    lv_obj_t *label_calendar_date;
    lv_obj_t *label_calendar_years;
    lv_obj_t *label_calendar_doy;
    lv_obj_t *bar_calendar_year;
    lv_obj_t *label_calendar_year_pct;
    lv_obj_t *label_calendar_gift;
    lv_obj_t *label_calendar_holiday;
    lv_obj_t *arc_focus_ring;
    lv_obj_t *label_focus_icon;
    lv_obj_t *label_focus_time;
    lv_obj_t *label_focus_mode;
    lv_obj_t *cont_focus_dot0;
    lv_obj_t *cont_focus_dot1;
    lv_obj_t *cont_focus_dot2;
    lv_obj_t *cont_focus_dot3;
    lv_obj_t *label_focus_hint;
    lv_obj_t *label_system_sun;
    lv_obj_t *slider_system_brightness;
    lv_obj_t *label_system_night;
    lv_obj_t *switch_system_night;
    lv_obj_t *btn_system_wifi;
    lv_obj_t *label_system_btn_wifi;
    lv_obj_t *btn_system_sync;
    lv_obj_t *label_system_btn_sync;
    lv_obj_t *label_system_wifi_icon;
    lv_obj_t *label_system_wifi_text;
    lv_obj_t *cont_system_bar0;
    lv_obj_t *cont_system_bar1;
    lv_obj_t *cont_system_bar2;
    lv_obj_t *cont_system_bar3;
    lv_obj_t *label_system_dbm;
    lv_obj_t *label_system_ip_icon;
    lv_obj_t *label_system_ip_text;
    lv_obj_t *label_system_sync_icon;
    lv_obj_t *label_system_sync_text;
    lv_obj_t *label_system_uptime_icon;
    lv_obj_t *label_system_uptime_text;
    lv_obj_t *label_system_battery_icon;
    lv_obj_t *label_system_battery_text;
    lv_obj_t *label_system_city_icon;
    lv_obj_t *label_system_city_text;
    lv_obj_t *cont_portal_wifi_frame;
    lv_obj_t *qrcode_portal_wifi;
    lv_obj_t *label_portal_title;
    lv_obj_t *label_portal_step1;
    lv_obj_t *label_portal_step2;
    lv_obj_t *label_portal_step3;
    lv_obj_t *label_portal_status;
    lv_obj_t *cont_portal_url_frame;
    lv_obj_t *qrcode_portal_url;
    lv_obj_t *label_portal_url_caption;
    lv_obj_t *btn_portal_close;
    lv_obj_t *label_portal_btn_close;
    lv_obj_t *spinner_splash;
    lv_obj_t *label_splash_title;
    lv_obj_t *label_splash_subtitle;
    lv_obj_t *cont_splash_underline;
    lv_obj_t *cont_splash_sweep;
    lv_obj_t *label_splash_status;
} objects_t;

extern objects_t objects;

void create_screen_clock_page();
void tick_screen_clock_page();

void create_screen_calendar_page();
void tick_screen_calendar_page();

void create_screen_focus_page();
void tick_screen_focus_page();

void create_screen_system_page();
void tick_screen_system_page();

void create_screen_portal_page();
void tick_screen_portal_page();

void create_screen_splash_page();
void tick_screen_splash_page();

void tick_screen_by_id(enum ScreensEnum screenId);
void tick_screen(int screen_index);

void create_screens();

// Color themes

enum Themes {
    THEME_ID_DEFAULT,
};
enum Colors {
    COLOR_ID_BG,
    COLOR_ID_PANEL,
    COLOR_ID_PANEL_HI,
    COLOR_ID_TEXT,
    COLOR_ID_TEXT_DIM,
    COLOR_ID_OK,
    COLOR_ID_WARN,
    COLOR_ID_ERR,
    COLOR_ID_NIGHT,
};
void change_color_theme(uint32_t themeIndex);
extern uint32_t theme_colors[1][9];
extern uint32_t active_theme_index;

#ifdef __cplusplus
}
#endif

#endif /*EEZ_LVGL_UI_SCREENS_H*/
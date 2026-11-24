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
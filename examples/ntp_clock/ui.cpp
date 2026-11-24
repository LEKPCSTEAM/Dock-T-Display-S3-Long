#include <string.h>
#include <stdio.h>
#include <sys/time.h>
#include "ui.h"
#include "ui_internal.h"
#include "board.h"
#include "eez/gen/screens.h"

#define TICK_MS          30
#define NET_REFRESH_MS   250
#define NIGHT_MAX_LEVEL  20
#define FADE_MS          600
#define BOOT_FADE_DELAY  300
#define INDICATOR_HOLD   1500
#define INDICATOR_FADE   300
#define TOAST_TOTAL_MS   1800
#define TOAST_EDGE_MS    250
#define FLASH_TOTAL_MS   1200
#define FLASH_PULSE_MS   400
#define FLASH_MAX_OPA    150

static lv_obj_t *tv;
#define TILE_MAX (PAGE_COUNT + DECK_MAX_PAGES)

static lv_obj_t *tiles[TILE_MAX];
static lv_obj_t *indicator;
static lv_obj_t *dots[TILE_MAX];
static uint8_t   deck_pages;
static lv_obj_t *toast;
static lv_obj_t *flash;

static int      last_page = -1;
static uint32_t init_ms;
static bool     splash_open = true;

static int          cur_level;
static int          last_target = -1;
static bool         boot_fade_started;
static bool         preview_active;
static uint32_t     preview_version;

static NetStatus     net_cache;
static uint32_t      net_cache_ms;
static bool          net_cache_ok;
static ClockSettings cfg_cache;
static uint32_t      cfg_version;
static bool          cfg_ok;

static int current_page()
{
    lv_obj_t *act = lv_tileview_get_tile_act(tv);
    for (int i = 0; i < PAGE_COUNT + deck_pages; i++) {
        if (tiles[i] == act) {
            return i;
        }
    }
    return 0;
}

static bool tile_visible(int i)
{
    lv_area_t a;
    lv_obj_get_coords(tiles[i], &a);
    return a.x1 < SCREEN_W && a.x2 >= 0;
}

static void indicator_fade_cb(void *obj, int32_t v)
{
    lv_obj_set_style_opa((lv_obj_t *)obj, 255 - v, 0);
}

static void indicator_done_cb(lv_anim_t *a)
{
    lv_obj_add_flag((lv_obj_t *)a->var, LV_OBJ_FLAG_HIDDEN);
}

static void indicator_show(int page, lv_color_t accent)
{
    for (int i = 0; i < PAGE_COUNT + deck_pages; i++) {
        bool on = i == page;
        lv_obj_set_width(dots[i], on ? 20 : 8);
        lv_obj_set_style_bg_color(dots[i], on ? accent : COLOR_TEXT_DIM, 0);
    }
    lv_anim_del(indicator, indicator_fade_cb);
    lv_obj_set_style_opa(indicator, LV_OPA_COVER, 0);
    lv_obj_clear_flag(indicator, LV_OBJ_FLAG_HIDDEN);

    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, indicator);
    lv_anim_set_exec_cb(&a, indicator_fade_cb);
    lv_anim_set_values(&a, 0, 255);
    lv_anim_set_delay(&a, INDICATOR_HOLD);
    lv_anim_set_time(&a, INDICATOR_FADE);
    lv_anim_set_path_cb(&a, lv_anim_path_linear);
    lv_anim_set_ready_cb(&a, indicator_done_cb);
    lv_anim_start(&a);
}

static lv_obj_t *dot_create()
{
    lv_obj_t *d = lv_obj_create(indicator);
    ui_strip_obj(d);
    lv_obj_clear_flag(d, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(d, 8, 8);
    lv_obj_set_style_radius(d, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_opa(d, LV_OPA_COVER, 0);
    return d;
}

static void indicator_create()
{
    indicator = lv_obj_create(lv_layer_top());
    ui_strip_obj(indicator);
    lv_obj_clear_flag(indicator, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(indicator, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(indicator, COLOR_PANEL_HI, 0);
    lv_obj_set_style_bg_opa(indicator, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(indicator, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_pad_hor(indicator, 12, 0);
    lv_obj_set_style_pad_ver(indicator, 6, 0);
    lv_obj_set_style_pad_column(indicator, 6, 0);
    lv_obj_set_flex_flow(indicator, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(indicator, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_align(indicator, LV_ALIGN_BOTTOM_MID, 0, -16);
    for (int i = 0; i < PAGE_COUNT; i++) {
        dots[i] = dot_create();
    }
    lv_obj_add_flag(indicator, LV_OBJ_FLAG_HIDDEN);
}

static void backlight_anim_cb(void *, int32_t v)
{
    cur_level = v;
    board_set_backlight((uint8_t)v);
}

static void backlight_fade_to(int target)
{
    lv_anim_del(&cur_level, backlight_anim_cb);
    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, &cur_level);
    lv_anim_set_exec_cb(&a, backlight_anim_cb);
    lv_anim_set_values(&a, cur_level, target);
    lv_anim_set_time(&a, FADE_MS);
    lv_anim_set_path_cb(&a, lv_anim_path_ease_out);
    lv_anim_start(&a);
}

static void brightness_update(const ClockSettings *s, bool night)
{
    if (!boot_fade_started) {
        if (lv_tick_elaps(init_ms) < BOOT_FADE_DELAY) {
            return;
        }
        boot_fade_started = true;
    }
    if (preview_active) {
        if (settings_version() == preview_version) {
            return;
        }
        preview_active = false;
        last_target    = -1;
    }
    int target = s->brightness;
    if (night && target > NIGHT_MAX_LEVEL) {
        target = NIGHT_MAX_LEVEL;
    }
    if (target != last_target) {
        last_target = target;
        backlight_fade_to(target);
    }
}

static void tick_cb(lv_timer_t *)
{
    UiTick t;
    memset(&t, 0, sizeof(t));

    struct timeval tvl;
    gettimeofday(&tvl, NULL);
    time_t sec = tvl.tv_sec;
    localtime_r(&sec, &t.now);
    t.time_valid = t.now.tm_year + 1900 >= 2024;
    t.ms         = (uint16_t)(tvl.tv_usec / 1000);

    static time_t last_sec = -1;
    t.new_second = sec != last_sec;
    t.new_minute = t.new_second && (last_sec < 0 || sec / 60 != last_sec / 60);
    last_sec     = sec;

    if (!net_cache_ok || lv_tick_elaps(net_cache_ms) >= NET_REFRESH_MS) {
        net_get_status(&net_cache);
        net_cache_ms = lv_tick_get();
        net_cache_ok = true;
    }
    uint32_t ver = settings_version();
    if (!cfg_ok || ver != cfg_version) {
        cfg_cache = settings_get();
        cfg_version = ver;
        cfg_ok = true;
    }
    t.net      = &net_cache;
    t.settings = &cfg_cache;
    t.night    = t.time_valid && ui_is_night(&t.now, &cfg_cache);
    t.accent   = ui_accent(&t.now, &cfg_cache, t.night);

    int page = current_page();
    if (page != last_page) {
        if (last_page >= 0) {
            indicator_show(page, t.accent);
        }
        last_page = page;
    }

    brightness_update(&cfg_cache, t.night);

    t.active = tile_visible(PAGE_CLOCK);
    page_clock_update(&t);
    t.active = tile_visible(PAGE_CALENDAR);
    page_calendar_update(&t);
    t.active = tile_visible(PAGE_FOCUS);
    page_focus_update(&t);
    t.active = tile_visible(PAGE_SYSTEM);
    page_system_update(&t);
    t.active = true;

    page_deck_update(&t);
    ui_claude_overlay_update(&t);
    ui_pair_update(&t);
    ui_portal_update(&t);
    if (splash_open) {
        splash_open = ui_splash_update(&t);
    }
}

static void mount_page(lv_obj_t *tile, void (*create_screen)(), lv_obj_t **screen, void (*bind)(lv_obj_t *))
{
    create_screen();
    ui_mount_screen(*screen, tile);
    *screen = NULL;
    bind(tile);
}

static lv_obj_t *tile_create(int col)
{
    lv_obj_t *tile = lv_tileview_add_tile(tv, col, 0, (lv_dir_t)(LV_DIR_LEFT | LV_DIR_RIGHT));
    lv_obj_remove_style_all(tile);
    // remove_style_all also drops the tile's local size and position.
    lv_obj_set_size(tile, SCREEN_W, SCREEN_H);
    lv_obj_set_pos(tile, col * SCREEN_W, 0);
    return tile;
}

void ui_init()
{
    board_set_backlight(0);
    init_ms = lv_tick_get();

    lv_disp_t  *disp  = lv_disp_get_default();
    lv_theme_t *theme = lv_theme_default_init(disp, lv_palette_main(LV_PALETTE_BLUE),
                                              lv_palette_main(LV_PALETTE_ORANGE), true, &ui_font_th_16);
    lv_disp_set_theme(disp, theme);

    lv_obj_t *scr = lv_scr_act();
    lv_obj_set_style_bg_color(scr, COLOR_BG, 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_set_style_text_font(scr, &ui_font_th_16, 0);

    tv = lv_tileview_create(scr);
    lv_obj_remove_style_all(tv);
    lv_obj_set_size(tv, SCREEN_W, SCREEN_H);
    lv_obj_set_style_bg_color(tv, COLOR_BG, 0);
    lv_obj_set_style_bg_opa(tv, LV_OPA_COVER, 0);
    lv_obj_set_scrollbar_mode(tv, LV_SCROLLBAR_MODE_OFF);

    for (int i = 0; i < PAGE_COUNT; i++) {
        tiles[i] = tile_create(i);
    }
    mount_page(tiles[PAGE_CLOCK], create_screen_clock_page, &objects.clock_page, page_clock_create);
    mount_page(tiles[PAGE_CALENDAR], create_screen_calendar_page, &objects.calendar_page, page_calendar_create);
    mount_page(tiles[PAGE_FOCUS], create_screen_focus_page, &objects.focus_page, page_focus_create);
    mount_page(tiles[PAGE_SYSTEM], create_screen_system_page, &objects.system_page, page_system_create);

    indicator_create();
    ui_splash_create();

    lv_timer_create(tick_cb, TICK_MS, NULL);
}

void ui_next_page()
{
    if (!tv) {
        return;
    }
    lv_obj_set_tile_id(tv, (current_page() + 1) % (PAGE_COUNT + deck_pages), 0, LV_ANIM_ON);
}

void ui_set_deck_pages(uint8_t n)
{
    if (!tv) {
        return;
    }
    if (n > DECK_MAX_PAGES) {
        n = DECK_MAX_PAGES;
    }
    if (n == deck_pages) {
        return;
    }
    if (current_page() >= PAGE_COUNT + n) {
        lv_obj_set_tile_id(tv, PAGE_CLOCK, 0, LV_ANIM_OFF);
    }
    for (int i = deck_pages; i < n; i++) {
        tiles[PAGE_COUNT + i] = tile_create(PAGE_COUNT + i);
        dots[PAGE_COUNT + i]  = dot_create();
    }
    for (int i = n; i < deck_pages; i++) {
        lv_obj_del(tiles[PAGE_COUNT + i]);
        lv_obj_del(dots[PAGE_COUNT + i]);
        tiles[PAGE_COUNT + i] = NULL;
        dots[PAGE_COUNT + i]  = NULL;
    }
    deck_pages = n;
    last_page  = -1;
}

lv_obj_t *ui_deck_tile(uint8_t i)
{
    return i < deck_pages ? tiles[PAGE_COUNT + i] : NULL;
}

void ui_preview_backlight(uint8_t level)
{
    lv_anim_del(&cur_level, backlight_anim_cb);
    cur_level       = level;
    last_target     = -1;
    preview_active  = true;
    preview_version = settings_version();
    boot_fade_started = true;
    board_set_backlight(level);
}

static void toast_anim_cb(void *obj, int32_t v)
{
    int opa = 255;
    if (v < TOAST_EDGE_MS) {
        opa = v * 255 / TOAST_EDGE_MS;
    } else if (v > TOAST_TOTAL_MS - TOAST_EDGE_MS) {
        opa = (TOAST_TOTAL_MS - v) * 255 / TOAST_EDGE_MS;
    }
    lv_obj_set_style_opa((lv_obj_t *)obj, (lv_opa_t)opa, 0);
}

static void toast_done_cb(lv_anim_t *a)
{
    lv_obj_t *obj = (lv_obj_t *)a->var;
    if (toast == obj) {
        toast = NULL;
    }
    lv_obj_del(obj);
}

void ui_toast(const char *text)
{
    if (toast) {
        lv_obj_del(toast);
        toast = NULL;
    }
    toast = lv_obj_create(lv_layer_top());
    ui_strip_obj(toast);
    lv_obj_clear_flag(toast, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(toast, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(toast, COLOR_PANEL_HI, 0);
    lv_obj_set_style_bg_opa(toast, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(toast, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_color(toast, COLOR_TEXT_DIM, 0);
    lv_obj_set_style_border_width(toast, 1, 0);
    lv_obj_set_style_pad_hor(toast, 22, 0);
    lv_obj_set_style_pad_ver(toast, 8, 0);
    lv_obj_set_style_opa(toast, LV_OPA_TRANSP, 0);
    ui_label(toast, &ui_font_th_16, COLOR_TEXT, text);
    lv_obj_align(toast, LV_ALIGN_BOTTOM_MID, 0, -22);

    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, toast);
    lv_anim_set_exec_cb(&a, toast_anim_cb);
    lv_anim_set_values(&a, 0, TOAST_TOTAL_MS);
    lv_anim_set_time(&a, TOAST_TOTAL_MS);
    lv_anim_set_path_cb(&a, lv_anim_path_linear);
    lv_anim_set_ready_cb(&a, toast_done_cb);
    lv_anim_start(&a);
}

static void flash_anim_cb(void *obj, int32_t v)
{
    int p   = v % FLASH_PULSE_MS;
    int half = FLASH_PULSE_MS / 2;
    int lvl = (p < half ? p : FLASH_PULSE_MS - p) * FLASH_MAX_OPA / half;
    lv_obj_set_style_bg_opa((lv_obj_t *)obj, (lv_opa_t)lvl, 0);
}

static void flash_done_cb(lv_anim_t *a)
{
    lv_obj_t *obj = (lv_obj_t *)a->var;
    if (flash == obj) {
        flash = NULL;
    }
    lv_obj_del(obj);
}

void ui_flash_screen(lv_color_t color)
{
    if (flash) {
        lv_obj_del(flash);
        flash = NULL;
    }
    flash = lv_obj_create(lv_layer_top());
    ui_strip_obj(flash);
    lv_obj_clear_flag(flash, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(flash, SCREEN_W, SCREEN_H);
    lv_obj_set_style_bg_color(flash, color, 0);
    lv_obj_set_style_bg_opa(flash, LV_OPA_TRANSP, 0);

    lv_anim_t a;
    lv_anim_init(&a);
    lv_anim_set_var(&a, flash);
    lv_anim_set_exec_cb(&a, flash_anim_cb);
    lv_anim_set_values(&a, 0, FLASH_TOTAL_MS);
    lv_anim_set_time(&a, FLASH_TOTAL_MS);
    lv_anim_set_path_cb(&a, lv_anim_path_linear);
    lv_anim_set_ready_cb(&a, flash_done_cb);
    lv_anim_start(&a);
}

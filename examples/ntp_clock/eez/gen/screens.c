#include <string.h>

#include "screens.h"
#include "images.h"
#include "fonts.h"
#include "actions.h"
#include "vars.h"
#include "styles.h"
#include "ui.h"

#include <string.h>

objects_t objects;

//
// Event handlers
//

lv_obj_t *tick_value_change_obj;

//
// Screens
//

void create_screen_clock_page() {
    lv_obj_t *obj = lv_obj_create(0);
    objects.clock_page = obj;
    lv_obj_set_pos(obj, 0, 0);
    lv_obj_set_size(obj, 640, 180);
    lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
    {
        lv_obj_t *parent_obj = obj;
        {
            // cont_clock_time
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_clock_time = obj;
            lv_obj_set_pos(obj, 0, 0);
            lv_obj_set_size(obj, 458, 175);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // cont_clock_d0
                    lv_obj_t *obj = lv_obj_create(parent_obj);
                    objects.cont_clock_d0 = obj;
                    lv_obj_set_pos(obj, 16, 28);
                    lv_obj_set_size(obj, 84, 87);
                    lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_bg_opa(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_radius(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
                    {
                        lv_obj_t *parent_obj = obj;
                        {
                            // label_clock_d0_a
                            lv_obj_t *obj = lv_label_create(parent_obj);
                            objects.label_clock_d0_a = obj;
                            lv_obj_set_pos(obj, 0, 0);
                            lv_obj_set_size(obj, 84, LV_SIZE_CONTENT);
                            lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
                            lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_label_set_text_static(obj, "0");
                        }
                        {
                            // label_clock_d0_b
                            lv_obj_t *obj = lv_label_create(parent_obj);
                            objects.label_clock_d0_b = obj;
                            lv_obj_set_pos(obj, 0, 0);
                            lv_obj_set_size(obj, 84, LV_SIZE_CONTENT);
                            lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_label_set_text_static(obj, "1");
                        }
                    }
                }
                {
                    // cont_clock_d1
                    lv_obj_t *obj = lv_obj_create(parent_obj);
                    objects.cont_clock_d1 = obj;
                    lv_obj_set_pos(obj, 100, 28);
                    lv_obj_set_size(obj, 84, 87);
                    lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_bg_opa(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_radius(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
                    {
                        lv_obj_t *parent_obj = obj;
                        {
                            // label_clock_d1_a
                            lv_obj_t *obj = lv_label_create(parent_obj);
                            objects.label_clock_d1_a = obj;
                            lv_obj_set_pos(obj, 0, 0);
                            lv_obj_set_size(obj, 84, LV_SIZE_CONTENT);
                            lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
                            lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_label_set_text_static(obj, "0");
                        }
                        {
                            // label_clock_d1_b
                            lv_obj_t *obj = lv_label_create(parent_obj);
                            objects.label_clock_d1_b = obj;
                            lv_obj_set_pos(obj, 0, 0);
                            lv_obj_set_size(obj, 84, LV_SIZE_CONTENT);
                            lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_label_set_text_static(obj, "1");
                        }
                    }
                }
                {
                    // label_clock_colon
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_colon = obj;
                    lv_obj_set_pos(obj, 184, 28);
                    lv_obj_set_size(obj, 28, LV_SIZE_CONTENT);
                    lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, ":");
                }
                {
                    // cont_clock_d2
                    lv_obj_t *obj = lv_obj_create(parent_obj);
                    objects.cont_clock_d2 = obj;
                    lv_obj_set_pos(obj, 212, 28);
                    lv_obj_set_size(obj, 84, 87);
                    lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_bg_opa(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_radius(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
                    {
                        lv_obj_t *parent_obj = obj;
                        {
                            // label_clock_d2_a
                            lv_obj_t *obj = lv_label_create(parent_obj);
                            objects.label_clock_d2_a = obj;
                            lv_obj_set_pos(obj, 0, 0);
                            lv_obj_set_size(obj, 84, LV_SIZE_CONTENT);
                            lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
                            lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_label_set_text_static(obj, "2");
                        }
                        {
                            // label_clock_d2_b
                            lv_obj_t *obj = lv_label_create(parent_obj);
                            objects.label_clock_d2_b = obj;
                            lv_obj_set_pos(obj, 0, 0);
                            lv_obj_set_size(obj, 84, LV_SIZE_CONTENT);
                            lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_label_set_text_static(obj, "3");
                        }
                    }
                }
                {
                    // cont_clock_d3
                    lv_obj_t *obj = lv_obj_create(parent_obj);
                    objects.cont_clock_d3 = obj;
                    lv_obj_set_pos(obj, 296, 28);
                    lv_obj_set_size(obj, 84, 87);
                    lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_bg_opa(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_radius(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
                    {
                        lv_obj_t *parent_obj = obj;
                        {
                            // label_clock_d3_a
                            lv_obj_t *obj = lv_label_create(parent_obj);
                            objects.label_clock_d3_a = obj;
                            lv_obj_set_pos(obj, 0, 0);
                            lv_obj_set_size(obj, 84, LV_SIZE_CONTENT);
                            lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
                            lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_label_set_text_static(obj, "5");
                        }
                        {
                            // label_clock_d3_b
                            lv_obj_t *obj = lv_label_create(parent_obj);
                            objects.label_clock_d3_b = obj;
                            lv_obj_set_pos(obj, 0, 0);
                            lv_obj_set_size(obj, 84, LV_SIZE_CONTENT);
                            lv_obj_set_style_text_font(obj, &ui_font_digits_128, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                            lv_label_set_text_static(obj, "6");
                        }
                    }
                }
                {
                    // label_clock_placeholder
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_placeholder = obj;
                    lv_obj_set_pos(obj, 16, 47);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
                    lv_obj_set_style_text_font(obj, &ui_font_digits_56, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "--:--");
                }
                {
                    // label_clock_sec
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_sec = obj;
                    lv_obj_set_pos(obj, 382, 71);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_text_font(obj, &ui_font_digits_56, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "12");
                }
                {
                    // label_clock_hint
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_hint = obj;
                    lv_obj_set_pos(obj, 20, 125);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, " กรุงเทพฯ");
                }
            }
        }
        {
            // panel_clock_info
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.panel_clock_info = obj;
            lv_obj_set_pos(obj, 462, 8);
            lv_obj_set_size(obj, 170, 159);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // cont_clock_stripe
                    lv_obj_t *obj = lv_obj_create(parent_obj);
                    objects.cont_clock_stripe = obj;
                    lv_obj_set_pos(obj, 7, 14);
                    lv_obj_set_size(obj, 3, 131);
                    lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
                    lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_radius(obj, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
                }
                {
                    // label_clock_wifi
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_wifi = obj;
                    lv_obj_set_pos(obj, 16, 8);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][6]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "");
                }
                {
                    // label_clock_sat
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_sat = obj;
                    lv_obj_set_pos(obj, 48, 8);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "");
                }
                {
                    // label_clock_day
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_day = obj;
                    lv_obj_set_pos(obj, 16, 37);
                    lv_obj_set_size(obj, 146, LV_SIZE_CONTENT);
                    lv_label_set_long_mode(obj, LV_LABEL_LONG_SCROLL_CIRCULAR);
                    lv_obj_set_style_text_font(obj, &ui_font_th_32, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "อังคาร");
                }
                {
                    // label_clock_date
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_date = obj;
                    lv_obj_set_pos(obj, 16, 86);
                    lv_obj_set_size(obj, 146, LV_SIZE_CONTENT);
                    lv_label_set_long_mode(obj, LV_LABEL_LONG_SCROLL_CIRCULAR);
                    lv_obj_set_style_text_font(obj, &ui_font_th_22, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "24 พ.ย. 2569");
                }
                {
                    // label_clock_wx_icon
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_wx_icon = obj;
                    lv_obj_set_pos(obj, 16, 123);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_22, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "");
                }
                {
                    // label_clock_wx_temp
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_wx_temp = obj;
                    lv_obj_set_pos(obj, 50, 123);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_22, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "31°");
                }
                {
                    // label_clock_wx_text
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_clock_wx_text = obj;
                    lv_obj_set_pos(obj, 81, 127);
                    lv_obj_set_size(obj, 70, LV_SIZE_CONTENT);
                    lv_label_set_long_mode(obj, LV_LABEL_LONG_SCROLL_CIRCULAR);
                    lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "มีเมฆบางส่วน");
                }
            }
        }
        {
            // bar_clock_seconds
            lv_obj_t *obj = lv_bar_create(parent_obj);
            objects.bar_clock_seconds = obj;
            lv_obj_set_pos(obj, 0, 175);
            lv_obj_set_size(obj, 640, 5);
            lv_bar_set_range(obj, 0, 640);
            lv_bar_set_value(obj, 131, LV_ANIM_OFF);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_INDICATOR | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_INDICATOR | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 0, LV_PART_INDICATOR | LV_STATE_DEFAULT);
        }
    }
    
    tick_screen_clock_page();
}

void tick_screen_clock_page() {
}

void create_screen_calendar_page() {
    lv_obj_t *obj = lv_obj_create(0);
    objects.calendar_page = obj;
    lv_obj_set_pos(obj, 0, 0);
    lv_obj_set_size(obj, 640, 180);
    lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
    {
        lv_obj_t *parent_obj = obj;
        {
            // cont_calendar_meter
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_calendar_meter = obj;
            lv_obj_set_pos(obj, 14, 6);
            lv_obj_set_size(obj, 168, 168);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 32767, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // label_calendar_date
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_calendar_date = obj;
            lv_obj_set_pos(obj, 204, 6);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_22, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "วันอังคารที่ 24 พฤศจิกายน");
        }
        {
            // label_calendar_years
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_calendar_years = obj;
            lv_obj_set_pos(obj, 204, 38);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "พ.ศ. 2569 · ค.ศ. 2026");
        }
        {
            // label_calendar_doy
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_calendar_doy = obj;
            lv_obj_set_pos(obj, 204, 62);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "วันที่ 328 ของปี · สัปดาห์ที่ 48");
        }
        {
            // bar_calendar_year
            lv_obj_t *obj = lv_bar_create(parent_obj);
            objects.bar_calendar_year = obj;
            lv_obj_set_pos(obj, 204, 94);
            lv_obj_set_size(obj, 300, 8);
            lv_bar_set_range(obj, 0, 1000);
            lv_bar_set_value(obj, 897, LV_ANIM_OFF);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_INDICATOR | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_INDICATOR | LV_STATE_DEFAULT);
        }
        {
            // label_calendar_year_pct
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_calendar_year_pct = obj;
            lv_obj_set_pos(obj, 204, 108);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "ปีนี้ผ่านไปแล้ว 89.7%");
        }
        {
            // label_calendar_gift
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_calendar_gift = obj;
            lv_obj_set_pos(obj, 204, 142);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_22, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "");
        }
        {
            // label_calendar_holiday
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_calendar_holiday = obj;
            lv_obj_set_pos(obj, 238, 146);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "อีก 11 วัน · วันพ่อแห่งชาติ (5 ธ.ค.)");
        }
    }
    
    tick_screen_calendar_page();
}

void tick_screen_calendar_page() {
}

void create_screen_focus_page() {
    lv_obj_t *obj = lv_obj_create(0);
    objects.focus_page = obj;
    lv_obj_set_pos(obj, 0, 0);
    lv_obj_set_size(obj, 640, 180);
    lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
    {
        lv_obj_t *parent_obj = obj;
        {
            // arc_focus_ring
            lv_obj_t *obj = lv_arc_create(parent_obj);
            objects.arc_focus_ring = obj;
            lv_obj_set_pos(obj, 24, 15);
            lv_obj_set_size(obj, 150, 150);
            lv_arc_set_range(obj, 0, 1000);
            lv_arc_set_value(obj, 1000);
            lv_arc_set_bg_start_angle(obj, 0);
            lv_arc_set_bg_end_angle(obj, 360);
            lv_arc_set_rotation(obj, 270);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_arc_width(obj, 12, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_arc_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_arc_width(obj, 12, LV_PART_INDICATOR | LV_STATE_DEFAULT);
            lv_obj_set_style_arc_rounded(obj, true, LV_PART_INDICATOR | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 0, LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_KNOB | LV_STATE_DEFAULT);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // label_focus_icon
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_focus_icon = obj;
                    lv_obj_set_pos(obj, 0, 0);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_32, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_align(obj, LV_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "");
                }
            }
        }
        {
            // label_focus_time
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_focus_time = obj;
            lv_obj_set_pos(obj, 214, 10);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_digits_56, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "25:00");
        }
        {
            // label_focus_mode
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_focus_mode = obj;
            lv_obj_set_pos(obj, 214, 68);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_22, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "โฟกัส");
        }
        {
            // cont_focus_dot0
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_focus_dot0 = obj;
            lv_obj_set_pos(obj, 214, 108);
            lv_obj_set_size(obj, 16, 16);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_radius(obj, 32767, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // cont_focus_dot1
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_focus_dot1 = obj;
            lv_obj_set_pos(obj, 242, 108);
            lv_obj_set_size(obj, 16, 16);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_radius(obj, 32767, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // cont_focus_dot2
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_focus_dot2 = obj;
            lv_obj_set_pos(obj, 270, 108);
            lv_obj_set_size(obj, 16, 16);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_radius(obj, 32767, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // cont_focus_dot3
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_focus_dot3 = obj;
            lv_obj_set_pos(obj, 298, 108);
            lv_obj_set_size(obj, 16, 16);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_radius(obj, 32767, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // label_focus_hint
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_focus_hint = obj;
            lv_obj_set_pos(obj, 214, 140);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "แตะเพื่อเริ่ม/หยุด · กดค้างเพื่อรีเซ็ต");
        }
    }
    
    tick_screen_focus_page();
}

void tick_screen_focus_page() {
}

void create_screen_system_page() {
    lv_obj_t *obj = lv_obj_create(0);
    objects.system_page = obj;
    lv_obj_set_pos(obj, 0, 0);
    lv_obj_set_size(obj, 640, 180);
    lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
    {
        lv_obj_t *parent_obj = obj;
        {
            // label_system_sun
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_sun = obj;
            lv_obj_set_pos(obj, 372, 8);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_22, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "");
        }
        {
            // slider_system_brightness
            lv_obj_t *obj = lv_slider_create(parent_obj);
            objects.slider_system_brightness = obj;
            lv_obj_set_pos(obj, 416, 18);
            lv_obj_set_size(obj, 190, 10);
            lv_slider_set_range(obj, 10, 255);
            lv_slider_set_value(obj, 180, LV_ANIM_OFF);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_INDICATOR | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_INDICATOR | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 5, LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 5, LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_left(obj, 5, LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 5, LV_PART_KNOB | LV_STATE_DEFAULT);
        }
        {
            // label_system_night
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_night = obj;
            lv_obj_set_pos(obj, 372, 62);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "หรี่จอกลางคืน");
        }
        {
            // switch_system_night
            lv_obj_t *obj = lv_switch_create(parent_obj);
            objects.switch_system_night = obj;
            lv_obj_set_pos(obj, 576, 64);
            lv_obj_set_size(obj, 52, 28);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_KNOB | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_INDICATOR | LV_STATE_CHECKED);
        }
        {
            // btn_system_wifi
            lv_obj_t *obj = lv_btn_create(parent_obj);
            objects.btn_system_wifi = obj;
            lv_obj_set_pos(obj, 368, 132);
            lv_obj_set_size(obj, 128, 40);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 12, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_shadow_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_PRESSED);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // label_system_btn_wifi
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_system_btn_wifi = obj;
                    lv_obj_set_pos(obj, 0, 0);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_align(obj, LV_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "  ตั้งค่า WiFi");
                }
            }
        }
        {
            // btn_system_sync
            lv_obj_t *obj = lv_btn_create(parent_obj);
            objects.btn_system_sync = obj;
            lv_obj_set_pos(obj, 500, 132);
            lv_obj_set_size(obj, 128, 40);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 12, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_shadow_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][1]), LV_PART_MAIN | LV_STATE_PRESSED);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // label_system_btn_sync
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_system_btn_sync = obj;
                    lv_obj_set_pos(obj, 0, 0);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_align(obj, LV_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "  ซิงค์เวลา");
                }
            }
        }
        {
            // label_system_wifi_icon
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_wifi_icon = obj;
            lv_obj_set_pos(obj, 12, 10);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "");
        }
        {
            // label_system_wifi_text
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_wifi_text = obj;
            lv_obj_set_pos(obj, 40, 10);
            lv_obj_set_size(obj, 150, LV_SIZE_CONTENT);
            lv_label_set_long_mode(obj, LV_LABEL_LONG_DOT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text(obj, "MyHomeWiFi");
        }
        {
            // cont_system_bar0
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_system_bar0 = obj;
            lv_obj_set_pos(obj, 200, 23);
            lv_obj_set_size(obj, 4, 5);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 1, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // cont_system_bar1
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_system_bar1 = obj;
            lv_obj_set_pos(obj, 207, 19);
            lv_obj_set_size(obj, 4, 9);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 1, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // cont_system_bar2
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_system_bar2 = obj;
            lv_obj_set_pos(obj, 214, 15);
            lv_obj_set_size(obj, 4, 13);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 1, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // cont_system_bar3
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_system_bar3 = obj;
            lv_obj_set_pos(obj, 221, 11);
            lv_obj_set_size(obj, 4, 17);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 1, LV_PART_MAIN | LV_STATE_DEFAULT);
        }
        {
            // label_system_dbm
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_dbm = obj;
            lv_obj_set_pos(obj, 232, 10);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "-58 dBm");
        }
        {
            // label_system_ip_icon
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_ip_icon = obj;
            lv_obj_set_pos(obj, 12, 38);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "");
        }
        {
            // label_system_ip_text
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_ip_text = obj;
            lv_obj_set_pos(obj, 40, 38);
            lv_obj_set_size(obj, 310, LV_SIZE_CONTENT);
            lv_label_set_long_mode(obj, LV_LABEL_LONG_DOT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text(obj, "IP 192.168.1.42 · longdeck.local");
        }
        {
            // label_system_sync_icon
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_sync_icon = obj;
            lv_obj_set_pos(obj, 12, 66);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "");
        }
        {
            // label_system_sync_text
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_sync_text = obj;
            lv_obj_set_pos(obj, 40, 66);
            lv_obj_set_size(obj, 310, LV_SIZE_CONTENT);
            lv_label_set_long_mode(obj, LV_LABEL_LONG_DOT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text(obj, "ซิงค์ล่าสุด 11:30 น. (6 นาทีที่แล้ว)");
        }
        {
            // label_system_uptime_icon
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_uptime_icon = obj;
            lv_obj_set_pos(obj, 12, 94);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "");
        }
        {
            // label_system_uptime_text
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_uptime_text = obj;
            lv_obj_set_pos(obj, 40, 94);
            lv_obj_set_size(obj, 310, LV_SIZE_CONTENT);
            lv_label_set_long_mode(obj, LV_LABEL_LONG_DOT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text(obj, "เปิดเครื่อง 2 ชม. 15 นาที");
        }
        {
            // label_system_battery_icon
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_battery_icon = obj;
            lv_obj_set_pos(obj, 12, 122);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "");
        }
        {
            // label_system_battery_text
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_battery_text = obj;
            lv_obj_set_pos(obj, 40, 122);
            lv_obj_set_size(obj, 310, LV_SIZE_CONTENT);
            lv_label_set_long_mode(obj, LV_LABEL_LONG_DOT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text(obj, "4.12 V");
        }
        {
            // label_system_city_icon
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_city_icon = obj;
            lv_obj_set_pos(obj, 12, 150);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "");
        }
        {
            // label_system_city_text
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_system_city_text = obj;
            lv_obj_set_pos(obj, 40, 150);
            lv_obj_set_size(obj, 310, LV_SIZE_CONTENT);
            lv_label_set_long_mode(obj, LV_LABEL_LONG_DOT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text(obj, "กรุงเทพฯ · อากาศอัปเดต 11:30 น.");
        }
    }
    
    tick_screen_system_page();
}

void tick_screen_system_page() {
}

void create_screen_portal_page() {
    lv_obj_t *obj = lv_obj_create(0);
    objects.portal_page = obj;
    lv_obj_set_pos(obj, 0, 0);
    lv_obj_set_size(obj, 640, 180);
    lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
    {
        lv_obj_t *parent_obj = obj;
        {
            // cont_portal_wifi_frame
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_portal_wifi_frame = obj;
            lv_obj_set_pos(obj, 14, 15);
            lv_obj_set_size(obj, 150, 150);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(0xffffff), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 8, LV_PART_MAIN | LV_STATE_DEFAULT);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // qrcode_portal_wifi
                    lv_obj_t *obj = lv_qrcode_create(parent_obj, 134, lv_color_hex(0x000000), lv_color_hex(0xffffff));
                    objects.qrcode_portal_wifi = obj;
                    lv_obj_set_pos(obj, 0, 0);
                    lv_obj_set_size(obj, 134, 134);
                    lv_qrcode_update(obj, "WIFI:T:nopass;S:LongDeck-D5C0;;", 31);
                    lv_obj_set_style_align(obj, LV_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                }
            }
        }
        {
            // label_portal_title
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_portal_title = obj;
            lv_obj_set_pos(obj, 176, 10);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_22, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "  ตั้งค่า WiFi");
        }
        {
            // label_portal_step1
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_portal_step1 = obj;
            lv_obj_set_pos(obj, 176, 48);
            lv_obj_set_size(obj, 330, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "1) สแกน QR หรือต่อ WiFi: LongDeck-D5C0");
        }
        {
            // label_portal_step2
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_portal_step2 = obj;
            lv_obj_set_pos(obj, 176, 77);
            lv_obj_set_size(obj, 330, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "2) หน้าตั้งค่าจะเปิดเอง หรือเข้า 192.168.4.1");
        }
        {
            // label_portal_step3
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_portal_step3 = obj;
            lv_obj_set_pos(obj, 176, 106);
            lv_obj_set_size(obj, 330, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "3) เลือก WiFi บ้าน ใส่รหัส แล้วกดบันทึก");
        }
        {
            // label_portal_status
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_portal_status = obj;
            lv_obj_set_pos(obj, 176, 146);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "  รออุปกรณ์เชื่อมต่อ…");
        }
        {
            // cont_portal_url_frame
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_portal_url_frame = obj;
            lv_obj_set_pos(obj, 526, 40);
            lv_obj_set_size(obj, 100, 100);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(0xffffff), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 8, LV_PART_MAIN | LV_STATE_DEFAULT);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // qrcode_portal_url
                    lv_obj_t *obj = lv_qrcode_create(parent_obj, 84, lv_color_hex(0x000000), lv_color_hex(0xffffff));
                    objects.qrcode_portal_url = obj;
                    lv_obj_set_pos(obj, 0, 0);
                    lv_obj_set_size(obj, 84, 84);
                    lv_qrcode_update(obj, "http://192.168.4.1", 18);
                    lv_obj_set_style_align(obj, LV_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                }
            }
        }
        {
            // label_portal_url_caption
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_portal_url_caption = obj;
            lv_obj_set_pos(obj, 544, 144);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "หน้าตั้งค่า");
        }
        {
            // btn_portal_close
            lv_obj_t *obj = lv_btn_create(parent_obj);
            objects.btn_portal_close = obj;
            lv_obj_set_pos(obj, 594, 6);
            lv_obj_set_size(obj, 38, 30);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 15, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_shadow_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // label_portal_btn_close
                    lv_obj_t *obj = lv_label_create(parent_obj);
                    objects.label_portal_btn_close = obj;
                    lv_obj_set_pos(obj, 0, 0);
                    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
                    lv_obj_set_style_align(obj, LV_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_label_set_text_static(obj, "");
                }
            }
        }
    }
    
    tick_screen_portal_page();
}

void tick_screen_portal_page() {
}

void create_screen_splash_page() {
    lv_obj_t *obj = lv_obj_create(0);
    objects.splash_page = obj;
    lv_obj_set_pos(obj, 0, 0);
    lv_obj_set_size(obj, 640, 180);
    lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
    {
        lv_obj_t *parent_obj = obj;
        {
            // spinner_splash
            lv_obj_t *obj = lv_spinner_create(parent_obj, 1000, 60);
            objects.spinner_splash = obj;
            lv_obj_set_pos(obj, 215, 31);
            lv_obj_set_size(obj, 52, 52);
            lv_obj_set_style_arc_width(obj, 5, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_arc_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_arc_width(obj, 5, LV_PART_INDICATOR | LV_STATE_DEFAULT);
            lv_obj_set_style_arc_color(obj, lv_color_hex(0xfacc15), LV_PART_INDICATOR | LV_STATE_DEFAULT);
        }
        {
            // label_splash_title
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_splash_title = obj;
            lv_obj_set_pos(obj, 285, 22);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_32, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "LongDeck");
        }
        {
            // label_splash_subtitle
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_splash_subtitle = obj;
            lv_obj_set_pos(obj, 285, 67);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "นาฬิกา · Mac Deck");
        }
        {
            // cont_splash_underline
            lv_obj_t *obj = lv_obj_create(parent_obj);
            objects.cont_splash_underline = obj;
            lv_obj_set_pos(obj, 210, 106);
            lv_obj_set_size(obj, 220, 4);
            lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_set_style_bg_color(obj, lv_color_hex(theme_colors[active_theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_radius(obj, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
            {
                lv_obj_t *parent_obj = obj;
                {
                    // cont_splash_sweep
                    lv_obj_t *obj = lv_obj_create(parent_obj);
                    objects.cont_splash_sweep = obj;
                    lv_obj_set_pos(obj, 0, 0);
                    lv_obj_set_size(obj, 70, 4);
                    lv_obj_set_style_pad_left(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_top(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_right(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_pad_bottom(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_border_width(obj, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE|LV_OBJ_FLAG_SCROLLABLE);
                    lv_obj_set_style_bg_color(obj, lv_color_hex(0xff4040), LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_bg_opa(obj, 255, LV_PART_MAIN | LV_STATE_DEFAULT);
                    lv_obj_set_style_radius(obj, 2, LV_PART_MAIN | LV_STATE_DEFAULT);
                }
            }
        }
        {
            // label_splash_status
            lv_obj_t *obj = lv_label_create(parent_obj);
            objects.label_splash_status = obj;
            lv_obj_set_pos(obj, 0, 128);
            lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
            lv_obj_set_style_text_font(obj, &ui_font_th_16, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_color(obj, lv_color_hex(theme_colors[active_theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_align(obj, LV_ALIGN_TOP_MID, LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_label_set_text_static(obj, "กำลังเริ่มระบบ…");
        }
    }
    
    tick_screen_splash_page();
}

void tick_screen_splash_page() {
}

typedef void (*tick_screen_func_t)();
tick_screen_func_t tick_screen_funcs[] = {
    tick_screen_clock_page,
    tick_screen_calendar_page,
    tick_screen_focus_page,
    tick_screen_system_page,
    tick_screen_portal_page,
    tick_screen_splash_page,
};
void tick_screen(int screen_index) {
    if (screen_index >= 0 && screen_index < 6) {
        tick_screen_funcs[screen_index]();
    }
}
void tick_screen_by_id(enum ScreensEnum screenId) {
    tick_screen(screenId - 1);
}

//
// Fonts
//

ext_font_desc_t fonts[] = {
    { "digits_128", &ui_font_digits_128 },
    { "digits_56", &ui_font_digits_56 },
    { "th_16", &ui_font_th_16 },
    { "th_22", &ui_font_th_22 },
    { "th_32", &ui_font_th_32 },
#if LV_FONT_MONTSERRAT_8
    { "MONTSERRAT_8", &lv_font_montserrat_8 },
#endif
#if LV_FONT_MONTSERRAT_10
    { "MONTSERRAT_10", &lv_font_montserrat_10 },
#endif
#if LV_FONT_MONTSERRAT_12
    { "MONTSERRAT_12", &lv_font_montserrat_12 },
#endif
#if LV_FONT_MONTSERRAT_14
    { "MONTSERRAT_14", &lv_font_montserrat_14 },
#endif
#if LV_FONT_MONTSERRAT_16
    { "MONTSERRAT_16", &lv_font_montserrat_16 },
#endif
#if LV_FONT_MONTSERRAT_18
    { "MONTSERRAT_18", &lv_font_montserrat_18 },
#endif
#if LV_FONT_MONTSERRAT_20
    { "MONTSERRAT_20", &lv_font_montserrat_20 },
#endif
#if LV_FONT_MONTSERRAT_22
    { "MONTSERRAT_22", &lv_font_montserrat_22 },
#endif
#if LV_FONT_MONTSERRAT_24
    { "MONTSERRAT_24", &lv_font_montserrat_24 },
#endif
#if LV_FONT_MONTSERRAT_26
    { "MONTSERRAT_26", &lv_font_montserrat_26 },
#endif
#if LV_FONT_MONTSERRAT_28
    { "MONTSERRAT_28", &lv_font_montserrat_28 },
#endif
#if LV_FONT_MONTSERRAT_30
    { "MONTSERRAT_30", &lv_font_montserrat_30 },
#endif
#if LV_FONT_MONTSERRAT_32
    { "MONTSERRAT_32", &lv_font_montserrat_32 },
#endif
#if LV_FONT_MONTSERRAT_34
    { "MONTSERRAT_34", &lv_font_montserrat_34 },
#endif
#if LV_FONT_MONTSERRAT_36
    { "MONTSERRAT_36", &lv_font_montserrat_36 },
#endif
#if LV_FONT_MONTSERRAT_38
    { "MONTSERRAT_38", &lv_font_montserrat_38 },
#endif
#if LV_FONT_MONTSERRAT_40
    { "MONTSERRAT_40", &lv_font_montserrat_40 },
#endif
#if LV_FONT_MONTSERRAT_42
    { "MONTSERRAT_42", &lv_font_montserrat_42 },
#endif
#if LV_FONT_MONTSERRAT_44
    { "MONTSERRAT_44", &lv_font_montserrat_44 },
#endif
#if LV_FONT_MONTSERRAT_46
    { "MONTSERRAT_46", &lv_font_montserrat_46 },
#endif
#if LV_FONT_MONTSERRAT_48
    { "MONTSERRAT_48", &lv_font_montserrat_48 },
#endif
};

//
// Color themes
//

uint32_t active_theme_index = 0;
void change_color_theme(uint32_t theme_index) {
    active_theme_index = theme_index;
    
    {
        lv_obj_set_style_bg_color(objects.clock_page, lv_color_hex(theme_colors[theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_d0_a, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_d0_b, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_d1_a, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_d1_b, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_colon, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_d2_a, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_d2_b, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_d3_a, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_d3_b, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_placeholder, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_sec, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_hint, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.panel_clock_info, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_clock_stripe, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_wifi, lv_color_hex(theme_colors[theme_index][6]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_sat, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_day, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_date, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_wx_icon, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_wx_temp, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_clock_wx_text, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.bar_clock_seconds, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.bar_clock_seconds, lv_color_hex(theme_colors[theme_index][4]), LV_PART_INDICATOR | LV_STATE_DEFAULT);
    }
    {
        lv_obj_set_style_bg_color(objects.calendar_page, lv_color_hex(theme_colors[theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_calendar_meter, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_calendar_date, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_calendar_years, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_calendar_doy, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.bar_calendar_year, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.bar_calendar_year, lv_color_hex(theme_colors[theme_index][3]), LV_PART_INDICATOR | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_calendar_year_pct, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_calendar_gift, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_calendar_holiday, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    {
        lv_obj_set_style_bg_color(objects.focus_page, lv_color_hex(theme_colors[theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_arc_color(objects.arc_focus_ring, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_focus_icon, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_focus_time, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_focus_mode, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_focus_dot0, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_color(objects.cont_focus_dot0, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_focus_dot1, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_color(objects.cont_focus_dot1, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_focus_dot2, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_color(objects.cont_focus_dot2, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_focus_dot3, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_border_color(objects.cont_focus_dot3, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_focus_hint, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    {
        lv_obj_set_style_bg_color(objects.system_page, lv_color_hex(theme_colors[theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_sun, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.slider_system_brightness, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.slider_system_brightness, lv_color_hex(theme_colors[theme_index][3]), LV_PART_INDICATOR | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.slider_system_brightness, lv_color_hex(theme_colors[theme_index][3]), LV_PART_KNOB | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_night, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.switch_system_night, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.switch_system_night, lv_color_hex(theme_colors[theme_index][3]), LV_PART_KNOB | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.switch_system_night, lv_color_hex(theme_colors[theme_index][3]), LV_PART_INDICATOR | LV_STATE_CHECKED);
        lv_obj_set_style_bg_color(objects.btn_system_wifi, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.btn_system_wifi, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_PRESSED);
        lv_obj_set_style_text_color(objects.label_system_btn_wifi, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.btn_system_sync, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.btn_system_sync, lv_color_hex(theme_colors[theme_index][1]), LV_PART_MAIN | LV_STATE_PRESSED);
        lv_obj_set_style_text_color(objects.label_system_btn_sync, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_wifi_icon, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_wifi_text, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_system_bar0, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_system_bar1, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_system_bar2, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_system_bar3, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_dbm, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_ip_icon, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_ip_text, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_sync_icon, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_sync_text, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_uptime_icon, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_uptime_text, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_battery_icon, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_battery_text, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_city_icon, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_system_city_text, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    {
        lv_obj_set_style_bg_color(objects.portal_page, lv_color_hex(theme_colors[theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_portal_title, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_portal_step1, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_portal_step2, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_portal_step3, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_portal_status, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_portal_url_caption, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.btn_portal_close, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_portal_btn_close, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    {
        lv_obj_set_style_bg_color(objects.splash_page, lv_color_hex(theme_colors[theme_index][0]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_arc_color(objects.spinner_splash, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_splash_title, lv_color_hex(theme_colors[theme_index][3]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_splash_subtitle, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_color(objects.cont_splash_underline, lv_color_hex(theme_colors[theme_index][2]), LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_text_color(objects.label_splash_status, lv_color_hex(theme_colors[theme_index][4]), LV_PART_MAIN | LV_STATE_DEFAULT);
    }
    lv_obj_invalidate(objects.clock_page);
    lv_obj_invalidate(objects.calendar_page);
    lv_obj_invalidate(objects.focus_page);
    lv_obj_invalidate(objects.system_page);
    lv_obj_invalidate(objects.portal_page);
    lv_obj_invalidate(objects.splash_page);
}
uint32_t theme_colors[1][9] = {
    { 0xff05070a, 0xff121820, 0xff1c2530, 0xfff2f4f7, 0xff7d8794, 0xff4ade80, 0xfffbbf24, 0xfff87171, 0xffc2341f },
};

//
//
//

void create_screens() {

// Set default LVGL theme
    lv_disp_t *dispp = lv_disp_get_default();
    lv_theme_t *theme = lv_theme_default_init(dispp, lv_palette_main(LV_PALETTE_BLUE), lv_palette_main(LV_PALETTE_RED), false, LV_FONT_DEFAULT);
    lv_disp_set_theme(dispp, theme);
    
    // Initialize screens
    // Create screens
    create_screen_clock_page();
    create_screen_calendar_page();
    create_screen_focus_page();
    create_screen_system_page();
    create_screen_portal_page();
    create_screen_splash_page();
}
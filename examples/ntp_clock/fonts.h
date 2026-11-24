#pragma once

#include "lvgl.h"

// Names match the EEZ project fonts so generated screens link to these.
// Kanit (OFL). Digits fonts hold only "0-9 :" (+ " %+-./C°—" for 56px).
LV_FONT_DECLARE(ui_font_digits_128);
LV_FONT_DECLARE(ui_font_digits_56);

// Thai + ASCII + "°·•–—…" + all LV_SYMBOL_* + the SYM_* icons below.
LV_FONT_DECLARE(ui_font_th_32);
LV_FONT_DECLARE(ui_font_th_22);
LV_FONT_DECLARE(ui_font_th_16);

#define SYM_SUN               "\xEF\x86\x85"
#define SYM_MOON              "\xEF\x86\x86"
#define SYM_CLOUD             "\xEF\x83\x82"
#define SYM_CLOUD_SUN         "\xEF\x9B\x84"
#define SYM_CLOUD_MOON        "\xEF\x9B\x83"
#define SYM_CLOUD_RAIN        "\xEF\x9C\xBD"
#define SYM_CLOUD_HEAVY_RAIN  "\xEF\x9D\x80"
#define SYM_SNOWFLAKE         "\xEF\x8B\x9C"
#define SYM_FOG               "\xEF\x9D\x9F"
#define SYM_THERMOMETER       "\xEF\x8B\x89"
#define SYM_DROPLET           "\xEF\x81\x83"
#define SYM_CLOCK             "\xEF\x80\x97"
#define SYM_HOURGLASS         "\xEF\x89\x92"
#define SYM_STOPWATCH         "\xEF\x8B\xB2"
#define SYM_CALENDAR          "\xEF\x81\xB3"
#define SYM_GLOBE             "\xEF\x82\xAC"
#define SYM_QRCODE            "\xEF\x80\xA9"
#define SYM_PHONE             "\xEF\x8F\x8D"
#define SYM_CHECK_CIRCLE      "\xEF\x81\x98"
#define SYM_X_CIRCLE          "\xEF\x81\x97"
#define SYM_COFFEE            "\xEF\x83\xB4"
#define SYM_BRAIN             "\xEF\x97\x9C"
#define SYM_GIFT              "\xEF\x81\xAB"
#define SYM_PIN               "\xEF\x8F\x85"
#define SYM_SATELLITE         "\xEF\x9F\x80"
#define SYM_SIGNAL            "\xEF\x80\x92"
#define SYM_STAR              "\xEF\x80\x85"

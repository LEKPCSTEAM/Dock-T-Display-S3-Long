#include "ui_internal.h"

const char *const TH_DAY_NAME[7] = {
    "อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์",
};

const char *const TH_MONTH_FULL[12] = {
    "มกราคม", "กุมภาพันธ์", "มีนาคม",   "เมษายน",  "พฤษภาคม",  "มิถุนายน",
    "กรกฎาคม", "สิงหาคม",   "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม",
};

const char *const TH_MONTH_SHORT[12] = {
    "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
    "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค.",
};

lv_color_t ui_day_color(int wday)
{
    static const uint32_t colors[7] = {
        0xEF4444,  // Sunday red
        0xFACC15,  // Monday yellow
        0xF472B6,  // Tuesday pink
        0x22C55E,  // Wednesday green
        0xFB923C,  // Thursday orange
        0x38BDF8,  // Friday light blue
        0xA855F7,  // Saturday purple
    };
    return lv_color_hex(colors[((wday % 7) + 7) % 7]);
}

bool ui_is_night(const struct tm *now, const ClockSettings *s)
{
    return s->auto_night && (now->tm_hour >= 22 || now->tm_hour < 6);
}

lv_color_t ui_accent(const struct tm *now, const ClockSettings *s, bool night)
{
    if (night) {
        return COLOR_NIGHT;
    }
    switch (s->theme) {
    case THEME_RAINBOW:
        // One full hue turn every ~22 s.
        return lv_color_hsv_to_rgb((lv_tick_get() / 60) % 360, 70, 100);
    case THEME_MONO:
        return lv_color_hex(0xE5E7EB);
    default:
        return ui_day_color(now->tm_wday);
    }
}

int ui_be_year(const struct tm *t)
{
    return t->tm_year + 1900 + 543;
}

const char *ui_weather_text(uint16_t code)
{
    switch (code) {
    case 0:  return "ท้องฟ้าแจ่มใส";
    case 1:  return "มีเมฆเล็กน้อย";
    case 2:  return "มีเมฆบางส่วน";
    case 3:  return "เมฆมาก";
    case 45:
    case 48: return "มีหมอก";
    case 51:
    case 53:
    case 55:
    case 56:
    case 57: return "ฝนปรอย";
    case 61: return "ฝนเล็กน้อย";
    case 63: return "ฝนปานกลาง";
    case 65: return "ฝนหนัก";
    case 66:
    case 67: return "ฝนตก";
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86: return "หิมะตก";
    case 80: return "ฝนซู่เล็กน้อย";
    case 81: return "ฝนซู่";
    case 82: return "ฝนซู่หนัก";
    case 95: return "พายุฝนฟ้าคะนอง";
    case 96:
    case 99: return "พายุลูกเห็บ";
    default: return "-";
    }
}

const char *ui_weather_icon(uint16_t code, bool is_day)
{
    if (code == 0) {
        return is_day ? SYM_SUN : SYM_MOON;
    }
    if (code <= 2) {
        return is_day ? SYM_CLOUD_SUN : SYM_CLOUD_MOON;
    }
    if (code == 3) {
        return SYM_CLOUD;
    }
    if (code == 45 || code == 48) {
        return SYM_FOG;
    }
    if (code == 65 || code == 82) {
        return SYM_CLOUD_HEAVY_RAIN;
    }
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
        return SYM_SNOWFLAKE;
    }
    if (code >= 95) {
        return LV_SYMBOL_CHARGE;
    }
    return SYM_CLOUD_RAIN;
}

lv_obj_t *ui_label(lv_obj_t *parent, const lv_font_t *font, lv_color_t color, const char *text)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, color, 0);
    lv_label_set_text(label, text);
    return label;
}

void ui_strip_obj(lv_obj_t *obj)
{
    lv_obj_remove_style_all(obj);
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
}

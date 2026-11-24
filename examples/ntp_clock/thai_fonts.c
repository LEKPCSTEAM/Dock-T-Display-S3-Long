#include "lvgl.h"

LV_FONT_DECLARE(font_th_16_base);
LV_FONT_DECLARE(font_th_22_base);
LV_FONT_DECLARE(font_th_32_base);

typedef struct {
    const lv_font_t *base;
    int8_t           tone_raise;  // px: lifts a tone mark clear of an upper vowel
} thai_font_dsc_t;

static bool is_upper_vowel(uint32_t c)
{
    return c == 0x0E31 || (c >= 0x0E34 && c <= 0x0E37) || c == 0x0E47;
}

static bool is_tone_mark(uint32_t c)
{
    return c >= 0x0E48 && c <= 0x0E4C;
}

// No GPOS in LVGL: stack tone marks by hand using the previous letter.
// LVGL queries glyphs in text order (often twice per letter), so track the last distinct one.
static bool thai_glyph_dsc(const lv_font_t *font, lv_font_glyph_dsc_t *dsc, uint32_t letter, uint32_t next)
{
    static uint32_t cur, prev;
    if (letter != cur) {
        prev = cur;
        cur  = letter;
    }

    const thai_font_dsc_t *t = (const thai_font_dsc_t *)font->dsc;
    if (!t->base->get_glyph_dsc(t->base, dsc, letter, next)) {
        return false;
    }
    if (is_tone_mark(letter) && is_upper_vowel(prev)) {
        dsc->ofs_y += t->tone_raise;
    }
    return true;
}

static const uint8_t *thai_glyph_bitmap(const lv_font_t *font, uint32_t letter)
{
    const thai_font_dsc_t *t = (const thai_font_dsc_t *)font->dsc;
    return t->base->get_glyph_bitmap(t->base, letter);
}

// Raise and extra line height measured from the generated Kanit metrics.
static const thai_font_dsc_t th16 = {&font_th_16_base, 6};
static const thai_font_dsc_t th22 = {&font_th_22_base, 8};
static const thai_font_dsc_t th32 = {&font_th_32_base, 9};

const lv_font_t font_th_16 = {
    .get_glyph_dsc       = thai_glyph_dsc,
    .get_glyph_bitmap    = thai_glyph_bitmap,
    .line_height         = 20 + 5,
    .base_line           = 5,
    .subpx               = LV_FONT_SUBPX_NONE,
    .underline_position  = -2,
    .underline_thickness = 1,
    .dsc                 = &th16,
};

const lv_font_t font_th_22 = {
    .get_glyph_dsc       = thai_glyph_dsc,
    .get_glyph_bitmap    = thai_glyph_bitmap,
    .line_height         = 26 + 7,
    .base_line           = 6,
    .subpx               = LV_FONT_SUBPX_NONE,
    .underline_position  = -2,
    .underline_thickness = 1,
    .dsc                 = &th22,
};

const lv_font_t font_th_32 = {
    .get_glyph_dsc       = thai_glyph_dsc,
    .get_glyph_bitmap    = thai_glyph_bitmap,
    .line_height         = 38 + 7,
    .base_line           = 9,
    .subpx               = LV_FONT_SUBPX_NONE,
    .underline_position  = -3,
    .underline_thickness = 2,
    .dsc                 = &th32,
};

#!/usr/bin/env bash
# Regenerates the LVGL fonts. Needs lv_font_conv 1.5.x and the Kanit TTFs (OFL).
# Usage: KANIT_DIR=/path/to/kanit ./gen_fonts.sh
set -euo pipefail

cd "$(dirname "$0")"
KANIT_DIR="${KANIT_DIR:-${TMPDIR:-/tmp}/kanit}"
FA="../../../lib/lvgl/scripts/built_in_font/FontAwesome5-Solid+Brands+Regular.woff"

if [ ! -f "$KANIT_DIR/Kanit-Medium.ttf" ]; then
    mkdir -p "$KANIT_DIR"
    for w in Regular Medium; do
        curl -sSL -o "$KANIT_DIR/Kanit-$w.ttf" "https://github.com/google/fonts/raw/main/ofl/kanit/Kanit-$w.ttf"
    done
fi

LVGL_SYMS="61441,61448,61451,61452,61453,61457,61459,61461,61465,61468,61473,61478,61479,61480,61502,61507,61512,61515,61516,61517,61521,61522,61523,61524,61543,61544,61550,61552,61553,61556,61559,61560,61561,61563,61587,61589,61636,61637,61639,61641,61664,61671,61674,61683,61724,61732,61787,61931,62016,62017,62018,62019,62020,62087,62099,62212,62189,62810,63426,63650"
# Weather, calendar and status icons used by fonts.h SYM_* macros.
EXTRA_SYMS="0xF185,0xF186,0xF0C2,0xF6C4,0xF6C3,0xF73D,0xF740,0xF2DC,0xF75F,0xF2C9,0xF043,0xF017,0xF252,0xF2F2,0xF073,0xF0AC,0xF029,0xF3CD,0xF058,0xF057,0xF0F4,0xF5DC,0xF06B,0xF3C5,0xF7C0,0xF012,0xF005"
TEXT_RANGE="0x20-0x7E,0x0E01-0x0E3A,0x0E3F-0x0E5B,0xB0,0xB7,0x2022,0x2013,0x2014,0x2026"

conv() { lv_font_conv --bpp 4 --no-compress --format lvgl --lv-include lvgl.h "$@"; }

conv --font "$KANIT_DIR/Kanit-Medium.ttf" -r 0x30-0x3A --size 128 -o font_digits_128.c
conv --font "$KANIT_DIR/Kanit-Medium.ttf" -r 0x20-0x3A,0x43,0xB0,0x2014 --size 56 -o font_digits_56.c

# *_base fonts are wrapped by ../thai_fonts.c, which stacks tone marks.
for spec in "Medium 32" "Regular 22" "Regular 16"; do
    set -- $spec
    conv --font "$KANIT_DIR/Kanit-$1.ttf" -r "$TEXT_RANGE" \
         --font "$FA" -r "$LVGL_SYMS,$EXTRA_SYMS" \
         --size "$2" -o "font_th_$2_base.c"
done

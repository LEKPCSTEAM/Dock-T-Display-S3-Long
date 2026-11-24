#pragma once

#include <stdint.h>

// Call only from the LVGL (Arduino loop) task: PMU shares I2C with touch.
void    board_backlight_begin();
void    board_set_backlight(uint8_t level);  // 0..255
uint8_t board_get_backlight();
bool    board_has_pmu();
int     board_battery_mv();                  // -1 when no PMU or no battery
bool    board_usb_powered();

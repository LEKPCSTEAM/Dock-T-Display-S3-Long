#include <Arduino.h>
#include <Wire.h>
#include <time.h>
#include "lvgl.h"
#include "pins_config.h"
#include "AXS15231B.h"
#include "hyn_core.h"
#include "app_state.h"
#include "board.h"
#include "ui.h"

#define BUTTON_LONG_PRESS_MS 2000
#define BUTTON_DEBOUNCE_MS   40
#define AXS_TOUCH_ADDR       0x3B  // touch built into AXS15231B (pre-CST3530 boards)
#define TOUCH_PRESS_READS    3
#define TOUCH_RELEASE_READS  2

extern uint32_t transfer_num;
extern size_t   lcd_PushColors_len;

static lv_disp_draw_buf_t draw_buf;
static bool               touch_is_axs = false;

static void disp_flush(lv_disp_drv_t *disp, const lv_area_t *area, lv_color_t *color_p)
{
    uint32_t w = area->x2 - area->x1 + 1;
    uint32_t h = area->y2 - area->y1 + 1;
    while (get_lcd_spi_dma_write()) {
        lcd_PushColors(0, 0, 0, 0, NULL);
    }
    // lv_disp_flush_ready() is called from the DMA-done ISR in AXS15231B.cpp.
    lcd_PushColors(area->x1, area->y1, w, h, (uint16_t *)&color_p->full);
    // Low-heap guard queued nothing; drop the chunk instead of hanging LVGL.
    if (!get_lcd_spi_dma_write()) {
        lv_disp_flush_ready(disp);
    }
}

static bool i2c_probe(uint8_t addr)
{
    Wire.beginTransmission(addr);
    return Wire.endTransmission() == 0;
}

static void touch_read_axs(lv_indev_data_t *data)
{
    static const uint8_t cmd[8] = {0xB5, 0xAB, 0xA5, 0x5A, 0x00, 0x00, 0x00, 0x08};
    static uint8_t       good = 0;
    static uint8_t       bad  = 0;
    static lv_point_t    last;
    uint8_t              buf[8] = {0};

    bool ok = false;
    Wire.beginTransmission(AXS_TOUCH_ADDR);
    Wire.write(cmd, sizeof(cmd));
    if (Wire.endTransmission() == 0 && Wire.requestFrom((uint8_t)AXS_TOUCH_ADDR, (uint8_t)8) == 8) {
        Wire.readBytes(buf, sizeof(buf));
        uint8_t  gesture = buf[0];
        uint8_t  fingers = buf[1];
        uint8_t  event   = buf[2] >> 6;  // 0 down, 1 lift, 2 contact
        uint16_t x       = ((buf[2] & 0x0F) << 8) | buf[3];
        uint16_t y       = ((buf[4] & 0x0F) << 8) | buf[5];
        // Idle reads return junk finger counts; only single-finger contact is real.
        ok = gesture == 0 && fingers == 1 && event != 1 && (x || y);
        if (ok) {
            // Controller reports landscape; LVGL wants the unrotated 180x640 frame.
            last.x = y > EXAMPLE_LCD_H_RES ? EXAMPLE_LCD_H_RES : y;
            last.y = x > EXAMPLE_LCD_V_RES ? EXAMPLE_LCD_V_RES : EXAMPLE_LCD_V_RES - x;
        }
    }

    // Ghost reports come as isolated samples, so press/release need consecutive reads.
    if (ok) {
        bad = 0;
        if (good < TOUCH_PRESS_READS) good++;
    } else if (++bad >= TOUCH_RELEASE_READS) {
        good = 0;
    }
    data->point = last;
    data->state = good >= TOUCH_PRESS_READS ? LV_INDEV_STATE_PR : LV_INDEV_STATE_REL;
}

static void touch_read(lv_indev_drv_t *drv, lv_indev_data_t *data)
{
    if (touch_is_axs) {
        touch_read_axs(data);
        return;
    }
    struct hyn_ts_data *ts = get_touch_data();
    if (ts->rp_buf.rep_num > 0) {
        data->state   = LV_INDEV_STATE_PR;
        data->point.x = ts->rp_buf.pos_info[0].pos_x;
        data->point.y = ts->rp_buf.pos_info[0].pos_y;
    } else {
        data->state = LV_INDEV_STATE_REL;
    }
}

static void lvgl_begin()
{
    lv_init();

    size_t      px  = EXAMPLE_LCD_H_RES * EXAMPLE_LCD_V_RES;
    lv_color_t *bf1 = (lv_color_t *)ps_malloc(px * sizeof(lv_color_t));
    lv_color_t *bf2 = (lv_color_t *)ps_malloc(px * sizeof(lv_color_t));
    while (bf1 == NULL || bf2 == NULL) {
        Serial.println("LVGL draw buffer alloc failed (PSRAM?)");
        delay(1000);
    }
    lv_disp_draw_buf_init(&draw_buf, bf1, bf2, px);

    static lv_disp_drv_t disp_drv;
    lv_disp_drv_init(&disp_drv);
    disp_drv.hor_res      = EXAMPLE_LCD_H_RES;
    disp_drv.ver_res      = EXAMPLE_LCD_V_RES;
    disp_drv.flush_cb     = disp_flush;
    disp_drv.draw_buf     = &draw_buf;
    disp_drv.sw_rotate    = 1;  // panel is 180x640 portrait, UI is landscape
    disp_drv.rotated      = LV_DISP_ROT_90;
    disp_drv.full_refresh = 1;  // required by the QSPI driver with sw_rotate
    lv_disp_drv_register(&disp_drv);

    static lv_indev_drv_t indev_drv;
    lv_indev_drv_init(&indev_drv);
    indev_drv.type    = LV_INDEV_TYPE_POINTER;
    indev_drv.read_cb = touch_read;
    lv_indev_drv_register(&indev_drv);
}

static void lvgl_service()
{
    if (transfer_num <= 0 && lcd_PushColors_len <= 0) {
        lv_timer_handler();
    }
    if (transfer_num <= 1 && lcd_PushColors_len > 0) {
        lcd_PushColors(0, 0, 0, 0, NULL);
    }
}

static void button_service()
{
    static bool     last_raw      = false;
    static bool     pressed       = false;
    static bool     long_fired    = false;
    static uint32_t last_change   = 0;
    static uint32_t pressed_since = 0;

    bool     raw = digitalRead(PIN_BUTTON_1) == LOW;
    uint32_t now = millis();
    if (raw != last_raw) {
        last_raw    = raw;
        last_change = now;
    }
    if (now - last_change < BUTTON_DEBOUNCE_MS || raw == pressed) {
        if (pressed && !long_fired && now - pressed_since >= BUTTON_LONG_PRESS_MS) {
            long_fired = true;
            net_request_portal();
        }
        return;
    }

    pressed = raw;
    if (pressed) {
        pressed_since = now;
        long_fired    = false;
    } else if (!long_fired) {
        ui_next_page();
    }
}

void setup()
{
    Serial.begin(115200);

    setenv("TZ", CLOCK_TZ, 1);
    tzset();

    pinMode(PIN_BUTTON_1, INPUT_PULLUP);
    Wire.begin(I2C_SDA, I2C_SCL);
    board_backlight_begin();

    axs15231_init();
    touch_is_axs = i2c_probe(AXS_TOUCH_ADDR);
    if (!touch_is_axs) {
        touch_init(I2C_SDA, I2C_SCL, TP_IRQ, TP_RST);
    }
    Serial.printf("touch: %s\n", touch_is_axs ? "AXS15231B" : "CST3530");
    lvgl_begin();

    settings_begin();
    ui_init();
    net_begin();
}

void loop()
{
    lvgl_service();
    button_service();
    delay(1);
}

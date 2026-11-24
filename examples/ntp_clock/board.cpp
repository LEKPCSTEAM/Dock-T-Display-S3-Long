#include "board.h"
#include <Arduino.h>
#include <Wire.h>
#include <XPowersLib.h>
#include "pins_config.h"

#define BL_LEDC_CHANNEL 0
#define BL_LEDC_FREQ    20000  // above audible range, no coil whine
#define BL_LEDC_BITS    8

#define BOARD_INPUT_LIMIT_MA 1500
#define BOARD_SYS_MIN_MV     3700  // SY6970 maximum

static PowersSY6970 pmu;
static bool         pmu_ok = false;
static uint8_t      backlight = 0;

void board_backlight_begin()
{
    ledcSetup(BL_LEDC_CHANNEL, BL_LEDC_FREQ, BL_LEDC_BITS);
    ledcAttachPin(TFT_BL, BL_LEDC_CHANNEL);
    ledcWrite(BL_LEDC_CHANNEL, 0);

    pmu_ok = pmu.init(Wire, I2C_SDA, I2C_SCL, SY6970_SLAVE_ADDRESS);
    if (pmu_ok) {
        pmu.enableADCMeasure();
        pmu.disableStatLed();
        pmu.disableOTG();
        // Auto-detect picks 500 mA; WiFi TX peaks then brown out VSYS.
        pmu.setInputCurrentLimit(BOARD_INPUT_LIMIT_MA);
        // Without a battery VSYS sags to SYS_MIN (3.5 V default), too close to the 3.3 V LDO.
        pmu.setSysPowerDownVoltage(BOARD_SYS_MIN_MV);
    }
}

void board_set_backlight(uint8_t level)
{
    backlight = level;
    ledcWrite(BL_LEDC_CHANNEL, level);
}

uint8_t board_get_backlight()
{
    return backlight;
}

bool board_has_pmu()
{
    return pmu_ok;
}

int board_battery_mv()
{
    if (!pmu_ok) {
        return -1;
    }
    int mv = pmu.getBattVoltage();
    return mv < 2500 ? -1 : mv;  // not a plausible Li-ion reading
}

bool board_usb_powered()
{
    return pmu_ok ? pmu.isVbusIn() : true;
}

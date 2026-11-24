#pragma once

#include <stdint.h>
#include <stddef.h>
#include <time.h>

#define CLOCK_TZ          "ICT-7"
#define CLOCK_NTP_1       "time.navy.mi.th"
#define CLOCK_NTP_2       "clock.nectec.or.th"
#define CLOCK_NTP_3       "th.pool.ntp.org"
#define CLOCK_HOSTNAME    "longdeck"
#define CLOCK_AP_PREFIX   "LongDeck-"
#define CLOCK_PORTAL_IP   "192.168.4.1"

enum ClockTheme : uint8_t {
    THEME_DAY_COLOR = 0,
    THEME_RAINBOW,
    THEME_MONO,
    THEME_COUNT,
};

struct ClockSettings {
    uint8_t brightness;  // backlight PWM 10..255
    bool    auto_night;  // dim + red palette from 22:00 to 06:00
    uint8_t theme;       // ClockTheme
    float   latitude;
    float   longitude;
    char    city[48];    // UTF-8
};

// All settings_* and net_* functions are thread-safe.
void          settings_begin();
ClockSettings settings_get();
void          settings_set(const ClockSettings &s);  // writes NVS: avoid calling per slider step
uint32_t      settings_version();                    // bumps on every settings_set

bool settings_get_wifi(char *ssid, size_t ssid_len, char *pass, size_t pass_len);
void settings_set_wifi(const char *ssid, const char *pass);
void settings_clear_wifi();

bool settings_get_deck_key(uint8_t key[32]);
void settings_set_deck_key(const uint8_t key[32]);
void settings_clear_deck_key();

enum NetPhase : uint8_t {
    NET_BOOTING = 0,
    NET_CONNECTING,  // trying the saved network
    NET_CONNECTED,
    NET_PORTAL,      // config AP + captive portal running
    NET_OFFLINE,     // saved network unreachable, retrying in background
};

struct WeatherInfo {
    bool     valid;
    float    temp_c;
    uint8_t  humidity;  // %
    uint16_t code;      // WMO weather interpretation code
    bool     is_day;
    time_t   updated;
};

struct NetStatus {
    NetPhase    phase;
    char        ssid[33];
    char        ip[16];
    int8_t      rssi;           // dBm, valid when NET_CONNECTED
    char        ap_ssid[33];    // valid when NET_PORTAL
    bool        portal_client;  // a station is joined to the config AP
    bool        portal_manual;  // opened by the user, not by a failed connect
    bool        time_synced;
    time_t      last_sync;      // 0 = never
    WeatherInfo weather;
};

void net_begin();  // after settings_begin(); runs on its own task, core 0
void net_get_status(NetStatus *out);
void net_request_portal();
void net_cancel_portal();
void net_request_ntp_sync();
void net_request_weather();

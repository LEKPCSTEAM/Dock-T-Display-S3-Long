#include <Arduino.h>
#include <Preferences.h>
#include <string.h>
#include "app_state.h"

#define NVS_NS     "longdeck"
#define NVS_NS_OLD "thai" "clock"

static SemaphoreHandle_t s_mutex;
static ClockSettings     s_cur;
static uint32_t          s_version;

static ClockSettings defaults()
{
    ClockSettings s;
    memset(&s, 0, sizeof(s));
    s.brightness = 200;
    s.auto_night = true;
    s.theme      = THEME_DAY_COLOR;
    s.latitude   = 13.7563f;
    s.longitude  = 100.5018f;
    strlcpy(s.city, "กรุงเทพฯ", sizeof(s.city));
    return s;
}

static void sanitize(ClockSettings &s)
{
    if (s.brightness < 10) s.brightness = 10;
    if (s.theme >= THEME_COUNT) s.theme = THEME_DAY_COLOR;
    if (!(s.latitude >= -90.0f && s.latitude <= 90.0f)) s.latitude = 13.7563f;
    if (!(s.longitude >= -180.0f && s.longitude <= 180.0f)) s.longitude = 100.5018f;
    s.city[sizeof(s.city) - 1] = 0;
}

static void lock()
{
    if (s_mutex) xSemaphoreTake(s_mutex, portMAX_DELAY);
}

static void unlock()
{
    if (s_mutex) xSemaphoreGive(s_mutex);
}

static bool copy_str(Preferences &from, Preferences &to, const char *key)
{
    if (!from.isKey(key)) return true;
    String v = from.getString(key, "");
    if (v.length() == 0) return true;
    return to.putString(key, v) == v.length();
}

static void migrate_old_namespace()
{
    Preferences dst;
    if (!dst.begin(NVS_NS, false)) return;
    if (dst.isKey("ssid")) {
        dst.end();
        return;
    }
    Preferences src;
    if (!src.begin(NVS_NS_OLD, false)) {
        dst.end();
        return;
    }
    if (src.isKey("ssid") || src.isKey("bright")) {
        bool ok = true;
        if (src.isKey("bright")) ok &= dst.putUChar("bright", src.getUChar("bright", 200)) > 0;
        if (src.isKey("night")) ok &= dst.putBool("night", src.getBool("night", true)) > 0;
        if (src.isKey("theme")) ok &= dst.putUChar("theme", src.getUChar("theme", THEME_DAY_COLOR)) > 0;
        if (src.isKey("lat")) ok &= dst.putFloat("lat", src.getFloat("lat", 13.7563f)) > 0;
        if (src.isKey("lon")) ok &= dst.putFloat("lon", src.getFloat("lon", 100.5018f)) > 0;
        ok &= copy_str(src, dst, "city");
        ok &= copy_str(src, dst, "pass");
        ok &= copy_str(src, dst, "ssid");
        if (ok) {
            src.clear();
            Serial.println("[settings] migrated legacy NVS namespace");
        } else {
            Serial.println("[settings] migration failed, keeping old namespace");
        }
    }
    src.end();
    dst.end();
}

void settings_begin()
{
    migrate_old_namespace();
    s_mutex = xSemaphoreCreateMutex();
    lock();
    ClockSettings s = defaults();
    Preferences   p;
    if (p.begin(NVS_NS, false)) {
        if (p.isKey("bright")) s.brightness = p.getUChar("bright", s.brightness);
        if (p.isKey("night")) s.auto_night = p.getBool("night", s.auto_night);
        if (p.isKey("theme")) s.theme = p.getUChar("theme", s.theme);
        if (p.isKey("lat")) s.latitude = p.getFloat("lat", s.latitude);
        if (p.isKey("lon")) s.longitude = p.getFloat("lon", s.longitude);
        if (p.isKey("city")) {
            char   tmp[sizeof(s.city)];
            size_t n = p.getString("city", tmp, sizeof(tmp));
            if (n > 0) strlcpy(s.city, tmp, sizeof(s.city));
        }
        p.end();
    } else {
        Serial.println("[settings] NVS open failed, using defaults");
    }
    sanitize(s);
    s_cur     = s;
    s_version = 1;
    unlock();
}

ClockSettings settings_get()
{
    lock();
    ClockSettings s = s_cur;
    unlock();
    return s;
}

void settings_set(const ClockSettings &in)
{
    ClockSettings s = in;
    sanitize(s);
    lock();
    Preferences p;
    if (p.begin(NVS_NS, false)) {
        p.putUChar("bright", s.brightness);
        p.putBool("night", s.auto_night);
        p.putUChar("theme", s.theme);
        p.putFloat("lat", s.latitude);
        p.putFloat("lon", s.longitude);
        p.putString("city", s.city);
        p.end();
    } else {
        Serial.println("[settings] NVS write failed");
    }
    s_cur = s;
    s_version++;
    unlock();
}

uint32_t settings_version()
{
    lock();
    uint32_t v = s_version;
    unlock();
    return v;
}

bool settings_get_wifi(char *ssid, size_t ssid_len, char *pass, size_t pass_len)
{
    if (ssid == NULL || ssid_len == 0) return false;
    ssid[0] = 0;
    if (pass != NULL && pass_len > 0) pass[0] = 0;
    lock();
    Preferences p;
    bool        ok = false;
    if (p.begin(NVS_NS, false)) {
        if (p.isKey("ssid")) {
            p.getString("ssid", ssid, ssid_len);
            if (pass != NULL && pass_len > 0 && p.isKey("pass")) p.getString("pass", pass, pass_len);
        }
        p.end();
        ok = ssid[0] != 0;
    }
    unlock();
    return ok;
}

void settings_set_wifi(const char *ssid, const char *pass)
{
    lock();
    Preferences p;
    if (p.begin(NVS_NS, false)) {
        p.putString("ssid", ssid ? ssid : "");
        p.putString("pass", pass ? pass : "");
        p.end();
    }
    unlock();
}

void settings_clear_wifi()
{
    lock();
    Preferences p;
    if (p.begin(NVS_NS, false)) {
        p.remove("ssid");
        p.remove("pass");
        p.end();
    }
    unlock();
}

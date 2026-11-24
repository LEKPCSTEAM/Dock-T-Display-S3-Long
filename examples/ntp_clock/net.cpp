#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <esp_sntp.h>
#include <esp_system.h>
#include <math.h>
#include <string.h>
#include <sys/time.h>
#include "app_state.h"
#include "web_pages.h"

#define NET_TASK_STACK        16384
#define CONNECT_TIMEOUT_MS    20000
#define RETRY_MS              30000
#define SAVE_TIMEOUT_MS       20000
#define SAVE_KEEP_AP_MS       8000
#define SAVE_FAIL_SHOW_MS     10000
#define MANUAL_PORTAL_IDLE_MS 300000
#define WEATHER_PERIOD_MS     900000
#define WEATHER_RETRY_MS      60000
#define SCAN_MIN_GAP_MS       10000
#define NTP_SYNC_INTERVAL_MS  3600000
#define MAX_NETS              24

enum SaveState : uint8_t { SAVE_IDLE = 0, SAVE_CONNECTING, SAVE_OK, SAVE_FAIL };

struct ScanEntry {
    char   ssid[33];
    int8_t rssi;
    bool   secure;
};

static SemaphoreHandle_t s_mutex;
static NetStatus         s_status;
static WebServer         s_server(80);
static DNSServer         s_dns;

static volatile bool   f_portal, f_cancel, f_ntp, f_weather;
static volatile bool   s_got_ip, s_ever_connected, s_time_synced;
static volatile time_t s_last_sync;

static bool     portal_active, portal_manual, has_creds, was_connected, ntp_started, mdns_started;
static char     cur_ssid[33], cur_pass[65], sta_ssid[33], ap_ssid[33];
static uint32_t connect_start, last_retry, last_client_ms, last_publish;
static uint32_t reboot_at;

static SaveState save_state;
static char      save_ssid[33], save_pass[65], save_ip[16];
static uint32_t  save_start, save_end_ms;

static ScanEntry scan_list[MAX_NETS];
static int       scan_count;
static bool      scan_running;
static uint32_t  last_scan_ms;

static bool     weather_due;
static uint32_t weather_next;
static float    weather_lat, weather_lon;
static uint32_t seen_settings_ver;

static void on_wifi_event(arduino_event_id_t ev, arduino_event_info_t info)
{
    switch (ev) {
    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
        s_got_ip         = true;
        s_ever_connected = true;
        break;
    case ARDUINO_EVENT_WIFI_STA_LOST_IP:
        s_got_ip = false;
        break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
        s_got_ip = false;
        Serial.printf("[net] sta disconnected, reason %u\n", info.wifi_sta_disconnected.reason);
        break;
    default:
        break;
    }
}

static void on_ntp_sync(struct timeval *tv)
{
    s_last_sync   = tv->tv_sec;
    s_time_synced = true;
    Serial.println("[ntp] synced");
}

static void json_str(String &o, const char *s)
{
    o += '"';
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') {
            o += '\\';
            o += (char)c;
        } else if (c < 0x20 || c == 0x7f) {
            char b[8];
            snprintf(b, sizeof(b), "\\u%04x", c);
            o += b;
        } else {
            o += (char)c;
        }
    }
    o += '"';
}

static void sta_begin(const char *ssid, const char *pass)
{
    // WiFi.begin() with the live config returns early and fires no events.
    if (WiFi.isConnected() && WiFi.SSID() == ssid && WiFi.psk() == (pass ? pass : "")) return;
    s_got_ip = false;
    WiFi.begin(ssid, (pass && pass[0]) ? pass : NULL);
}

static void publish(NetPhase phase)
{
    bool   connected = s_got_ip;
    int8_t rssi = connected ? (int8_t)WiFi.RSSI() : 0;
    bool   cli  = portal_active && WiFi.softAPgetStationNum() > 0;

    xSemaphoreTake(s_mutex, portMAX_DELAY);
    s_status.phase = phase;
    strlcpy(s_status.ssid, connected ? sta_ssid : cur_ssid, sizeof(s_status.ssid));
    if (connected) {
        strlcpy(s_status.ip, WiFi.localIP().toString().c_str(), sizeof(s_status.ip));
        s_status.rssi = rssi;
    } else {
        s_status.ip[0] = 0;
        s_status.rssi  = 0;
    }
    strlcpy(s_status.ap_ssid, portal_active ? ap_ssid : "", sizeof(s_status.ap_ssid));
    s_status.portal_client = cli;
    s_status.portal_manual = portal_active && portal_manual;
    s_status.time_synced   = s_time_synced;
    s_status.last_sync     = s_last_sync;
    xSemaphoreGive(s_mutex);
}

static void scan_start(uint32_t now)
{
    if (scan_running || save_state == SAVE_CONNECTING) return;
    last_scan_ms = now;
    WiFi.scanNetworks(true, false);
    scan_running = true;
}

static void scan_collect(int n)
{
    scan_count = 0;
    for (int i = 0; i < n; i++) {
        String ssid = WiFi.SSID(i);
        if (ssid.length() == 0 || ssid.length() > 32) continue;
        int8_t rssi   = (int8_t)WiFi.RSSI(i);
        bool   secure = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
        int    dup    = -1;
        for (int j = 0; j < scan_count; j++) {
            if (strcmp(scan_list[j].ssid, ssid.c_str()) == 0) {
                dup = j;
                break;
            }
        }
        if (dup >= 0) {
            if (rssi > scan_list[dup].rssi) {
                scan_list[dup].rssi   = rssi;
                scan_list[dup].secure = secure;
            }
            continue;
        }
        int slot = scan_count;
        if (scan_count < MAX_NETS) {
            scan_count++;
        } else {
            slot = 0;
            for (int j = 1; j < MAX_NETS; j++) {
                if (scan_list[j].rssi < scan_list[slot].rssi) slot = j;
            }
            if (rssi <= scan_list[slot].rssi) continue;
        }
        strlcpy(scan_list[slot].ssid, ssid.c_str(), sizeof(scan_list[slot].ssid));
        scan_list[slot].rssi   = rssi;
        scan_list[slot].secure = secure;
    }
    for (int i = 1; i < scan_count; i++) {
        ScanEntry e = scan_list[i];
        int       j = i - 1;
        while (j >= 0 && scan_list[j].rssi < e.rssi) {
            scan_list[j + 1] = scan_list[j];
            j--;
        }
        scan_list[j + 1] = e;
    }
}

static void scan_poll()
{
    if (!scan_running) return;
    int n = WiFi.scanComplete();
    if (n == WIFI_SCAN_RUNNING) return;
    scan_running = false;
    if (n >= 0) {
        scan_collect(n);
        Serial.printf("[net] scan: %d unique networks\n", scan_count);
    }
    WiFi.scanDelete();
}

static void open_portal(bool manual, uint32_t now)
{
    portal_active  = true;
    portal_manual  = manual;
    save_state     = SAVE_IDLE;
    last_client_ms = now;
    last_retry     = now;
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP(ap_ssid);
    if (!manual) WiFi.setAutoReconnect(false);
    s_dns.start(53, "*", WiFi.softAPIP());
    scan_count = 0;
    scan_start(now);
    Serial.printf("[net] portal open: %s (%s)\n", ap_ssid, manual ? "manual" : "auto");
}

static void close_portal()
{
    s_dns.stop();
    WiFi.softAPdisconnect(true);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    portal_active = false;
    scan_running  = false;
    WiFi.scanDelete();
    Serial.println("[net] portal closed");
}

static bool find_num(const char *base, const char *key, double *out)
{
    char pat[40];
    snprintf(pat, sizeof(pat), "\"%s\":", key);
    const char *p = strstr(base, pat);
    if (!p) return false;
    p += strlen(pat);
    char *end;
    double v = strtod(p, &end);
    if (end == p) return false;
    *out = v;
    return true;
}

static bool parse_weather(const char *body, WeatherInfo *w)
{
    const char *cur = strstr(body, "\"current\":{");
    if (!cur) return false;
    double t, h, c, d;
    if (!find_num(cur, "temperature_2m", &t) || !find_num(cur, "relative_humidity_2m", &h) ||
        !find_num(cur, "weather_code", &c) || !find_num(cur, "is_day", &d)) {
        return false;
    }
    w->valid    = true;
    w->temp_c   = (float)t;
    w->humidity = (uint8_t)constrain((int)h, 0, 100);
    w->code     = (uint16_t)constrain((int)c, 0, 999);
    w->is_day   = d > 0.5;
    w->updated  = time(NULL);
    return true;
}

static bool weather_fetch()
{
    ClockSettings cs = settings_get();
    weather_lat      = cs.latitude;
    weather_lon      = cs.longitude;
    char url[220];
    snprintf(url, sizeof(url),
             "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
             "&current=temperature_2m,relative_humidity_2m,weather_code,is_day&timezone=Asia%%2FBangkok",
             cs.latitude, cs.longitude);

    WeatherInfo w;
    memset(&w, 0, sizeof(w));
    bool ok = false;
    {
        WiFiClientSecure client;
        client.setInsecure();
        client.setTimeout(8);
        HTTPClient http;
        http.setConnectTimeout(8000);
        http.setTimeout(8000);
        if (http.begin(client, url)) {
            int code = http.GET();
            if (code == 200) {
                String body = http.getString();
                ok          = parse_weather(body.c_str(), &w);
            } else {
                Serial.printf("[weather] http %d\n", code);
            }
            http.end();
        }
    }
    if (ok) {
        xSemaphoreTake(s_mutex, portMAX_DELAY);
        s_status.weather = w;
        xSemaphoreGive(s_mutex);
        Serial.printf("[weather] %.1fC %u%% code %u\n", w.temp_c, w.humidity, w.code);
    } else {
        Serial.println("[weather] fetch failed");
    }
    Serial.printf("[weather] free heap %u\n", (unsigned)ESP.getFreeHeap());
    return ok;
}

static void on_connected(uint32_t now)
{
    strlcpy(sta_ssid, WiFi.SSID().c_str(), sizeof(sta_ssid));
    Serial.printf("[net] connected to %s ip %s\n", sta_ssid, WiFi.localIP().toString().c_str());

    if (mdns_started) MDNS.end();
    mdns_started = MDNS.begin(CLOCK_HOSTNAME);
    if (mdns_started) MDNS.addService("http", "tcp", 80);

    if (!ntp_started) {
        sntp_set_time_sync_notification_cb(on_ntp_sync);
        sntp_set_sync_interval(NTP_SYNC_INTERVAL_MS);
        configTzTime(CLOCK_TZ, CLOCK_NTP_1, CLOCK_NTP_2, CLOCK_NTP_3);
        ntp_started = true;
    } else if (!s_time_synced) {
        sntp_restart();
    }

    weather_due  = true;
    weather_next = now;
}

static void send_json(int code, const String &body)
{
    s_server.sendHeader("Cache-Control", "no-store");
    s_server.send(code, "application/json", body);
}

static void redirect_portal()
{
    s_server.sendHeader("Location", "http://" CLOCK_PORTAL_IP "/");
    s_server.send(302, "text/plain", "");
}

static void handle_root()
{
    s_server.sendHeader("Cache-Control", "no-store");
    s_server.send_P(200, "text/html; charset=utf-8", portal_active ? PORTAL_HTML : LAN_HTML);
}

static void handle_not_found()
{
    if (portal_active) {
        redirect_portal();
    } else {
        s_server.send(404, "text/plain", "not found");
    }
}

static void handle_scan()
{
    if (!portal_active) return handle_not_found();
    uint32_t now = millis();
    if (!scan_running && now - last_scan_ms >= SCAN_MIN_GAP_MS) scan_start(now);
    String o;
    o.reserve(64 + scan_count * 64);
    o += "{\"scanning\":";
    o += scan_running ? "true" : "false";
    o += ",\"list\":[";
    for (int i = 0; i < scan_count; i++) {
        if (i) o += ',';
        o += "{\"ssid\":";
        json_str(o, scan_list[i].ssid);
        o += ",\"rssi\":";
        o += (int)scan_list[i].rssi;
        o += ",\"secure\":";
        o += scan_list[i].secure ? "true" : "false";
        o += '}';
    }
    o += "]}";
    send_json(200, o);
}

static bool reject_cross_site();

static void handle_save()
{
    if (!portal_active) return handle_not_found();
    if (reject_cross_site()) return;
    String ssid = s_server.arg("ssid");
    String pass = s_server.arg("pass");
    if (ssid.length() < 1 || ssid.length() > 32) {
        return send_json(400, "{\"ok\":false,\"err\":\"ชื่อ WiFi ไม่ถูกต้อง\"}");
    }
    if (pass.length() != 0 && (pass.length() < 8 || pass.length() > 63)) {
        return send_json(400, "{\"ok\":false,\"err\":\"รหัสผ่านต้องยาว 8-63 ตัวอักษร\"}");
    }
    if (save_state == SAVE_CONNECTING) {
        return send_json(409, "{\"ok\":false,\"err\":\"กำลังเชื่อมต่ออยู่\"}");
    }
    strlcpy(save_ssid, ssid.c_str(), sizeof(save_ssid));
    strlcpy(save_pass, pass.c_str(), sizeof(save_pass));
    save_ip[0]   = 0;
    save_state   = SAVE_CONNECTING;
    save_start   = millis();
    WiFi.setAutoReconnect(false);
    sta_begin(save_ssid, save_pass);
    Serial.printf("[net] trying new network %s\n", save_ssid);
    send_json(200, "{\"ok\":true}");
}

static void handle_status()
{
    NetStatus st;
    net_get_status(&st);
    ClockSettings cs = settings_get();
    String        o;
    o.reserve(640);
    o += "{\"phase\":";
    o += (int)st.phase;
    o += ",\"ssid\":";
    json_str(o, st.ssid);
    o += ",\"ip\":";
    json_str(o, st.ip);
    o += ",\"rssi\":";
    o += (int)st.rssi;
    o += ",\"ap_ssid\":";
    json_str(o, st.ap_ssid);
    o += ",\"client\":";
    o += st.portal_client ? "true" : "false";
    o += ",\"manual\":";
    o += st.portal_manual ? "true" : "false";
    o += ",\"synced\":";
    o += st.time_synced ? "true" : "false";
    o += ",\"last_sync\":";
    o += (long)st.last_sync;
    o += ",\"now\":";
    o += st.time_synced ? (long)time(NULL) : 0L;
    o += ",\"city\":";
    json_str(o, cs.city);
    char wb[96];
    snprintf(wb, sizeof(wb), ",\"weather\":{\"valid\":%s,\"t\":%.1f,\"h\":%u,\"code\":%u,\"day\":%s,\"updated\":%ld}",
             st.weather.valid ? "true" : "false", st.weather.temp_c, st.weather.humidity, st.weather.code,
             st.weather.is_day ? "true" : "false", (long)st.weather.updated);
    o += wb;
    static const char *const names[] = {"idle", "connecting", "ok", "fail"};
    o += ",\"save\":\"";
    o += names[save_state];
    o += "\",\"save_ip\":";
    json_str(o, save_ip);
    o += '}';
    send_json(200, o);
}

static bool reject_in_portal()
{
    if (!portal_active) return false;
    send_json(403, "{\"ok\":false}");
    return true;
}

// Browsers send Origin on cross-site POSTs; blocks other pages from rebooting the clock.
static bool reject_cross_site()
{
    if (!s_server.hasHeader("Origin")) return false;
    if (s_server.header("Origin") == "http://" + s_server.header("Host")) return false;
    send_json(403, "{\"ok\":false}");
    return true;
}

static void handle_settings_get()
{
    if (reject_in_portal()) return;
    ClockSettings cs = settings_get();
    char          b[160];
    String        o;
    o.reserve(260);
    snprintf(b, sizeof(b), "{\"brightness\":%u,\"auto_night\":%s,\"theme\":%u,\"lat\":%.4f,\"lon\":%.4f,\"city\":",
             cs.brightness, cs.auto_night ? "true" : "false", cs.theme, cs.latitude, cs.longitude);
    o += b;
    json_str(o, cs.city);
    o += '}';
    send_json(200, o);
}

static bool arg_bool(const char *name, bool cur)
{
    if (!s_server.hasArg(name)) return cur;
    String v = s_server.arg(name);
    return v == "1" || v == "on" || v == "true";
}

static void handle_settings_post()
{
    if (reject_in_portal() || reject_cross_site()) return;
    ClockSettings s = settings_get();
    if (s_server.hasArg("brightness")) s.brightness = (uint8_t)constrain(s_server.arg("brightness").toInt(), 10, 255);
    s.auto_night = arg_bool("auto_night", s.auto_night);
    if (s_server.hasArg("theme")) {
        long t = s_server.arg("theme").toInt();
        if (t >= 0 && t < THEME_COUNT) s.theme = (uint8_t)t;
    }
    if (s_server.hasArg("lat") && s_server.hasArg("lon")) {
        float la = s_server.arg("lat").toFloat();
        float lo = s_server.arg("lon").toFloat();
        if (la >= -90.0f && la <= 90.0f && lo >= -180.0f && lo <= 180.0f) {
            s.latitude  = la;
            s.longitude = lo;
        }
    }
    if (s_server.hasArg("city")) {
        String c = s_server.arg("city");
        c.trim();
        if (c.length() > 0) {
            size_t len = c.length();
            if (len > sizeof(s.city) - 1) {
                len = sizeof(s.city) - 1;
                while (len > 0 && (((uint8_t)c[len]) & 0xC0) == 0x80) len--;
            }
            memcpy(s.city, c.c_str(), len);
            s.city[len] = 0;
            for (size_t i = 0; i < len; i++) {
                if ((uint8_t)s.city[i] < 0x20) s.city[i] = ' ';
            }
        }
    }
    settings_set(s);
    send_json(200, "{\"ok\":true}");
}

static void handle_sync()
{
    if (reject_in_portal() || reject_cross_site()) return;
    net_request_ntp_sync();
    send_json(200, "{\"ok\":true}");
}

static void handle_portal_req()
{
    if (reject_in_portal() || reject_cross_site()) return;
    net_request_portal();
    String o = "{\"ok\":true,\"ap\":";
    json_str(o, ap_ssid);
    o += '}';
    send_json(200, o);
}

static void handle_reboot()
{
    if (reject_in_portal() || reject_cross_site()) return;
    send_json(200, "{\"ok\":true}");
    reboot_at = millis() + 500;
    if (reboot_at == 0) reboot_at = 1;
}

static void server_setup()
{
    static const char *const probes[] = {"/generate_204", "/gen_204", "/hotspot-detect.html", "/library/test/success.html",
                                         "/connecttest.txt", "/ncsi.txt", "/redirect", "/canonical.html",
                                         "/success.txt", "/fwlink"};
    for (size_t i = 0; i < sizeof(probes) / sizeof(probes[0]); i++) s_server.on(probes[i], HTTP_ANY, handle_not_found);
    s_server.on("/", HTTP_GET, handle_root);
    s_server.on("/scan", HTTP_GET, handle_scan);
    s_server.on("/save", HTTP_POST, handle_save);
    s_server.on("/api/status", HTTP_GET, handle_status);
    s_server.on("/api/settings", HTTP_GET, handle_settings_get);
    s_server.on("/api/settings", HTTP_POST, handle_settings_post);
    s_server.on("/api/sync", HTTP_POST, handle_sync);
    s_server.on("/api/portal", HTTP_POST, handle_portal_req);
    s_server.on("/api/reboot", HTTP_POST, handle_reboot);
    s_server.onNotFound(handle_not_found);
    static const char *headers[] = {"Origin", "Host"};
    s_server.collectHeaders(headers, 2);
    s_server.begin();
}

static void save_tick(uint32_t now, bool connected)
{
    if (save_state == SAVE_CONNECTING) {
        if (connected && strcmp(WiFi.SSID().c_str(), save_ssid) == 0) {
            settings_set_wifi(save_ssid, save_pass);
            strlcpy(cur_ssid, save_ssid, sizeof(cur_ssid));
            strlcpy(cur_pass, save_pass, sizeof(cur_pass));
            strlcpy(save_ip, WiFi.localIP().toString().c_str(), sizeof(save_ip));
            has_creds  = true;
            save_state = SAVE_OK;
            save_end_ms = now;
            Serial.printf("[net] new credentials saved, ip %s\n", save_ip);
        } else if (now - save_start >= SAVE_TIMEOUT_MS) {
            save_state  = SAVE_FAIL;
            save_end_ms = now;
            Serial.println("[net] new network failed, keeping old credentials");
            if (has_creds) {
                sta_begin(cur_ssid, cur_pass);
            } else {
                WiFi.disconnect(false);
            }
            last_retry = now;
        }
    } else if (save_state == SAVE_OK) {
        if (now - save_end_ms >= SAVE_KEEP_AP_MS && portal_active) close_portal();
    } else if (save_state == SAVE_FAIL) {
        if (now - save_end_ms >= SAVE_FAIL_SHOW_MS) save_state = SAVE_IDLE;
    }
}

static void net_tick(uint32_t now)
{
    bool connected = s_got_ip;
    if (connected != was_connected) {
        was_connected = connected;
        if (connected) {
            on_connected(now);
        } else {
            Serial.println("[net] link down");
        }
    }

    if (f_portal) {
        f_portal = false;
        if (!portal_active) open_portal(true, now);
    }
    if (f_cancel) {
        f_cancel = false;
        if (portal_active && (portal_manual || connected) && save_state != SAVE_CONNECTING) close_portal();
    }

    if (portal_active) {
        int stations = WiFi.softAPgetStationNum();
        if (stations > 0) last_client_ms = now;
        scan_poll();
        save_tick(now, connected);
        if (portal_active && connected && !portal_manual && save_state == SAVE_IDLE) {
            Serial.println("[net] saved network joined, closing auto portal");
            close_portal();
        } else if (portal_active && portal_manual && stations == 0 && save_state != SAVE_CONNECTING &&
                   now - last_client_ms >= MANUAL_PORTAL_IDLE_MS) {
            Serial.println("[net] manual portal idle timeout");
            close_portal();
        }
    } else if (!connected && !s_ever_connected && has_creds && now - connect_start >= CONNECT_TIMEOUT_MS) {
        open_portal(false, now);
    }

    if (!connected && has_creds && save_state != SAVE_CONNECTING && now - last_retry >= RETRY_MS) {
        bool allowed = portal_active ? (!portal_manual && WiFi.softAPgetStationNum() == 0) : true;
        if (allowed && (portal_active || now - connect_start >= CONNECT_TIMEOUT_MS)) {
            last_retry = now;
            Serial.println("[net] retrying saved network");
            sta_begin(cur_ssid, cur_pass);
        }
    }

    if (connected) {
        if (f_ntp && ntp_started) {
            f_ntp = false;
            sntp_restart();
            Serial.println("[ntp] resync requested");
        }
        if (f_weather) {
            f_weather   = false;
            weather_due = true;
        }
        uint32_t ver = settings_version();
        if (ver != seen_settings_ver) {
            seen_settings_ver = ver;
            ClockSettings cs  = settings_get();
            if (fabsf(cs.latitude - weather_lat) > 0.00005f || fabsf(cs.longitude - weather_lon) > 0.00005f) {
                weather_due = true;
            }
        }
        if ((int32_t)(now - weather_next) >= 0) weather_due = true;
        if (weather_due && save_state != SAVE_CONNECTING && !(portal_active && WiFi.softAPgetStationNum() > 0)) {
            weather_due  = false;
            bool ok      = weather_fetch();
            weather_next = millis() + (ok ? WEATHER_PERIOD_MS : WEATHER_RETRY_MS);
        }
    }

    if (now - last_publish >= 500) {
        last_publish = now;
        NetPhase phase = portal_active ? NET_PORTAL : connected ? NET_CONNECTED : s_ever_connected ? NET_OFFLINE : NET_CONNECTING;
        publish(phase);
    }
}

static void net_task(void *)
{
    WiFi.persistent(false);
    WiFi.setHostname(CLOCK_HOSTNAME);
    WiFi.onEvent(on_wifi_event);
    WiFi.mode(WIFI_STA);
    WiFi.setSleep(false);
    WiFi.setAutoReconnect(true);

    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(ap_ssid, sizeof(ap_ssid), "%s%02X%02X", CLOCK_AP_PREFIX, mac[4], mac[5]);

    server_setup();

    has_creds         = settings_get_wifi(cur_ssid, sizeof(cur_ssid), cur_pass, sizeof(cur_pass));
    seen_settings_ver = settings_version();
    connect_start     = millis();
    last_retry        = connect_start;
    if (has_creds) {
        Serial.printf("[net] connecting to %s\n", cur_ssid);
        sta_begin(cur_ssid, cur_pass);
    } else {
        open_portal(false, connect_start);
    }

    for (;;) {
        s_server.handleClient();
        if (portal_active) s_dns.processNextRequest();
        // Read after the handlers: they stamp millis() and deltas are unsigned.
        uint32_t now = millis();
        net_tick(now);
        if (reboot_at && (int32_t)(now - reboot_at) >= 0) {
            Serial.println("[net] rebooting");
            ESP.restart();
        }
        vTaskDelay(pdMS_TO_TICKS(3));
    }
}

void net_begin()
{
    s_mutex = xSemaphoreCreateMutex();
    memset(&s_status, 0, sizeof(s_status));
    s_status.phase = NET_BOOTING;
    xTaskCreatePinnedToCore(net_task, "net", NET_TASK_STACK, NULL, 1, NULL, 0);
}

void net_get_status(NetStatus *out)
{
    if (!out) return;
    xSemaphoreTake(s_mutex, portMAX_DELAY);
    *out = s_status;
    xSemaphoreGive(s_mutex);
}

void net_request_portal()
{
    f_portal = true;
}

void net_cancel_portal()
{
    f_cancel = true;
}

void net_request_ntp_sync()
{
    f_ntp = true;
}

void net_request_weather()
{
    f_weather = true;
}

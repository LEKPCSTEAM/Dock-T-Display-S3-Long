#include <Arduino.h>
#include <ArduinoJson.h>
#include <ESPmDNS.h>
#include <WebSocketsServer.h>
#include <esp_heap_caps.h>
#include <esp_system.h>
#include <string>
#include <string.h>
#include <vector>
#include "app_state.h"
#include "deck_layout.h"
#include "deck_net.h"
#include "deck_proto.h"
#include "deck_store.h"

#define SLOTS          WEBSOCKETS_SERVER_CLIENT_MAX
#define MAX_FACE_JOBS  4
#define FACE_MAX_W     640
#define FACE_MAX_H     180
#define OUT_QUEUE_LEN  8

struct OutMsg {
    uint8_t kind;  // 0 = press, 1 = page
    bool    long_press;
    int8_t  index;
    char    id[16];
};

struct FaceJob {
    uint8_t *buf;
    uint16_t id, w, h, rows;
};

class DeckWs : public WebSocketsServer {
 public:
    using WebSocketsServer::WebSocketsServer;
    void resetHeartbeat(uint8_t num)
    {
        if (num >= SLOTS) return;
        _clients[num].pongTimeoutCount = 0;
        _clients[num].pongReceived     = false;
        _clients[num].lastPing         = millis();
    }
};

static DeckWs           s_ws(DECK_WS_PORT);
static DeckSession     *s_sess[SLOTS];
static bool             s_was_ready[SLOTS];
static FaceJob          s_jobs[MAX_FACE_JOBS];
static char             s_board_id[13];
static DeckLayout       s_parse_tmp;

static SemaphoreHandle_t volatile s_mu;
static QueueHandle_t volatile     s_queue;
static bool                       s_snap_ready;
static uint32_t                   s_snap_version;
static DeckLayout                 s_snap_layout;
static bool                       s_snap_has_layout;
static uint8_t                    s_snap_dirty[DECK_MAX_FACES / 8];
static bool                       s_snap_pair_show;
static uint32_t                   s_snap_pair_code;

static void lock()
{
    if (s_mu) xSemaphoreTake(s_mu, portMAX_DELAY);
}

static void unlock()
{
    if (s_mu) xSemaphoreGive(s_mu);
}

static void env_random(uint8_t *buf, size_t len)
{
    esp_fill_random(buf, len);
}

static uint32_t env_now_ms()
{
    return millis();
}

static void env_pair_code(uint32_t code, bool show)
{
    lock();
    s_snap_pair_show = show;
    s_snap_pair_code = show ? code : 0;
    unlock();
}

static const DeckEnv s_env = {env_random, settings_get_deck_key, settings_set_deck_key, env_pair_code, env_now_ms, s_board_id};

static void free_jobs()
{
    for (FaceJob &j : s_jobs) {
        if (j.buf) free(j.buf);
        j = FaceJob{};
    }
}

static void on_face(void *, const DeckFaceChunk *c)
{
    if (c->id < 1 || c->id > DECK_MAX_FACES || c->w == 0 || c->h == 0 || c->w > FACE_MAX_W || c->h > FACE_MAX_H) return;

    FaceJob *job = nullptr, *spare = nullptr;
    for (FaceJob &j : s_jobs) {
        if (j.buf && j.id == c->id) job = &j;
        if (!j.buf && !spare) spare = &j;
    }
    if (job && (job->w != c->w || job->h != c->h || c->y == 0 || c->y != job->rows)) {
        free(job->buf);
        *job = FaceJob{};
        spare = job;
        job   = nullptr;
    }
    if (!job) {
        if (c->y != 0) return;
        if (!spare) {
            Serial.printf("[deck] face %u dropped: too many in progress\n", c->id);
            return;
        }
        spare->buf = (uint8_t *)ps_malloc((size_t)c->w * c->h * 3);
        if (!spare->buf) {
            Serial.println("[deck] face buffer alloc failed");
            return;
        }
        spare->id = c->id;
        spare->w  = c->w;
        spare->h  = c->h;
        job       = spare;
    }

    memcpy(job->buf + (size_t)c->y * c->w * 3, c->px, c->px_len);
    job->rows = c->y + c->n;
    if (job->rows != c->h) return;

    if (deck_store_save_face(job->id, job->w, job->h, job->buf)) {
        lock();
        s_snap_dirty[(job->id - 1) / 8] |= (uint8_t)(1u << ((job->id - 1) % 8));
        unlock();
    } else {
        Serial.printf("[deck] face %u save failed\n", job->id);
    }
    free(job->buf);
    *job = FaceJob{};
}

static void on_message(void *, const char *type, const char *body, size_t body_len)
{
    if (strcmp(type, "layout") != 0) return;
    char err[48];
    if (!deck_layout_parse(body, body_len, &s_parse_tmp, err, sizeof(err))) {
        Serial.printf("[deck] layout rejected: %s\n", err);
        return;
    }
    if (!deck_store_save_layout(body, body_len)) Serial.println("[deck] layout save failed");
    deck_store_prune(&s_parse_tmp);
    lock();
    s_snap_layout     = s_parse_tmp;
    s_snap_has_layout = true;
    s_snap_version++;
    unlock();
    Serial.printf("[deck] layout %s: %u pages\n", s_parse_tmp.hash, s_parse_tmp.page_count);
}

static std::string to_json(const JsonDocument &d)
{
    std::string s;
    serializeJson(d, s);
    return s;
}

static void send_all(uint8_t num, const std::vector<std::string> &replies)
{
    for (const std::string &r : replies) s_ws.sendTXT(num, r.c_str(), r.size());
}

static void send_sealed(uint8_t num, const char *type, const std::string &body)
{
    std::string frame;
    if (s_sess[num] && s_sess[num]->seal(type, body.c_str(), &frame)) s_ws.sendTXT(num, frame.c_str(), frame.size());
}

static bool cache_complete()
{
    if (!s_snap_has_layout) return false;
    for (int p = 0; p < s_snap_layout.page_count; p++) {
        const DeckPage &pg = s_snap_layout.pages[p];
        for (int i = 0; i < pg.count; i++) {
            if (!deck_store_face_exists(pg.widgets[i].face)) return false;
        }
    }
    return true;
}

static void check_became_ready(uint8_t num)
{
    DeckSession *s = s_sess[num];
    if (!s || s_was_ready[num] || !s->ready()) return;
    s_was_ready[num] = true;
    for (uint8_t i = 0; i < SLOTS; i++) {
        if (i != num && s_was_ready[i]) {
            Serial.printf("[deck] slot %u replaced by slot %u\n", i, num);
            s_ws.disconnect(i);
        }
    }
    JsonDocument d;
    d["hash"] = cache_complete() ? s_snap_layout.hash : "";
    send_sealed(num, "hello_state", to_json(d));
    Serial.printf("[deck] slot %u ready\n", num);
}

static void on_ws_event(uint8_t num, WStype_t type, uint8_t *payload, size_t length)
{
    if (num >= SLOTS) return;
    switch (type) {
    case WStype_CONNECTED:
        s_ws.resetHeartbeat(num);
        delete s_sess[num];
        s_sess[num]      = new DeckSession(&s_env);
        s_was_ready[num] = false;
        s_sess[num]->on_message = on_message;
        s_sess[num]->on_face    = on_face;
        Serial.printf("[deck] slot %u connected\n", num);
        break;
    case WStype_DISCONNECTED:
        s_ws.resetHeartbeat(num);
        if (s_was_ready[num]) free_jobs();
        delete s_sess[num];
        s_sess[num]      = nullptr;
        s_was_ready[num] = false;
        Serial.printf("[deck] slot %u dropped\n", num);
        break;
    case WStype_TEXT: {
        if (!s_sess[num]) break;
        std::vector<std::string> replies;
        bool                     ok = s_sess[num]->on_text((const char *)payload, length, &replies);
        send_all(num, replies);
        if (!ok) {
            s_ws.disconnect(num);
            break;
        }
        check_became_ready(num);
        break;
    }
    case WStype_BIN:
        if (s_sess[num] && !s_sess[num]->on_binary(payload, length)) s_ws.disconnect(num);
        break;
    default:
        break;
    }
}

static void drain_queue()
{
    uint8_t active = SLOTS;
    for (uint8_t i = 0; i < SLOTS; i++) {
        if (s_sess[i] && s_sess[i]->ready()) active = i;
    }
    OutMsg m;
    while (s_queue && xQueueReceive(s_queue, &m, 0) == pdTRUE) {
        if (active >= SLOTS) continue;
        JsonDocument d;
        if (m.kind == 0) {
            d["id"]   = m.id;
            d["kind"] = m.long_press ? "long" : "tap";
        } else {
            d["index"] = m.index;
        }
        send_sealed(active, m.kind == 0 ? "press" : "page", to_json(d));
    }
}

void deck_net_begin()
{
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    snprintf(s_board_id, sizeof(s_board_id), "%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    s_queue = xQueueCreate(OUT_QUEUE_LEN, sizeof(OutMsg));
    s_mu    = xSemaphoreCreateMutex();

    if (deck_store_begin()) {
        char *buf = (char *)ps_malloc(DECK_LAYOUT_MAX_BYTES + 1);
        if (buf) {
            size_t n = deck_store_load_layout(buf, DECK_LAYOUT_MAX_BYTES + 1);
            char   err[48];
            if (n > 0 && deck_layout_parse(buf, n, &s_parse_tmp, err, sizeof(err))) {
                lock();
                s_snap_layout     = s_parse_tmp;
                s_snap_has_layout = true;
                s_snap_version++;
                unlock();
                Serial.printf("[deck] cached layout %s loaded\n", s_parse_tmp.hash);
            }
            free(buf);
        }
    }

    s_ws.onEvent(on_ws_event);
    s_ws.begin();
    s_ws.enableHeartbeat(5000, 3000, 2);
}

void deck_net_on_connected()
{
    MDNS.addService("longdeck", "tcp", DECK_WS_PORT);
    MDNS.addServiceTxt("longdeck", "tcp", "id", (const char *)s_board_id);
}

void deck_net_loop()
{
    s_ws.loop();
    bool any_ready = false;
    for (uint8_t i = 0; i < SLOTS; i++) {
        if (!s_sess[i]) continue;
        s_sess[i]->tick();
        if (s_sess[i]->ready()) any_ready = true;
    }
    drain_queue();
    lock();
    s_snap_ready = any_ready;
    unlock();
}

bool deck_net_ready()
{
    lock();
    bool r = s_snap_ready;
    unlock();
    return r;
}

uint32_t deck_net_layout_version()
{
    lock();
    uint32_t v = s_snap_version;
    unlock();
    return v;
}

bool deck_net_layout(DeckLayout *out)
{
    if (!out) return false;
    lock();
    bool has = s_snap_has_layout;
    if (has) *out = s_snap_layout;
    unlock();
    return has;
}

bool deck_net_take_dirty_faces(uint8_t bits[DECK_MAX_FACES / 8])
{
    uint8_t any = 0;
    lock();
    for (int i = 0; i < DECK_MAX_FACES / 8; i++) {
        bits[i]        = s_snap_dirty[i];
        any           |= s_snap_dirty[i];
        s_snap_dirty[i] = 0;
    }
    unlock();
    return any != 0;
}

bool deck_net_pair_code(uint32_t *code)
{
    lock();
    bool show = s_snap_pair_show;
    if (show && code) *code = s_snap_pair_code;
    unlock();
    return show;
}

void deck_net_press(const char *id, bool long_press)
{
    if (!s_queue || !id || !deck_net_ready()) return;
    OutMsg m = {};
    m.kind       = 0;
    m.long_press = long_press;
    strlcpy(m.id, id, sizeof(m.id));
    xQueueSend(s_queue, &m, 0);
}

void deck_net_page(int8_t deck_index)
{
    if (!s_queue || !deck_net_ready()) return;
    OutMsg m = {};
    m.kind  = 1;
    m.index = deck_index;
    xQueueSend(s_queue, &m, 0);
}

void deck_net_forget()
{
    settings_clear_deck_key();
    s_ws.disconnect();
    Serial.println("[deck] paired key forgotten");
}

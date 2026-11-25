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
    uint8_t kind;  // 0 = press, 1 = page, 2 = slider, 3 = claude_action
    bool    long_press;
    int8_t  index;
    uint8_t value;
    char    id[16];
    char    session[DECK_CLAUDE_ID_MAX];
    char    request[DECK_CLAUDE_REQ_MAX];
    uint8_t action;
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
static bool             s_layout_rejected;

static SemaphoreHandle_t volatile s_mu;
static QueueHandle_t volatile     s_queue;
static bool                       s_snap_ready;
static uint32_t                   s_snap_version;
static DeckLayout                 s_snap_layout;
static bool                       s_snap_has_layout;
static uint8_t                    s_snap_dirty[DECK_MAX_FACES / 8];
static bool                       s_snap_pair_show;
static uint32_t                   s_snap_pair_code;
static DeckStats                  s_live_stats;
static DeckHistory                s_live_hist;
static DeckVolume                 s_live_volume;
static bool                       s_live_stats_ok;
static bool                       s_live_volume_ok;
static uint32_t                   s_live_version;
static uint32_t                   s_stats_last_ms;
static int8_t                     s_last_page = -1;
static bool                       s_had_ready;
static DeckSliderGate             s_gate;
static char                       s_slider_id[16];
static DeckClaude                 s_claude_parse;
static DeckClaude                 s_claude;
static DeckClaudeAck              s_claude_ack;
static bool                       s_claude_ok;
static bool                       s_claude_ack_ok;
static uint32_t                   s_claude_version;

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

static bool face_referenced(uint16_t id)
{
    bool found = false;
    lock();
    if (s_snap_has_layout) {
        for (int p = 0; p < s_snap_layout.page_count && !found; p++) {
            const DeckPage &pg = s_snap_layout.pages[p];
            for (int i = 0; i < pg.count; i++) {
                if (pg.widgets[i].type == DW_KEY && pg.widgets[i].face == id) found = true;
            }
        }
        const DeckAgentSprites &sp = s_snap_layout.sprites;
        if (sp.present) {
            if (id >= sp.first_id && id < sp.first_id + sp.frames) found = true;
            if (sp.hat_count && id >= sp.hat_first && id < sp.hat_first + sp.hat_count) found = true;
        }
    }
    unlock();
    return found;
}

static void on_face(void *, const DeckFaceChunk *c)
{
    if (c->id < 1 || c->id > DECK_MAX_FACES || c->w == 0 || c->h == 0 || c->w > FACE_MAX_W || c->h > FACE_MAX_H) return;
    if (s_layout_rejected || !face_referenced(c->id)) return;

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
    if (strcmp(type, "stats") == 0) {
        DeckStats st;
        if (!deck_stats_parse(body, body_len, &st)) {
            Serial.println("[deck] stats ignored");
            return;
        }
        uint32_t now = millis();
        lock();
        bool resumed = s_stats_last_ms != 0 && now - s_stats_last_ms >= 3000;
        s_stats_last_ms = now ? now : 1;
        s_live_stats    = st;
        deck_history_push(&s_live_hist, &st);
        s_live_stats_ok = true;
        s_live_version++;
        unlock();
        if (resumed) Serial.println("[deck] stats resumed");
        return;
    }
    if (strcmp(type, "volume") == 0) {
        DeckVolume vol;
        if (!deck_volume_parse(body, body_len, &vol)) {
            Serial.println("[deck] volume ignored");
            return;
        }
        lock();
        s_live_volume    = vol;
        s_live_volume_ok = true;
        s_live_version++;
        unlock();
        return;
    }
    if (strcmp(type, "claude") == 0) {
        if (!deck_claude_parse(body, body_len, &s_claude_parse)) {
            Serial.println("[deck] claude ignored");
            return;
        }
        lock();
        bool changed = !s_claude_ok || !deck_claude_prompt_same(&s_claude.prompt, &s_claude_parse.prompt);
        s_claude     = s_claude_parse;
        s_claude_ok  = true;
        s_claude_version++;
        unlock();
        if (changed) {
            if (s_claude_parse.prompt.present) Serial.printf("[deck] claude prompt %s\n", s_claude_parse.prompt.request);
            else Serial.println("[deck] claude prompt cleared");
        }
        return;
    }
    if (strcmp(type, "claude_ack") == 0) {
        DeckClaudeAck ack;
        if (!deck_claude_ack_parse(body, body_len, &ack)) {
            Serial.println("[deck] claude_ack ignored");
            return;
        }
        lock();
        s_claude_ack    = ack;
        s_claude_ack_ok = true;
        s_claude_version++;
        unlock();
        if (ack.ok) Serial.printf("[deck] claude ack %s ok\n", ack.request);
        else Serial.printf("[deck] claude ack %s %s\n", ack.request, ack.reason);
        return;
    }
    if (strcmp(type, "layout") != 0) return;
    char err[48];
    if (!deck_layout_parse(body, body_len, &s_parse_tmp, err, sizeof(err))) {
        Serial.printf("[deck] layout rejected: %s\n", err);
        s_layout_rejected = true;
        return;
    }
    s_layout_rejected = false;
    free_jobs();
    if (!deck_store_save_layout(body, body_len)) Serial.println("[deck] layout save failed");
    deck_store_invalidate_faces(&s_parse_tmp);
    deck_store_prune(&s_parse_tmp);
    lock();
    s_snap_layout     = s_parse_tmp;
    s_snap_has_layout = true;
    memset(s_snap_dirty, 0, sizeof(s_snap_dirty));
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
            if (pg.widgets[i].type != DW_KEY) continue;
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
    JsonDocument pg;
    lock();
    pg["index"] = s_last_page;
    unlock();
    send_sealed(num, "page", to_json(pg));
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
        s_layout_rejected = false;
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
        if (m.kind == 2) {
            char body[64];
            if (deck_slider_body(m.id, m.value, body, sizeof(body))) send_sealed(active, "slider", body);
            continue;
        }
        if (m.kind == 3) {
            char body[160];
            if (deck_claude_action_body(m.session, m.request, m.action, body, sizeof(body))) send_sealed(active, "claude_action", body);
            else Serial.println("[deck] claude action dropped");
            continue;
        }
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

static void queue_slider(const char *id, uint8_t value)
{
    OutMsg m = {};
    m.kind  = 2;
    m.value = value;
    strlcpy(m.id, id, sizeof(m.id));
    xQueueSend(s_queue, &m, 0);
}

static void poll_slider()
{
    int  out;
    char id[16];
    lock();
    bool send = deck_slider_poll(&s_gate, millis(), &out);
    strlcpy(id, s_slider_id, sizeof(id));
    unlock();
    if (send && s_queue) queue_slider(id, (uint8_t)out);
}

void deck_net_begin()
{
    deck_slider_reset(&s_gate);
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
    poll_slider();
    drain_queue();
    lock();
    s_snap_ready = any_ready;
    if (!any_ready && s_had_ready) {
        s_live_stats_ok  = false;
        s_live_volume_ok = false;
        s_stats_last_ms  = 0;
        deck_history_clear(&s_live_hist);
        deck_slider_reset(&s_gate);
        s_live_version++;
        s_claude_ok     = false;
        s_claude_ack_ok = false;
        s_claude_version++;
    }
    s_had_ready = any_ready;
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
    lock();
    s_last_page = deck_index;
    unlock();
    if (!s_queue || !deck_net_ready()) return;
    OutMsg m = {};
    m.kind  = 1;
    m.index = deck_index;
    xQueueSend(s_queue, &m, 0);
}

uint32_t deck_net_live_version()
{
    lock();
    uint32_t v = s_live_version;
    unlock();
    return v;
}

bool deck_net_stats(DeckStats *stats, DeckHistory *hist)
{
    if (!stats) return false;
    lock();
    bool ok = s_live_stats_ok;
    if (ok) {
        *stats = s_live_stats;
        if (hist) *hist = s_live_hist;
    }
    unlock();
    return ok;
}

bool deck_net_volume(DeckVolume *out)
{
    if (!out) return false;
    lock();
    bool ok = s_live_volume_ok;
    if (ok) *out = s_live_volume;
    unlock();
    return ok;
}

void deck_net_slider(const char *id, uint8_t value)
{
    if (!s_queue || !id || !deck_net_ready()) return;
    int out;
    lock();
    strlcpy(s_slider_id, id, sizeof(s_slider_id));
    bool send = deck_slider_offer(&s_gate, millis(), value, &out);
    unlock();
    if (send) queue_slider(id, (uint8_t)out);
}

uint32_t deck_net_claude_version()
{
    lock();
    uint32_t v = s_claude_version;
    unlock();
    return v;
}

bool deck_net_claude(DeckClaude *out)
{
    if (!out) return false;
    lock();
    bool ok = s_claude_ok;
    if (ok) *out = s_claude;
    unlock();
    return ok;
}

bool deck_net_take_claude_ack(DeckClaudeAck *out)
{
    if (!out) return false;
    lock();
    bool ok = s_claude_ack_ok;
    if (ok) {
        *out            = s_claude_ack;
        s_claude_ack_ok = false;
    }
    unlock();
    return ok;
}

void deck_net_claude_action(const char *session, const char *request, uint8_t action)
{
    if (!s_queue || !session || !request || !deck_net_ready()) return;
    OutMsg m = {};
    m.kind   = 3;
    m.action = action;
    strlcpy(m.session, session, sizeof(m.session));
    strlcpy(m.request, request, sizeof(m.request));
    xQueueSend(s_queue, &m, 0);
}

void deck_net_forget()
{
    settings_clear_deck_key();
    s_ws.disconnect();
    Serial.println("[deck] paired key forgotten");
}

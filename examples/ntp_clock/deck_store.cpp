#include <Arduino.h>
#include <LittleFS.h>
#include <esp_heap_caps.h>
#include <string.h>
#include "deck_store.h"

#define DECK_DIR       "/deck"
#define LAYOUT_PATH    DECK_DIR "/layout.json"
#define LAYOUT_TMP     DECK_DIR "/layout.tmp"
#define FACE_TMP       DECK_DIR "/face.tmp"
#define FACE_HDR_LEN  4
#define FACE_MAX_DIM   1024

static bool s_ok;

bool deck_store_begin()
{
    s_ok = LittleFS.begin(true, "/littlefs", 10, "spiffs");
    if (!s_ok) {
        Serial.println("[deck] LittleFS mount failed");
        return false;
    }
    if (!LittleFS.exists(DECK_DIR) && !LittleFS.mkdir(DECK_DIR)) {
        Serial.println("[deck] mkdir failed");
        s_ok = false;
    }
    return s_ok;
}

static bool write_file(const char *path, const uint8_t *hdr, size_t hdr_len, const uint8_t *data, size_t len)
{
    File f = LittleFS.open(path, "w");
    if (!f) return false;
    bool ok = (hdr_len == 0 || f.write(hdr, hdr_len) == hdr_len) && f.write(data, len) == len;
    f.close();
    return ok;
}

bool deck_store_save_layout(const char *json, size_t len)
{
    if (!s_ok || !json) return false;
    if (!write_file(LAYOUT_TMP, nullptr, 0, (const uint8_t *)json, len)) {
        LittleFS.remove(LAYOUT_TMP);
        return false;
    }
    return LittleFS.rename(LAYOUT_TMP, LAYOUT_PATH);
}

size_t deck_store_load_layout(char *buf, size_t cap)
{
    if (!s_ok || !buf || cap < 2) return 0;
    File f = LittleFS.open(LAYOUT_PATH, "r");
    if (!f) return 0;
    size_t sz = f.size();
    if (sz == 0 || sz >= cap) {
        f.close();
        return 0;
    }
    size_t n = f.read((uint8_t *)buf, sz);
    f.close();
    if (n != sz) return 0;
    buf[n] = 0;
    return n;
}

static void face_path(char *out, size_t cap, uint16_t id)
{
    snprintf(out, cap, DECK_DIR "/f%u.bin", (unsigned)id);
}

bool deck_store_save_face(uint16_t id, uint16_t w, uint16_t h, const uint8_t *px)
{
    if (!s_ok || !px || w == 0 || h == 0) return false;
    char path[32];
    face_path(path, sizeof(path), id);
    uint8_t hdr[FACE_HDR_LEN] = {(uint8_t)w, (uint8_t)(w >> 8), (uint8_t)h, (uint8_t)(h >> 8)};
    bool    ok = write_file(FACE_TMP, hdr, sizeof(hdr), px, (size_t)w * h * 3);
    if (ok) ok = LittleFS.rename(FACE_TMP, path);
    if (!ok) LittleFS.remove(FACE_TMP);
    return ok;
}

void deck_store_invalidate_faces(const DeckLayout *layout)
{
    if (!s_ok || !layout) return;
    for (int p = 0; p < layout->page_count; p++) {
        const DeckPage &pg = layout->pages[p];
        for (int i = 0; i < pg.count; i++) {
            if (pg.widgets[i].type != DW_KEY) continue;
            char path[32];
            face_path(path, sizeof(path), pg.widgets[i].face);
            LittleFS.remove(path);
        }
    }
    const DeckAgentSprites &sp = layout->sprites;
    if (!sp.present) return;
    for (int i = 0; i < sp.frames + sp.hat_count; i++) {
        char path[32];
        face_path(path, sizeof(path), i < sp.frames ? sp.first_id + i : sp.hat_first + (i - sp.frames));
        LittleFS.remove(path);
    }
}

bool deck_store_face_exists(uint16_t id)
{
    if (!s_ok) return false;
    char path[32];
    face_path(path, sizeof(path), id);
    return LittleFS.exists(path);
}

bool deck_store_load_face(uint16_t id, lv_img_dsc_t *out)
{
    if (!s_ok || !out) return false;
    char path[32];
    face_path(path, sizeof(path), id);
    File f = LittleFS.open(path, "r");
    if (!f) return false;
    uint8_t hdr[FACE_HDR_LEN];
    if (f.read(hdr, sizeof(hdr)) != sizeof(hdr)) {
        f.close();
        return false;
    }
    uint16_t w = hdr[0] | (hdr[1] << 8);
    uint16_t h = hdr[2] | (hdr[3] << 8);
    size_t   bytes = (size_t)w * h * 3;
    if (w == 0 || h == 0 || w > FACE_MAX_DIM || h > FACE_MAX_DIM || f.size() != FACE_HDR_LEN + bytes) {
        f.close();
        return false;
    }
    uint8_t *px = (uint8_t *)ps_malloc(bytes);
    if (!px) {
        f.close();
        return false;
    }
    bool ok = f.read(px, bytes) == bytes;
    f.close();
    if (!ok) {
        free(px);
        return false;
    }
    memset(out, 0, sizeof(*out));
    out->header.cf = LV_IMG_CF_TRUE_COLOR_ALPHA;
    out->header.w = w;
    out->header.h = h;
    out->data_size = bytes;
    out->data = px;
    return true;
}

void deck_store_free_face(lv_img_dsc_t *img)
{
    if (!img) return;
    free((void *)img->data);
    img->data = nullptr;
    img->data_size = 0;
}

void deck_store_prune(const DeckLayout *keep)
{
    if (!s_ok || !keep) return;
    bool used[DECK_MAX_FACES + 1] = {false};
    for (int p = 0; p < keep->page_count; p++) {
        const DeckPage &pg = keep->pages[p];
        for (int i = 0; i < pg.count; i++) {
            uint16_t face = pg.widgets[i].face;
            if (face >= 1 && face <= DECK_MAX_FACES) used[face] = true;
        }
    }
    const DeckAgentSprites &sp = keep->sprites;
    if (sp.present) {
        for (int i = 0; i < sp.frames; i++) used[sp.first_id + i] = true;
        for (int i = 0; i < sp.hat_count; i++) used[sp.hat_first + i] = true;
    }
    File dir = LittleFS.open(DECK_DIR);
    if (!dir) return;
    String *doomed = new (std::nothrow) String[DECK_MAX_FACES + 1];
    if (!doomed) return;
    int    n = 0;
    for (File e = dir.openNextFile(); e && n <= DECK_MAX_FACES; e = dir.openNextFile()) {
        String name = e.name();
        int    slash = name.lastIndexOf('/');
        if (slash >= 0) name = name.substring(slash + 1);
        e.close();
        unsigned id = 0;
        char     tail = 0;
        if (name.startsWith("f") && sscanf(name.c_str(), "f%u.bi%c", &id, &tail) == 2 && tail == 'n') {
            if (id < 1 || id > DECK_MAX_FACES || !used[id]) doomed[n++] = name;
        }
    }
    dir.close();
    for (int i = 0; i < n; i++) LittleFS.remove(String(DECK_DIR "/") + doomed[i]);
    delete[] doomed;
}

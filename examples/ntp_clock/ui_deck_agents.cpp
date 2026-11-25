#include <stdio.h>
#include <string.h>
#include <esp_heap_caps.h>
#include "ui_deck_agents.h"
#include "deck_net.h"
#include "deck_store.h"

#define CELL_W        80
#define CELL_H        90
#define CELL_PAD      3
#define OFFLINE_OPA   102
#define MAX_AGENTS    2     // each costs up to 24 tiles of internal-heap LVGL objects
#define SPRITE_SLOTS  (DECK_MAX_FACES - DECK_SPRITE_FIRST_ID + 1)
#define NO_HAT        0xFF
#define UNSET         0xFF
#define TILE_INSET    2
#define TILE_RADIUS   8
#define SPRITE_X      5
#define TEXT_GAP      3
#define TEXT_PAD_R    4
#define LINE_H        25
#define CHIP_H        16
#define CHIP_PAD_TOP  (-6)  // Thai line box puts digits 9 px down; centre them
#define CHIP_PAD_HOR  2
#define ACCENT_SIZE   18
#define ACCENT_W      3
#define STRIPE_INSET  3     // keeps square stripes inside the 8 px rounded corners
#define STRIPE_N      16
#define STRIPE_BAND   6
#define STRIPE_OPA    64
#define THUMB_W       4
#define THUMB_MIN_H   10
#define HAT_OPA       LV_OPA_60
#define BEAT_MS       100   // every tile steps on one beat: one full-screen flush
#define AGENT_ORANGE  lv_color_hex(0xD97757)

static const uint32_t HAT_TINTS[] = {0x4ADE80, 0x60A5FA, 0xF472B6, 0xFBBF24, 0xA78BFA, 0xF87171, 0x2DD4BF, 0xF2F4F7};

struct AgentTile {
    lv_obj_t *obj;
    lv_obj_t *deco;
    lv_obj_t *sprite;
    lv_obj_t *hat;
    lv_obj_t *name;
    lv_obj_t *status;
    lv_obj_t *badge;
    uint32_t  entered;
    int8_t    tag;
    uint8_t   frame;
    uint8_t   idx;
    uint8_t   state;
    uint8_t   hat_slot;
    uint8_t   tint;
    uint8_t   agents;
    bool      live;
    bool      tappable;
};

struct AgentWidget {
    lv_obj_t  *page;
    lv_obj_t  *box;
    lv_obj_t  *cont;
    lv_obj_t  *msg;
    lv_obj_t  *pill;
    lv_obj_t  *thumb;
    int        cols, rows, tw, th;
    lv_coord_t box_h, text_x, text_w, text_y;
    int        total;
    uint8_t    built;
    uint8_t    shown;
    AgentTile  tile[DECK_CLAUDE_MAX_SESSIONS];
};

struct AgentShared {
    DeckClaude       snap;
    DeckAgentSprites sp;
    lv_img_dsc_t     img[SPRITE_SLOTS];
    bool             img_ok[SPRITE_SLOTS];
    lv_img_dsc_t     stripe;
    uint8_t          stripe_px[STRIPE_N * STRIPE_N * LV_IMG_PX_SIZE_ALPHA_BYTE];
    uint32_t         needy[DECK_CLAUDE_MAX_SESSIONS];
    uint8_t          needy_count;
    AgentWidget      w[MAX_AGENTS];
};

static AgentShared *agents;
static int          widget_count;
static bool         snap_ok;
static uint32_t     seen_beat = UINT32_MAX;
static AgentTile   *pressed_tile;
static char         pressed_id[DECK_CLAUDE_ID_MAX];  // rows can re-sort while a finger is down

static bool         agents_dirty = true;
static uint32_t     seen_version;
static bool         seen_ready;

static void no_click(lv_obj_t *o)
{
    lv_obj_clear_flag(o, LV_OBJ_FLAG_CLICKABLE);
}

static lv_obj_t *child_label(lv_obj_t *parent, lv_color_t color, const char *text)
{
    lv_obj_t *l = ui_label(parent, &ui_font_th_16, color, text);
    no_click(l);
    return l;
}

static void set_text(lv_obj_t *l, const char *text)
{
    if (strcmp(lv_label_get_text(l), text) != 0) {
        lv_label_set_text(l, text);
    }
}

static void set_shown(lv_obj_t *o, bool on)
{
    if (on == lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN)) {
        if (on) {
            lv_obj_clear_flag(o, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
        }
    }
}

static lv_obj_t *chip_create(lv_obj_t *parent)
{
    lv_obj_t *l = child_label(parent, COLOR_BG, "");
    lv_obj_set_height(l, CHIP_H);
    lv_obj_set_style_pad_top(l, CHIP_PAD_TOP, 0);
    lv_obj_set_style_pad_hor(l, CHIP_PAD_HOR, 0);
    lv_obj_set_style_radius(l, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(l, AGENT_ORANGE, 0);
    lv_obj_set_style_bg_opa(l, LV_OPA_COVER, 0);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
    return l;
}

static void stripe_init()
{
    lv_color_t c  = AGENT_ORANGE;
    uint8_t   *px = agents->stripe_px;
    for (int y = 0; y < STRIPE_N; y++) {
        for (int x = 0; x < STRIPE_N; x++) {
            memcpy(px, &c, sizeof(c));
            px[sizeof(c)] = (x + y) % STRIPE_N < STRIPE_BAND ? STRIPE_OPA : LV_OPA_TRANSP;
            px += LV_IMG_PX_SIZE_ALPHA_BYTE;
        }
    }
    lv_img_dsc_t *d = &agents->stripe;
    d->header.cf = LV_IMG_CF_TRUE_COLOR_ALPHA;
    d->header.w  = STRIPE_N;
    d->header.h  = STRIPE_N;
    d->data_size = sizeof(agents->stripe_px);
    d->data      = agents->stripe_px;
}

static bool shared_alloc()
{
    if (!agents) {
        agents = (AgentShared *)heap_caps_calloc(1, sizeof(AgentShared), MALLOC_CAP_SPIRAM);
        if (agents) {
            stripe_init();
        }
    }
    return agents != NULL;
}

static bool is_body(uint16_t id)
{
    const DeckAgentSprites *sp = &agents->sp;
    return id >= sp->first_id && id < sp->first_id + sp->frames;
}

static int slot_of(uint16_t id)
{
    const DeckAgentSprites *sp = &agents->sp;
    if (!sp->present || id < DECK_SPRITE_FIRST_ID || id > DECK_MAX_FACES) {
        return -1;
    }
    bool hat = sp->hat_count && id >= sp->hat_first && id < sp->hat_first + sp->hat_count;
    return is_body(id) || hat ? id - DECK_SPRITE_FIRST_ID : -1;
}

static lv_img_dsc_t *slot_img(uint16_t id)
{
    int k = slot_of(id);
    return k >= 0 && agents->img_ok[k] ? &agents->img[k] : NULL;
}

static void slot_load(uint16_t id)
{
    int k = slot_of(id);
    if (k < 0) {
        return;
    }
    const DeckAgentSprites *sp = &agents->sp;
    bool body = is_body(id);
    lv_img_dsc_t nu;
    bool ok = deck_store_load_face(id, &nu);
    if (ok && (nu.header.w != (body ? sp->w : sp->hat_w) || nu.header.h != (body ? sp->h : sp->hat_h))) {
        deck_store_free_face(&nu);
        ok = false;
    }
    if (agents->img_ok[k]) {
        deck_store_free_face(&agents->img[k]);
    }
    agents->img_ok[k] = ok;
    if (ok) {
        agents->img[k] = nu;
    }
}

static void images_load()
{
    const DeckAgentSprites *sp = &agents->sp;
    for (int i = 0; sp->present && i < sp->frames; i++) {
        slot_load(sp->first_id + i);
    }
    for (int i = 0; sp->present && i < sp->hat_count; i++) {
        slot_load(sp->hat_first + i);
    }
}

static void images_unload()
{
    for (int k = 0; k < SPRITE_SLOTS; k++) {
        if (agents->img_ok[k]) {
            deck_store_free_face(&agents->img[k]);
            agents->img_ok[k] = false;
        }
    }
}

static void tile_show_frame(AgentTile *tl)
{
    const DeckAgentSprites *sp = &agents->sp;
    lv_img_dsc_t *body = tl->tag >= 0 ? slot_img(sp->first_id + tl->frame) : NULL;
    if (!body) {
        set_shown(tl->sprite, false);
        return;
    }
    lv_img_set_src(tl->sprite, body);
    set_shown(tl->sprite, true);
    lv_img_dsc_t *hat = tl->hat_slot != NO_HAT ? slot_img(sp->hat_first + tl->hat_slot) : NULL;
    if (hat) {
        if (lv_img_get_src(tl->hat) != hat) {
            lv_img_set_src(tl->hat, hat);
        }
        lv_obj_set_pos(tl->hat, sp->hat_x[tl->frame], sp->hat_y[tl->frame]);
    }
    set_shown(tl->hat, hat != NULL);
}

static void tile_cb(lv_event_t *e)
{
    AgentTile      *tl   = (AgentTile *)lv_event_get_user_data(e);
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_PRESSED) {
        bool ok = snap_ok && tl->idx < agents->snap.count;
        deck_claude_copy(pressed_id, sizeof(pressed_id), ok ? agents->snap.s[tl->idx].id : "");
        pressed_tile = tl;
        return;
    }
    if (tl != pressed_tile || !deck_net_ready() || !snap_ok) {
        return;
    }
    bool interrupt = code == LV_EVENT_LONG_PRESSED;
    const DeckClaudeSession *s = deck_claude_tap_target(&agents->snap, pressed_id, interrupt);
    if (s) {
        deck_net_claude_action(s->id, "", interrupt ? DCA_INTERRUPT : DCA_FOCUS);
    }
}

static void tile_create(AgentWidget *aw, int i)
{
    const DeckAgentSprites *sp = &agents->sp;
    AgentTile *tl = &aw->tile[i];
    memset(tl, 0, sizeof(*tl));
    tl->idx      = (uint8_t)i;
    tl->tag      = -1;
    tl->state    = UNSET;
    tl->hat_slot = NO_HAT;
    tl->tint     = UNSET;
    tl->live     = true;

    lv_obj_t *o = lv_obj_create(aw->cont);
    ui_strip_obj(o);
    lv_obj_set_pos(o, (i % aw->cols) * aw->tw, (i / aw->cols) * aw->th);
    lv_obj_set_size(o, aw->tw, aw->th);
    lv_obj_set_style_transform_width(o, -TILE_INSET, 0);
    lv_obj_set_style_transform_height(o, -TILE_INSET, 0);
    lv_obj_set_style_radius(o, TILE_RADIUS, 0);
    lv_obj_set_style_bg_color(o, COLOR_PANEL, 0);
    lv_obj_set_style_bg_color(o, COLOR_PANEL_HI, LV_STATE_PRESSED);
    lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
    no_click(o);
    lv_obj_add_flag(o, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(o, tile_cb, LV_EVENT_PRESSED, tl);
    lv_obj_add_event_cb(o, tile_cb, LV_EVENT_SHORT_CLICKED, tl);
    lv_obj_add_event_cb(o, tile_cb, LV_EVENT_LONG_PRESSED, tl);
    tl->obj = o;

    tl->deco = lv_obj_create(o);
    ui_strip_obj(tl->deco);
    no_click(tl->deco);
    lv_obj_set_style_radius(tl->deco, TILE_RADIUS, 0);
    lv_obj_set_style_border_color(tl->deco, AGENT_ORANGE, 0);
    lv_obj_set_style_border_side(tl->deco, (lv_border_side_t)(LV_BORDER_SIDE_TOP | LV_BORDER_SIDE_LEFT), 0);
    lv_obj_set_style_bg_img_tiled(tl->deco, true, 0);
    lv_obj_add_flag(tl->deco, LV_OBJ_FLAG_HIDDEN);

    tl->sprite = lv_img_create(o);
    no_click(tl->sprite);
    lv_obj_set_size(tl->sprite, sp->w, sp->h);
    lv_obj_set_pos(tl->sprite, SPRITE_X, (aw->th - sp->h) / 2);
    lv_obj_add_flag(tl->sprite, LV_OBJ_FLAG_HIDDEN);

    tl->hat = lv_img_create(tl->sprite);
    no_click(tl->hat);
    lv_obj_set_size(tl->hat, sp->hat_w, sp->hat_h);
    lv_obj_set_style_img_recolor_opa(tl->hat, HAT_OPA, 0);
    lv_obj_add_flag(tl->hat, LV_OBJ_FLAG_HIDDEN);

    tl->name = child_label(o, COLOR_TEXT, "");
    lv_label_set_long_mode(tl->name, LV_LABEL_LONG_DOT);
    lv_obj_set_size(tl->name, aw->text_w, LINE_H);
    lv_obj_set_pos(tl->name, aw->text_x, aw->text_y);

    tl->status = child_label(o, COLOR_TEXT_DIM, "");
    lv_label_set_long_mode(tl->status, LV_LABEL_LONG_DOT);
    lv_obj_set_size(tl->status, aw->text_w, 2 * LINE_H);
    lv_obj_set_pos(tl->status, aw->text_x, aw->text_y + LINE_H);

    tl->badge = chip_create(o);
    lv_obj_set_pos(tl->badge, SPRITE_X, aw->th - TILE_INSET - CHIP_H - 3);
    lv_obj_add_flag(tl->badge, LV_OBJ_FLAG_HIDDEN);
}

static void deco_set(AgentWidget *aw, AgentTile *tl, uint8_t state)
{
    lv_obj_t *d = tl->deco;
    if (state == DCS_WAITING) {
        lv_coord_t in = TILE_INSET + STRIPE_INSET;
        lv_obj_set_pos(d, in, in);
        lv_obj_set_size(d, aw->tw - 2 * in, aw->th - 2 * in);
        lv_obj_set_style_border_width(d, 0, 0);
        lv_obj_set_style_bg_img_src(d, &agents->stripe, 0);
    } else if (state == DCS_WORKING || state == DCS_PERMISSION) {
        lv_obj_set_pos(d, TILE_INSET, TILE_INSET);
        lv_obj_set_size(d, ACCENT_SIZE, ACCENT_SIZE);
        lv_obj_set_style_border_width(d, ACCENT_W, 0);
        lv_obj_set_style_bg_img_src(d, NULL, 0);
    }
    set_shown(d, state <= DCS_WAITING);
}

static void status_set(AgentWidget *aw, AgentTile *tl, const DeckClaudeSession *s, uint32_t now)
{
    char buf[48];
    deck_claude_agent_status(s, now, " · ", buf, sizeof(buf));
    lv_point_t sz;
    lv_txt_get_size(&sz, buf, &ui_font_th_16, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
    if (sz.x > aw->text_w) {
        deck_claude_agent_status(s, now, "\n", buf, sizeof(buf));
    }
    set_text(tl->status, buf);
}

static void tile_refresh(AgentWidget *aw, AgentTile *tl, const DeckClaudeSession *s, uint32_t now)
{
    const DeckAgentSprites *sp = &agents->sp;
    bool frame_dirty = false;

    bool tappable = s->tmux;
    if (tappable != tl->tappable) {
        tl->tappable = tappable;
        if (tappable) {
            lv_obj_add_flag(tl->obj, LV_OBJ_FLAG_CLICKABLE);
        } else {
            lv_obj_clear_flag(tl->obj, LV_OBJ_FLAG_CLICKABLE);
        }
    }
    if (s->live != tl->live) {
        tl->live = s->live;
        lv_obj_set_style_text_color(tl->name, s->live ? COLOR_TEXT : COLOR_TEXT_DIM, 0);
    }
    set_text(tl->name, s->name);

    if (s->state != tl->state) {
        tl->state = s->state;
        bool warn = s->state == DCS_PERMISSION || s->state == DCS_WAITING;
        lv_obj_set_style_text_color(tl->status, warn ? AGENT_ORANGE : COLOR_TEXT_DIM, 0);
        deco_set(aw, tl, s->state);
        tl->tag     = (int8_t)deck_claude_agent_tag(sp, s->state);
        tl->frame   = tl->tag >= 0 ? sp->tag_first[tl->tag] : 0;
        tl->entered = lv_tick_get() / BEAT_MS * BEAT_MS;
        frame_dirty = true;
    }
    status_set(aw, tl, s, now);

    uint8_t hat = sp->hat_count ? s->hat % sp->hat_count : NO_HAT;
    if (hat != tl->hat_slot) {
        tl->hat_slot = hat;
        frame_dirty  = true;
    }
    uint8_t tint = s->tint % (sizeof(HAT_TINTS) / sizeof(HAT_TINTS[0]));
    if (tint != tl->tint) {
        tl->tint = tint;
        lv_obj_set_style_img_recolor(tl->hat, lv_color_hex(HAT_TINTS[tint]), 0);
    }
    if (s->agents != tl->agents) {
        tl->agents = s->agents;
        char b[8];
        snprintf(b, sizeof(b), "x%u", (unsigned)s->agents);
        set_text(tl->badge, b);
        set_shown(tl->badge, s->agents > 0);
    }
    if (frame_dirty) {
        tile_show_frame(tl);
    }
}

static int total_rows(const AgentWidget *aw)
{
    return (aw->shown + aw->cols - 1) / aw->cols;
}

static lv_coord_t scroll_max(const AgentWidget *aw)
{
    int extra = total_rows(aw) - aw->rows;
    return extra > 0 ? extra * aw->th : 0;
}

static void thumb_update(AgentWidget *aw)
{
    lv_coord_t max = scroll_max(aw);
    if (max <= 0) {
        set_shown(aw->thumb, false);
        return;
    }
    lv_coord_t track_y = TILE_INSET + CHIP_H + 4;
    lv_coord_t track_h = aw->box_h - TILE_INSET - track_y;
    lv_coord_t h       = track_h * aw->rows / total_rows(aw);
    if (h < THUMB_MIN_H) {
        h = THUMB_MIN_H;
    }
    lv_coord_t y = lv_obj_get_scroll_y(aw->cont);
    y = y < 0 ? 0 : (y > max ? max : y);
    lv_obj_set_height(aw->thumb, h);
    lv_obj_set_y(aw->thumb, track_y + (lv_coord_t)((int32_t)(track_h - h) * y / max));
    set_shown(aw->thumb, true);
}

static void scroll_cb(lv_event_t *e)
{
    thumb_update((AgentWidget *)lv_event_get_user_data(e));
}

static void pill_set(AgentWidget *aw, int total)
{
    if (total == aw->total) {
        return;
    }
    aw->total = total;
    lv_obj_set_style_bg_color(aw->pill, total > 0 ? AGENT_ORANGE : COLOR_PANEL_HI, 0);
    lv_obj_set_style_text_color(aw->pill, total > 0 ? COLOR_BG : COLOR_TEXT_DIM, 0);
    char b[8];
    snprintf(b, sizeof(b), "%d", total);
    set_text(aw->pill, b);
}

static void show_message(AgentWidget *aw, const char *text)
{
    set_shown(aw->cont, text == NULL);
    set_shown(aw->msg, text != NULL);
    lv_obj_set_style_bg_opa(aw->box, text ? LV_OPA_COVER : LV_OPA_TRANSP, 0);
    if (text) {
        set_text(aw->msg, text);
    }
}

static void widget_refresh(AgentWidget *aw, bool live, bool needy_new, uint32_t now)
{
    const DeckClaude *c = &agents->snap;
    int  n       = live ? LV_MIN(c->count, DECK_CLAUDE_MAX_SESSIONS) : 0;
    bool created = false;
    for (int i = 0; i < n; i++) {
        if (i >= aw->built) {
            tile_create(aw, i);
            aw->built++;
            created = true;
        }
        tile_refresh(aw, &aw->tile[i], &c->s[i], now);
        set_shown(aw->tile[i].obj, true);
    }
    for (int i = n; i < aw->built; i++) {
        set_shown(aw->tile[i].obj, false);
    }
    aw->shown = (uint8_t)n;

    if (!live) {
        show_message(aw, "--");
    } else {
        show_message(aw, n == 0 ? "No sessions" : NULL);
        pill_set(aw, c->agents_total);
    }
    set_shown(aw->pill, live);
    if (created) {
        lv_obj_update_layout(aw->cont);
    }
    lv_coord_t max = scroll_max(aw);
    lv_coord_t y   = lv_obj_get_scroll_y(aw->cont);
    if (needy_new && y > 0) {
        lv_obj_scroll_to_y(aw->cont, 0, LV_ANIM_ON);
    } else if (y > max) {
        lv_obj_scroll_to_y(aw->cont, max, LV_ANIM_OFF);
    }
    thumb_update(aw);
}

static void widget_ages(AgentWidget *aw, uint32_t now)
{
    for (int i = 0; i < aw->shown; i++) {
        if (aw->tile[i].state == DCS_DONE) {
            status_set(aw, &aw->tile[i], &agents->snap.s[i], now);
        }
    }
}

static bool on_screen(lv_obj_t *o)
{
    lv_area_t a;
    lv_obj_get_coords(o, &a);
    return a.x2 >= 0 && a.x1 < SCREEN_W;
}

static void widget_animate(AgentWidget *aw, uint32_t ms)
{
    if (!on_screen(aw->page)) {
        return;
    }
    lv_area_t view;
    lv_obj_get_coords(aw->cont, &view);
    for (int i = 0; i < aw->shown; i++) {
        AgentTile *tl = &aw->tile[i];
        lv_area_t  a;
        lv_obj_get_coords(tl->obj, &a);
        if (a.y2 < view.y1 || a.y1 > view.y2) {
            continue;
        }
        if (deck_claude_agent_step(&agents->sp, tl->tag, &tl->frame, &tl->entered, ms, BEAT_MS)) {
            tile_show_frame(tl);
        }
    }
}

void ui_agents_reset()
{
    widget_count = 0;
    agents_dirty = true;
    if (agents) {
        images_unload();
        memset(&agents->sp, 0, sizeof(agents->sp));
    }
}

bool ui_agents_create(lv_obj_t *tile, const DeckWidget *w, const DeckAgentSprites *sprites)
{
    if (w->type != DW_CLAUDE_AGENTS) {
        return false;
    }
    lv_coord_t bw  = w->w * CELL_W - 2 * CELL_PAD;
    lv_coord_t bh  = w->h * CELL_H - 2 * CELL_PAD;
    lv_obj_t  *box = lv_obj_create(tile);
    ui_strip_obj(box);
    lv_obj_set_pos(box, w->col * CELL_W + CELL_PAD, w->row * CELL_H + CELL_PAD);
    lv_obj_set_size(box, bw, bh);
    lv_obj_set_style_bg_color(box, COLOR_PANEL, 0);
    lv_obj_set_style_bg_opa(box, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(box, 8, 0);
    no_click(box);
    lv_obj_add_flag(box, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_set_style_opa(box, OFFLINE_OPA, 0);
    lv_obj_t *msg = child_label(box, COLOR_TEXT_DIM, "--");
    lv_obj_center(msg);
    if (widget_count >= MAX_AGENTS || !shared_alloc()) {
        return true;
    }
    if (widget_count == 0) {
        if (sprites) {
            agents->sp = *sprites;
        } else {
            memset(&agents->sp, 0, sizeof(agents->sp));
        }
        images_load();
    }

    AgentWidget *aw = &agents->w[widget_count++];
    memset(aw, 0, sizeof(*aw));
    aw->page  = tile;
    aw->box   = box;
    aw->msg   = msg;
    aw->box_h = bh;
    aw->total = -1;
    deck_claude_agents_grid(w->w, w->h, bw, bh, &aw->cols, &aw->rows, &aw->tw, &aw->th);
    lv_coord_t sw = agents->sp.present ? LV_MIN(agents->sp.w, aw->tw / 2) : 0;
    aw->text_x = sw ? SPRITE_X + sw + TEXT_GAP : SPRITE_X + 4;
    aw->text_w = aw->tw - TILE_INSET - TEXT_PAD_R - aw->text_x;
    aw->text_y = (aw->th - 3 * LINE_H) / 2;

    aw->cont = lv_obj_create(box);
    ui_strip_obj(aw->cont);
    lv_obj_add_flag(aw->cont, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(aw->cont, bw - DECK_AGENTS_RAIL_W, bh);
    lv_obj_set_scroll_dir(aw->cont, LV_DIR_VER);
    lv_obj_set_scroll_snap_y(aw->cont, LV_SCROLL_SNAP_START);
    lv_obj_set_scrollbar_mode(aw->cont, LV_SCROLLBAR_MODE_OFF);
    lv_obj_add_flag(aw->cont, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_flag(aw->cont, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(aw->cont, scroll_cb, LV_EVENT_SCROLL, aw);

    aw->pill = chip_create(box);
    lv_obj_set_style_min_width(aw->pill, DECK_AGENTS_RAIL_W, 0);
    lv_obj_align(aw->pill, LV_ALIGN_TOP_RIGHT, 0, TILE_INSET);
    lv_obj_add_flag(aw->pill, LV_OBJ_FLAG_HIDDEN);

    aw->thumb = lv_obj_create(box);
    ui_strip_obj(aw->thumb);
    no_click(aw->thumb);
    lv_obj_set_size(aw->thumb, THUMB_W, THUMB_MIN_H);
    lv_obj_set_x(aw->thumb, bw - (DECK_AGENTS_RAIL_W + THUMB_W) / 2);
    lv_obj_set_style_radius(aw->thumb, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(aw->thumb, COLOR_TEXT_DIM, 0);
    lv_obj_set_style_bg_opa(aw->thumb, LV_OPA_COVER, 0);
    lv_obj_add_flag(aw->thumb, LV_OBJ_FLAG_HIDDEN);

    agents_dirty = true;
    return true;
}

void ui_agents_face_changed(uint16_t id)
{
    if (widget_count == 0 || slot_of(id) < 0) {
        return;
    }
    slot_load(id);
    const DeckAgentSprites *sp = &agents->sp;
    for (int i = 0; i < widget_count; i++) {
        AgentWidget *aw = &agents->w[i];
        for (int j = 0; j < aw->built; j++) {
            AgentTile *tl = &aw->tile[j];
            bool uses = (tl->tag >= 0 && sp->first_id + tl->frame == id) ||
                        (tl->hat_slot != NO_HAT && sp->hat_first + tl->hat_slot == id);
            if (uses) {
                tile_show_frame(tl);
            }
        }
    }
}

void ui_agents_update(const UiTick *t, bool ready, bool visible)
{
    if (widget_count == 0) {
        return;
    }
    uint32_t ver       = deck_net_claude_version();
    bool     full      = agents_dirty || ver != seen_version || ready != seen_ready;
    bool     needy_new = false;
    if (full) {
        agents_dirty = false;
        seen_version = ver;
        seen_ready   = ready;
        snap_ok      = deck_net_claude(&agents->snap);
        needy_new    = ready && snap_ok && deck_claude_needy_update(&agents->snap, agents->needy, &agents->needy_count);
    }
    bool     live = ready && snap_ok;
    uint32_t now  = t->time_valid ? (uint32_t)time(NULL) : 0;
    uint32_t beat = lv_tick_get() / BEAT_MS;
    bool     step = beat != seen_beat;
    seen_beat     = beat;
    for (int i = 0; i < widget_count; i++) {
        AgentWidget *aw = &agents->w[i];
        if (full) {
            lv_obj_set_style_opa(aw->box, ready ? LV_OPA_COVER : OFFLINE_OPA, 0);
            widget_refresh(aw, live, needy_new, now);
        } else if (t->new_minute && live) {
            widget_ages(aw, now);
        }
        if (step && visible && live) {
            widget_animate(aw, beat * BEAT_MS);
        }
    }
}

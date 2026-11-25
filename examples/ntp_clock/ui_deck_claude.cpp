#include <stdio.h>
#include <string.h>
#include "ui_internal.h"
#include "deck_net.h"

#define CELL_W       80
#define CELL_H       90
#define CELL_PAD     3
#define OFFLINE_OPA  102
#define MAX_CLAUDE   16
#define MAX_ROWS     4
#define ROW_H        40
#define DOT_SIZE     10
#define BAR_H        8

struct SessRow {
    lv_obj_t *obj;
    lv_obj_t *dot;
    lv_obj_t *proj;
    lv_obj_t *right;
    int       idx;
};

struct UsageSec {
    lv_obj_t *pct;
    lv_obj_t *reset;
    lv_obj_t *bar;
};

struct ClaudeWidget {
    lv_obj_t *box;
    lv_obj_t *msg;
    uint8_t   type;
    uint8_t   w;
    int       rows;
    SessRow   row[MAX_ROWS];
    UsageSec  sec[2];
};

static ClaudeWidget widgets[MAX_CLAUDE];
static int          widget_count;

static DeckClaude snap;
static bool       snap_ok;

static bool       claude_dirty = true;
static uint32_t   seen_version;
static bool       seen_ready;
static uint32_t   seen_accent = UINT32_MAX;
static SessRow   *pressed_row;
static char       pressed_id[DECK_CLAUDE_ID_MAX];  // rows can re-sort while a finger is down

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

static lv_obj_t *box_create(lv_obj_t *tile, const DeckWidget *w, lv_coord_t *bw, lv_coord_t *bh)
{
    *bw = w->w * CELL_W - 2 * CELL_PAD;
    *bh = w->h * CELL_H - 2 * CELL_PAD;
    lv_obj_t *box = lv_obj_create(tile);
    ui_strip_obj(box);
    lv_obj_set_pos(box, w->col * CELL_W + CELL_PAD, w->row * CELL_H + CELL_PAD);
    lv_obj_set_size(box, *bw, *bh);
    lv_obj_set_style_bg_color(box, COLOR_PANEL, 0);
    lv_obj_set_style_bg_opa(box, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(box, 8, 0);
    no_click(box);
    lv_obj_add_flag(box, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_set_style_opa(box, OFFLINE_OPA, 0);
    return box;
}

static lv_coord_t right_reserve(uint8_t w)
{
    if (w >= 6) {
        return 250;
    }
    return w >= 4 ? 170 : 56;
}

static void row_cb(lv_event_t *e)
{
    SessRow *r = (SessRow *)lv_event_get_user_data(e);
    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_PRESSED) {
        bool ok = snap_ok && r->idx >= 0 && r->idx < snap.count;
        deck_claude_copy(pressed_id, sizeof(pressed_id), ok ? snap.s[r->idx].id : "");
        pressed_row = r;
        return;
    }
    if (r != pressed_row || !deck_net_ready() || !snap_ok) {
        return;
    }
    bool interrupt = code == LV_EVENT_LONG_PRESSED;
    const DeckClaudeSession *s = deck_claude_tap_target(&snap, pressed_id, interrupt);
    if (s) {
        deck_net_claude_action(s->id, "", interrupt ? DCA_INTERRUPT : DCA_FOCUS);
    }
}

static void sessions_create(ClaudeWidget *cw, lv_coord_t bw, lv_coord_t bh)
{
    cw->rows = (bh - 4) / ROW_H;
    if (cw->rows > MAX_ROWS) {
        cw->rows = MAX_ROWS;
    }
    lv_coord_t row_w  = bw - 8;
    lv_coord_t proj_w = row_w - 26 - right_reserve(cw->w) - 12;

    for (int i = 0; i < cw->rows; i++) {
        SessRow *r = &cw->row[i];
        r->idx = i;
        r->obj = lv_obj_create(cw->box);
        ui_strip_obj(r->obj);
        lv_obj_set_pos(r->obj, 4, 2 + ROW_H * i);
        lv_obj_set_size(r->obj, row_w, ROW_H);
        lv_obj_set_style_radius(r->obj, 6, 0);
        lv_obj_set_style_bg_color(r->obj, COLOR_PANEL_HI, LV_STATE_PRESSED);
        lv_obj_set_style_bg_opa(r->obj, LV_OPA_COVER, LV_STATE_PRESSED);
        lv_obj_add_flag(r->obj, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_flag(r->obj, LV_OBJ_FLAG_GESTURE_BUBBLE);
        lv_obj_add_flag(r->obj, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_event_cb(r->obj, row_cb, LV_EVENT_PRESSED, r);
        lv_obj_add_event_cb(r->obj, row_cb, LV_EVENT_SHORT_CLICKED, r);
        lv_obj_add_event_cb(r->obj, row_cb, LV_EVENT_LONG_PRESSED, r);

        r->dot = lv_obj_create(r->obj);
        ui_strip_obj(r->dot);
        no_click(r->dot);
        lv_obj_set_size(r->dot, DOT_SIZE, DOT_SIZE);
        lv_obj_set_style_radius(r->dot, LV_RADIUS_CIRCLE, 0);
        lv_obj_set_style_bg_opa(r->dot, LV_OPA_COVER, 0);
        lv_obj_align(r->dot, LV_ALIGN_LEFT_MID, 8, 0);

        r->proj = child_label(r->obj, COLOR_TEXT, "");
        lv_label_set_long_mode(r->proj, LV_LABEL_LONG_DOT);
        lv_obj_set_size(r->proj, proj_w, 25);
        lv_obj_align(r->proj, LV_ALIGN_LEFT_MID, 26, 0);

        r->right = child_label(r->obj, COLOR_TEXT_DIM, "");
        lv_label_set_long_mode(r->right, LV_LABEL_LONG_CLIP);
        lv_obj_set_size(r->right, right_reserve(cw->w), 25);
        lv_obj_set_style_text_align(r->right, LV_TEXT_ALIGN_RIGHT, 0);
        lv_obj_align(r->right, LV_ALIGN_RIGHT_MID, -8, 0);
    }
    cw->msg = child_label(cw->box, COLOR_TEXT_DIM, "--");
    lv_obj_center(cw->msg);
}

static lv_coord_t section_h(lv_coord_t bh)
{
    return bh / 2;
}

static void usage_create(ClaudeWidget *cw, lv_coord_t bw, lv_coord_t bh)
{
    static const char *const names[2] = {"5h", "7d"};
    lv_coord_t sh = section_h(bh);
    for (int i = 0; i < 2; i++) {
        UsageSec *s = &cw->sec[i];
        lv_obj_t *sec = lv_obj_create(cw->box);
        ui_strip_obj(sec);
        no_click(sec);
        lv_obj_set_size(sec, bw, sh);
        lv_obj_set_pos(sec, 0, sh * i);

        lv_obj_t *name = child_label(sec, COLOR_TEXT_DIM, names[i]);
        lv_obj_align(name, LV_ALIGN_TOP_LEFT, 6, 2);
        s->pct = child_label(sec, COLOR_TEXT, "--");
        lv_obj_align(s->pct, LV_ALIGN_TOP_RIGHT, -6, 2);
        if (cw->w >= 2) {
            s->reset = child_label(sec, COLOR_TEXT_DIM, "");
            lv_obj_align(s->reset, LV_ALIGN_TOP_LEFT, 34, 2);
        }
        lv_obj_t *b = lv_bar_create(sec);
        no_click(b);
        lv_obj_set_size(b, bw - 12, BAR_H);
        lv_obj_align(b, LV_ALIGN_BOTTOM_MID, 0, -4);
        lv_bar_set_range(b, 0, 100);
        lv_obj_set_style_bg_color(b, COLOR_PANEL_HI, LV_PART_MAIN);
        lv_obj_set_style_bg_opa(b, LV_OPA_COVER, LV_PART_MAIN);
        lv_obj_set_style_bg_opa(b, LV_OPA_COVER, LV_PART_INDICATOR);
        s->bar = b;
    }
}

void ui_claude_reset()
{
    widget_count = 0;
    claude_dirty = true;
}

bool ui_claude_create(lv_obj_t *tile, const DeckWidget *w)
{
    if (w->type != DW_CLAUDE_SESSIONS && w->type != DW_CLAUDE_USAGE) {
        return false;
    }
    lv_coord_t bw, bh;
    lv_obj_t *box = box_create(tile, w, &bw, &bh);
    if (widget_count >= MAX_CLAUDE) {
        return true;
    }
    ClaudeWidget *cw = &widgets[widget_count++];
    memset(cw, 0, sizeof(*cw));
    cw->box  = box;
    cw->type = w->type;
    cw->w    = w->w;
    if (w->type == DW_CLAUDE_SESSIONS) {
        sessions_create(cw, bw, bh);
    } else {
        usage_create(cw, bw, bh);
    }
    claude_dirty = true;
    return true;
}

static lv_color_t state_color(uint8_t state, const UiTick *t)
{
    switch (state) {
    case DCS_WORKING:    return t->accent;
    case DCS_PERMISSION: return COLOR_WARN;
    case DCS_WAITING:    return COLOR_OK;
    default:             return COLOR_TEXT_DIM;
    }
}

static void right_text(char *out, size_t n, const DeckClaudeSession *s, uint8_t w)
{
    char ctx[8], cost[16];
    if (s->ctx < 0) {
        snprintf(ctx, sizeof(ctx), "--");
    } else {
        snprintf(ctx, sizeof(ctx), "%d%%", s->ctx);
    }
    if (w < 4) {
        snprintf(out, n, "%s", ctx);
    } else if (w < 6) {
        snprintf(out, n, "%s  %s", s->model, ctx);
    } else {
        deck_claude_format_cost(s->cost_cents, cost, sizeof(cost));
        snprintf(out, n, "%s  %s  %s", s->model, cost, ctx);
    }
}

static void row_show(SessRow *r, bool show)
{
    if (show) {
        lv_obj_clear_flag(r->obj, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(r->obj, LV_OBJ_FLAG_HIDDEN);
    }
}

static void sessions_refresh(ClaudeWidget *cw, const UiTick *t, bool live)
{
    const DeckClaudeSession *rows[DECK_CLAUDE_MAX_SESSIONS];
    int count = 0;
    for (int i = 0; live && i < snap.count && i < DECK_CLAUDE_MAX_SESSIONS; i++) {
        if (snap.s[i].live) {
            rows[count++] = &snap.s[i];
        }
    }
    if (!live || count == 0) {
        for (int i = 0; i < cw->rows; i++) {
            row_show(&cw->row[i], false);
        }
        set_text(cw->msg, live ? "No sessions" : "--");
        lv_obj_clear_flag(cw->msg, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_add_flag(cw->msg, LV_OBJ_FLAG_HIDDEN);

    bool more = count > cw->rows;
    for (int i = 0; i < cw->rows; i++) {
        SessRow *r = &cw->row[i];
        if (i >= count) {
            row_show(r, false);
            continue;
        }
        row_show(r, true);
        if (more && i == cw->rows - 1) {
            r->idx = -1;
            lv_obj_clear_flag(r->obj, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_add_flag(r->dot, LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(r->right, LV_OBJ_FLAG_HIDDEN);
            lv_obj_set_style_text_color(r->proj, COLOR_TEXT_DIM, 0);
            char more_txt[16];
            snprintf(more_txt, sizeof(more_txt), "+%d more", count - cw->rows + 1);
            set_text(r->proj, more_txt);
            continue;
        }
        const DeckClaudeSession *s = rows[i];
        char right[56];
        r->idx = (int)(s - snap.s);
        if (s->tmux) {
            lv_obj_add_flag(r->obj, LV_OBJ_FLAG_CLICKABLE);
        } else {
            lv_obj_clear_flag(r->obj, LV_OBJ_FLAG_CLICKABLE);
        }
        lv_obj_clear_flag(r->dot, LV_OBJ_FLAG_HIDDEN);
        lv_obj_clear_flag(r->right, LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_style_bg_color(r->dot, state_color(s->state, t), 0);
        lv_obj_set_style_text_color(r->proj, COLOR_TEXT, 0);
        set_text(r->proj, s->project);
        right_text(right, sizeof(right), s, cw->w);
        set_text(r->right, right);
    }
}

static void usage_set(ClaudeWidget *cw, int i, const DeckClaudeWindow *win, const UiTick *t, bool live)
{
    UsageSec *s = &cw->sec[i];
    bool known = live && win->known;
    int pct = win->pct > 100 ? 100 : win->pct;
    char pbuf[8] = "--";
    if (known) {
        snprintf(pbuf, sizeof(pbuf), "%d%%", pct);
    }
    set_text(s->pct, pbuf);
    if (s->reset) {
        char buf[16] = "";
        if (known) {
            uint32_t now = t->time_valid ? (uint32_t)time(NULL) : 0;
            deck_claude_format_reset(win->resets_at, now, buf, sizeof(buf));
        }
        set_text(s->reset, buf);
    }
    lv_color_t c = t->accent;
    if (known && pct >= 95) {
        c = COLOR_ERR;
    } else if (known && pct >= 80) {
        c = COLOR_WARN;
    }
    lv_obj_set_style_bg_color(s->bar, c, LV_PART_INDICATOR);
    lv_bar_set_value(s->bar, known ? pct : 0, LV_ANIM_OFF);
}

static void usage_refresh(ClaudeWidget *cw, const UiTick *t, bool live)
{
    usage_set(cw, 0, &snap.five_hour, t, live);
    usage_set(cw, 1, &snap.seven_day, t, live);
}

void ui_claude_update(const UiTick *t, bool ready)
{
    if (widget_count == 0) {
        return;
    }
    uint32_t accent = lv_color_to32(t->accent);
    uint32_t ver    = deck_net_claude_version();
    bool full = claude_dirty || ver != seen_version || ready != seen_ready || accent != seen_accent;
    if (!full && !t->new_minute) {
        return;
    }
    if (full) {
        claude_dirty = false;
        seen_version = ver;
        seen_ready   = ready;
        seen_accent  = accent;
        snap_ok      = deck_net_claude(&snap);
    }
    bool live = ready && snap_ok;
    for (int i = 0; i < widget_count; i++) {
        ClaudeWidget *cw = &widgets[i];
        if (cw->type == DW_CLAUDE_USAGE) {
            if (full) {
                lv_obj_set_style_opa(cw->box, ready ? LV_OPA_COVER : OFFLINE_OPA, 0);
            }
            usage_refresh(cw, t, live);
        } else if (full) {
            lv_obj_set_style_opa(cw->box, ready ? LV_OPA_COVER : OFFLINE_OPA, 0);
            sessions_refresh(cw, t, live);
        }
    }
}

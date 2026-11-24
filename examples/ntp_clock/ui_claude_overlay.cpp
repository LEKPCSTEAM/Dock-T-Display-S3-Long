#include <stdio.h>
#include <string.h>
#include "ui_internal.h"
#include "deck_net.h"

#define ARM_GUARD_MS 600
#define SEND_RETRY_MS 4000
#define BTN_W        150
#define BTN_H        80
#define BTN_Y        94
#define KEYBOARD_MSG "Answer at the keyboard"

enum { B_APPROVE, B_ALWAYS, B_DENY, B_OPEN, B_COUNT };

static const uint8_t BTN_ACTION[B_COUNT] = { DCA_APPROVE, DCA_ALWAYS, DCA_DENY, DCA_FOCUS };

static DeckClaude       cl;
static bool             cl_valid;
static uint32_t         seen_version = UINT32_MAX;
static DeckClaudePrompt shown;
static DeckClaudePrompt hidden_for;
static uint32_t         armed_at;
static uint32_t         sent_at;  // 0 when not sending

static lv_obj_t *root;
static lv_obj_t *lbl_project;
static lv_obj_t *lbl_tool;
static lv_obj_t *lbl_pending;
static lv_obj_t *lbl_summary;
static lv_obj_t *lbl_keyboard;
static lv_obj_t *btn[B_COUNT];
static lv_obj_t *btn_close;

static void set_sendable(bool enabled)
{
    for (int i = B_APPROVE; i <= B_DENY; i++) {
        if (enabled) {
            lv_obj_clear_state(btn[i], LV_STATE_DISABLED);
        } else {
            lv_obj_add_state(btn[i], LV_STATE_DISABLED);
        }
    }
    if (enabled) {
        sent_at = 0;
    }
}

static void hide_root()
{
    if (root && !lv_obj_has_flag(root, LV_OBJ_FLAG_HIDDEN)) {
        lv_obj_add_flag(root, LV_OBJ_FLAG_HIDDEN);
    }
}

static void btn_cb(lv_event_t *e)
{
    int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (lv_tick_elaps(armed_at) < ARM_GUARD_MS || !deck_net_ready() || !shown.present) {
        return;
    }
    if (idx == B_OPEN) {
        deck_net_claude_action(shown.session, "", DCA_FOCUS);
        return;
    }
    if (lv_obj_has_state(btn[idx], LV_STATE_DISABLED)) {
        return;
    }
    deck_net_claude_action(shown.session, shown.request, BTN_ACTION[idx]);
    set_sendable(false);
    sent_at = lv_tick_get() | 1;
}

static void close_cb(lv_event_t *)
{
    if (lv_tick_elaps(armed_at) < ARM_GUARD_MS) {
        return;
    }
    hidden_for = shown;
    hide_root();
}

static lv_obj_t *make_button(int idx, const char *text, lv_color_t bg, lv_color_t fg)
{
    lv_obj_t *b = lv_btn_create(root);
    lv_obj_set_size(b, BTN_W, BTN_H);
    lv_obj_set_pos(b, 8 + idx * (BTN_W + 8), BTN_Y);
    lv_obj_set_style_radius(b, 10, 0);
    lv_obj_set_style_bg_color(b, bg, 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_width(b, 0, 0);
    lv_obj_set_style_opa(b, LV_OPA_40, LV_STATE_DISABLED);
    lv_obj_t *l = ui_label(b, &ui_font_th_22, fg, text);
    lv_obj_center(l);
    lv_obj_add_event_cb(b, btn_cb, LV_EVENT_SHORT_CLICKED, (void *)(intptr_t)idx);
    return b;
}

static void overlay_create(const UiTick *t)
{
    root = lv_obj_create(lv_layer_top());
    ui_strip_obj(root);
    lv_obj_add_flag(root, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(root, SCREEN_W, SCREEN_H);
    lv_obj_set_style_bg_color(root, COLOR_BG, 0);
    lv_obj_set_style_bg_opa(root, LV_OPA_COVER, 0);

    lv_obj_t *row = lv_obj_create(root);
    ui_strip_obj(row);
    lv_obj_set_size(row, 470, 36);
    lv_obj_set_pos(row, 8, 6);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, 10, 0);

    ui_label(row, &lv_font_montserrat_14, COLOR_WARN, LV_SYMBOL_WARNING);
    lbl_project = ui_label(row, &ui_font_th_22, COLOR_TEXT, "");
    lv_label_set_long_mode(lbl_project, LV_LABEL_LONG_DOT);
    lv_obj_set_style_max_width(lbl_project, 300, 0);
    lv_obj_set_height(lbl_project, 33);
    lbl_tool = ui_label(row, &ui_font_th_22, t->accent, "");
    lv_label_set_long_mode(lbl_tool, LV_LABEL_LONG_DOT);
    lv_obj_set_size(lbl_tool, 120, 33);

    btn_close = lv_btn_create(root);
    lv_obj_set_size(btn_close, 44, 36);
    lv_obj_set_pos(btn_close, SCREEN_W - 8 - 44, 6);
    lv_obj_set_ext_click_area(btn_close, 10);
    lv_obj_set_style_bg_color(btn_close, COLOR_PANEL_HI, 0);
    lv_obj_set_style_bg_opa(btn_close, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_width(btn_close, 0, 0);
    lv_obj_center(ui_label(btn_close, &lv_font_montserrat_14, COLOR_TEXT, LV_SYMBOL_CLOSE));
    lv_obj_add_event_cb(btn_close, close_cb, LV_EVENT_SHORT_CLICKED, NULL);

    lbl_pending = ui_label(root, &ui_font_th_16, COLOR_TEXT_DIM, "");
    lv_obj_set_width(lbl_pending, 60);
    lv_obj_set_style_text_align(lbl_pending, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_align_to(lbl_pending, btn_close, LV_ALIGN_OUT_LEFT_MID, -16, 0);

    lbl_summary = ui_label(root, &ui_font_th_22, COLOR_TEXT, "");
    lv_label_set_long_mode(lbl_summary, LV_LABEL_LONG_DOT);
    lv_obj_set_size(lbl_summary, 624, 33);
    lv_obj_set_pos(lbl_summary, 8, 48);

    btn[B_APPROVE] = make_button(B_APPROVE, "Approve", COLOR_OK, COLOR_BG);
    btn[B_ALWAYS]  = make_button(B_ALWAYS, "Always", COLOR_PANEL_HI, COLOR_OK);
    btn[B_DENY]    = make_button(B_DENY, "Deny", COLOR_ERR, COLOR_BG);
    btn[B_OPEN]    = make_button(B_OPEN, "Open", COLOR_PANEL_HI, COLOR_TEXT);

    lbl_keyboard = ui_label(root, &ui_font_th_22, COLOR_TEXT_DIM, KEYBOARD_MSG);
    lv_obj_set_width(lbl_keyboard, SCREEN_W);
    lv_obj_set_style_text_align(lbl_keyboard, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(lbl_keyboard, 0, 110);
}

static void show_prompt(const UiTick *t, const DeckClaudePrompt *p)
{
    if (!root) {
        overlay_create(t);
    }
    bool is_new          = !deck_claude_prompt_same(&shown, p);
    bool pending_changed = is_new || p->pending != shown.pending;
    shown                = *p;
    if (is_new) {
        lv_label_set_text(lbl_project, p->project);
        lv_label_set_text(lbl_tool, p->tool);
        lv_obj_set_style_text_color(lbl_tool, t->accent, 0);
        lv_label_set_text(lbl_summary, p->summary);
        for (int i = 0; i < B_COUNT; i++) {
            if (p->tmux) {
                lv_obj_clear_flag(btn[i], LV_OBJ_FLAG_HIDDEN);
            } else {
                lv_obj_add_flag(btn[i], LV_OBJ_FLAG_HIDDEN);
            }
        }
        if (p->tmux) {
            lv_obj_add_flag(lbl_keyboard, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_clear_flag(lbl_keyboard, LV_OBJ_FLAG_HIDDEN);
        }
        set_sendable(true);
        armed_at = lv_tick_get();
        lv_obj_move_foreground(root);
        ui_flash_screen(COLOR_WARN);
    }
    if (pending_changed) {
        char buf[16];
        snprintf(buf, sizeof(buf), "+%u", (unsigned)(p->pending - 1));
        lv_label_set_text(lbl_pending, buf);
    }
    bool want_pending = p->pending > 1;
    if (want_pending == lv_obj_has_flag(lbl_pending, LV_OBJ_FLAG_HIDDEN)) {
        if (want_pending) {
            lv_obj_clear_flag(lbl_pending, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(lbl_pending, LV_OBJ_FLAG_HIDDEN);
        }
    }
    if (lv_obj_has_flag(root, LV_OBJ_FLAG_HIDDEN)) {
        lv_obj_clear_flag(root, LV_OBJ_FLAG_HIDDEN);
    }
}

void ui_claude_overlay_update(const UiTick *t)
{
    uint32_t v = deck_net_claude_version();
    if (v != seen_version) {
        seen_version = v;
        cl_valid     = deck_net_claude(&cl);
    }

    if (sent_at && lv_tick_elaps(sent_at & ~1u) >= SEND_RETRY_MS) {
        set_sendable(true);
    }

    if (cl_valid && cl.prompt.present) {
        if (!deck_claude_prompt_same(&hidden_for, &cl.prompt)) {
            show_prompt(t, &cl.prompt);
        } else {
            hide_root();
        }
    } else {
        memset(&shown, 0, sizeof(shown));
        memset(&hidden_for, 0, sizeof(hidden_for));
        hide_root();
    }

    // After show_prompt so a same-tick toast stays above the overlay.
    DeckClaudeAck ack;
    if (deck_net_take_claude_ack(&ack) && !ack.ok) {
        ui_toast(KEYBOARD_MSG);
        if (root && strcmp(ack.request, shown.request) == 0) {
            set_sendable(true);
        }
    }
}

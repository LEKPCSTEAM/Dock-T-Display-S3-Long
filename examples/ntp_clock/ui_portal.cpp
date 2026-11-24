#include <stdio.h>
#include <string.h>
#include "ui_internal.h"

#define QR_MAIN_SIZE  150
#define QR_SMALL_SIZE 100
#define QR_PAD        8
#define MID_X         176
#define MID_W         330

static lv_obj_t *overlay;
static lv_obj_t *qr_wifi;
static lv_obj_t *steps[3];
static lv_obj_t *status_label;
static lv_obj_t *close_btn;

static bool prev_portal;
static bool dismissed;
static bool close_requested;
static bool manual_portal;
static int  client_shown = -1;
static char last_ap[33];

static lv_obj_t *make_qr(lv_obj_t *parent, lv_coord_t size, lv_coord_t x, lv_coord_t y, lv_obj_t **qr_out)
{
    lv_obj_t *frame = lv_obj_create(parent);
    ui_strip_obj(frame);
    lv_obj_clear_flag(frame, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(frame, x, y);
    lv_obj_set_size(frame, size, size);
    lv_obj_set_style_bg_color(frame, lv_color_white(), 0);
    lv_obj_set_style_bg_opa(frame, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(frame, 8, 0);
    lv_obj_t *qr = lv_qrcode_create(frame, size - 2 * QR_PAD, lv_color_black(), lv_color_white());
    lv_obj_center(qr);
    *qr_out = qr;
    return frame;
}

static void close_cb(lv_event_t *)
{
    if (manual_portal) {
        net_cancel_portal();
    }
    close_requested = true;
}

static void set_wifi_qr(const char *ap_ssid)
{
    char data[80];
    int  n = snprintf(data, sizeof(data), "WIFI:T:nopass;S:%s;;", ap_ssid);
    lv_qrcode_update(qr_wifi, data, n);
    snprintf(last_ap, sizeof(last_ap), "%s", ap_ssid);
}

static void set_status(bool client)
{
    client_shown = client;
    lv_label_set_text(status_label, client ? LV_SYMBOL_OK "  มีอุปกรณ์เชื่อมต่อแล้ว" : LV_SYMBOL_REFRESH "  รออุปกรณ์เชื่อมต่อ…");
    lv_obj_set_style_text_color(status_label, client ? COLOR_OK : COLOR_TEXT_DIM, 0);
}

static void overlay_create(const UiTick *t)
{
    overlay = lv_obj_create(lv_layer_top());
    ui_strip_obj(overlay);
    lv_obj_set_size(overlay, SCREEN_W, SCREEN_H);
    lv_obj_set_style_bg_color(overlay, COLOR_BG, 0);
    lv_obj_set_style_bg_opa(overlay, LV_OPA_COVER, 0);

    make_qr(overlay, QR_MAIN_SIZE, 14, (SCREEN_H - QR_MAIN_SIZE) / 2, &qr_wifi);
    set_wifi_qr(t->net->ap_ssid);

    lv_obj_t *title_row = lv_obj_create(overlay);
    ui_strip_obj(title_row);
    lv_obj_clear_flag(title_row, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(title_row, MID_X, 10);
    lv_obj_set_size(title_row, MID_W, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(title_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(title_row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(title_row, 10, 0);
    ui_label(title_row, &font_th_22, t->accent, LV_SYMBOL_WIFI);
    ui_label(title_row, &font_th_22, t->accent, "ตั้งค่า WiFi");

    char buf[96];
    snprintf(buf, sizeof(buf), "1) สแกน QR หรือต่อ WiFi: %s", t->net->ap_ssid);
    const char *texts[3] = {buf, "2) หน้าตั้งค่าจะเปิดเอง หรือเข้า " CLOCK_PORTAL_IP,
                            "3) เลือก WiFi บ้าน ใส่รหัส แล้วกดบันทึก"};
    lv_obj_t *col = lv_obj_create(overlay);
    ui_strip_obj(col);
    lv_obj_clear_flag(col, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(col, MID_X, 48);
    lv_obj_set_size(col, MID_W, 92);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(col, 4, 0);
    for (int i = 0; i < 3; i++) {
        steps[i] = ui_label(col, &font_th_16, COLOR_TEXT, texts[i]);
        lv_label_set_long_mode(steps[i], LV_LABEL_LONG_WRAP);
        lv_obj_set_width(steps[i], MID_W);
    }

    status_label = ui_label(overlay, &font_th_16, COLOR_TEXT_DIM, "");
    lv_obj_set_pos(status_label, MID_X, SCREEN_H - 34);
    client_shown = -1;
    set_status(t->net->portal_client);

    lv_obj_t *qr_url;
    lv_obj_t *url_frame = make_qr(overlay, QR_SMALL_SIZE, 526, 40, &qr_url);
    const char *url = "http://" CLOCK_PORTAL_IP;
    lv_qrcode_update(qr_url, url, strlen(url));
    lv_obj_t *cap = ui_label(overlay, &font_th_16, COLOR_TEXT_DIM, "หน้าตั้งค่า");
    lv_obj_align_to(cap, url_frame, LV_ALIGN_OUT_BOTTOM_MID, 0, 4);

    close_btn = lv_btn_create(overlay);
    lv_obj_set_size(close_btn, 38, 30);
    lv_obj_set_pos(close_btn, SCREEN_W - 38 - 8, 6);
    lv_obj_set_style_bg_color(close_btn, COLOR_PANEL_HI, 0);
    lv_obj_set_style_radius(close_btn, 15, 0);
    lv_obj_set_style_shadow_width(close_btn, 0, 0);
    lv_obj_t *x = ui_label(close_btn, &font_th_16, COLOR_TEXT, LV_SYMBOL_CLOSE);
    lv_obj_center(x);
    lv_obj_add_event_cb(close_btn, close_cb, LV_EVENT_CLICKED, NULL);
}

static void overlay_destroy()
{
    if (overlay) {
        lv_obj_del(overlay);
        overlay = NULL;
    }
    close_requested = false;
    last_ap[0]      = '\0';
}

void ui_portal_update(const UiTick *t)
{
    bool in_portal = t->net->phase == NET_PORTAL;
    manual_portal  = t->net->portal_manual;

    if (in_portal) {
        if (!prev_portal) {
            dismissed = false;
        }
        if (close_requested) {
            dismissed = true;
        }
        if (dismissed) {
            overlay_destroy();
        } else if (!overlay) {
            overlay_create(t);
        } else {
            if (strcmp(last_ap, t->net->ap_ssid) != 0) {
                set_wifi_qr(t->net->ap_ssid);
            }
            if ((int)t->net->portal_client != client_shown) {
                set_status(t->net->portal_client);
            }
        }
    } else if (prev_portal) {
        overlay_destroy();
        dismissed = false;
        if (t->net->phase == NET_CONNECTED) {
            char buf[80];
            snprintf(buf, sizeof(buf), "เชื่อมต่อ %s สำเร็จ", t->net->ssid);
            ui_toast(buf);
        }
    }
    prev_portal = in_portal;
}

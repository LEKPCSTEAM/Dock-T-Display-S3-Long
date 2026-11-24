#include <stdio.h>
#include <string.h>
#include "ui_internal.h"
#include "eez/gen/screens.h"

static lv_obj_t *overlay;

static bool prev_portal;
static bool dismissed;
static bool close_requested;
static bool manual_portal;
static int  client_shown = -1;
static char last_ap[33];

static bool overlay_shown()
{
    return overlay && !lv_obj_has_flag(overlay, LV_OBJ_FLAG_HIDDEN);
}

static void close_cb(lv_event_t *)
{
    // Press-lock can deliver a click after the overlay was hidden.
    if (!overlay_shown()) {
        return;
    }
    if (manual_portal) {
        net_cancel_portal();
    }
    close_requested = true;
}

static void set_wifi_qr(const char *ap_ssid)
{
    char data[80];
    int  n = snprintf(data, sizeof(data), "WIFI:T:nopass;S:%s;;", ap_ssid);
    lv_qrcode_update(objects.qrcode_portal_wifi, data, n);
    snprintf(last_ap, sizeof(last_ap), "%s", ap_ssid);
}

static void set_status(bool client)
{
    client_shown = client;
    lv_label_set_text(objects.label_portal_status, client ? LV_SYMBOL_OK "  มีอุปกรณ์เชื่อมต่อแล้ว" : LV_SYMBOL_REFRESH "  รออุปกรณ์เชื่อมต่อ…");
    lv_obj_set_style_text_color(objects.label_portal_status, client ? COLOR_OK : COLOR_TEXT_DIM, 0);
}

static void overlay_create(const char *ap_ssid)
{
    overlay = lv_obj_create(lv_layer_top());
    ui_strip_obj(overlay);
    lv_obj_set_size(overlay, SCREEN_W, SCREEN_H);
    lv_obj_set_style_bg_color(overlay, COLOR_BG, 0);
    lv_obj_set_style_bg_opa(overlay, LV_OPA_COVER, 0);

    create_screen_portal_page();
    ui_mount_screen(objects.portal_page, overlay);
    objects.portal_page = NULL;

    set_wifi_qr(ap_ssid);
    lv_label_set_text_static(objects.label_portal_step2, "2) หน้าตั้งค่าจะเปิดเอง หรือเข้า " CLOCK_PORTAL_IP);
    const char *url = "http://" CLOCK_PORTAL_IP;
    lv_qrcode_update(objects.qrcode_portal_url, url, strlen(url));
    lv_obj_add_event_cb(objects.btn_portal_close, close_cb, LV_EVENT_CLICKED, NULL);
}

static void overlay_show(const UiTick *t)
{
    if (!overlay) {
        overlay_create(t->net->ap_ssid);
    } else if (strcmp(last_ap, t->net->ap_ssid) != 0) {
        set_wifi_qr(t->net->ap_ssid);
    }
    lv_obj_set_style_text_color(objects.label_portal_title, t->accent, 0);

    char buf[96];
    snprintf(buf, sizeof(buf), "1) สแกน QR หรือต่อ WiFi: %s", t->net->ap_ssid);
    lv_label_set_text(objects.label_portal_step1, buf);
    set_status(t->net->portal_client);

    // Cover the splash and any toast or flash created since.
    lv_obj_move_foreground(overlay);
    lv_obj_clear_flag(overlay, LV_OBJ_FLAG_HIDDEN);
}

static void overlay_hide()
{
    if (overlay) {
        lv_obj_add_flag(overlay, LV_OBJ_FLAG_HIDDEN);
    }
    close_requested = false;
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
            overlay_hide();
        } else if (!overlay_shown()) {
            overlay_show(t);
        } else {
            if (strcmp(last_ap, t->net->ap_ssid) != 0) {
                set_wifi_qr(t->net->ap_ssid);
            }
            if ((int)t->net->portal_client != client_shown) {
                set_status(t->net->portal_client);
            }
        }
    } else if (prev_portal) {
        overlay_hide();
        dismissed = false;
        if (t->net->phase == NET_CONNECTED) {
            char buf[80];
            snprintf(buf, sizeof(buf), "เชื่อมต่อ %s สำเร็จ", t->net->ssid);
            ui_toast(buf);
        }
    }
    prev_portal = in_portal;
}

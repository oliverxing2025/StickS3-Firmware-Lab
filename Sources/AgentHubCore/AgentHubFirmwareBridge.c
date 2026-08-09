#include "AgentHubFirmwareBridge.h"
#include <stdlib.h>
#include <string.h>
#include "lvgl.h"

typedef struct {
    uint32_t now_ms;
    uint32_t last_person_frame_ms;
    uint32_t last_activity_frame_ms;
    int last_person_animation;
    uint32_t frame_serial;
    uint16_t *framebuffer;
    uint8_t *draw_buffer;
    int32_t frame_width;
    int32_t frame_height;
} AgentHubHostContext;
static AgentHubHostContext *s_host_context;

#define VIRTUAL_DEVICE_HOST 1
#define codex_host_time_us agent_hub_host_time_us
#ifndef AGENT_HUB_FIRMWARE_MAIN
#define AGENT_HUB_FIRMWARE_MAIN "../../Vendor/Firmware/agentHub/src/main.c"
#endif
#include AGENT_HUB_FIRMWARE_MAIN

int64_t agent_hub_host_time_us(void) {
    return s_host_context ? (int64_t)s_host_context->now_ms * 1000 : 0;
}

static void host_flush(lv_display_t *display, const lv_area_t *area, uint8_t *px_map)
{
    AgentHubHostContext *context = lv_display_get_user_data(display);
    if (!context) return;
    int width = area->x2 - area->x1 + 1;
    int height = area->y2 - area->y1 + 1;
    const uint16_t *source = (const uint16_t *)px_map;
    for (int row = 0; row < height; ++row) {
        memcpy(context->framebuffer + (area->y1 + row) * context->frame_width + area->x1,
               source + row * width, (size_t)width * sizeof(uint16_t));
    }
    lv_display_flush_ready(display);
}

static void copy_text(char *target, size_t size, const char *source)
{
    if (!source) source = "";
    snprintf(target, size, "%s", source);
}

void *agent_hub_firmware_create(void)
{
    AgentHubHostContext *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    context->framebuffer = calloc(LCD_V_RES * LCD_H_RES, sizeof(uint16_t));
    context->draw_buffer = malloc(LCD_V_RES * LVGL_DRAW_BUF_LINES * sizeof(uint16_t));
    if (!context->framebuffer || !context->draw_buffer) {
        agent_hub_firmware_destroy(context); return NULL;
    }
    s_host_context = context;
    context->last_person_animation = -1;
    context->frame_width = LCD_H_RES;
    context->frame_height = LCD_V_RES;
    if (!lv_is_initialized()) lv_init();
    s_display = lv_display_create(LCD_H_RES, LCD_V_RES);
    lv_display_set_default(s_display);
    lv_display_set_user_data(s_display, context);
    lv_display_set_color_format(s_display, LV_COLOR_FORMAT_RGB565);
    lv_display_set_flush_cb(s_display, host_flush);
    lv_display_set_buffers(s_display, context->draw_buffer, NULL,
        LCD_V_RES * LVGL_DRAW_BUF_LINES * sizeof(uint16_t), LV_DISPLAY_RENDER_MODE_PARTIAL);
    s_landscape_active = false;
    s_landscape_reverse = false;
    s_wifi_connected = true;
    s_provider_selector_active = true;
    create_provider_selector_ui(lv_display_get_screen_active(s_display));
    render_state();
    lv_refr_now(s_display);
    ++context->frame_serial;
    return context;
}

void agent_hub_firmware_destroy(void *opaque)
{
    AgentHubHostContext *context = opaque;
    if (!context) return;
    if (s_host_context == context) {
        if (s_activity_timer) {
            lv_timer_delete(s_activity_timer);
            s_activity_timer = NULL;
        }
        if (s_status_person_timer) {
            lv_timer_delete(s_status_person_timer);
            s_status_person_timer = NULL;
        }
        if (s_display) lv_display_delete(s_display);
        s_display = NULL; s_host_context = NULL;
    }
    free(context->framebuffer); free(context->draw_buffer); free(context);
}

void agent_hub_firmware_set_state(
    void *opaque, const char *status, const char *time, const char *date,
    const char *weekday, int32_t battery, bool charging, bool usb_powered,
    int32_t quota_5h, int32_t quota_5h_reset_minutes,
    int32_t quota_7d, int32_t quota_7d_reset_minutes,
    double month_cost, int64_t month_tokens,
    int32_t today_used_percent, int64_t today_tokens,
    int32_t running_tasks, int32_t waiting_tasks, int32_t finished_tasks,
    bool quota_5h_valid, bool quota_5h_reset_valid,
    bool quota_7d_valid, bool quota_7d_reset_valid,
    bool month_cost_valid, bool month_tokens_valid,
    bool today_used_percent_valid, bool today_tokens_valid)
{
    AgentHubHostContext *context = opaque;
    if (!context) return;
    s_host_context = context; lv_display_set_default(s_display);
    agent_state_t next_state = s_state;
    copy_text(next_state.time, sizeof(next_state.time), time);
    copy_text(next_state.date, sizeof(next_state.date), date);
    copy_text(next_state.weekday, sizeof(next_state.weekday), weekday);
    next_state.battery = battery; next_state.battery_charging = charging;
    next_state.usb_powered = usb_powered;
    provider_display_state_t *provider = &s_provider_states[s_current_provider];
    provider_display_state_t next_provider = *provider;
    copy_text(next_provider.status, sizeof(next_provider.status), status);
    next_provider.quota_5h = quota_5h; next_provider.quota_5h_valid = quota_5h_valid;
    next_provider.quota_5h_reset_minutes = quota_5h_reset_minutes;
    next_provider.quota_5h_reset_minutes_valid = quota_5h_reset_valid;
    next_provider.quota_7d = quota_7d; next_provider.quota_7d_valid = quota_7d_valid;
    next_provider.quota_7d_reset_minutes = quota_7d_reset_minutes;
    next_provider.quota_7d_reset_minutes_valid = quota_7d_reset_valid;
    next_provider.month_cost_usd = month_cost; next_provider.month_cost_usd_valid = month_cost_valid;
    next_provider.month_tokens = month_tokens; next_provider.month_tokens_valid = month_tokens_valid;
    next_provider.today_used_percent = today_used_percent;
    next_provider.today_used_percent_valid = today_used_percent_valid;
    next_provider.today_tokens = today_tokens;
    next_provider.today_tokens_valid = today_tokens_valid;
    next_provider.running_tasks = running_tasks; next_provider.waiting_tasks = waiting_tasks;
    next_provider.finished_tasks = finished_tasks;
    const bool changed = memcmp(&s_state, &next_state, sizeof(s_state)) != 0
        || memcmp(provider, &next_provider, sizeof(*provider)) != 0;
    s_state = next_state;
    *provider = next_provider;
    if (!changed) return;
    render_state(); lv_refr_now(s_display); ++context->frame_serial;
}

void agent_hub_firmware_update(void *opaque, uint32_t now_ms)
{
    AgentHubHostContext *context = opaque;
    if (!context) return;
    s_host_context = context; context->now_ms = now_ms;
    lv_display_set_default(s_display);
    /* 虚拟机使用与真机 LVGL 相同的毫秒周期，不跟随屏幕 FPS 切帧。 */
    const int animation = (int)s_status_person_animation;
    if (context->last_person_animation != animation) {
        context->last_person_animation = animation;
        context->last_person_frame_ms = now_ms;
    }
    uint32_t person_period_ms = 0;
    if (s_status_person_animation == STATUS_PERSON_ANIMATION_RUN) {
        person_period_ms = 120;
    } else if (s_status_person_animation == STATUS_PERSON_ANIMATION_WAIT) {
        person_period_ms = 300;
    } else if (s_status_person_animation == STATUS_PERSON_ANIMATION_DONE) {
        person_period_ms = 150;
    }
    if (person_period_ms > 0) {
        const uint32_t elapsed = now_ms - context->last_person_frame_ms;
        if (elapsed >= person_period_ms) {
            uint32_t steps = elapsed / person_period_ms;
            /* 长时间暂停后只追赶有限帧，避免一次更新阻塞。 */
            if (steps > 8) steps = 8;
            for (uint32_t i = 0; i < steps; ++i) {
                status_person_timer_cb(NULL);
            }
            context->last_person_frame_ms = now_ms;
        }
    }
    bool changed = false;
    if (person_period_ms > 0 && now_ms == context->last_person_frame_ms) changed = true;
    if (now_ms - context->last_activity_frame_ms >= ACTIVITY_FRAME_MS) {
        activity_timer_cb(NULL);
        context->last_activity_frame_ms = now_ms;
        changed = true;
    }
    if (changed) {
        lv_refr_now(s_display);
        ++context->frame_serial;
    }
}

void agent_hub_firmware_set_recording(void *opaque, bool recording)
{
    AgentHubHostContext *context = opaque;
    if (!context) return;
    s_host_context = context; lv_display_set_default(s_display);
    show_recording_overlay("LISTENING", "RELEASE TO SEND", recording);
    lv_refr_now(s_display); ++context->frame_serial;
}

void agent_hub_firmware_set_orientation(void *opaque, bool landscape, bool landscape_reverse)
{
    AgentHubHostContext *context = opaque;
    if (!context || !s_display) return;
    /* The startup selector is a fixed portrait screen, matching the device. */
    if (s_provider_selector_active) return;
    if (s_landscape_active == landscape &&
        (!landscape || s_landscape_reverse == landscape_reverse)) return;

    s_host_context = context;
    lv_display_set_default(s_display);
    lv_obj_t *old_screen = lv_display_get_screen_active(s_display);
    if (s_activity_timer) {
        lv_timer_delete(s_activity_timer);
        s_activity_timer = NULL;
    }
    if (s_status_person_timer) {
        lv_timer_delete(s_status_person_timer);
        s_status_person_timer = NULL;
    }
    s_status_person_animation = STATUS_PERSON_ANIMATION_NONE;

    context->frame_width = landscape ? LCD_V_RES : LCD_H_RES;
    context->frame_height = landscape ? LCD_H_RES : LCD_V_RES;
    memset(context->framebuffer, 0, LCD_V_RES * LCD_H_RES * sizeof(uint16_t));
    lv_display_set_resolution(s_display, context->frame_width, context->frame_height);

    lv_obj_t *new_screen = lv_obj_create(NULL);
    s_landscape_active = landscape;
    s_landscape_reverse = landscape && landscape_reverse;
    if (landscape) {
        create_landscape_ui(new_screen);
    } else {
        create_portrait_ui(new_screen);
        /* 虚拟设备竖屏显示秒；只调整 host 标签宽度，不修改原固件源码。 */
        lv_obj_set_width(s_time_label, 58);
    }
    lv_screen_load(new_screen);
    lv_obj_delete(old_screen);
    render_state();
    lv_refr_now(s_display);
    ++context->frame_serial;
}

AgentHubFirmwareSnapshot agent_hub_firmware_snapshot(void *opaque)
{
    AgentHubFirmwareSnapshot result = {0};
    if (!opaque) return result;
    provider_display_state_t *provider = &s_provider_states[s_current_provider];
    result.running_tasks = provider->running_tasks;
    result.waiting_tasks = provider->waiting_tasks;
    result.finished_tasks = provider->finished_tasks;
    result.quota_5h = provider->quota_5h; result.quota_7d = provider->quota_7d;
    result.battery = s_state.battery;
    result.today_used_percent = provider->today_used_percent;
    result.today_tokens = provider->today_tokens;
    result.status_person_frame = s_status_person_frame;
    result.recording = s_recording_overlay_visible;
    return result;
}

void agent_hub_firmware_button(void *opaque, bool side_button, int32_t clicks)
{
    AgentHubHostContext *context = opaque;
    if (!context || clicks < 1) return;
    s_host_context = context;
    lv_display_set_default(s_display);

    if (s_provider_selector_active) {
        if (side_button && (clicks == 1 || clicks == 3)) {
            s_current_provider = (agent_provider_t)(
                ((int)s_current_provider + 1) % PROVIDER_COUNT);
            render_state();
        } else if (!side_button && clicks == 1) {
            load_provider_dashboard();
        } else {
            return;
        }
    } else if (side_button && clicks == 3) {
        s_current_provider = (agent_provider_t)(
            ((int)s_current_provider + 1) % PROVIDER_COUNT);
        render_state();
    } else {
        return;
    }

    lv_refr_now(s_display);
    ++context->frame_serial;
}

const uint16_t *agent_hub_firmware_framebuffer(void *opaque) {
    AgentHubHostContext *context = opaque; return context ? context->framebuffer : NULL;
}
uint32_t agent_hub_firmware_frame_serial(void *opaque) {
    AgentHubHostContext *context = opaque; return context ? context->frame_serial : 0;
}
int32_t agent_hub_firmware_frame_width(void *opaque) {
    AgentHubHostContext *context = opaque; return context ? context->frame_width : 0;
}
int32_t agent_hub_firmware_frame_height(void *opaque) {
    AgentHubHostContext *context = opaque; return context ? context->frame_height : 0;
}
int32_t agent_hub_firmware_active_provider(void *opaque) {
    return opaque ? (int32_t)s_current_provider : 0;
}
bool agent_hub_firmware_selector_active(void *opaque) {
    return opaque && s_provider_selector_active;
}

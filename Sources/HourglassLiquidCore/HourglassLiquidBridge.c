#include "HourglassLiquidBridge.h"
#include <stdlib.h>
#include <string.h>
#include "lvgl.h"

typedef struct {
    uint32_t now_ms;
    uint32_t last_animation_ms;
    uint32_t frame_serial;
    uint16_t *framebuffer;
    uint8_t *draw_buffer;
    uint32_t chime_serial;
} HourglassLiquidHostContext;
static HourglassLiquidHostContext *s_host_context;

#define hg_physics_init hg_liquid_physics_init
#define hg_physics_reset hg_liquid_physics_reset
#define hg_physics_step hg_liquid_physics_step
#define hg_physics_set_limits hg_liquid_physics_set_limits
#define hg_physics_request_particle_count hg_liquid_physics_request_particle_count
#define hg_physics_wake_surface hg_liquid_physics_wake_surface
#define hg_physics_particles hg_liquid_physics_particles
#define hg_physics_particle_count hg_liquid_physics_particle_count
#define hg_physics_stats hg_liquid_physics_stats
#define hg_geometry_left_boundary hg_liquid_geometry_left_boundary
#define hg_geometry_right_boundary hg_liquid_geometry_right_boundary

#define VIRTUAL_DEVICE_HOST 1
#ifndef LIQUID_FIRMWARE_MAIN
#define LIQUID_FIRMWARE_MAIN "../../Vendor/Firmware/liquid/src/main.c"
#endif
#include LIQUID_FIRMWARE_MAIN

int64_t hourglass_liquid_host_now_ms(void) { return s_host_context ? s_host_context->now_ms : 0; }

static void reset_firmware_state(void)
{
    s_preset_index = 1; s_duration_minutes = 5; s_custom_backup_minutes = 5;
    s_duration_ms = 5 * 60 * 1000; s_remaining_ms = s_duration_ms; s_deadline_ms = 0;
    s_running = false; s_custom_mode = false; s_inverted = false; s_flipping = false;
    s_pending_inverted = false; s_side_long_active = false;
    s_last_display_second = -1; s_last_display_percent = -1; s_last_frame_ms = 0;
    s_flip_start_ms = 0; s_flip_from_angle = 0; s_flip_to_angle = 0; s_render_angle = 0;
    s_render_cos = 1.0f; s_render_sin = 0.0f; s_physics_accumulator = 0.0f;
    s_perf_window_start_ms = 0; s_perf_frame_count = 0; s_low_fps_windows = 0;
    s_performance_level = 0; s_particle_glow_enabled = true; s_force_canvas_redraw = true;
    s_finish_settled_logged = false; s_imu_period_ms = 50;
    s_gravity_x = 0.0f; s_gravity_y = 1.0f; s_frame_overlay_count = 0;
    s_sand_cache_upper = -1; s_sand_cache_lower = -1;
    s_sand_cache_gravity_x = 0; s_sand_cache_gravity_y = 0; s_sand_cache_angle = -1;
}

esp_err_t hourglass_liquid_host_chime_play(void)
{
    if (s_host_context) ++s_host_context->chime_serial;
    return ESP_OK;
}

static void host_flush(lv_display_t *display, const lv_area_t *area, uint8_t *px_map)
{
    HourglassLiquidHostContext *context = lv_display_get_user_data(display);
    if (!context) return;
    int width = area->x2 - area->x1 + 1;
    int height = area->y2 - area->y1 + 1;
    const uint16_t *source = (const uint16_t *)px_map;
    for (int row = 0; row < height; ++row) {
        if (!s_inverted) {
            memcpy(context->framebuffer + (area->y1 + row) * LCD_H_RES + area->x1,
                   source + row * width, (size_t)width * sizeof(uint16_t));
            continue;
        }
        /* 与真机 LCD 倒置镜像保持一致。 */
        for (int column = 0; column < width; ++column) {
            int source_x = area->x1 + column;
            int source_y = area->y1 + row;
            int target_x = LCD_H_RES - 1 - source_x;
            int target_y = LCD_V_RES - 1 - source_y;
            context->framebuffer[target_y * LCD_H_RES + target_x] = source[row * width + column];
        }
    }
    lv_display_flush_ready(display);
}

void *hourglass_liquid_create(void)
{
    HourglassLiquidHostContext *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    context->framebuffer = calloc(LCD_H_RES * LCD_V_RES, sizeof(uint16_t));
    context->draw_buffer = malloc(LCD_H_RES * LVGL_DRAW_BUF_LINES * sizeof(uint16_t));
    if (!context->framebuffer || !context->draw_buffer) { hourglass_liquid_destroy(context); return NULL; }
    s_host_context = context;
    if (!lv_is_initialized()) lv_init();
    s_display = lv_display_create(LCD_H_RES, LCD_V_RES);
    lv_display_set_default(s_display);
    lv_display_set_user_data(s_display, context);
    lv_display_set_color_format(s_display, LV_COLOR_FORMAT_RGB565);
    lv_display_set_flush_cb(s_display, host_flush);
    lv_display_set_buffers(s_display, context->draw_buffer, NULL,
        LCD_H_RES * LVGL_DRAW_BUF_LINES * sizeof(uint16_t), LV_DISPLAY_RENDER_MODE_PARTIAL);
    reset_firmware_state();
    hg_physics_init();
    hg_physics_set_limits(HG_DEFAULT_MAX_ACTIVE, HG_DEFAULT_CONSTRAINT_ITERATIONS);
    create_ui();
    lv_refr_now(s_display);
    ++context->frame_serial;
    return context;
}

void hourglass_liquid_destroy(void *opaque)
{
    HourglassLiquidHostContext *context = opaque;
    if (!context) return;
    if (s_host_context == context) {
        if (s_animation_timer) {
            lv_timer_delete(s_animation_timer);
            s_animation_timer = NULL;
        }
        if (s_display) lv_display_delete(s_display);
        free(s_canvas_buffer); free(s_frame_overlay); free(s_sand_body_buffer);
        s_canvas_buffer = NULL; s_frame_overlay = NULL;
        s_sand_body_buffer = NULL; s_display = NULL;
        s_host_context = NULL;
    }
    free(context->framebuffer); free(context->draw_buffer); free(context);
}

void hourglass_liquid_update(void *opaque, uint32_t now_ms_value, float gravity_x, float gravity_y)
{
    HourglassLiquidHostContext *context = opaque;
    if (!context) return;
    s_host_context = context;
    lv_display_set_default(s_display);
    context->now_ms = now_ms_value;
    s_gravity_x = gravity_x; s_gravity_y = gravity_y;
    bool wants_inverted = gravity_y < -0.72f;
    bool wants_upright = gravity_y > 0.72f;
    if (!s_flipping && ((wants_inverted && !s_inverted) || (wants_upright && s_inverted))) {
        handle_event(wants_inverted ? EVENT_FLIP_INVERTED : EVENT_FLIP_UPRIGHT);
    }
    if (now_ms_value - context->last_animation_ms < ANIMATION_PERIOD_MS) return;
    context->last_animation_ms = now_ms_value;
    animation_timer_cb(NULL);
    lv_refr_now(s_display);
    ++context->frame_serial;
}

void hourglass_liquid_button(void *opaque, int32_t button, int32_t clicks)
{
    HourglassLiquidHostContext *context = opaque;
    if (!context) return;
    s_host_context = context; lv_display_set_default(s_display);
    if (button == 0) {
        if (clicks == 1) handle_event(EVENT_FRONT_SINGLE);
        else if (clicks == 2) handle_event(EVENT_FRONT_DOUBLE);
    } else {
        if (clicks == 1) handle_event(EVENT_SIDE_SINGLE);
        else if (clicks == 2) handle_event(EVENT_SIDE_DOUBLE);
        else if (clicks == 3) handle_event(EVENT_SIDE_TRIPLE);
        else if (clicks == 5) handle_event(EVENT_SIDE_LONG);
    }
    lv_refr_now(s_display); ++context->frame_serial;
}

HourglassLiquidSnapshot hourglass_liquid_snapshot(void *opaque)
{
    HourglassLiquidSnapshot result = {0};
    if (!opaque) return result;
    HourglassLiquidHostContext *context = opaque;
    result.duration_minutes = s_duration_minutes;
    result.remaining_ms = current_remaining_ms();
    result.running = s_running; result.custom_mode = s_custom_mode;
    result.inverted = s_inverted; result.flipping = s_flipping;
    result.particle_count = hg_physics_particle_count();
    result.chime_serial = context->chime_serial;
    return result;
}

const uint16_t *hourglass_liquid_framebuffer(void *opaque) {
    HourglassLiquidHostContext *context = opaque; return context ? context->framebuffer : NULL;
}
uint32_t hourglass_liquid_frame_serial(void *opaque) {
    HourglassLiquidHostContext *context = opaque; return context ? context->frame_serial : 0;
}

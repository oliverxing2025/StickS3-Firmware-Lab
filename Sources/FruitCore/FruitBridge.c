#include "FruitBridge.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    uint32_t now_ms;
    uint32_t rng;
    uint32_t frame_serial;
    uint32_t sound_serial;
    int32_t last_sound;
} FruitHostContext;

static FruitHostContext *s_host_context;

#define VIRTUAL_DEVICE_HOST 1
#ifndef FRUIT_FIRMWARE_MAIN
#define FRUIT_FIRMWARE_MAIN "../../Vendor/Firmware/fruit/src/main.c"
#endif
#include FRUIT_FIRMWARE_MAIN

int64_t fruit_host_now_ms(void)
{
    return s_host_context ? s_host_context->now_ms : 0;
}

uint32_t esp_random(void)
{
    if (!s_host_context) return 0x5eed1234u;
    s_host_context->rng = s_host_context->rng * 1664525u + 1013904223u;
    return s_host_context->rng;
}

esp_err_t fruit_audio_init(void) { return ESP_OK; }

esp_err_t fruit_audio_play(fruit_sound_t sound)
{
    if (s_host_context) {
        s_host_context->last_sound = (int32_t)sound;
        ++s_host_context->sound_serial;
    }
    return ESP_OK;
}

static void reset_firmware_state(void)
{
    s_stats = (saved_stats_t){
        .credit = FRUIT_STARTING_CREDIT,
        .high_credit = FRUIT_STARTING_CREDIT,
        .settings_flags = SETTING_SOUND_ENABLED,
        .big_bang_armed = 1,
        .gem_level = 1,
    };
    memset(s_bets, 0, sizeof(s_bets));
    memset(s_prepaid_bets, 0, sizeof(s_prepaid_bets));
    s_selected_control = CONTROL_GO;
    s_highlight = 0;
    s_state = STATE_IDLE;
    s_message = MSG_READY;
    s_pending_win = 0;
    s_last_award = 0;
    s_last_stake = 0;
    s_result_number = 0;
    s_gamble_amount = 0;
    s_gamble_level = FRUIT_GAMBLE_LEVEL_COUNT - 1;
    s_guess_big = false;
    s_spin_steps = 0;
    s_spin_total = 0;
    s_spin_target = 0;
    s_next_step_ms = 0;
    s_bonus_steps = 0;
    s_bonus_award = 0;
    s_bonus_step_award = 0;
    s_bonus_peak_multiplier = 0;
    s_round_settled = false;
    s_free_spins = 0;
    s_current_spin_free = false;
    s_lucky_loss_count = 0;
    s_lucky_spin_active = false;
    s_last_net = 0;
    s_auto_spin_ms = 0;
    s_big_bang_armed = true;
    s_flash_steps = 0;
    s_fire_phase = 0;
    s_led_phase = 0;
    s_gem_gallery = false;
    s_flash_red = false;
    s_stats_dirty = false;
    s_stats_flush_ms = 0;
    s_battery_level = 86;
    s_battery_charging = true;
    s_usb_powered = false;
}

void *fruit_create(void)
{
    FruitHostContext *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    context->rng = 0x5eed1234u;
    context->last_sound = -1;
    s_host_context = context;
    reset_firmware_state();
    s_canvas_buffer = calloc(SCREEN_W * SCREEN_H, sizeof(uint16_t));
    s_canvas = calloc(1, sizeof(*s_canvas));
    s_display = calloc(1, sizeof(*s_display));
    if (!s_canvas_buffer || !s_canvas || !s_display) {
        fruit_destroy(context);
        return NULL;
    }
    s_canvas->buffer = s_canvas_buffer;
    render();
    ++context->frame_serial;
    return context;
}

void fruit_destroy(void *opaque)
{
    FruitHostContext *context = opaque;
    if (!context) return;
    if (s_host_context == context) {
        free(s_canvas_buffer);
        free(s_canvas);
        free(s_display);
        s_canvas_buffer = NULL;
        s_canvas = NULL;
        s_display = NULL;
        s_host_context = NULL;
    }
    free(context);
}

static FruitHostContext *activate(void *opaque)
{
    FruitHostContext *context = opaque;
    if (context) s_host_context = context;
    return context;
}

void fruit_update(void *opaque, uint32_t now_ms)
{
    FruitHostContext *context = activate(opaque);
    if (!context) return;
    context->now_ms = now_ms;
    const bool frame_due =
        ((s_state == STATE_SPIN || s_state == STATE_BONUS_CHAIN || s_state == STATE_BIG_BANG)
         && now_ms >= (uint32_t)s_next_step_ms)
        || (s_state == STATE_IDLE && s_free_spins > 0 && s_auto_spin_ms > 0
            && now_ms >= (uint32_t)s_auto_spin_ms);
    update_game();
    if (frame_due) ++context->frame_serial;
}

void fruit_button(void *opaque, int32_t button, int32_t clicks)
{
    FruitHostContext *context = activate(opaque);
    if (!context) return;
    if (button == 0) {
        if (clicks == 1) handle_event(EVENT_ACTIVATE);
        else if (clicks == 2) handle_event(EVENT_GO);
        else if (clicks == 5) handle_event(EVENT_ACTIVATE_LONG);
    } else {
        if (clicks == 1) handle_event(EVENT_ADD_CREDIT);
        else if (clicks == 2) handle_event(EVENT_PREVIOUS);
        else if (clicks == 4) handle_event(EVENT_RESET_CREDIT);
        else if (clicks == 5) handle_event(EVENT_TOGGLE_GEMS);
    }
    ++context->frame_serial;
}

void fruit_motion(void *opaque, int32_t horizontal, int32_t vertical)
{
    FruitHostContext *context = activate(opaque);
    if (!context) return;
    if (horizontal < 0) handle_event(EVENT_MOTION_LEFT);
    else if (horizontal > 0) handle_event(EVENT_MOTION_RIGHT);
    if (vertical < 0) handle_event(EVENT_MOTION_UP);
    else if (vertical > 0) handle_event(EVENT_MOTION_DOWN);
    ++context->frame_serial;
}

void fruit_set_power(void *opaque, int32_t battery, bool charging, bool usb_powered)
{
    FruitHostContext *context = activate(opaque);
    if (!context) return;
    s_battery_level = battery;
    s_battery_charging = charging;
    s_usb_powered = usb_powered;
    render();
    ++context->frame_serial;
}

void fruit_set_sound(void *opaque, bool enabled)
{
    FruitHostContext *context = activate(opaque);
    if (!context) return;
    if (enabled) s_stats.settings_flags |= SETTING_SOUND_ENABLED;
    else s_stats.settings_flags &= ~SETTING_SOUND_ENABLED;
    render();
    ++context->frame_serial;
}

FruitSnapshot fruit_snapshot(void *opaque)
{
    FruitSnapshot result = {0};
    FruitHostContext *context = activate(opaque);
    if (!context) return result;
    result.credit = s_stats.credit;
    result.high_credit = s_stats.high_credit;
    result.pending_win = s_pending_win;
    result.state = s_state;
    result.selected_control = s_selected_control;
    result.total_rounds = s_stats.total_rounds;
    result.winning_rounds = s_stats.winning_rounds;
    result.sound_serial = context->sound_serial;
    result.last_sound = context->last_sound;
    result.battery = s_battery_level;
    result.battery_charging = s_battery_charging;
    result.usb_powered = s_usb_powered;
    return result;
}

const uint16_t *fruit_framebuffer(void *opaque)
{
    return activate(opaque) ? (const uint16_t *)s_canvas_buffer : NULL;
}

uint32_t fruit_frame_serial(void *opaque)
{
    FruitHostContext *context = activate(opaque);
    return context ? context->frame_serial : 0;
}

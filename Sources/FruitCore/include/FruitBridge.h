#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t credit;
    int32_t high_credit;
    int32_t pending_win;
    int32_t state;
    int32_t selected_control;
    uint32_t total_rounds;
    uint32_t winning_rounds;
    uint32_t sound_serial;
    int32_t last_sound;
    int32_t battery;
    bool battery_charging;
    bool usb_powered;
} FruitSnapshot;

void *fruit_create(void);
void fruit_destroy(void *context);
void fruit_update(void *context, uint32_t now_ms);
void fruit_button(void *context, int32_t button, int32_t clicks);
void fruit_motion(void *context, int32_t horizontal, int32_t vertical);
void fruit_set_power(void *context, int32_t battery, bool charging, bool usb_powered);
void fruit_set_sound(void *context, bool enabled);
FruitSnapshot fruit_snapshot(void *context);
const uint16_t *fruit_framebuffer(void *context);
uint32_t fruit_frame_serial(void *context);

#ifdef __cplusplus
}
#endif

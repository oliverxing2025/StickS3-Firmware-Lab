#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int32_t duration_minutes;
    int64_t remaining_ms;
    bool running;
    bool custom_mode;
    bool inverted;
    bool flipping;
    uint16_t particle_count;
    uint32_t chime_serial;
} HourglassLiquidSnapshot;

void *hourglass_liquid_create(void);
void hourglass_liquid_destroy(void *context);
void hourglass_liquid_update(void *context, uint32_t now_ms, float gravity_x, float gravity_y);
void hourglass_liquid_button(void *context, int32_t button, int32_t clicks);
HourglassLiquidSnapshot hourglass_liquid_snapshot(void *context);
const uint16_t *hourglass_liquid_framebuffer(void *context);
uint32_t hourglass_liquid_frame_serial(void *context);

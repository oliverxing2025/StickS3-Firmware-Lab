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
} HourglassSnapshot;

void *hourglass_create(void);
void hourglass_destroy(void *context);
void hourglass_update(void *context, uint32_t now_ms, float gravity_x, float gravity_y);
void hourglass_button(void *context, int32_t button, int32_t clicks);
HourglassSnapshot hourglass_snapshot(void *context);
const uint16_t *hourglass_framebuffer(void *context);
uint32_t hourglass_frame_serial(void *context);

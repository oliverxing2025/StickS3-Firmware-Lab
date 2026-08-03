#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void s3vd_bridge_begin(void);
void s3vd_send_frame_rgb565_be(const uint8_t* pixels, uint16_t width, uint16_t height);
bool s3vd_button_pressed(uint8_t button);
void s3vd_get_accel(float* x, float* y, float* z);

#ifdef __cplusplus
}
#endif

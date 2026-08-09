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
bool s3vd_audio_enabled(void);
void s3vd_send_audio_event(uint8_t sound);
int64_t s3vd_frame_interval_micros(void);

// ESP-IDF's standard esp_http_client API is redirected to the host only in the
// app's private QEMU build. The imported source tree is never modified.

#ifdef __cplusplus
}
#endif

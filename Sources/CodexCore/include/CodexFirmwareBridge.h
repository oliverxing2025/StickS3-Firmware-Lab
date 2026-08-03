#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int32_t running_tasks;
    int32_t waiting_tasks;
    int32_t finished_tasks;
    int32_t quota_5h;
    int32_t quota_7d;
    int32_t battery;
    int32_t today_used_percent;
    int64_t today_tokens;
    uint8_t status_person_frame;
    bool recording;
} CodexFirmwareSnapshot;

void *codex_firmware_create(void);
void codex_firmware_destroy(void *context);
void codex_firmware_update(void *context, uint32_t now_ms);
void codex_firmware_set_state(
    void *context, const char *status, const char *time, const char *date,
    const char *weekday, int32_t battery, bool charging, bool usb_powered,
    int32_t quota_5h, int32_t quota_5h_reset_minutes,
    int32_t quota_7d, int32_t quota_7d_reset_minutes,
    double month_cost, int64_t month_tokens,
    int32_t today_used_percent, int64_t today_tokens,
    int32_t running_tasks, int32_t waiting_tasks, int32_t finished_tasks,
    bool quota_5h_valid, bool quota_5h_reset_valid,
    bool quota_7d_valid, bool quota_7d_reset_valid,
    bool month_cost_valid, bool month_tokens_valid,
    bool today_used_percent_valid, bool today_tokens_valid);
void codex_firmware_set_recording(void *context, bool recording);
void codex_firmware_set_orientation(void *context, bool landscape, bool landscape_reverse);
CodexFirmwareSnapshot codex_firmware_snapshot(void *context);
const uint16_t *codex_firmware_framebuffer(void *context);
uint32_t codex_firmware_frame_serial(void *context);
int32_t codex_firmware_frame_width(void *context);
int32_t codex_firmware_frame_height(void *context);

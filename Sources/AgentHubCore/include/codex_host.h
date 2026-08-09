#pragma once
#include <stdint.h>
#include "lvgl.h"
typedef void *QueueHandle_t;
typedef void *SemaphoreHandle_t;
typedef void *esp_lcd_panel_handle_t;
#define ESP_LOGI(tag, format, ...) ((void)0)
#define ESP_LOGW(tag, format, ...) ((void)0)
#define ESP_LOGE(tag, format, ...) ((void)0)
int64_t codex_host_time_us(void);
static inline int64_t esp_timer_get_time(void) { return codex_host_time_us(); }

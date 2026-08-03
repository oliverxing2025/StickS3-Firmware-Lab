#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "lvgl.h"

typedef int esp_err_t;
typedef void *QueueHandle_t;
typedef void *SemaphoreHandle_t;
typedef void *esp_lcd_panel_handle_t;

#define ESP_OK 0
#define ESP_FAIL (-1)
#define ESP_ERR_INVALID_ARG (-2)
#define MALLOC_CAP_8BIT 1

#define ESP_LOGI(tag, format, ...) ((void)0)
#define ESP_LOGW(tag, format, ...) ((void)0)
#define ESP_LOGE(tag, format, ...) ((void)0)

static inline size_t heap_caps_get_free_size(int caps) {
    (void)caps;
    return 1024 * 1024;
}

int64_t fruit_host_now_ms(void);
uint32_t esp_random(void);

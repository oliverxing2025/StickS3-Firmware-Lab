#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "lvgl.h"
typedef int esp_err_t;
typedef void *QueueHandle_t;
typedef void *SemaphoreHandle_t;
typedef void *esp_lcd_panel_handle_t;
#define ESP_OK 0
#define ESP_ERR_NO_MEM (-1)
#define MALLOC_CAP_SPIRAM 1
#define MALLOC_CAP_8BIT 2
#define ESP_LOGI(tag, format, ...) ((void)0)
#define ESP_LOGW(tag, format, ...) ((void)0)
#define ESP_LOGE(tag, format, ...) ((void)0)
#define ESP_ERROR_CHECK(value) do { if ((value) != ESP_OK) abort(); } while (0)
#define ESP_ERROR_CHECK_WITHOUT_ABORT(value) ((void)(value))
static inline void *heap_caps_calloc(size_t count, size_t size, int caps) {
    (void)caps; return calloc(count, size);
}
static inline void *heap_caps_malloc(size_t size, int caps) {
    (void)caps; return malloc(size);
}
static inline esp_err_t esp_lcd_panel_mirror(
    esp_lcd_panel_handle_t panel, bool mirror_x, bool mirror_y) {
    (void)panel; (void)mirror_x; (void)mirror_y; return ESP_OK;
}
static inline const char *esp_err_to_name(esp_err_t error) {
    (void)error; return "HOST";
}
int64_t hourglass_host_now_ms(void);

#include <stdbool.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef VIRTUAL_DEVICE_HOST
#include "hourglass_host.h"
#else
#include "button_gpio.h"
#include "driver/ledc.h"
#include "driver/spi_master.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_st7789.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "iot_button.h"
#endif
#include "lvgl.h"
#include "hourglass_physics.h"
#ifndef VIRTUAL_DEVICE_HOST
#include "vibe_board.h"
#endif

#define LCD_HOST SPI2_HOST
#define LCD_H_RES 135
#define LCD_V_RES 240
#define LCD_X_GAP 52
#define LCD_Y_GAP 40
#define LCD_PIXEL_CLOCK_HZ (20 * 1000 * 1000)
#define LCD_BACKLIGHT_PWM_HZ 5000
#define LCD_BACKLIGHT_DEFAULT 150
#define LVGL_DRAW_BUF_LINES 24
#define LVGL_TICK_PERIOD_MS 10

#define PIN_BUTTON_FRONT 11
#define PIN_BUTTON_SIDE 12
#define PIN_LCD_MOSI 39
#define PIN_LCD_SCK 40
#define PIN_LCD_DC 45
#define PIN_LCD_CS 41
#define PIN_LCD_RST 21
#define PIN_LCD_BL 38

#define SAND_LOGICAL_W 115
#define SAND_LOGICAL_H 118
#define SAND_CANVAS_W 111
#define SAND_CANVAS_H 168
#define ANIMATION_PERIOD_MS 33
#define CUSTOM_MAX_MINUTES 60
#define FLIP_DURATION_MS 700
#define STICKS3_PORTRAIT_SIGN (-1)
#define PERFORMANCE_MIN_FPS 22.0f
#define PERFORMANCE_WINDOW_MS 3000
#define FRAME_OVERLAY_CAPACITY 4096

static const char *TAG = "hourglass";
static const int s_presets[] = {1, 5, 10, 15, 25};

typedef enum {
    EVENT_FRONT_SINGLE,
    EVENT_FRONT_DOUBLE,
    EVENT_SIDE_SINGLE,
    EVENT_SIDE_DOUBLE,
    EVENT_SIDE_LONG,
    EVENT_SIDE_TRIPLE,
    EVENT_FLIP_UPRIGHT,
    EVENT_FLIP_INVERTED,
} app_event_t;

static QueueHandle_t s_event_queue;
static SemaphoreHandle_t s_lvgl_lock;
static lv_display_t *s_display;
static esp_lcd_panel_handle_t s_panel;
static lv_obj_t *s_title_label;
static lv_obj_t *s_progress_label;
static lv_obj_t *s_timer_label;
static lv_obj_t *s_preset_labels[5];
static lv_obj_t *s_canvas;
static lv_obj_t *s_divider;
static uint8_t *s_canvas_buffer;
static uint32_t *s_frame_overlay;
static uint16_t s_frame_overlay_count;
static uint8_t s_canvas_x0[SAND_LOGICAL_W];
static uint8_t s_canvas_x1[SAND_LOGICAL_W];
static uint8_t s_canvas_y0[SAND_LOGICAL_H];
static uint8_t s_canvas_y1[SAND_LOGICAL_H];

static int s_preset_index = 1;
static int s_duration_minutes = 5;
static int s_custom_backup_minutes = 5;
static int64_t s_duration_ms = 5 * 60 * 1000;
static int64_t s_remaining_ms = 5 * 60 * 1000;
static int64_t s_deadline_ms;
static bool s_running;
static bool s_custom_mode;
static bool s_inverted;
static bool s_flipping;
static bool s_pending_inverted;
static bool s_side_long_active;
static int s_last_display_second = -1;
static int s_last_display_percent = -1;
static int64_t s_last_frame_ms;
static int64_t s_flip_start_ms;
static int s_flip_from_angle;
static int s_flip_to_angle;
static int s_render_angle;
static float s_render_cos = 1.0f;
static float s_render_sin;
static float s_physics_accumulator;
static lv_timer_t *s_animation_timer;
static int64_t s_perf_window_start_ms;
static uint16_t s_perf_frame_count;
static uint8_t s_low_fps_windows;
static uint8_t s_performance_level;
static bool s_particle_glow_enabled = true;
static bool s_force_canvas_redraw = true;
static bool s_finish_settled_logged;
static volatile uint16_t s_imu_period_ms = 50;
static volatile float s_gravity_x;
static volatile float s_gravity_y = 1.0f;

static void set_duration_minutes(int minutes);
static void toggle_running(void);
static void layout_ui_for_orientation(bool inverted);

static int64_t now_ms(void)
{
#ifdef VIRTUAL_DEVICE_HOST
    return hourglass_host_now_ms();
#else
    return esp_timer_get_time() / 1000;
#endif
}

static void switch_to_other_app(void)
{
#ifdef VIRTUAL_DEVICE_HOST
    return;
#else
    const esp_partition_t *running = esp_ota_get_running_partition();
    const esp_partition_t *next = esp_ota_get_next_update_partition(NULL);
    if (!running || !next || next == running) {
        ESP_LOGE(TAG, "app switch target unavailable");
        return;
    }
    esp_err_t err = esp_ota_set_boot_partition(next);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "app switch failed: %s", esp_err_to_name(err));
        return;
    }
    ESP_LOGI(TAG, "switch app %s -> %s", running->label, next->label);
    vTaskDelay(pdMS_TO_TICKS(120));
    esp_restart();
#endif
}

static bool lvgl_lock(void)
{
#ifdef VIRTUAL_DEVICE_HOST
    return true;
#else
    return s_lvgl_lock && xSemaphoreTake(s_lvgl_lock, pdMS_TO_TICKS(250)) == pdTRUE;
#endif
}

static void lvgl_unlock(void)
{
#ifndef VIRTUAL_DEVICE_HOST
    if (s_lvgl_lock) {
        xSemaphoreGive(s_lvgl_lock);
    }
#endif
}

#ifndef VIRTUAL_DEVICE_HOST
static void lvgl_tick_cb(void *arg)
{
    (void)arg;
    lv_tick_inc(LVGL_TICK_PERIOD_MS);
}

static void lvgl_task(void *arg)
{
    (void)arg;
    while (true) {
        if (lvgl_lock()) {
            uint32_t wait_ms = lv_timer_handler();
            lvgl_unlock();
            if (wait_ms < 5) {
                wait_ms = 5;
            } else if (wait_ms > 100) {
                wait_ms = 100;
            }
            vTaskDelay(pdMS_TO_TICKS(wait_ms));
        } else {
            vTaskDelay(pdMS_TO_TICKS(5));
        }
    }
}

static bool notify_lvgl_flush_ready(esp_lcd_panel_io_handle_t panel_io,
                                    esp_lcd_panel_io_event_data_t *edata,
                                    void *user_ctx)
{
    (void)panel_io;
    (void)edata;
    lv_display_flush_ready((lv_display_t *)user_ctx);
    return false;
}

static void lvgl_flush_cb(lv_display_t *display, const lv_area_t *area, uint8_t *px_map)
{
    esp_lcd_panel_handle_t panel = lv_display_get_user_data(display);
    int32_t width = area->x2 - area->x1 + 1;
    int32_t height = area->y2 - area->y1 + 1;
    lv_draw_sw_rgb565_swap(px_map, width * height);
    esp_lcd_panel_draw_bitmap(panel, area->x1, area->y1, area->x2 + 1, area->y2 + 1, px_map);
}

static void set_backlight(uint8_t brightness)
{
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, brightness);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0);
}

static void init_backlight(void)
{
    const ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .timer_num = LEDC_TIMER_0,
        .duty_resolution = LEDC_TIMER_8_BIT,
        .freq_hz = LCD_BACKLIGHT_PWM_HZ,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));
    const ledc_channel_config_t channel = {
        .gpio_num = PIN_LCD_BL,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LEDC_CHANNEL_0,
        .timer_sel = LEDC_TIMER_0,
        .duty = 0,
        .hpoint = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&channel));
    set_backlight(LCD_BACKLIGHT_DEFAULT);
}

static esp_err_t init_display(void)
{
    init_backlight();
    const spi_bus_config_t bus_config = {
        .sclk_io_num = PIN_LCD_SCK,
        .mosi_io_num = PIN_LCD_MOSI,
        .miso_io_num = -1,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = LCD_H_RES * LVGL_DRAW_BUF_LINES * sizeof(lv_color_t),
    };
    ESP_RETURN_ON_ERROR(spi_bus_initialize(LCD_HOST, &bus_config, SPI_DMA_CH_AUTO), TAG, "spi bus");

    esp_lcd_panel_io_handle_t io_handle = NULL;
    const esp_lcd_panel_io_spi_config_t io_config = {
        .dc_gpio_num = PIN_LCD_DC,
        .cs_gpio_num = PIN_LCD_CS,
        .pclk_hz = LCD_PIXEL_CLOCK_HZ,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
        .spi_mode = 0,
        .trans_queue_depth = 10,
    };
    ESP_RETURN_ON_ERROR(
        esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST, &io_config, &io_handle),
        TAG, "panel io");

    const esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = PIN_LCD_RST,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = 16,
    };
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_st7789(io_handle, &panel_config, &s_panel), TAG, "panel");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_reset(s_panel), TAG, "panel reset");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_init(s_panel), TAG, "panel init");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_invert_color(s_panel, true), TAG, "panel invert");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_mirror(s_panel, false, false), TAG, "panel mirror");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_set_gap(s_panel, LCD_X_GAP, LCD_Y_GAP), TAG, "panel gap");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_disp_on_off(s_panel, true), TAG, "panel on");

    lv_init();
    s_display = lv_display_create(LCD_H_RES, LCD_V_RES);
    lv_display_set_user_data(s_display, s_panel);
    lv_display_set_flush_cb(s_display, lvgl_flush_cb);

    const size_t buffer_size = LCD_H_RES * LVGL_DRAW_BUF_LINES * sizeof(lv_color_t);
    void *draw_buffer = heap_caps_malloc(buffer_size, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    ESP_RETURN_ON_FALSE(draw_buffer != NULL, ESP_ERR_NO_MEM, TAG, "lvgl draw buffer");
    lv_display_set_buffers(s_display, draw_buffer, NULL, buffer_size, LV_DISPLAY_RENDER_MODE_PARTIAL);

    const esp_lcd_panel_io_callbacks_t callbacks = {
        .on_color_trans_done = notify_lvgl_flush_ready,
    };
    ESP_RETURN_ON_ERROR(
        esp_lcd_panel_io_register_event_callbacks(io_handle, &callbacks, s_display),
        TAG, "panel callback");

    const esp_timer_create_args_t tick_args = {
        .callback = lvgl_tick_cb,
        .name = "lvgl_tick",
    };
    esp_timer_handle_t tick_timer = NULL;
    ESP_RETURN_ON_ERROR(esp_timer_create(&tick_args, &tick_timer), TAG, "tick timer");
    ESP_RETURN_ON_ERROR(
        esp_timer_start_periodic(tick_timer, LVGL_TICK_PERIOD_MS * 1000),
        TAG, "tick start");
    xTaskCreate(lvgl_task, "lvgl", 4096, NULL, 3, NULL);
    return ESP_OK;
}
#endif

static void init_canvas_coordinate_map(void)
{
    for (int x = 0; x < SAND_LOGICAL_W; ++x) {
        int draw_x0 = x * SAND_CANVAS_W / SAND_LOGICAL_W;
        int draw_x1 =
            ((x + 1) * SAND_CANVAS_W / SAND_LOGICAL_W) - 1;
        s_canvas_x0[x] = (uint8_t)draw_x0;
        s_canvas_x1[x] = (uint8_t)(draw_x1 < draw_x0 ? draw_x0 : draw_x1);
    }
    for (int y = 0; y < SAND_LOGICAL_H; ++y) {
        int draw_y0 = y * SAND_CANVAS_H / SAND_LOGICAL_H;
        int draw_y1 =
            ((y + 1) * SAND_CANVAS_H / SAND_LOGICAL_H) - 1;
        s_canvas_y0[y] = (uint8_t)draw_y0;
        s_canvas_y1[y] = (uint8_t)(draw_y1 < draw_y0 ? draw_y0 : draw_y1);
    }
}

static void canvas_pixel(int x, int y, lv_color_t color)
{
    int logical_x = x;
    int logical_y = y;
    if (s_render_angle == 1800) {
        logical_x = SAND_LOGICAL_W - 1 - x;
        logical_y = SAND_LOGICAL_H - 1 - y;
    } else if (s_render_angle != 0) {
        float relative_x =
            (float)x - (float)(SAND_LOGICAL_W - 1) * 0.5f;
        float relative_y =
            (float)y - (float)(SAND_LOGICAL_H - 1) * 0.5f;
        logical_x = (int)(relative_x * s_render_cos -
                          relative_y * s_render_sin +
                          (float)(SAND_LOGICAL_W - 1) * 0.5f + 0.5f);
        logical_y = (int)(relative_x * s_render_sin +
                          relative_y * s_render_cos +
                          (float)(SAND_LOGICAL_H - 1) * 0.5f + 0.5f);
    }
    if (logical_x < 0 || logical_x >= SAND_LOGICAL_W ||
        logical_y < 0 || logical_y >= SAND_LOGICAL_H) {
        return;
    }
    int draw_x0 = s_canvas_x0[logical_x];
    int draw_x1 = s_canvas_x1[logical_x];
    int draw_y0 = s_canvas_y0[logical_y];
    int draw_y1 = s_canvas_y1[logical_y];
    uint16_t *pixels = (uint16_t *)s_canvas_buffer;
    uint16_t pixel = lv_color_to_u16(color);
    for (int draw_y = draw_y0; draw_y <= draw_y1; ++draw_y) {
        for (int draw_x = draw_x0; draw_x <= draw_x1; ++draw_x) {
            pixels[draw_y * SAND_CANVAS_W + draw_x] = pixel;
        }
    }
}

static void clear_hourglass_canvas(void)
{
    uint16_t background = lv_color_to_u16(lv_color_hex(0x050b0b));
    uint16_t *pixels = (uint16_t *)s_canvas_buffer;
    size_t pixel_count = SAND_CANVAS_W * SAND_CANVAS_H;
    for (size_t i = 0; i < pixel_count; ++i) {
        pixels[i] = background;
    }
}

static void set_render_angle(int angle)
{
    s_render_angle = angle;
    if (angle == 0) {
        s_render_cos = 1.0f;
        s_render_sin = 0.0f;
    } else if (angle == 1800) {
        s_render_cos = -1.0f;
        s_render_sin = 0.0f;
    } else {
        float radians = (float)angle * (float)M_PI / 1800.0f;
        s_render_cos = cosf(radians);
        s_render_sin = sinf(radians);
    }
}

static void canvas_line(int x0, int y0, int x1, int y1,
                        lv_color_t color, lv_color_t glow)
{
    int dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int sx = x0 < x1 ? 1 : -1;
    int dy = y1 > y0 ? y0 - y1 : y1 - y0;
    int sy = y0 < y1 ? 1 : -1;
    int error = dx + dy;
    bool horizontal_dominant = dx >= -dy;
    while (true) {
        if (horizontal_dominant) {
            canvas_pixel(x0, y0 - 1, glow);
            canvas_pixel(x0, y0 + 1, glow);
        } else {
            canvas_pixel(x0 - 1, y0, glow);
            canvas_pixel(x0 + 1, y0, glow);
        }
        canvas_pixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) {
            break;
        }
        int twice = 2 * error;
        if (twice >= dy) {
            error += dy;
            x0 += sx;
        }
        if (twice <= dx) {
            error += dx;
            y0 += sy;
        }
    }
}

static void canvas_quadratic(float x0, float y0, float cx, float cy,
                             float x1, float y1,
                             lv_color_t color, lv_color_t glow)
{
    int previous_x = (int)x0;
    int previous_y = (int)y0;
    for (int step = 1; step <= 24; ++step) {
        float t = (float)step / 24.0f;
        float one_minus_t = 1.0f - t;
        int x = (int)(one_minus_t * one_minus_t * x0 +
                      2.0f * one_minus_t * t * cx + t * t * x1 + 0.5f);
        int y = (int)(one_minus_t * one_minus_t * y0 +
                      2.0f * one_minus_t * t * cy + t * t * y1 + 0.5f);
        canvas_line(previous_x, previous_y, x, y, color, glow);
        previous_x = x;
        previous_y = y;
    }
}

static void canvas_line_core(int x0, int y0, int x1, int y1, lv_color_t color)
{
    int dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int sx = x0 < x1 ? 1 : -1;
    int dy = y1 > y0 ? y0 - y1 : y1 - y0;
    int sy = y0 < y1 ? 1 : -1;
    int error = dx + dy;
    while (true) {
        canvas_pixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) {
            break;
        }
        int twice = 2 * error;
        if (twice >= dy) {
            error += dy;
            x0 += sx;
        }
        if (twice <= dx) {
            error += dx;
            y0 += sy;
        }
    }
}

static void canvas_quadratic_core(float x0, float y0, float cx, float cy,
                                  float x1, float y1, lv_color_t color)
{
    int previous_x = (int)(x0 + 0.5f);
    int previous_y = (int)(y0 + 0.5f);
    for (int step = 1; step <= 24; ++step) {
        float t = (float)step / 24.0f;
        float one_minus_t = 1.0f - t;
        int x = (int)(one_minus_t * one_minus_t * x0 +
                      2.0f * one_minus_t * t * cx + t * t * x1 + 0.5f);
        int y = (int)(one_minus_t * one_minus_t * y0 +
                      2.0f * one_minus_t * t * cy + t * t * y1 + 0.5f);
        canvas_line_core(previous_x, previous_y, x, y, color);
        previous_x = x;
        previous_y = y;
    }
}

static void draw_rounded_support(int top)
{
    const lv_color_t frame = lv_color_hex(0xdce5e8);
    const lv_color_t glow = lv_color_hex(0x29363a);
    const lv_color_t inside = lv_color_hex(0x0d1416);
    int bottom = top + 4;
    for (int y = top; y <= bottom; ++y) {
        for (int x = 12; x <= 102; ++x) {
            bool rounded_corner =
                ((x == 12 || x == 102) && (y == top || y == bottom));
            if (rounded_corner) {
                continue;
            }
            bool edge = y == top || y == bottom || x == 12 || x == 102;
            canvas_pixel(x, y, edge ? frame : inside);
        }
    }
    for (int x = 14; x <= 100; ++x) {
        canvas_pixel(x, top - 1, glow);
        canvas_pixel(x, bottom + 1, glow);
    }
}

static void draw_hourglass_frame(void)
{
    const lv_color_t frame = lv_color_hex(0xdce5e8);
    const lv_color_t glow = lv_color_hex(0x29363a);
    const lv_color_t neck_frame = lv_color_hex(0xf5fbff);
    const lv_color_t neck_glow = lv_color_hex(0x52666d);
    draw_rounded_support(2);
    draw_rounded_support(110);

    canvas_line(19, 9, 19, 27, frame, glow);
    canvas_quadratic(19, 27, 19, 36, 51, 53, frame, glow);
    canvas_quadratic(
        51, 53, 52.5f, 55, 53.5f, 58, neck_frame, neck_glow);
    canvas_line(95, 9, 95, 27, frame, glow);
    canvas_quadratic(95, 27, 95, 36, 63, 53, frame, glow);
    canvas_quadratic(
        63, 53, 61.5f, 55, 60.5f, 58, neck_frame, neck_glow);

    canvas_quadratic(
        53.5f, 58, 52.5f, 61, 51, 63, neck_frame, neck_glow);
    canvas_quadratic(51, 63, 19, 80, 19, 89, frame, glow);
    canvas_line(19, 89, 19, 109, frame, glow);
    canvas_quadratic(
        60.5f, 58, 61.5f, 61, 63, 63, neck_frame, neck_glow);
    canvas_quadratic(63, 63, 95, 80, 95, 89, frame, glow);
    canvas_line(95, 89, 95, 109, frame, glow);

    /*
     * Use the same two-pixel pure-white core across every glass wall. The
     * second pixel is always on the outside edge, so the visible stroke is
     * uniform without narrowing the inner collision volume.
     */
    const lv_color_t wall_highlight = lv_color_hex(0xffffff);
    canvas_line_core(19, 9, 19, 27, wall_highlight);
    canvas_line_core(18, 9, 18, 27, wall_highlight);
    canvas_quadratic_core(
        19, 27, 19, 36, 51, 53, wall_highlight);
    canvas_quadratic_core(
        18, 27, 18, 36, 50, 53, wall_highlight);
    canvas_quadratic_core(
        51, 53, 52.5f, 55, 53.5f, 58, wall_highlight);
    canvas_quadratic_core(
        50, 53, 51.5f, 55, 52.5f, 58, wall_highlight);
    canvas_quadratic_core(
        53.5f, 58, 52.5f, 61, 51, 63, wall_highlight);
    canvas_quadratic_core(
        52.5f, 58, 51.5f, 61, 50, 63, wall_highlight);
    canvas_quadratic_core(
        51, 63, 19, 80, 19, 89, wall_highlight);
    canvas_quadratic_core(
        50, 63, 18, 80, 18, 89, wall_highlight);
    canvas_line_core(19, 89, 19, 109, wall_highlight);
    canvas_line_core(18, 89, 18, 109, wall_highlight);

    canvas_line_core(95, 9, 95, 27, wall_highlight);
    canvas_line_core(96, 9, 96, 27, wall_highlight);
    canvas_quadratic_core(
        95, 27, 95, 36, 63, 53, wall_highlight);
    canvas_quadratic_core(
        96, 27, 96, 36, 64, 53, wall_highlight);
    canvas_quadratic_core(
        63, 53, 61.5f, 55, 60.5f, 58, wall_highlight);
    canvas_quadratic_core(
        64, 53, 62.5f, 55, 61.5f, 58, wall_highlight);
    canvas_quadratic_core(
        60.5f, 58, 61.5f, 61, 63, 63, wall_highlight);
    canvas_quadratic_core(
        61.5f, 58, 62.5f, 61, 64, 63, wall_highlight);
    canvas_quadratic_core(
        63, 63, 95, 80, 95, 89, wall_highlight);
    canvas_quadratic_core(
        64, 63, 96, 80, 96, 89, wall_highlight);
    canvas_line_core(95, 89, 95, 109, wall_highlight);
    canvas_line_core(96, 89, 96, 109, wall_highlight);
}

static void build_frame_overlay(void)
{
    uint16_t background = lv_color_to_u16(lv_color_hex(0x050b0b));
    uint16_t *pixels = (uint16_t *)s_canvas_buffer;
    size_t pixel_count = SAND_CANVAS_W * SAND_CANVAS_H;
    clear_hourglass_canvas();
    draw_hourglass_frame();
    s_frame_overlay_count = 0;
    for (size_t i = 0; i < pixel_count; ++i) {
        if (pixels[i] == background) {
            continue;
        }
        if (s_frame_overlay_count >= FRAME_OVERLAY_CAPACITY) {
            ESP_LOGW(TAG, "frame overlay cache overflow; using live frame");
            s_frame_overlay_count = 0;
            break;
        }
        s_frame_overlay[s_frame_overlay_count++] =
            ((uint32_t)pixels[i] << 16) | (uint32_t)i;
    }
    clear_hourglass_canvas();
    ESP_LOGI(TAG, "frame overlay cached pixels=%u", s_frame_overlay_count);
}

static void apply_frame_overlay(void)
{
    uint16_t *pixels = (uint16_t *)s_canvas_buffer;
    for (uint16_t i = 0; i < s_frame_overlay_count; ++i) {
        uint32_t packed = s_frame_overlay[i];
        pixels[packed & 0xffffu] = (uint16_t)(packed >> 16);
    }
}

static float logical_gravity_x(void)
{
    return s_inverted ? -s_gravity_x : s_gravity_x;
}

static void draw_particle_sprite(int center_x, int center_y, uint8_t size,
                                 lv_color_t core, lv_color_t highlight,
                                 lv_color_t glow)
{
    static const int8_t glow_offsets[4][2] = {
        {-2, 0}, {2, 0}, {0, -2}, {0, 2},
    };
    int origin_x = center_x - (int)size / 2;
    int origin_y = center_y - (int)size / 2;
    if (s_particle_glow_enabled) {
        for (size_t i = 0; i < 4; ++i) {
            canvas_pixel(
                center_x + glow_offsets[i][0],
                center_y + glow_offsets[i][1], glow);
        }
    }
    for (uint8_t y = 0; y < size; ++y) {
        for (uint8_t x = 0; x < size; ++x) {
            canvas_pixel(origin_x + x, origin_y + y, core);
        }
    }
    canvas_pixel(origin_x, origin_y, highlight);
}

static void draw_physics_particles(float interpolation)
{
    const lv_color_t core_palette[5] = {
        lv_color_hex(0xaaff1d),
        lv_color_hex(0x91f34a),
        lv_color_hex(0x61e887),
        lv_color_hex(0x35dfbd),
        lv_color_hex(0x12d8ff),
    };
    const lv_color_t highlight_palette[5] = {
        lv_color_hex(0xe1ff70),
        lv_color_hex(0xc9ff7c),
        lv_color_hex(0xa6fca6),
        lv_color_hex(0x92f8d7),
        lv_color_hex(0x8df2ff),
    };
    const lv_color_t glow_palette[5] = {
        lv_color_hex(0x294709),
        lv_color_hex(0x244a1a),
        lv_color_hex(0x174638),
        lv_color_hex(0x0c4050),
        lv_color_hex(0x06384a),
    };
    const hg_particle_t *particles = hg_physics_particles();
    uint16_t count = hg_physics_particle_count();
    for (uint16_t i = 0; i < count; ++i) {
        const hg_particle_t *particle = &particles[i];
        bool active =
            particle->state == HG_PARTICLE_UPPER_ACTIVE ||
            particle->state == HG_PARTICLE_FALLING ||
            particle->state == HG_PARTICLE_LOWER_ACTIVE;
        float render_x = particle->x;
        float render_y = particle->y;
        if (active) {
            render_x += particle->vx * HG_PHYSICS_DT * interpolation;
            render_y += particle->vy * HG_PHYSICS_DT * interpolation;
            int boundary_y = (int)(render_y + 0.5f);
            if (boundary_y < 0) {
                boundary_y = 0;
            } else if (boundary_y >= SAND_LOGICAL_H) {
                boundary_y = SAND_LOGICAL_H - 1;
            }
            float margin = (float)particle->size * 0.5f + 0.5f;
            float left = hg_geometry_left_boundary(boundary_y) + margin;
            float right = hg_geometry_right_boundary(boundary_y) - margin;
            if (render_x < left) {
                render_x = left;
            } else if (render_x > right) {
                render_x = right;
            }
        }
        uint8_t phase = particle->color_phase;
        if (particle->state == HG_PARTICLE_UPPER_SLEEPING) {
            phase = 0;
        } else if (particle->state == HG_PARTICLE_UPPER_ACTIVE) {
            float motion =
                fabsf(particle->vx) + fabsf(particle->vy);
            phase = motion > 1.2f ? 1u : 0u;
        } else if (particle->state == HG_PARTICLE_LOWER_ACTIVE ||
                   particle->state == HG_PARTICLE_LOWER_SLEEPING) {
            phase = 4;
        }
        if (phase > 4) {
            phase = 4;
        }
        if (particle->state == HG_PARTICLE_FALLING) {
            /*
             * Two short motion samples make the real falling grain readable
             * on the small display.  They are only afterimages of this grain:
             * pile counts and progress still come exclusively from the
             * 300-object physics pool.
             */
            float speed = sqrtf(
                particle->vx * particle->vx +
                particle->vy * particle->vy);
            if (speed > 1.0f) {
                float direction_x = particle->vx / speed;
                float direction_y = particle->vy / speed;
                canvas_pixel(
                    (int)(render_x - direction_x * 4.0f + 0.5f),
                    (int)(render_y - direction_y * 4.0f + 0.5f),
                    glow_palette[phase]);
                draw_particle_sprite(
                    (int)(render_x - direction_x * 2.2f + 0.5f),
                    (int)(render_y - direction_y * 2.2f + 0.5f),
                    1u, core_palette[phase], highlight_palette[phase],
                    glow_palette[phase]);
            }
        }
        draw_particle_sprite(
            (int)(render_x + 0.5f), (int)(render_y + 0.5f),
            particle->size, core_palette[phase],
            highlight_palette[phase], glow_palette[phase]);
    }
}

static int64_t current_remaining_ms(void)
{
    if (!s_running) {
        return s_remaining_ms;
    }
    int64_t remaining = s_deadline_ms - now_ms();
    return remaining > 0 ? remaining : 0;
}

static void update_timer_text(int64_t remaining_ms)
{
    int total_seconds = (int)((remaining_ms + 999) / 1000);
    if (total_seconds == s_last_display_second) {
        return;
    }
    s_last_display_second = total_seconds;
    int minutes = total_seconds / 60;
    int seconds = total_seconds % 60;
    char text[16];
    snprintf(text, sizeof(text), "%02d:%02d", minutes, seconds);
    lv_label_set_text(s_timer_label, text);
}

static void update_progress_text(float progress)
{
    int elapsed_percent = (int)(progress * 100.0f + 0.5f);
    if (elapsed_percent < 0) {
        elapsed_percent = 0;
    } else if (elapsed_percent > 100) {
        elapsed_percent = 100;
    }
    if (elapsed_percent == s_last_display_percent) {
        return;
    }
    s_last_display_percent = elapsed_percent;
    char text[8];
    snprintf(text, sizeof(text), "%d%%", elapsed_percent);
    lv_label_set_text(s_progress_label, text);
    layout_ui_for_orientation(s_inverted);
}

static void render_presets(void)
{
    for (size_t i = 0; i < sizeof(s_presets) / sizeof(s_presets[0]); ++i) {
        bool selected = !s_custom_mode && s_duration_minutes == s_presets[i];
        lv_obj_set_style_text_color(
            s_preset_labels[i],
            selected ? lv_color_hex(0xcaff45) : lv_color_hex(0x63ddc1), 0);
        lv_obj_set_style_bg_opa(s_preset_labels[i], selected ? LV_OPA_30 : LV_OPA_TRANSP, 0);
        lv_obj_set_style_bg_color(s_preset_labels[i], lv_color_hex(0x8ed829), 0);
        lv_obj_set_style_radius(s_preset_labels[i], 4, 0);
    }
}

static void apply_performance_level(uint8_t level)
{
    switch (level) {
    case 1:
        hg_physics_set_limits(80, 2);
        break;
    case 2:
        hg_physics_set_limits(60, 2);
        break;
    case 3:
        s_imu_period_ms = 100;
        break;
    case 4:
        s_particle_glow_enabled = false;
        break;
    case 5:
        if (s_animation_timer) {
            lv_timer_set_period(s_animation_timer, 40);
        }
        break;
    case 6:
        hg_physics_request_particle_count(220);
        break;
    default:
        return;
    }
    ESP_LOGW(TAG, "performance fallback level=%u", level);
}

static void update_performance_monitor(int64_t frame_now_ms)
{
    if (!s_running || s_flipping) {
        s_perf_window_start_ms = frame_now_ms;
        s_perf_frame_count = 0;
        return;
    }
    if (s_perf_window_start_ms == 0) {
        s_perf_window_start_ms = frame_now_ms;
    }
    ++s_perf_frame_count;
    int64_t elapsed_ms = frame_now_ms - s_perf_window_start_ms;
    if (elapsed_ms < PERFORMANCE_WINDOW_MS) {
        return;
    }
    float fps = (float)s_perf_frame_count * 1000.0f / (float)elapsed_ms;
    hg_physics_stats_t stats = hg_physics_stats();
    ESP_LOGI(
        TAG,
        "render fps=%.1f physics=%uHz particles=%u upper=%u lower=%u "
        "active=%u throat=%u/%u stall=%ums detect=%u unblock=%u "
        "void=%u continuity=%u bridge=%u surface=%u/%u "
        "width=%.2f fallback=%u",
        fps, HG_PHYSICS_HZ, stats.total, stats.upper, stats.lower,
        stats.active, stats.throat_active, stats.throat_particles,
        stats.flow_stall_ms, stats.stall_detect_count,
        stats.unblock_count, stats.detected_void_count,
        stats.upper_continuity_fault_count, stats.bridge_break_count,
        stats.upper_surface_active, stats.upper_subsurface_active,
        stats.effective_throat_width, s_performance_level);
    if (fps < PERFORMANCE_MIN_FPS) {
        if (++s_low_fps_windows >= 2 && s_performance_level < 6) {
            s_low_fps_windows = 0;
            ++s_performance_level;
            apply_performance_level(s_performance_level);
        }
    } else {
        s_low_fps_windows = 0;
    }
    s_perf_window_start_ms = frame_now_ms;
    s_perf_frame_count = 0;
}

static void render_hourglass(float delta_seconds)
{
    int64_t remaining = current_remaining_ms();
    if (s_running && remaining == 0) {
        s_running = false;
        s_remaining_ms = 0;
        ESP_LOGI(TAG, "timer complete");
    }
    float progress = s_duration_ms > 0
        ? 1.0f - (float)remaining / (float)s_duration_ms
        : 1.0f;
    if (progress < 0.0f) {
        progress = 0.0f;
    } else if (progress > 1.0f) {
        progress = 1.0f;
    }

    hg_physics_stats_t stats = hg_physics_stats();
    bool finish_settling =
        remaining == 0 && (stats.upper > 0 || !stats.settled);
    bool physics_enabled = s_running || finish_settling;
    bool physics_stepped = false;
    if (physics_enabled && delta_seconds > 0.0f) {
        s_physics_accumulator += delta_seconds;
        if (s_physics_accumulator > HG_PHYSICS_DT * 3.0f) {
            s_physics_accumulator = HG_PHYSICS_DT * 3.0f;
        }
        while (s_physics_accumulator >= HG_PHYSICS_DT) {
            hg_physics_step(
                logical_gravity_x(), fabsf(s_gravity_y), progress,
                s_running || remaining == 0);
            s_physics_accumulator -= HG_PHYSICS_DT;
            physics_stepped = true;
        }
        stats = hg_physics_stats();
    }

    update_timer_text(remaining);
    update_progress_text(progress);
    bool redraw_canvas =
        s_force_canvas_redraw || s_flipping || physics_enabled ||
        physics_stepped;
    if (redraw_canvas) {
        float interpolation =
            physics_enabled ? s_physics_accumulator / HG_PHYSICS_DT : 0.0f;
        clear_hourglass_canvas();
        draw_physics_particles(interpolation);
        if (s_frame_overlay_count > 0 &&
            (s_render_angle == 0 || s_render_angle == 1800)) {
            apply_frame_overlay();
        } else {
            draw_hourglass_frame();
        }
        lv_obj_invalidate(s_canvas);
        s_force_canvas_redraw = false;
    }

    if (remaining == 0 && stats.settled && !s_finish_settled_logged) {
        s_finish_settled_logged = true;
        ESP_LOGI(TAG,
                 "sand settled total=%u upper=%u falling=%u lower=%u",
                 stats.total, stats.upper, stats.falling, stats.lower);
    }
}

static void animation_timer_cb(lv_timer_t *timer)
{
    (void)timer;
    int64_t frame_now_ms = now_ms();
    float delta_seconds = s_last_frame_ms > 0
        ? (float)(frame_now_ms - s_last_frame_ms) / 1000.0f
        : (float)ANIMATION_PERIOD_MS / 1000.0f;
    s_last_frame_ms = frame_now_ms;
    if (delta_seconds < 0.0f) {
        delta_seconds = 0.0f;
    } else if (delta_seconds > 0.05f) {
        delta_seconds = 0.05f;
    }

    update_performance_monitor(frame_now_ms);
    if (s_flipping) {
        float t = (float)(frame_now_ms - s_flip_start_ms) /
            (float)FLIP_DURATION_MS;
        if (t >= 1.0f) {
            s_flipping = false;
            s_inverted = s_pending_inverted;
            set_render_angle(0);
            layout_ui_for_orientation(s_inverted);
            esp_err_t mirror_status = esp_lcd_panel_mirror(
                s_panel, s_inverted, s_inverted);
            if (mirror_status != ESP_OK) {
                ESP_LOGE(TAG, "display mirror failed: %s",
                         esp_err_to_name(mirror_status));
            } else {
                lv_obj_invalidate(lv_screen_active());
            }
            set_duration_minutes(s_duration_minutes);
            toggle_running();
            ESP_LOGI(TAG, "flip animation complete orientation=%s",
                     s_inverted ? "inverted" : "upright");
        } else {
            float eased = t * t * (3.0f - 2.0f * t);
            int angle = s_flip_from_angle +
                (int)((float)(s_flip_to_angle - s_flip_from_angle) * eased);
            set_render_angle(angle);
            render_hourglass(0.0f);
            return;
        }
    }
    render_hourglass(delta_seconds);
}

static lv_obj_t *make_label(lv_obj_t *parent, const char *text, const lv_font_t *font,
                            lv_color_t color)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, color, 0);
    return label;
}

static void layout_ui_for_orientation(bool inverted)
{
    if (!s_title_label) {
        return;
    }
    lv_obj_update_layout(lv_screen_active());
    const int positions[] = {4, 29, 54, 79, 104};
    if (!inverted) {
        lv_obj_set_pos(
            s_title_label,
            (LCD_H_RES - lv_obj_get_width(s_title_label)) / 2, 4);
        lv_obj_set_pos(
            s_progress_label,
            LCD_H_RES - 8 - lv_obj_get_width(s_progress_label), 4);
        lv_obj_set_pos(s_canvas, 12, 18);
        lv_obj_set_pos(s_timer_label, 0, 188);
        lv_obj_set_pos(s_divider, 12, 205);
        for (size_t i = 0; i < sizeof(s_presets) / sizeof(s_presets[0]); ++i) {
            lv_obj_set_pos(s_preset_labels[i], positions[i], 210);
        }
    } else {
        for (size_t i = 0; i < sizeof(s_presets) / sizeof(s_presets[0]); ++i) {
            int mirrored_x =
                LCD_H_RES - positions[i] - lv_obj_get_width(s_preset_labels[i]);
            lv_obj_set_pos(s_preset_labels[i], mirrored_x, 4);
        }
        lv_obj_set_pos(s_divider, 12, 27);
        lv_obj_set_pos(s_timer_label, 0, 31);
        lv_obj_set_pos(s_canvas, 12, 48);
        lv_obj_set_pos(
            s_title_label,
            (LCD_H_RES - lv_obj_get_width(s_title_label)) / 2, 222);
        lv_obj_set_pos(s_progress_label, 8, 222);
    }
}

static void create_ui(void)
{
    lv_obj_t *screen = lv_display_get_screen_active(s_display);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_color(screen, lv_color_hex(0x050b0b), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);

    s_title_label = make_label(screen, "HOURGLASS", &lv_font_montserrat_10,
                               lv_color_hex(0x82f1bd));
    lv_obj_set_pos(s_title_label, 6, 4);

    s_progress_label = make_label(screen, "100%", &lv_font_montserrat_10,
                                  lv_color_hex(0x82f1bd));
    lv_obj_align(s_progress_label, LV_ALIGN_TOP_RIGHT, -5, 4);
    /*
     * Progress remains the single source of truth for time and particle
     * transfer, but the small corner label is intentionally hidden.  After
     * display mirroring its trailing '%' could be clipped, leaving a stray
     * digit beside the centered title.
     */
    lv_obj_add_flag(s_progress_label, LV_OBJ_FLAG_HIDDEN);

    s_canvas_buffer = heap_caps_calloc(
        SAND_CANVAS_W * SAND_CANVAS_H, sizeof(lv_color16_t),
        MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_canvas_buffer) {
        s_canvas_buffer = heap_caps_calloc(
            SAND_CANVAS_W * SAND_CANVAS_H, sizeof(lv_color16_t),
            MALLOC_CAP_8BIT);
    }
    ESP_ERROR_CHECK(s_canvas_buffer ? ESP_OK : ESP_ERR_NO_MEM);
    s_frame_overlay = heap_caps_malloc(
        FRAME_OVERLAY_CAPACITY * sizeof(*s_frame_overlay),
        MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_frame_overlay) {
        s_frame_overlay = heap_caps_malloc(
            FRAME_OVERLAY_CAPACITY * sizeof(*s_frame_overlay),
            MALLOC_CAP_8BIT);
    }
    ESP_ERROR_CHECK(s_frame_overlay ? ESP_OK : ESP_ERR_NO_MEM);
    init_canvas_coordinate_map();
    build_frame_overlay();
    s_canvas = lv_canvas_create(screen);
    lv_canvas_set_buffer(
        s_canvas, s_canvas_buffer, SAND_CANVAS_W, SAND_CANVAS_H,
        LV_COLOR_FORMAT_RGB565);
    lv_obj_set_pos(s_canvas, 12, 18);

    s_timer_label = make_label(screen, "05:00", &lv_font_montserrat_12,
                               lv_color_hex(0xcaff45));
    lv_obj_set_width(s_timer_label, LCD_H_RES);
    lv_obj_set_style_text_align(s_timer_label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(s_timer_label, 0, 188);

    s_divider = lv_obj_create(screen);
    lv_obj_remove_style_all(s_divider);
    lv_obj_set_size(s_divider, 111, 1);
    lv_obj_set_style_bg_color(s_divider, lv_color_hex(0x17423c), 0);
    lv_obj_set_style_bg_opa(s_divider, LV_OPA_COVER, 0);
    lv_obj_set_pos(s_divider, 12, 205);

    const int positions[] = {4, 29, 54, 79, 104};
    for (size_t i = 0; i < sizeof(s_presets) / sizeof(s_presets[0]); ++i) {
        char text[4];
        snprintf(text, sizeof(text), "%d", s_presets[i]);
        s_preset_labels[i] = make_label(
            screen, text, &lv_font_montserrat_12, lv_color_hex(0x63ddc1));
        lv_obj_set_size(s_preset_labels[i], 27, 20);
        lv_obj_set_style_text_align(s_preset_labels[i], LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_pad_top(s_preset_labels[i], 3, 0);
        lv_obj_set_pos(s_preset_labels[i], positions[i], 210);
    }

    layout_ui_for_orientation(false);
    render_presets();
    render_hourglass(0.0f);
    s_animation_timer =
        lv_timer_create(animation_timer_cb, ANIMATION_PERIOD_MS, NULL);
}

static void set_duration_minutes(int minutes)
{
    if (minutes < 1) {
        minutes = 1;
    } else if (minutes > CUSTOM_MAX_MINUTES) {
        minutes = CUSTOM_MAX_MINUTES;
    }
    s_duration_minutes = minutes;
    s_duration_ms = (int64_t)minutes * 60 * 1000;
    s_remaining_ms = s_duration_ms;
    s_running = false;
    s_last_display_second = -1;
    s_last_display_percent = -1;
    s_physics_accumulator = 0.0f;
    s_finish_settled_logged = false;
    s_force_canvas_redraw = true;
    hg_physics_reset();
}

static void toggle_running(void)
{
    if (s_running) {
        s_remaining_ms = current_remaining_ms();
        s_running = false;
    } else {
        if (s_remaining_ms <= 0) {
            s_remaining_ms = s_duration_ms;
        }
        s_deadline_ms = now_ms() + s_remaining_ms;
        s_running = true;
    }
    s_physics_accumulator = 0.0f;
    s_last_frame_ms = now_ms();
    ESP_LOGI(TAG, "timer %s remaining_ms=%lld",
             s_running ? "running" : "paused", (long long)s_remaining_ms);
}

static void enter_custom_mode(void)
{
    if (s_running) {
        s_remaining_ms = current_remaining_ms();
        s_running = false;
    }
    s_custom_backup_minutes = s_duration_minutes;
    s_custom_mode = true;
    lv_label_set_text(s_title_label, "SET MINUTES");
    layout_ui_for_orientation(s_inverted);
    render_presets();
}

static void finish_custom_mode(bool accept)
{
    int minutes = accept ? s_duration_minutes : s_custom_backup_minutes;
    set_duration_minutes(minutes);
    s_custom_mode = false;
    lv_label_set_text(s_title_label, "HOURGLASS");
    layout_ui_for_orientation(s_inverted);
    render_presets();
}

static void begin_flip(bool target_inverted)
{
    if (s_flipping || target_inverted == s_inverted) {
        return;
    }
    if (s_running) {
        s_remaining_ms = current_remaining_ms();
        s_running = false;
    }
    s_pending_inverted = target_inverted;
    s_flip_from_angle = 0;
    s_flip_to_angle = 1800;
    s_flip_start_ms = now_ms();
    s_flipping = true;
    ESP_LOGI(TAG, "flip animation start orientation=%s",
             target_inverted ? "inverted" : "upright");
}

static void handle_event(app_event_t event)
{
    if (!lvgl_lock()) {
        return;
    }
    if (event == EVENT_SIDE_TRIPLE) {
        lvgl_unlock();
        switch_to_other_app();
        return;
    }
    if (event == EVENT_FLIP_UPRIGHT || event == EVENT_FLIP_INVERTED) {
        s_custom_mode = false;
        lv_label_set_text(s_title_label, "HOURGLASS");
        layout_ui_for_orientation(s_inverted);
        begin_flip(event == EVENT_FLIP_INVERTED);
        lvgl_unlock();
        return;
    }
    if (s_flipping) {
        lvgl_unlock();
        return;
    }
    if (s_custom_mode) {
        switch (event) {
        case EVENT_SIDE_SINGLE:
            set_duration_minutes(s_duration_minutes % CUSTOM_MAX_MINUTES + 1);
            break;
        case EVENT_SIDE_DOUBLE: {
            int minutes = s_duration_minutes + 5;
            set_duration_minutes(minutes > CUSTOM_MAX_MINUTES ? 5 : minutes);
            break;
        }
        case EVENT_FRONT_SINGLE:
            finish_custom_mode(true);
            break;
        case EVENT_FRONT_DOUBLE:
        case EVENT_SIDE_LONG:
            finish_custom_mode(false);
            break;
        case EVENT_SIDE_TRIPLE:
        case EVENT_FLIP_UPRIGHT:
        case EVENT_FLIP_INVERTED:
            break;
        }
    } else {
        switch (event) {
        case EVENT_FRONT_SINGLE:
            toggle_running();
            break;
        case EVENT_FRONT_DOUBLE:
            set_duration_minutes(s_duration_minutes);
            break;
        case EVENT_SIDE_SINGLE:
            s_preset_index = (s_preset_index + 1) %
                (int)(sizeof(s_presets) / sizeof(s_presets[0]));
            set_duration_minutes(s_presets[s_preset_index]);
            render_presets();
            break;
        case EVENT_SIDE_DOUBLE:
            break;
        case EVENT_SIDE_LONG:
            enter_custom_mode();
            break;
        case EVENT_SIDE_TRIPLE:
        case EVENT_FLIP_UPRIGHT:
        case EVENT_FLIP_INVERTED:
            break;
        }
    }
    render_hourglass(0.0f);
    lvgl_unlock();
}

#ifndef VIRTUAL_DEVICE_HOST
static void queue_event(app_event_t event)
{
    if (s_event_queue) {
        xQueueSend(s_event_queue, &event, 0);
    }
}

static void front_single_cb(void *handle, void *user_data)
{
    (void)handle;
    (void)user_data;
    queue_event(EVENT_FRONT_SINGLE);
}

static void front_double_cb(void *handle, void *user_data)
{
    (void)handle;
    (void)user_data;
    queue_event(EVENT_FRONT_DOUBLE);
}

static void side_single_cb(void *handle, void *user_data)
{
    (void)handle;
    (void)user_data;
    queue_event(EVENT_SIDE_SINGLE);
}

static void side_double_cb(void *handle, void *user_data)
{
    (void)handle;
    (void)user_data;
    queue_event(EVENT_SIDE_DOUBLE);
}

static void side_triple_cb(void *handle, void *user_data)
{
    (void)handle;
    (void)user_data;
    queue_event(EVENT_SIDE_TRIPLE);
}

static void side_long_start_cb(void *handle, void *user_data)
{
    (void)handle;
    (void)user_data;
    s_side_long_active = true;
}

static void side_up_cb(void *handle, void *user_data)
{
    (void)handle;
    (void)user_data;
    if (s_side_long_active) {
        s_side_long_active = false;
        queue_event(EVENT_SIDE_LONG);
    }
}

static esp_err_t init_buttons(void)
{
    button_handle_t front_button = NULL;
    button_handle_t side_button = NULL;
    const button_config_t button_config = {0};
    const button_gpio_config_t front_config = {
        .gpio_num = PIN_BUTTON_FRONT,
        .active_level = 0,
        .enable_power_save = true,
    };
    ESP_RETURN_ON_ERROR(
        iot_button_new_gpio_device(&button_config, &front_config, &front_button),
        TAG, "front button");
    ESP_RETURN_ON_ERROR(
        iot_button_register_cb(front_button, BUTTON_SINGLE_CLICK, NULL, front_single_cb, NULL),
        TAG, "front single");
    ESP_RETURN_ON_ERROR(
        iot_button_register_cb(front_button, BUTTON_DOUBLE_CLICK, NULL, front_double_cb, NULL),
        TAG, "front double");

    const button_gpio_config_t side_config = {
        .gpio_num = PIN_BUTTON_SIDE,
        .active_level = 0,
        .enable_power_save = false,
    };
    ESP_RETURN_ON_ERROR(
        iot_button_new_gpio_device(&button_config, &side_config, &side_button),
        TAG, "side button");
    ESP_RETURN_ON_ERROR(
        iot_button_register_cb(side_button, BUTTON_SINGLE_CLICK, NULL, side_single_cb, NULL),
        TAG, "side single");
    ESP_RETURN_ON_ERROR(
        iot_button_register_cb(side_button, BUTTON_DOUBLE_CLICK, NULL, side_double_cb, NULL),
        TAG, "side double");
    button_event_args_t triple_click_args = {
        .multiple_clicks = {
            .clicks = 3,
        },
    };
    ESP_RETURN_ON_ERROR(
        iot_button_register_cb(
            side_button, BUTTON_MULTIPLE_CLICK, &triple_click_args,
            side_triple_cb, NULL),
        TAG, "side triple");
    button_event_args_t long_press_args = {
        .long_press = {
            .press_time = 500,
        },
    };
    ESP_RETURN_ON_ERROR(
        iot_button_register_cb(
            side_button, BUTTON_LONG_PRESS_START, &long_press_args, side_long_start_cb, NULL),
        TAG, "side long");
    ESP_RETURN_ON_ERROR(
        iot_button_register_cb(side_button, BUTTON_PRESS_UP, NULL, side_up_cb, NULL),
        TAG, "side up");
    return ESP_OK;
}

static void app_task(void *arg)
{
    (void)arg;
    app_event_t event;
    while (true) {
        if (xQueueReceive(s_event_queue, &event, pdMS_TO_TICKS(1000)) == pdTRUE) {
            handle_event(event);
        }
    }
}

static void gravity_task(void *arg)
{
    (void)arg;
    int log_ticks = 0;
    bool flip_candidate = false;
    int flip_stable_samples = 0;
    while (true) {
        vTaskDelay(pdMS_TO_TICKS(s_imu_period_ms));
        int16_t x = 0;
        int16_t y = 0;
        int16_t z = 0;
        if (vibe_board_accel_read(&x, &y, &z) != ESP_OK) {
            continue;
        }

        /*
         * StickS3 has a fixed BMI270-to-display mounting direction. Do not
         * infer its sign from the startup pose: booting while upside down must
         * never redefine that pose as upright.
         */
        float measured_x = (float)y * (float)STICKS3_PORTRAIT_SIGN;
        float measured_y = (float)x * (float)STICKS3_PORTRAIT_SIGN;
        float magnitude = sqrtf(measured_x * measured_x + measured_y * measured_y);
        if (magnitude < 3500.0f) {
            continue;
        }
        measured_x /= magnitude;
        measured_y /= magnitude;

        float filtered_x = s_gravity_x * 0.82f + measured_x * 0.18f;
        float filtered_y = s_gravity_y * 0.82f + measured_y * 0.18f;
        float filtered_magnitude = sqrtf(
            filtered_x * filtered_x + filtered_y * filtered_y);
        if (filtered_magnitude > 0.1f) {
            s_gravity_x = filtered_x / filtered_magnitude;
            s_gravity_y = filtered_y / filtered_magnitude;
        }

        bool orientation_known = fabsf(s_gravity_y) >= 0.72f;
        bool wants_inverted = s_gravity_y < 0.0f;
        if (!orientation_known || wants_inverted == s_inverted) {
            flip_stable_samples = 0;
        } else if (wants_inverted != flip_candidate) {
            flip_candidate = wants_inverted;
            flip_stable_samples = 1;
        } else if (++flip_stable_samples >= 8) {
            flip_stable_samples = 0;
            queue_event(wants_inverted ? EVENT_FLIP_INVERTED : EVENT_FLIP_UPRIGHT);
        }

        if (++log_ticks >= 100) {
            log_ticks = 0;
            ESP_LOGI(TAG, "gravity accel=%d,%d,%d screen=%.2f,%.2f",
                     x, y, z, s_gravity_x, s_gravity_y);
        }
    }
}

void app_main(void)
{
    ESP_LOGI(TAG, "boot VibeStick Hourglass 0.1.0");
    ESP_ERROR_CHECK_WITHOUT_ABORT(vibe_board_init_power());
    esp_err_t imu_status = vibe_board_imu_init();
    if (imu_status != ESP_OK) {
        ESP_LOGW(TAG, "gravity effect disabled: %s", esp_err_to_name(imu_status));
    }
    hg_physics_init();
    hg_physics_set_limits(
        HG_DEFAULT_MAX_ACTIVE, HG_DEFAULT_CONSTRAINT_ITERATIONS);
    s_event_queue = xQueueCreate(10, sizeof(app_event_t));
    s_lvgl_lock = xSemaphoreCreateMutex();
    ESP_ERROR_CHECK(init_display());
    if (lvgl_lock()) {
        create_ui();
        lvgl_unlock();
    }
    ESP_ERROR_CHECK(init_buttons());
    xTaskCreate(app_task, "hourglass_app", 4096, NULL, 4, NULL);
    if (imu_status == ESP_OK) {
        xTaskCreate(gravity_task, "gravity", 4096, NULL, 3, NULL);
    }
}
#endif

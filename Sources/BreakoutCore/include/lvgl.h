#pragma once

// macOS 主机适配：只实现 GameRenderer.cpp 使用的 LVGL Canvas 边界。
// 真实固件仍使用 ESP-IDF 管理的完整 LVGL，这个文件不会进入真机构建。
#include <cstdint>
#include <cstdlib>

typedef uint16_t lv_color_t;

struct lv_obj_t {
    void *buffer = nullptr;
    lv_obj_t *canvas = nullptr;
};

struct lv_display_t {
    int32_t width = 0;
    int32_t height = 0;
    lv_obj_t screen{};
};

enum { LV_COLOR_FORMAT_RGB565 = 1 };

static inline int32_t lv_display_get_horizontal_resolution(lv_display_t *display) {
    return display->width;
}
static inline int32_t lv_display_get_vertical_resolution(lv_display_t *display) {
    return display->height;
}
static inline lv_obj_t *lv_display_get_screen_active(lv_display_t *display) {
    return &display->screen;
}
static inline void lv_obj_remove_style_all(lv_obj_t *) {}
static inline lv_color_t lv_color_hex(uint32_t rgb) {
    return static_cast<uint16_t>((((rgb >> 16) & 0xffu) >> 3) << 11 |
                                 (((rgb >> 8) & 0xffu) >> 2) << 5 |
                                 ((rgb & 0xffu) >> 3));
}
static inline uint16_t lv_color_to_u16(lv_color_t color) { return color; }
static inline void lv_obj_set_style_bg_color(lv_obj_t *, lv_color_t, int) {}
static inline lv_obj_t *lv_canvas_create(lv_obj_t *parent) {
    parent->canvas = new lv_obj_t{};
    return parent->canvas;
}
static inline void lv_canvas_set_buffer(lv_obj_t *canvas, void *buffer,
                                        int32_t, int32_t, int) {
    canvas->buffer = buffer;
}
static inline void lv_obj_set_pos(lv_obj_t *, int32_t, int32_t) {}
static inline void lv_obj_invalidate(lv_obj_t *) {}

#pragma once

#include <stdint.h>

typedef uint16_t lv_color_t;
typedef uint16_t lv_color16_t;
typedef struct { int unused; } lv_display_t;
typedef struct { void *buffer; } lv_obj_t;

static inline lv_color_t lv_color_hex(uint32_t rgb) {
    return (uint16_t)((((rgb >> 16) & 0xffu) >> 3) << 11 |
                      (((rgb >> 8) & 0xffu) >> 2) << 5 |
                      ((rgb & 0xffu) >> 3));
}
static inline uint16_t lv_color_to_u16(lv_color_t color) { return color; }
static inline void lv_obj_invalidate(lv_obj_t *obj) { (void)obj; }
static inline void lv_refr_now(lv_display_t *display) { (void)display; }

#pragma once

#include <cstdint>
#include "lvgl.h"

class BreakoutGame;

class GameRenderer {
public:
    bool begin(lv_display_t *display);
    void render(const BreakoutGame &game, bool soundEnabled);

private:
    uint16_t color565(uint32_t rgb) const;
    void pixel(int x, int y, uint32_t color);
    void fillRect(int x, int y, int w, int h, uint32_t color);
    void rect(int x, int y, int w, int h, uint32_t color);
    void line(int x0, int y0, int x1, int y1, uint32_t color);
    void circle(int cx, int cy, int radius, uint32_t color);
    void text(const char *value, int x, int y, int scale, uint32_t color);
    int textWidth(const char *value, int scale) const;
    void centeredText(const char *value, int cx, int y, int scale, uint32_t color);
    void drawBackground(const BreakoutGame &game);
    void drawHud(const BreakoutGame &game);
    void drawFooter(const BreakoutGame &game, bool soundEnabled);
    void drawPlayfield(const BreakoutGame &game);
    void drawOverlay(const BreakoutGame &game);

    lv_display_t *display_ = nullptr;
    lv_obj_t *canvas_ = nullptr;
    uint16_t *buffer_ = nullptr;
    int width_ = 0;
    int height_ = 0;
    bool detailedTexture_ = true;
};

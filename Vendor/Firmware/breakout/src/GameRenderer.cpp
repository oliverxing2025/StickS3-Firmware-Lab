#include "GameRenderer.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "BreakoutGame.h"
#include "GameConfig.h"
#include "esp_heap_caps.h"

namespace {
// 5x7 像素字库：A-Z，0-9。
constexpr uint8_t kFont[36][7] = {
    {14,17,17,31,17,17,17},{30,17,17,30,17,17,30},
    {14,17,16,16,16,17,14},{30,17,17,17,17,17,30},
    {31,16,16,30,16,16,31},{31,16,16,30,16,16,16},
    {14,17,16,23,17,17,14},{17,17,17,31,17,17,17},
    {14,4,4,4,4,4,14},{7,2,2,2,2,18,12},
    {17,18,20,24,20,18,17},{16,16,16,16,16,16,31},
    {17,27,21,21,17,17,17},{17,25,21,19,17,17,17},
    {14,17,17,17,17,17,14},{30,17,17,30,16,16,16},
    {14,17,17,17,21,18,13},{30,17,17,30,20,18,17},
    {15,16,16,14,1,1,30},{31,4,4,4,4,4,4},
    {17,17,17,17,17,17,14},{17,17,17,17,17,10,4},
    {17,17,17,21,21,21,10},{17,17,10,4,10,17,17},
    {17,17,10,4,4,4,4},{31,1,2,4,8,16,31},
    {14,17,19,21,25,17,14},{4,12,4,4,4,4,14},
    {14,17,1,2,4,8,31},{30,1,1,14,1,1,30},
    {2,6,10,18,31,2,2},{31,16,30,1,1,17,14},
    {6,8,16,30,17,17,14},{31,1,2,4,8,8,8},
    {14,17,17,14,17,17,14},{14,17,17,15,1,2,12},
};

const uint8_t *glyph(char c) {
    if (c >= 'A' && c <= 'Z') return kFont[c - 'A'];
    if (c >= '0' && c <= '9') return kFont[26 + c - '0'];
    return nullptr;
}
}

bool GameRenderer::begin(lv_display_t *display)
{
    display_ = display;
    width_ = lv_display_get_horizontal_resolution(display);
    height_ = lv_display_get_vertical_resolution(display);
    const size_t bytes = static_cast<size_t>(width_) * height_ * sizeof(uint16_t);
    buffer_ = static_cast<uint16_t *>(heap_caps_calloc(
        width_ * height_, sizeof(uint16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
    detailedTexture_ = buffer_ != nullptr;
    if (!buffer_) buffer_ = static_cast<uint16_t *>(heap_caps_calloc(
        width_ * height_, sizeof(uint16_t), MALLOC_CAP_8BIT));
    if (!buffer_) return false;

    lv_obj_t *screen = lv_display_get_screen_active(display_);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_color(screen, lv_color_hex(GameConfig::COLOR_BACKGROUND), 0);
    canvas_ = lv_canvas_create(screen);
    lv_canvas_set_buffer(canvas_, buffer_, width_, height_, LV_COLOR_FORMAT_RGB565);
    lv_obj_set_pos(canvas_, 0, 0);
    (void)bytes;
    return true;
}

uint16_t GameRenderer::color565(uint32_t rgb) const {
    return lv_color_to_u16(lv_color_hex(rgb));
}

void GameRenderer::pixel(int x, int y, uint32_t color)
{
    if (x >= 0 && x < width_ && y >= 0 && y < height_)
        buffer_[y * width_ + x] = color565(color);
}

void GameRenderer::fillRect(int x, int y, int w, int h, uint32_t color)
{
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > width_) w = width_ - x;
    if (y + h > height_) h = height_ - y;
    if (w <= 0 || h <= 0) return;
    const uint16_t value = color565(color);
    for (int row = 0; row < h; ++row)
        std::fill_n(buffer_ + (y + row) * width_ + x, w, value);
}

void GameRenderer::rect(int x, int y, int w, int h, uint32_t color)
{
    fillRect(x, y, w, 1, color); fillRect(x, y + h - 1, w, 1, color);
    fillRect(x, y, 1, h, color); fillRect(x + w - 1, y, 1, h, color);
}

void GameRenderer::line(int x0, int y0, int x1, int y1, uint32_t color)
{
    int dx = std::abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = -std::abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int error = dx + dy;
    while (true) {
        pixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * error;
        if (e2 >= dy) { error += dy; x0 += sx; }
        if (e2 <= dx) { error += dx; y0 += sy; }
    }
}

void GameRenderer::circle(int cx, int cy, int radius, uint32_t color)
{
    const int rr = radius * radius;
    for (int y = -radius; y <= radius; ++y)
        for (int x = -radius; x <= radius; ++x)
            if (x * x + y * y <= rr) pixel(cx + x, cy + y, color);
}

void GameRenderer::text(const char *value, int x, int y, int scale, uint32_t color)
{
    for (const char *p = value; *p; ++p) {
        if (*p == ' ') { x += 4 * scale; continue; }
        if (*p == ':' || *p == '.' || *p == '-' || *p == '+') {
            if (*p == ':') { fillRect(x + scale, y + 2*scale, scale, scale, color); fillRect(x + scale, y + 5*scale, scale, scale, color); }
            else if (*p == '.') fillRect(x + scale, y + 6*scale, scale, scale, color);
            else { fillRect(x, y + 3*scale, 5*scale, scale, color); if (*p == '+') fillRect(x + 2*scale, y + scale, scale, 5*scale, color); }
            x += 6 * scale; continue;
        }
        const uint8_t *rows = glyph(*p);
        if (!rows) { x += 6 * scale; continue; }
        for (int row = 0; row < 7; ++row)
            for (int col = 0; col < 5; ++col)
                if (rows[row] & (1 << (4 - col)))
                    fillRect(x + col * scale, y + row * scale, scale, scale, color);
        x += 6 * scale;
    }
}

int GameRenderer::textWidth(const char *value, int scale) const
{
    int width = 0;
    for (const char *p = value; *p; ++p) width += (*p == ' ') ? 4 * scale : 6 * scale;
    return width ? width - scale : 0;
}

void GameRenderer::centeredText(const char *value, int cx, int y, int scale, uint32_t color)
{
    text(value, cx - textWidth(value, scale) / 2, y, scale, color);
}

void GameRenderer::drawBackground(const BreakoutGame &game)
{
    fillRect(0, 0, width_, height_, GameConfig::COLOR_BACKGROUND);
    const auto &b = game.bounds();
    const int step = detailedTexture_ ? 18 : 30;
    for (int y = b.playTop + 8; y < b.playBottom - 4; y += step) {
        const int shift = (y / step % 2) * 7;
        for (int x = b.safeInset + shift; x < width_ - b.safeInset; x += step) {
            line(x, y, std::min(x + 8, width_ - b.safeInset), y, GameConfig::COLOR_CIRCUIT);
            line(x + 8, y, x + 8, std::min(y + 5, b.playBottom), GameConfig::COLOR_CIRCUIT_GLOW);
            pixel(x, y, GameConfig::COLOR_DIVIDER);
        }
    }
    fillRect(0, b.headerBottom, width_, 1, GameConfig::COLOR_DIVIDER);
    fillRect(0, b.footerTop, width_, 1, GameConfig::COLOR_DIVIDER);
}

void GameRenderer::drawHud(const BreakoutGame &game)
{
    char value[16];
    const auto &b = game.bounds();
    const int y = std::max(3, b.safeInset - 1);
    text("SCORE", b.safeInset, y, 1, GameConfig::COLOR_TEXT_DIM);
    std::snprintf(value, sizeof(value), "%lu", static_cast<unsigned long>(game.score()));
    text(value, b.safeInset, y + 9, 1, GameConfig::COLOR_TEXT);
    centeredText("LEVEL", width_ / 2, y, 1, GameConfig::COLOR_TEXT_DIM);
    std::snprintf(value, sizeof(value), "%u", game.level());
    centeredText(value, width_ / 2, y + 9, 1, GameConfig::COLOR_TEXT);
    const int livesX = width_ - b.safeInset - 29;
    text("LIVES", livesX, y, 1, GameConfig::COLOR_TEXT_DIM);
    for (int i = 0; i < game.lives(); ++i)
        circle(livesX + 2 + i * 6, y + 12, 2, i < 3 ? GameConfig::COLOR_ORANGE : GameConfig::COLOR_PINK);
}

void GameRenderer::drawFooter(const BreakoutGame &game, bool soundEnabled)
{
    const int y = game.bounds().footerTop + 5;
    // 左侧暂停图标。
    fillRect(game.bounds().safeInset + 1, y, 2, 8, GameConfig::COLOR_TEXT_DIM);
    fillRect(game.bounds().safeInset + 6, y, 2, 8, GameConfig::COLOR_TEXT_DIM);
    centeredText("NEON BRICK", width_ / 2, y, 1, GameConfig::COLOR_TEXT_DIM);
    // 右侧扬声器图标，关闭时加斜线。
    int x = width_ - game.bounds().safeInset - 11;
    fillRect(x, y + 3, 3, 4, GameConfig::COLOR_TEXT_DIM);
    line(x + 3, y + 3, x + 6, y, GameConfig::COLOR_TEXT_DIM);
    line(x + 3, y + 6, x + 6, y + 9, GameConfig::COLOR_TEXT_DIM);
    if (soundEnabled) line(x + 8, y + 2, x + 8, y + 7, GameConfig::COLOR_ORANGE);
    else line(x - 1, y, x + 10, y + 9, GameConfig::COLOR_PINK);
}

void GameRenderer::drawPlayfield(const BreakoutGame &game)
{
    for (int i = 0; i < game.brickCount(); ++i) {
        const Brick &brick = game.bricks()[i];
        if (!brick.active) continue;
        const int x = static_cast<int>(brick.x), y = static_cast<int>(brick.y);
        const int w = std::max(2, static_cast<int>(brick.width));
        const int h = std::max(2, static_cast<int>(brick.height));
        uint32_t color = brick.color;
        if (brick.type == BrickType::STRONG && brick.hitsRemaining == 1) color = GameConfig::COLOR_CRACK;
        fillRect(x, y, w, h, color);
        fillRect(x + 1, y + 1, std::max(1, w - 2), 1, GameConfig::COLOR_WHITE);
        if (brick.type == BrickType::STRONG) { rect(x, y, w, h, GameConfig::COLOR_SILVER); line(x + 2, y + 1, x + w - 3, y + h - 2, GameConfig::COLOR_CRACK); }
        else if (brick.type == BrickType::BONUS) { fillRect(x + w/2, y + 1, 1, h - 2, GameConfig::COLOR_BACKGROUND); fillRect(x + 2, y + h/2, w - 4, 1, GameConfig::COLOR_BACKGROUND); }
        else if (brick.type == BrickType::SPEED) { line(x + 2, y + h - 2, x + w/2, y + 1, GameConfig::COLOR_WHITE); line(x + w/2, y + 1, x + w - 3, y + h - 2, GameConfig::COLOR_WHITE); }
        else if (brick.type == BrickType::EXTEND) { line(x + 2, y + h/2, x + w - 3, y + h/2, GameConfig::COLOR_WHITE); pixel(x + 2, y + h/2 - 1, GameConfig::COLOR_WHITE); pixel(x + w - 3, y + h/2 + 1, GameConfig::COLOR_WHITE); }
    }

    const Paddle &p = game.paddle();
    int px = static_cast<int>(p.x), py = static_cast<int>(p.y);
    int pw = static_cast<int>(p.width), ph = static_cast<int>(p.height);
    fillRect(px, py, pw, ph, GameConfig::COLOR_SILVER);
    const int cap = std::max(3, pw / 8);
    fillRect(px, py, cap, ph, GameConfig::COLOR_ORANGE);
    fillRect(px + pw - cap, py, cap, ph, GameConfig::COLOR_ORANGE);

    const Ball &ball = game.ball();
    circle(static_cast<int>(ball.x), static_cast<int>(ball.y),
           static_cast<int>(ball.radius) + 1, 0x744126);
    circle(static_cast<int>(ball.x), static_cast<int>(ball.y),
           static_cast<int>(ball.radius), GameConfig::COLOR_WHITE);
    pixel(static_cast<int>(ball.x) + 1, static_cast<int>(ball.y) - 1, GameConfig::COLOR_ORANGE);
}

void GameRenderer::drawOverlay(const BreakoutGame &game)
{
    const int centerY = (game.bounds().playTop + game.bounds().playBottom) / 2;
    char value[32];
    switch (game.state()) {
        case GameState::TITLE:
            centeredText("NEON", width_ / 2, centerY - 45, 2, GameConfig::COLOR_ORANGE);
            centeredText("BRICK PULSE", width_ / 2, centerY - 25, 1, GameConfig::COLOR_TEXT);
            centeredText("STICK S3 ARCADE", width_ / 2, centerY - 10, 1, GameConfig::COLOR_BLUE);
            centeredText("PRESS TO START", width_ / 2, centerY + 21, 1, GameConfig::COLOR_WHITE);
            std::snprintf(value, sizeof(value), "HIGH %lu", static_cast<unsigned long>(game.highScore()));
            centeredText(value, width_ / 2, centerY + 38, 1, GameConfig::COLOR_TEXT_DIM);
            break;
        case GameState::READY:
            centeredText("READY", width_ / 2, centerY + 34, 1, GameConfig::COLOR_WHITE);
            centeredText("PRESS TO LAUNCH", width_ / 2, centerY + 46, 1, GameConfig::COLOR_TEXT_DIM);
            break;
        case GameState::PAUSED:
            fillRect(game.bounds().safeInset + 8, centerY - 16,
                     width_ - 2 * (game.bounds().safeInset + 8), 32, GameConfig::COLOR_PANEL);
            rect(game.bounds().safeInset + 8, centerY - 16,
                 width_ - 2 * (game.bounds().safeInset + 8), 32, GameConfig::COLOR_DIVIDER);
            centeredText("PAUSED", width_ / 2, centerY - 10, 2, GameConfig::COLOR_ORANGE);
            centeredText("PRESS TO RESUME", width_ / 2, centerY + 7, 1, GameConfig::COLOR_TEXT_DIM);
            break;
        case GameState::LEVEL_CLEAR:
            centeredText("LEVEL CLEAR", width_ / 2, centerY - 8, 1, GameConfig::COLOR_GREEN);
            centeredText("NEXT PULSE", width_ / 2, centerY + 8, 1, GameConfig::COLOR_TEXT);
            break;
        case GameState::GAME_OVER:
            centeredText("GAME OVER", width_ / 2, centerY - 14, 2, GameConfig::COLOR_PINK);
            std::snprintf(value, sizeof(value), "SCORE %lu", static_cast<unsigned long>(game.score()));
            centeredText(value, width_ / 2, centerY + 7, 1, GameConfig::COLOR_TEXT);
            centeredText("PRESS TO RESTART", width_ / 2, centerY + 24, 1, GameConfig::COLOR_TEXT_DIM);
            break;
        case GameState::PLAYING: break;
    }
}

void GameRenderer::render(const BreakoutGame &game, bool soundEnabled)
{
    if (!canvas_ || !buffer_) return;
    drawBackground(game);
    drawHud(game);
    drawFooter(game, soundEnabled);
    if (game.state() != GameState::TITLE) drawPlayfield(game);
    drawOverlay(game);
    lv_obj_invalidate(canvas_);
}

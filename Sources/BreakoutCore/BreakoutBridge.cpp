#include "BreakoutBridge.h"

#include <memory>

#include "BreakoutGame.h"
#include "GameAudio.h"
#include "GameRenderer.h"

// 编译时直接纳入固件中的 C++ 游戏核心；硬件 main.cpp 和驱动不会进入 Mac 版。
#ifndef BREAKOUT_FIRMWARE_GAME_SOURCE
#define BREAKOUT_FIRMWARE_GAME_SOURCE "../../Vendor/Firmware/breakout/src/BreakoutGame.cpp"
#endif
#ifndef BREAKOUT_FIRMWARE_RENDERER_SOURCE
#define BREAKOUT_FIRMWARE_RENDERER_SOURCE "../../Vendor/Firmware/breakout/src/GameRenderer.cpp"
#endif
#include BREAKOUT_FIRMWARE_GAME_SOURCE
#include BREAKOUT_FIRMWARE_RENDERER_SOURCE

namespace {
struct Context {
    GameAudio audio;
    BreakoutGame game{&audio};
    lv_display_t display{};
    GameRenderer renderer;
    uint32_t frameSerial = 0;

    Context(int32_t width, int32_t height) {
        display.width = width;
        display.height = height;
        game.configureScreen(width, height);
        renderer.begin(&display);
        render();
    }

    ~Context() {
        delete display.screen.canvas;
    }

    void render() {
        renderer.render(game, audio.enabled());
        ++frameSerial;
    }
};

Context *as_context(void *value) { return static_cast<Context *>(value); }
}

extern "C" {

void *breakout_create(int32_t width, int32_t height)
{
    auto context = std::make_unique<Context>(width, height);
    return context.release();
}

void breakout_destroy(void *context) { delete as_context(context); }

void breakout_load_persistent(void *context, uint32_t high_score,
                              uint8_t unlocked_level)
{
    if (context) {
        as_context(context)->game.loadPersistent(high_score, unlocked_level);
        as_context(context)->render();
    }
}

void breakout_update(void *context, float delta_seconds,
                     float paddle_velocity, uint32_t now_ms)
{
    if (context) {
        Context *value = as_context(context);
        const GameState state = value->game.state();
        if (state == GameState::TITLE || state == GameState::PAUSED || state == GameState::GAME_OVER) {
            return;
        }
        value->game.update(delta_seconds, paddle_velocity, now_ms);
        value->render();
    }
}

void breakout_primary_short(void *context)
{
    if (context) {
        as_context(context)->game.primaryShortPress();
        as_context(context)->render();
    }
}

void breakout_primary_long(void *context)
{
    if (context) {
        as_context(context)->game.primaryLongPress();
        as_context(context)->render();
    }
}

void breakout_restart(void *context)
{
    if (context) {
        as_context(context)->game.restart();
        as_context(context)->render();
    }
}

BreakoutSnapshot breakout_snapshot(void *context)
{
    BreakoutSnapshot result{};
    if (!context) return result;
    const BreakoutGame &game = as_context(context)->game;
    const GameBounds &bounds = game.bounds();
    result.state = static_cast<int32_t>(game.state());
    result.width = bounds.screenWidth;
    result.height = bounds.screenHeight;
    result.safe_inset = bounds.safeInset;
    result.header_bottom = bounds.headerBottom;
    result.play_top = bounds.playTop;
    result.play_bottom = bounds.playBottom;
    result.footer_top = bounds.footerTop;
    result.score = game.score();
    result.high_score = game.highScore();
    result.level = game.level();
    result.unlocked_level = game.unlockedLevel();
    result.lives = game.lives();
    return result;
}

BreakoutBallSnapshot breakout_ball(void *context)
{
    BreakoutBallSnapshot result{};
    if (!context) return result;
    const Ball &ball = as_context(context)->game.ball();
    result.x = ball.x;
    result.y = ball.y;
    result.vx = ball.vx;
    result.vy = ball.vy;
    result.radius = ball.radius;
    result.attached = ball.attached;
    return result;
}

BreakoutPaddleSnapshot breakout_paddle(void *context)
{
    BreakoutPaddleSnapshot result{};
    if (!context) return result;
    const Paddle &paddle = as_context(context)->game.paddle();
    result.x = paddle.x;
    result.y = paddle.y;
    result.width = paddle.width;
    result.height = paddle.height;
    return result;
}

int32_t breakout_brick_count(void *context)
{
    return context ? as_context(context)->game.brickCount() : 0;
}

bool breakout_brick(void *context, int32_t index, BreakoutBrickSnapshot *result)
{
    if (!context || !result) return false;
    const BreakoutGame &game = as_context(context)->game;
    if (index < 0 || index >= game.brickCount()) return false;
    const Brick &brick = game.bricks()[index];
    result->x = brick.x;
    result->y = brick.y;
    result->width = brick.width;
    result->height = brick.height;
    result->color = brick.color;
    result->type = static_cast<uint8_t>(brick.type);
    result->hits_remaining = brick.hitsRemaining;
    result->active = brick.active;
    return true;
}

void breakout_set_sound_enabled(void *context, bool enabled)
{
    if (context) {
        as_context(context)->audio.setEnabled(enabled);
        as_context(context)->render();
    }
}

bool breakout_sound_enabled(void *context)
{
    return context && as_context(context)->audio.enabled();
}

uint32_t breakout_sound_serial(void *context)
{
    return context ? as_context(context)->audio.serial() : 0;
}

int32_t breakout_last_sound(void *context)
{
    return context ? static_cast<int32_t>(as_context(context)->audio.lastSound()) : -1;
}

const uint16_t *breakout_framebuffer(void *context)
{
    if (!context) return nullptr;
    lv_obj_t *canvas = as_context(context)->display.screen.canvas;
    return canvas ? static_cast<const uint16_t *>(canvas->buffer) : nullptr;
}

uint32_t breakout_frame_serial(void *context)
{
    return context ? as_context(context)->frameSerial : 0;
}

}  // extern "C"

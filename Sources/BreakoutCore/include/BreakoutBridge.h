#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t state;
    int32_t width;
    int32_t height;
    int32_t safe_inset;
    int32_t header_bottom;
    int32_t play_top;
    int32_t play_bottom;
    int32_t footer_top;
    uint32_t score;
    uint32_t high_score;
    uint8_t level;
    uint8_t unlocked_level;
    uint8_t lives;
    uint8_t reserved;
} BreakoutSnapshot;

typedef struct {
    float x;
    float y;
    float vx;
    float vy;
    float radius;
    bool attached;
} BreakoutBallSnapshot;

typedef struct {
    float x;
    float y;
    float width;
    float height;
} BreakoutPaddleSnapshot;

typedef struct {
    float x;
    float y;
    float width;
    float height;
    uint32_t color;
    uint8_t type;
    uint8_t hits_remaining;
    bool active;
} BreakoutBrickSnapshot;

void *breakout_create(int32_t width, int32_t height);
void breakout_destroy(void *context);
void breakout_load_persistent(void *context, uint32_t high_score,
                              uint8_t unlocked_level);
void breakout_update(void *context, float delta_seconds,
                     float paddle_velocity, uint32_t now_ms);
void breakout_primary_short(void *context);
void breakout_primary_long(void *context);
void breakout_restart(void *context);

BreakoutSnapshot breakout_snapshot(void *context);
BreakoutBallSnapshot breakout_ball(void *context);
BreakoutPaddleSnapshot breakout_paddle(void *context);
int32_t breakout_brick_count(void *context);
bool breakout_brick(void *context, int32_t index,
                    BreakoutBrickSnapshot *brick);

void breakout_set_sound_enabled(void *context, bool enabled);
bool breakout_sound_enabled(void *context);
uint32_t breakout_sound_serial(void *context);
int32_t breakout_last_sound(void *context);
const uint16_t *breakout_framebuffer(void *context);
uint32_t breakout_frame_serial(void *context);

#ifdef __cplusplus
}
#endif

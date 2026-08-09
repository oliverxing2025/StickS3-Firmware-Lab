#pragma once

#include <cstdint>

namespace GameConfig {

// 所有主题颜色集中在此，使用 0xRRGGBB。
constexpr uint32_t COLOR_BACKGROUND = 0x030612;
constexpr uint32_t COLOR_PANEL = 0x081126;
constexpr uint32_t COLOR_CIRCUIT = 0x111B48;
constexpr uint32_t COLOR_CIRCUIT_GLOW = 0x241650;
constexpr uint32_t COLOR_DIVIDER = 0x3856A8;
constexpr uint32_t COLOR_TEXT = 0xEAF2FF;
constexpr uint32_t COLOR_TEXT_DIM = 0x7C8CB8;
constexpr uint32_t COLOR_ORANGE = 0xFF7A18;
constexpr uint32_t COLOR_SILVER = 0xD9E2EC;
constexpr uint32_t COLOR_GREEN = 0x39D98A;
constexpr uint32_t COLOR_WHITE = 0xF4F6F8;
constexpr uint32_t COLOR_YELLOW = 0xFFD43B;
constexpr uint32_t COLOR_PINK = 0xFF5DA2;
constexpr uint32_t COLOR_BLUE = 0x3993FF;
constexpr uint32_t COLOR_CRACK = 0x2B3150;

constexpr uint32_t BRICK_ROW_COLORS[] = {
    COLOR_GREEN, COLOR_WHITE, COLOR_ORANGE,
    COLOR_YELLOW, COLOR_PINK, COLOR_BLUE,
};

constexpr int TARGET_FPS = 60;
constexpr int FRAME_INTERVAL_MS = 1000 / TARGET_FPS;
constexpr int MAX_BRICKS = 72;
constexpr int MAX_COLLISIONS_PER_FRAME = 12;
constexpr int MAX_LIVES = 5;
constexpr int STARTING_LIVES = 3;
constexpr int EXTRA_LIFE_SCORE_STEP = 1500;
constexpr int MIN_BRICK_COLUMNS = 5;
constexpr int MAX_BRICK_COLUMNS = 7;
constexpr int BRICK_ROWS = 6;

constexpr float BASE_BALL_SPEED = 92.0f;
constexpr float LEVEL_SPEED_STEP = 7.0f;
constexpr float MAX_BALL_SPEED = 175.0f;
constexpr float MIN_HORIZONTAL_SPEED = 24.0f;
constexpr float SPEED_BOOST_MULTIPLIER = 1.22f;
constexpr uint32_t SPEED_BOOST_MS = 6500;
constexpr uint32_t PADDLE_EXTEND_MS = 9000;
constexpr float PADDLE_EXTEND_MULTIPLIER = 1.45f;
constexpr uint32_t LEVEL_MESSAGE_MS = 1400;

// BMI270 中立基线与稳定恢复参数。
constexpr uint16_t MOTION_SAMPLE_MS = 30;
constexpr float TILT_DEAD_ZONE = 0.16f;
constexpr float TILT_MAX_SPEED = 115.0f;
constexpr float TILT_SENSITIVITY = 1.45f;
constexpr float TILT_SMOOTHING = 0.72f;
constexpr bool TILT_REVERSED = false;
constexpr int MOTION_STABLE_RAW = 600;
constexpr int MOTION_PICKUP_SETTLE_SAMPLES = 12;

}  // namespace GameConfig

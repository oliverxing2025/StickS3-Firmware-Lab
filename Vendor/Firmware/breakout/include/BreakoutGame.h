#pragma once

#include <cstdint>
#include "GameConfig.h"

class GameAudio;

enum class GameState : uint8_t {
    TITLE,
    READY,
    PLAYING,
    PAUSED,
    LEVEL_CLEAR,
    GAME_OVER,
};

enum class BrickType : uint8_t {
    NORMAL,
    STRONG,
    BONUS,
    SPEED,
    EXTEND,
    MULTIBALL,  // 本版只预留类型和生成接口。
};

struct Ball {
    float x = 0;
    float y = 0;
    float vx = 0;
    float vy = 0;
    float radius = 2;
    bool attached = true;
};

struct Paddle {
    float x = 0;
    float y = 0;
    float width = 0;
    float baseWidth = 0;
    float height = 4;
};

struct Brick {
    float x = 0;
    float y = 0;
    float width = 0;
    float height = 0;
    BrickType type = BrickType::NORMAL;
    uint32_t color = 0;
    uint8_t hitsRemaining = 0;
    bool active = false;
};

struct LevelConfig {
    uint8_t rows;
    uint8_t columns;
    float speed;
    uint8_t strongCount;
    uint8_t specialCount;
};

struct GameBounds {
    int screenWidth = 0;
    int screenHeight = 0;
    int safeInset = 0;
    int headerBottom = 0;
    int playTop = 0;
    int playBottom = 0;
    int footerTop = 0;
};

class BreakoutGame {
public:
    explicit BreakoutGame(GameAudio *audio);
    void configureScreen(int width, int height);
    void loadPersistent(uint32_t highScore, uint8_t unlockedLevel);
    void update(float dtSeconds, float paddleVelocity, uint32_t nowMs);
    void primaryShortPress();
    void primaryLongPress();
    void restart();

    GameState state() const { return state_; }
    const Ball &ball() const { return ball_; }
    const Paddle &paddle() const { return paddle_; }
    const Brick *bricks() const { return bricks_; }
    int brickCount() const { return brickCount_; }
    const GameBounds &bounds() const { return bounds_; }
    uint32_t score() const { return score_; }
    uint32_t highScore() const { return highScore_; }
    uint8_t level() const { return level_; }
    uint8_t unlockedLevel() const { return unlockedLevel_; }
    uint8_t lives() const { return lives_; }
    bool persistenceDirty() const { return persistenceDirty_; }
    void clearPersistenceDirty() { persistenceDirty_ = false; }

private:
    LevelConfig levelConfig(uint8_t level) const;
    void beginLevel(bool resetLives);
    void generateBricks();
    void attachBall();
    void launchBall();
    void stepBall(float dt, uint32_t nowMs);
    bool collidePaddle();
    bool collideBrick(Brick &brick, float previousX, float previousY, uint32_t nowMs);
    void destroyBrick(Brick &brick, uint32_t nowMs);
    void loseLife(uint32_t nowMs);
    void enterLevelClear(uint32_t nowMs);
    void ensureHorizontalVelocity();
    void updateHighScore();
    int remainingBricks() const;

    GameAudio *audio_ = nullptr;
    GameState state_ = GameState::TITLE;
    Ball ball_{};
    Paddle paddle_{};
    Brick bricks_[GameConfig::MAX_BRICKS]{};
    int brickCount_ = 0;
    GameBounds bounds_{};
    uint32_t score_ = 0;
    uint32_t highScore_ = 0;
    uint32_t nextLifeScore_ = GameConfig::EXTRA_LIFE_SCORE_STEP;
    uint32_t stateSinceMs_ = 0;
    uint32_t speedBoostUntilMs_ = 0;
    uint32_t extendUntilMs_ = 0;
    uint8_t level_ = 1;
    uint8_t unlockedLevel_ = 1;
    uint8_t lives_ = GameConfig::STARTING_LIVES;
    bool persistenceDirty_ = false;
};


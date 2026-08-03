#include "BreakoutGame.h"

#include <algorithm>
#include <cmath>

#include "GameAudio.h"

namespace {
constexpr float kPi = 3.14159265358979323846f;
float clampf(float value, float low, float high) {
    return std::max(low, std::min(value, high));
}
bool overlaps(float ax, float ay, float aw, float ah,
              float bx, float by, float bw, float bh) {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
}
}

BreakoutGame::BreakoutGame(GameAudio *audio) : audio_(audio) {}

void BreakoutGame::configureScreen(int width, int height)
{
    bounds_.screenWidth = width;
    bounds_.screenHeight = height;
    bounds_.safeInset = std::max(3, std::min(width, height) / 28);
    bounds_.headerBottom = std::max(24, height * 12 / 100);
    bounds_.footerTop = height - std::max(18, height * 10 / 100);
    bounds_.playTop = bounds_.headerBottom + 3;
    bounds_.playBottom = bounds_.footerTop - 2;
    paddle_.baseWidth = clampf(width * 0.28f, 26.0f, 48.0f);
    paddle_.width = paddle_.baseWidth;
    paddle_.height = std::max(4.0f, height / 55.0f);
    paddle_.y = bounds_.playBottom - paddle_.height - bounds_.safeInset;
    ball_.radius = std::max(2.0f, std::min(width, height) / 54.0f);
    paddle_.x = (width - paddle_.width) * 0.5f;
    attachBall();
}

void BreakoutGame::loadPersistent(uint32_t highScore, uint8_t unlockedLevel)
{
    highScore_ = highScore;
    unlockedLevel_ = std::max<uint8_t>(1, unlockedLevel);
}

LevelConfig BreakoutGame::levelConfig(uint8_t level) const
{
    const int available = bounds_.screenWidth - bounds_.safeInset * 2;
    const int columns = std::clamp(available / 19,
        GameConfig::MIN_BRICK_COLUMNS, GameConfig::MAX_BRICK_COLUMNS);
    const uint8_t cycle = static_cast<uint8_t>((level - 1) % 5);
    return {
        static_cast<uint8_t>(GameConfig::BRICK_ROWS),
        static_cast<uint8_t>(columns),
        std::min(GameConfig::BASE_BALL_SPEED + (level - 1) * GameConfig::LEVEL_SPEED_STEP,
                 GameConfig::MAX_BALL_SPEED),
        static_cast<uint8_t>(cycle + 1),
        static_cast<uint8_t>(1 + cycle / 2),
    };
}

void BreakoutGame::restart()
{
    score_ = 0;
    level_ = 1;
    lives_ = GameConfig::STARTING_LIVES;
    nextLifeScore_ = GameConfig::EXTRA_LIFE_SCORE_STEP;
    speedBoostUntilMs_ = 0;
    extendUntilMs_ = 0;
    beginLevel(false);
}

void BreakoutGame::beginLevel(bool resetLives)
{
    if (resetLives) lives_ = GameConfig::STARTING_LIVES;
    paddle_.width = paddle_.baseWidth;
    paddle_.x = (bounds_.screenWidth - paddle_.width) * 0.5f;
    speedBoostUntilMs_ = 0;
    extendUntilMs_ = 0;
    generateBricks();
    attachBall();
    state_ = GameState::READY;
}

void BreakoutGame::generateBricks()
{
    const LevelConfig cfg = levelConfig(level_);
    brickCount_ = std::min<int>(cfg.rows * cfg.columns, GameConfig::MAX_BRICKS);
    const float gap = 2.0f;
    const float left = static_cast<float>(bounds_.safeInset);
    const float totalWidth = bounds_.screenWidth - 2.0f * left;
    const float brickWidth = (totalWidth - gap * (cfg.columns - 1)) / cfg.columns;
    const float brickHeight = clampf(bounds_.screenHeight * 0.036f, 6.0f, 10.0f);
    const float startY = bounds_.playTop + bounds_.safeInset + 3;
    int index = 0;
    for (int row = 0; row < cfg.rows; ++row) {
        for (int col = 0; col < cfg.columns && index < brickCount_; ++col, ++index) {
            Brick &brick = bricks_[index];
            brick.x = left + col * (brickWidth + gap);
            brick.y = startY + row * (brickHeight + gap);
            brick.width = brickWidth;
            brick.height = brickHeight;
            brick.color = GameConfig::BRICK_ROW_COLORS[row % 6];
            brick.type = BrickType::NORMAL;
            // 使用固定公式生成少量特殊砖，不需要运行时随机对象。
            const int marker = (index * 17 + level_ * 13) % 37;
            if (marker < cfg.strongCount) brick.type = BrickType::STRONG;
            else if (marker == 11 && cfg.specialCount >= 1) brick.type = BrickType::BONUS;
            else if (marker == 23 && cfg.specialCount >= 2) brick.type = BrickType::SPEED;
            else if (marker == 31 && cfg.specialCount >= 3) brick.type = BrickType::EXTEND;
            brick.hitsRemaining = brick.type == BrickType::STRONG ? 2 : 1;
            brick.active = true;
        }
    }
    for (; index < GameConfig::MAX_BRICKS; ++index) bricks_[index].active = false;
}

void BreakoutGame::attachBall()
{
    ball_.attached = true;
    ball_.x = paddle_.x + paddle_.width * 0.5f;
    ball_.y = paddle_.y - ball_.radius - 1.0f;
    ball_.vx = 0;
    ball_.vy = 0;
}

void BreakoutGame::launchBall()
{
    const float speed = levelConfig(level_).speed;
    const float direction = (level_ & 1U) ? 1.0f : -1.0f;
    ball_.vx = speed * 0.42f * direction;
    ball_.vy = -std::sqrt(std::max(1.0f, speed * speed - ball_.vx * ball_.vx));
    ball_.attached = false;
    state_ = GameState::PLAYING;
}

void BreakoutGame::primaryShortPress()
{
    switch (state_) {
        case GameState::TITLE: restart(); break;
        case GameState::READY: launchBall(); break;
        case GameState::PLAYING: state_ = GameState::PAUSED; break;
        case GameState::PAUSED: state_ = GameState::PLAYING; break;
        case GameState::LEVEL_CLEAR:
            ++level_;
            beginLevel(false);
            break;
        case GameState::GAME_OVER: restart(); break;
    }
}

void BreakoutGame::primaryLongPress()
{
    state_ = GameState::TITLE;
    score_ = 0;
    level_ = 1;
    lives_ = GameConfig::STARTING_LIVES;
    paddle_.width = paddle_.baseWidth;
    paddle_.x = (bounds_.screenWidth - paddle_.width) * 0.5f;
    attachBall();
}

void BreakoutGame::update(float dt, float paddleVelocity, uint32_t nowMs)
{
    dt = clampf(dt, 0.0f, 0.05f);
    if (state_ == GameState::READY || state_ == GameState::PLAYING) {
        paddle_.x += paddleVelocity * dt;
        paddle_.x = clampf(paddle_.x, static_cast<float>(bounds_.safeInset),
                           bounds_.screenWidth - bounds_.safeInset - paddle_.width);
    }
    if (ball_.attached) attachBall();

    if (extendUntilMs_ && nowMs >= extendUntilMs_) {
        const float center = paddle_.x + paddle_.width * 0.5f;
        paddle_.width = paddle_.baseWidth;
        paddle_.x = clampf(center - paddle_.width * 0.5f,
                           static_cast<float>(bounds_.safeInset),
                           bounds_.screenWidth - bounds_.safeInset - paddle_.width);
        extendUntilMs_ = 0;
    }
    if (speedBoostUntilMs_ && nowMs >= speedBoostUntilMs_) {
        const float speed = std::hypot(ball_.vx, ball_.vy);
        if (speed > 0.0f) {
            const float target = levelConfig(level_).speed;
            ball_.vx *= target / speed;
            ball_.vy *= target / speed;
        }
        speedBoostUntilMs_ = 0;
    }

    if (state_ == GameState::PLAYING) stepBall(dt, nowMs);
    if (state_ == GameState::LEVEL_CLEAR &&
        nowMs - stateSinceMs_ >= GameConfig::LEVEL_MESSAGE_MS) {
        ++level_;
        beginLevel(false);
    }
}

void BreakoutGame::stepBall(float dt, uint32_t nowMs)
{
    const float travel = std::max(std::fabs(ball_.vx * dt), std::fabs(ball_.vy * dt));
    const int steps = std::clamp(static_cast<int>(std::ceil(travel /
        std::max(1.0f, ball_.radius * 0.7f))), 1, GameConfig::MAX_COLLISIONS_PER_FRAME);
    const float subDt = dt / steps;
    for (int step = 0; step < steps && state_ == GameState::PLAYING; ++step) {
        const float previousX = ball_.x;
        const float previousY = ball_.y;
        ball_.x += ball_.vx * subDt;
        ball_.y += ball_.vy * subDt;

        const float left = bounds_.safeInset + ball_.radius;
        const float right = bounds_.screenWidth - bounds_.safeInset - ball_.radius;
        const float top = bounds_.playTop + ball_.radius;
        if (ball_.x < left) { ball_.x = left; ball_.vx = std::fabs(ball_.vx); }
        if (ball_.x > right) { ball_.x = right; ball_.vx = -std::fabs(ball_.vx); }
        if (ball_.y < top) { ball_.y = top; ball_.vy = std::fabs(ball_.vy); }

        if (ball_.vy > 0.0f && collidePaddle()) continue;
        for (int i = 0; i < brickCount_; ++i) {
            if (bricks_[i].active && collideBrick(bricks_[i], previousX, previousY, nowMs)) break;
        }
        if (ball_.y - ball_.radius > bounds_.playBottom) loseLife(nowMs);
    }
}

bool BreakoutGame::collidePaddle()
{
    if (!overlaps(ball_.x - ball_.radius, ball_.y - ball_.radius,
                  ball_.radius * 2, ball_.radius * 2,
                  paddle_.x, paddle_.y, paddle_.width, paddle_.height)) return false;
    ball_.y = paddle_.y - ball_.radius - 0.2f;
    const float impact = clampf((ball_.x - (paddle_.x + paddle_.width * 0.5f)) /
                                (paddle_.width * 0.5f), -1.0f, 1.0f);
    const float speed = std::max(levelConfig(level_).speed, std::hypot(ball_.vx, ball_.vy));
    const float angle = impact * 62.0f * kPi / 180.0f;
    ball_.vx = speed * std::sin(angle);
    ball_.vy = -std::fabs(speed * std::cos(angle));
    ensureHorizontalVelocity();
    if (audio_) audio_->play(GameSound::Paddle);
    return true;
}

bool BreakoutGame::collideBrick(Brick &brick, float previousX, float previousY, uint32_t nowMs)
{
    if (!overlaps(ball_.x - ball_.radius, ball_.y - ball_.radius,
                  ball_.radius * 2, ball_.radius * 2,
                  brick.x, brick.y, brick.width, brick.height)) return false;
    const bool wasAbove = previousY + ball_.radius <= brick.y;
    const bool wasBelow = previousY - ball_.radius >= brick.y + brick.height;
    const bool wasLeft = previousX + ball_.radius <= brick.x;
    const bool wasRight = previousX - ball_.radius >= brick.x + brick.width;
    if (wasAbove) { ball_.y = brick.y - ball_.radius - 0.1f; ball_.vy = -std::fabs(ball_.vy); }
    else if (wasBelow) { ball_.y = brick.y + brick.height + ball_.radius + 0.1f; ball_.vy = std::fabs(ball_.vy); }
    else if (wasLeft) { ball_.x = brick.x - ball_.radius - 0.1f; ball_.vx = -std::fabs(ball_.vx); }
    else if (wasRight) { ball_.x = brick.x + brick.width + ball_.radius + 0.1f; ball_.vx = std::fabs(ball_.vx); }
    else ball_.vy = -ball_.vy;
    destroyBrick(brick, nowMs);
    ensureHorizontalVelocity();
    return true;
}

void BreakoutGame::destroyBrick(Brick &brick, uint32_t nowMs)
{
    if (brick.hitsRemaining > 0) --brick.hitsRemaining;
    if (audio_) audio_->play(GameSound::Brick);
    if (brick.hitsRemaining > 0) return;
    brick.active = false;
    uint32_t award = 100 + level_ * 10;
    if (brick.type == BrickType::BONUS) award += 400;
    score_ += award;
    if (brick.type == BrickType::SPEED) {
        const float speed = std::hypot(ball_.vx, ball_.vy);
        const float boosted = std::min(speed * GameConfig::SPEED_BOOST_MULTIPLIER,
                                       GameConfig::MAX_BALL_SPEED);
        if (speed > 0) { ball_.vx *= boosted / speed; ball_.vy *= boosted / speed; }
        speedBoostUntilMs_ = nowMs + GameConfig::SPEED_BOOST_MS;
    } else if (brick.type == BrickType::EXTEND) {
        const float center = paddle_.x + paddle_.width * 0.5f;
        paddle_.width = std::min(paddle_.baseWidth * GameConfig::PADDLE_EXTEND_MULTIPLIER,
                                 bounds_.screenWidth * 0.58f);
        paddle_.x = clampf(center - paddle_.width * 0.5f,
                           static_cast<float>(bounds_.safeInset),
                           bounds_.screenWidth - bounds_.safeInset - paddle_.width);
        extendUntilMs_ = nowMs + GameConfig::PADDLE_EXTEND_MS;
    }
    while (score_ >= nextLifeScore_) {
        if (lives_ < GameConfig::MAX_LIVES) ++lives_;
        nextLifeScore_ += GameConfig::EXTRA_LIFE_SCORE_STEP;
    }
    updateHighScore();
    if (remainingBricks() == 0) enterLevelClear(nowMs);
}

void BreakoutGame::loseLife(uint32_t nowMs)
{
    if (audio_) { audio_->play(GameSound::LifeLost); audio_->vibrateLifeLost(); }
    if (lives_ > 0) --lives_;
    if (lives_ == 0) {
        state_ = GameState::GAME_OVER;
        stateSinceMs_ = nowMs;
        updateHighScore();
        if (audio_) audio_->play(GameSound::GameOver);
    } else {
        state_ = GameState::READY;
        attachBall();
    }
}

void BreakoutGame::enterLevelClear(uint32_t nowMs)
{
    state_ = GameState::LEVEL_CLEAR;
    stateSinceMs_ = nowMs;
    unlockedLevel_ = std::max<uint8_t>(unlockedLevel_, level_ + 1);
    persistenceDirty_ = true;
    if (audio_) audio_->play(GameSound::LevelClear);
}

void BreakoutGame::ensureHorizontalVelocity()
{
    if (std::fabs(ball_.vx) >= GameConfig::MIN_HORIZONTAL_SPEED) return;
    const float speed = std::max(levelConfig(level_).speed, std::hypot(ball_.vx, ball_.vy));
    const float sign = ball_.vx < 0 ? -1.0f : 1.0f;
    ball_.vx = GameConfig::MIN_HORIZONTAL_SPEED * sign;
    ball_.vy = (ball_.vy < 0 ? -1.0f : 1.0f) *
               std::sqrt(std::max(1.0f, speed * speed - ball_.vx * ball_.vx));
}

void BreakoutGame::updateHighScore()
{
    if (score_ > highScore_) {
        highScore_ = score_;
        persistenceDirty_ = true;
    }
}

int BreakoutGame::remainingBricks() const
{
    int count = 0;
    for (int i = 0; i < brickCount_; ++i) if (bricks_[i].active) ++count;
    return count;
}

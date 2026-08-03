#pragma once

#include <cstdint>

// Mac 适配层：保留与真机相同的音效事件，由桌面窗口实际播放。
enum class GameSound : uint8_t {
    Paddle,
    Brick,
    LifeLost,
    LevelClear,
    GameOver,
};

class GameAudio {
public:
    void play(GameSound sound) {
        if (!enabled_) return;
        lastSound_ = sound;
        ++serial_;
    }
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool enabled() const { return enabled_; }
    bool available() const { return true; }
    void vibrateLifeLost() { ++vibrationSerial_; }
    uint32_t serial() const { return serial_; }
    GameSound lastSound() const { return lastSound_; }

private:
    bool enabled_ = true;
    uint32_t serial_ = 0;
    uint32_t vibrationSerial_ = 0;
    GameSound lastSound_ = GameSound::Paddle;
};
